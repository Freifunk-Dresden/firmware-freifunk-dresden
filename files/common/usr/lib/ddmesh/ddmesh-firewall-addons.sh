#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

[ -z "$1" ] && exit 1

. /lib/functions.sh

#firewall rules that can not be created
eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)

TAG="ddmesh-firewall-addons"

fwprint()
{
 logger -s -t "addon" "iptables $*"
 iptables $*
}

# export IPT=fwprint
export IPT=iptables

setup_custom_rules() {
# temp firewall rules (fw uci can not add custom chains)
	logger -s -t $TAG "setup_custom_rules"

	# remove "ctstate RELATED,ESTABLISHED" rule from OUTPUT, as this accepts packets (e.g. wireguard)
	# where firewall is not ready yet, but a packet gets out because rules not yet fully setup.
	# backbone/vpn can setup connections through freifunk network.
	$IPT -w -D OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment '!fw3'

	#input rules for backbone packets ( to restrict tunnel pakets only via allowed interfaces )
	#tbb traffic is controlled by zone rules tbb+
	$IPT -w -N input_backbone_accept
	$IPT -w -N input_backbone_reject
	$IPT -w -A input_wan_rule -j input_backbone_accept
	$IPT -w -A input_lan_rule -j input_backbone_accept
	$IPT -w -A input_mesh_rule -j input_backbone_reject
	$IPT -w -A input_bat_rule -j input_backbone_reject
	$IPT -w -A input_wifi2_rule -j input_backbone_reject

	$IPT -w -N output_backbone_accept
	$IPT -w -N output_backbone_reject
	$IPT -w -A output_wan_rule -j output_backbone_accept
	$IPT -w -A output_lan_rule -j output_backbone_accept
	$IPT -w -A output_mesh_rule -j output_backbone_reject
	$IPT -w -A output_bat_rule -j output_backbone_reject
	$IPT -w -A output_wifi2_rule -j output_backbone_reject

	#input rules for privnet packets( to restrict tunnel pakets only via allowed interfaces )
	#private data traffic is controlled by zone rules lan (br-lan)
	$IPT -w -N input_privnet_accept
	$IPT -w -N input_privnet_reject
	$IPT -w -A input_wan_rule -j input_privnet_reject
	$IPT -w -A input_lan_rule -j input_privnet_reject
	$IPT -w -A input_mesh_rule -j input_privnet_accept
	$IPT -w -A input_bat_rule -j input_privnet_reject
	$IPT -w -A input_wifi2_rule -j input_privnet_reject

	#add tables that are later filled with IPs that should be blocked.
	# loop through zones
	for i in mesh wifi2 bat lan wan vpn
	do
	        $IPT -w -N input_"$i"_deny
	        $IPT -w -I input_"$i"_rule -j input_"$i"_deny
	done

	# allow dhcp because "subnet" definition. client has no ip yet.
	# $IPT -w -A input_rule -i $wifi2_ifname -p udp --dport 67 -j ACCEPT -m comment --comment 'dhcp-wifi2-request'
	# $IPT -w -A output_rule -o $wifi2_ifname -p udp --dport 68 -j ACCEPT -m comment --comment 'dhcp-wifi2-response'
	# $IPT -w -A input_rule -i $lan_ifname -p udp --dport 67 -j ACCEPT -m comment --comment 'dhcp-lan-request'
	# $IPT -w -A output_rule -o $lan_ifname -p udp --dport 68 -j ACCEPT -m comment --comment 'dhcp-lan-response'

	#snat mesh from 10.201.xxx to 10.200.xxxx
	$IPT -w -t nat -A postrouting_mesh_rule -p udp --dport 4305:4307 -j ACCEPT
	$IPT -w -t nat -A postrouting_mesh_rule -p tcp --dport 4305:4307 -j ACCEPT
	# don't snat icmp to debug tbb links with ping (MUST come after other rules bufgix:#57)
	$IPT -w -t nat -A postrouting_mesh_rule -s $_ddmesh_fullnet -p icmp -j ACCEPT
	$IPT -w -t nat -A postrouting_mesh_rule -s $_ddmesh_linknet -j SNAT --to-source $_ddmesh_ip
	$IPT -w -t nat -A postrouting_mesh_rule -s $_ddmesh_wifi2net -j SNAT --to-source $_ddmesh_ip
}

setup_openvpn_rules() {
	logger -s -t $TAG "setup_openvpn_rules"
	CONF=/etc/openvpn/openvpn.conf
	$IPT -w -N output_openvpn_reject
	$IPT -w -A output_mesh_rule -j output_openvpn_reject
	$IPT -w -A output_bat_rule -j output_openvpn_reject
	$IPT -w -A output_wifi2_rule -j output_openvpn_reject
	$IPT -w -A output_vpn_rule -j output_openvpn_reject

	IFS='
'
	if [ -f "$CONF" ]; then
		for opt in $(cat $CONF | awk '/remote/{print $4","$3}')
		do
			proto=${opt%,*}
			port=${opt#*,}
			$IPT -w -A output_openvpn_reject -p $proto --dport $port -j reject
		done
	fi
	unset IFS

}

callback_add_ignored_nodes() {
	local entry="$1"
	IFS=':'
	set $entry
	unset IFS
	local node=$1
	local opt_lan=$2
	local opt_tbb=$3
	local opt_wifi_adhoc=$4
	local opt_wifi_mesh2g=$5
	local opt_wifi_mesh5g=$6
	local opt_vlan=$7

	# if no flag is set, only node is given (old format)
	# -> enable wifi only

	[ -z "$opt_lan" -a -z "$opt_tbb" -a -z "$opt_wifi_adhoc" -a -z "$opt_wifi_mesh2g" -a -z "$opt_wifi_mesh5g" -a -z "$opt_vlan" ] && opt_wifi_adhoc='1'

	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)

	if [ "$opt_lan" = "1" ]; then
		$IPT -w -A input_ignore_nodes_lan -s $_ddmesh_nonprimary_ip -j DROP
		$IPT -w -A input_ignore_nodes_wan -s $_ddmesh_nonprimary_ip -j DROP
	fi
	if [ "$opt_tbb" = "1" ]; then
		$IPT -w -A input_ignore_nodes_tbb -s $_ddmesh_nonprimary_ip -j DROP
	fi
	if [ "$opt_wifi_adhoc" = "1" ]; then
		$IPT -w -A input_ignore_nodes_wifia -s $_ddmesh_nonprimary_ip -j DROP
	fi
	if [ "$opt_wifi_mesh2g" = "1" ]; then
		$IPT -w -A input_ignore_nodes_wifi2m -s $_ddmesh_nonprimary_ip -j DROP
	fi
	if [ "$opt_wifi_mesh5g" = "1" ]; then
		$IPT -w -A input_ignore_nodes_wifi5m -s $_ddmesh_nonprimary_ip -j DROP
	fi
	if [ "$opt_vlan" = "1" ]; then
		$IPT -w -A input_ignore_nodes_vlan -s $_ddmesh_nonprimary_ip -j DROP
	fi

	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
}

setup_ignored_nodes() {
	logger -s -t $TAG "setup_ignored_nodes"

	$IPT -w -N input_ignore_nodes_wifia
	$IPT -w -N input_ignore_nodes_wifi2m
	$IPT -w -N input_ignore_nodes_wifi5m
	$IPT -w -N input_ignore_nodes_lan
	$IPT -w -N input_ignore_nodes_wan
	$IPT -w -N input_ignore_nodes_vlan
	$IPT -w -N input_ignore_nodes_tbb # fastd+wg

	# use uci to get ifname because "ubus call" returnes only when interface is detected which is to late for wifi
	wifi_mesh2g_ifname="$(uci -q get wireless.wifi_mesh2g.ifname)"
	wifi_mesh5g_ifname="$(uci -q get wireless.wifi_mesh5g.ifname)"
	mesh_lan_ifname="$(uci -q get network.mesh_lan.device)"
	mesh_wan_ifname="$(uci -q get network.mesh_wan.device)"
	mesh_vlan_ifname="$(uci -q get network.mesh_vlan.device)"
	tbb_wg_ifname="$(uci -q get network.tbb_wg.device)"
	tbb_fastd_ifname="$(uci -q get network.tbb_fastd.device)"

	[ -n "$wifi_mesh2g_ifname" ] && $IPT -w -I input_mesh_rule -i $wifi_mesh2g_ifname -j input_ignore_nodes_wifi2m
	[ -n "$wifi_mesh5g_ifname" ] && $IPT -w -I input_mesh_rule -i $wifi_mesh5g_ifname -j input_ignore_nodes_wifi5m
	[ -n "$mesh_lan_ifname" ] && $IPT -w -I input_mesh_rule -i $mesh_lan_ifname -j input_ignore_nodes_lan
	[ -n "$mesh_wan_ifname" ] && $IPT -w -I input_mesh_rule -i $mesh_wan_ifname -j input_ignore_nodes_wan
	[ -n "$mesh_vlan_ifname" ] && $IPT -w -I input_mesh_rule -i $mesh_vlan_ifname -j input_ignore_nodes_vlan
	[ -n "$tbb_fastd_ifname" ] && $IPT -w -I input_mesh_rule -i $tbb_fastd_ifname -j input_ignore_nodes_tbb
	[ -n "$tbb_wg_ifname" ] && $IPT -w -I input_mesh_rule -i $tbb_wg_ifname -j input_ignore_nodes_tbb


	config_load ddmesh
	config_list_foreach ignore_nodes node callback_add_ignored_nodes
}

update_ignored_nodes() {
	$IPT -w -F input_ignore_nodes_wifia
	$IPT -w -F input_ignore_nodes_wifi2m
	$IPT -w -F input_ignore_nodes_wifi5m
	$IPT -w -F input_ignore_nodes_lan
	$IPT -w -F input_ignore_nodes_wan
	$IPT -w -F input_ignore_nodes_vlan
	$IPT -w -F input_ignore_nodes_tbb

	config_load ddmesh
	config_list_foreach ignore_nodes node callback_add_ignored_nodes
}

_init()
{
	#init all rules that can not be set by openwrt-firewall
	setup_custom_rules
	setup_ignored_nodes
	setup_openvpn_rules
}

_update()
{
	# ips are not valid if iface went down -> clear tables
	# use reject instead of DROP, else it is possible to scan for ip timeout
	$IPT -w -F input_wan_deny
	$IPT -w -F input_lan_deny
	$IPT -w -F input_mesh_deny
	$IPT -w -F input_wifi2_deny
	$IPT -w -F input_bat_deny
	$IPT -w -F input_vpn_deny

	if [ "$lan_up" = "1" -a -n "$lan_network" -a -n "$lan_mask" ]; then
		for n in wan mesh wifi2 bat vpn
		do
			$IPT -w -D "input_"$n"_deny" -d $lan_network/$lan_mask -j reject 2>/dev/null
			$IPT -w -A "input_"$n"_deny" -d $lan_network/$lan_mask -j reject
		done

		# remove/add SNAT rule when iface becomes available
		for cmd in D A
		do
			$IPT -w -t nat -$cmd postrouting_lan_rule -d $lan_ipaddr/$lan_mask -j SNAT --to-source $lan_ipaddr -m comment --comment 'portfw-lan' 2>/dev/null
			$IPT -w -t nat -$cmd postrouting_mesh_rule -s $lan_network/$lan_mask -j SNAT --to-source $_ddmesh_ip -m comment --comment 'lan-to-mesh' 2>/dev/null
		done

		#add rules if gateway is on lan
		if [ -n "$lan_gateway" ]; then
			# remove/add SNAT rule when iface becomes available
			for cmd in D A
			do
				$IPT -w -$cmd forwarding_lan_rule -o $lan_ifname ! -d $lan_ipaddr/$lan_mask -j ACCEPT 2>/dev/null
				$IPT -w -$cmd forwarding_wifi2_rule -o $lan_ifname ! -d $lan_ipaddr/$lan_mask -j ACCEPT 2>/dev/null
				$IPT -w -t nat -$cmd postrouting_lan_rule ! -d $lan_ipaddr/$lan_mask -j SNAT --to-source $lan_ipaddr -m comment --comment 'lan-gateway' 2>/dev/null
			done
		fi

	fi

	if [ "$wan_up" = "1" -a -n "$wan_network" -a -n "$wan_mask" ]; then
		for n in lan mesh wifi2 bat vpn
		do
 			$IPT -w -D "input_"$n"_deny" -d $wan_network/$wan_mask -j reject 2>/dev/null
			$IPT -w -A "input_"$n"_deny" -d $wan_network/$wan_mask -j reject
		done
	fi

	if [ "$wifi2_up" = "1" -a -n "$wifi2_ipaddr" -a -n "$wifi2_mask" ]; then
		# remove/add SNAT rule when iface becomes available
		for cmd in D A
		do
			$IPT -w -t nat -$cmd postrouting_wifi2_rule -d $wifi2_ipaddr/$wifi2_mask -j SNAT --to-source $wifi2_ipaddr -m comment --comment 'portfw-wifi2' 2>/dev/null
		done
	fi

	#update port forwarding on hotplug.d/iface (wan rules)
	/usr/lib/ddmesh/ddmesh-portfw.sh load
}

logger -s -t $TAG "called with $1"
case "$1" in
	init-update)
		_init
		_update
		;;

	firewall-update)
		_update
		;;

	update_ignore) update_ignored_nodes
		;;
	*)
	 	echo "invalid param"
		;;

esac
