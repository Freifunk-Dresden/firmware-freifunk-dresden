#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

if [ -z "$1" ]; then
	echo "usage $(basename $0) init-update | firewall-update | update-ignore"
	exit 1
fi

. /lib/functions.sh

#firewall rules that can not be created
eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

/usr/lib/ddmesh/ddmesh-utils-network-info.sh update
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)

TAG="ddmesh-firewall-addons.sh"

fwprint()
{
 logger -s -t "$TAG" "nft $*"
 nft $*
}

export NFT=fwprint
#export NFT=nft

export CHAIN_NAME="ddmesh_ignore_nodes"

setup_ipv6_rules()
{
	logger -s -t $TAG "setup_ipv6_rules"

	# block any ipv6
	for chain in input forward output
	do
		# insert chains in standard chains (input,output,forward)
		$NFT insert rule inet fw4 "$chain" position 0 meta l4proto ipv6 counter drop comment '"block ipv6"'
	done
}

setup_custom_rules() {
# temp firewall rules (fw uci can not add custom chains)
	logger -s -t $TAG "setup_custom_rules"



#---------
	# remove "ctstate RELATED,ESTABLISHED" rule from OUTPUT, as this accepts packets (e.g. wireguard)
	# where firewall is not ready yet, but a packet gets out because rules not yet fully setup.
	# backbone/vpn can setup connections through freifunk network.
#	$NFT -w -D OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment '!fw3'


	#input rules for privnet packets( to restrict tunnel pakets only via allowed interfaces )
	#private data traffic is controlled by zone rules lan (br-lan)
#	$NFT -w -N input_privnet_accept
#	$NFT -w -N input_privnet_reject
#	$NFT -w -A input_wan_rule -j input_privnet_reject -m comment --comment 'ddmesh:privnet'
#	$NFT -w -A input_lan_rule -j input_privnet_reject -m comment --comment 'ddmesh:privnet'
#	$NFT -w -A input_mesh_rule -j input_privnet_accept -m comment --comment 'ddmesh:privnet'
#	$NFT -w -A input_ffgw_rule -j input_privnet_reject -m comment --comment 'ddmesh:privnet'
#	$NFT -w -A input_wifi2_rule -j input_privnet_reject -m comment --comment 'ddmesh:privnet'

	#add tables that are later filled with IPs that should be blocked.
	# loop through zones
	for i in mesh wifi2 ffgw lan wan vpn
	do
	        $NFT -w -N input_"$i"_deny
	        $NFT -w -I input_"$i"_rule -j input_"$i"_deny -m comment --comment 'ddmesh'
	done

	# allow dhcp because "subnet" definition. client has no ip yet.
	# $NFT -w -A input_rule -i $wifi2_ifname -p udp --dport 67 -j ACCEPT -m comment --comment 'dhcp-wifi2-request'
	# $NFT -w -A output_rule -o $wifi2_ifname -p udp --dport 68 -j ACCEPT -m comment --comment 'dhcp-wifi2-response'
	# $NFT -w -A input_rule -i $lan_ifname -p udp --dport 67 -j ACCEPT -m comment --comment 'dhcp-lan-request'
	# $NFT -w -A output_rule -o $lan_ifname -p udp --dport 68 -j ACCEPT -m comment --comment 'dhcp-lan-response'

	#snat mesh from 10.201.xxx to 10.200.xxxx
	$NFT -w -t nat -A postrouting_mesh_rule -p udp --dport 4305 -j ACCEPT -m comment --comment 'ddmesh:bmxd'
	$NFT -w -t nat -A postrouting_mesh_rule -p tcp --dport 4305 -j ACCEPT -m comment --comment 'ddmesh:bmxd'
	# don't snat icmp to debug tbb links with ping (MUST come after other rules bufgix:#57)
	$NFT -w -t nat -A postrouting_mesh_rule -s $_ddmesh_fullnet -p icmp -j ACCEPT -m comment --comment 'ddmesh:ping'
	$NFT -w -t nat -A postrouting_mesh_rule -s $_ddmesh_linknet -j SNAT --to-source $_ddmesh_ip -m comment --comment 'ddmesh:snat'
	$NFT -w -t nat -A postrouting_mesh_rule -s $_ddmesh_wifi2net -j SNAT --to-source $_ddmesh_ip -m comment --comment 'ddmesh:snat'
}

callback_add_ignored_nodes() {
	local entry="$1"
	IFS=':'
	set $entry
	unset IFS
	local node=$1
	local opt_lan=$2
	local opt_tbb=$3
	local opt_wifi_mesh2g=$5
	local opt_wifi_mesh5g=$6
	local opt_vlan=$7

	# if no flag is set, only node is given (old format)
	# -> enable wifi only

	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)

	if [ "$opt_lan" = "1" ]; then
		$NFT -w -A input_ignore_nodes_lan -s $_ddmesh_nonprimary_ip -j DROP -m comment --comment 'ddmesh:ignore-nodes'
		$NFT -w -A input_ignore_nodes_wan -s $_ddmesh_nonprimary_ip -j DROP -m comment --comment 'ddmesh:ignore-nodes'
	fi
	if [ "$opt_tbb" = "1" ]; then
		$NFT -w -A input_ignore_nodes_tbb -s $_ddmesh_nonprimary_ip -j DROP -m comment --comment 'ddmesh:ignore-nodes'
	fi
	if [ "$opt_wifi_mesh2g" = "1" ]; then
		$NFT -w -A input_ignore_nodes_wifi2m -s $_ddmesh_nonprimary_ip -j DROP -m comment --comment 'ddmesh:ignore-nodes'
	fi
	if [ "$opt_wifi_mesh5g" = "1" ]; then
		$NFT -w -A input_ignore_nodes_wifi5m -s $_ddmesh_nonprimary_ip -j DROP -m comment --comment 'ddmesh:ignore-nodes'
	fi
	if [ "$opt_vlan" = "1" ]; then
		$NFT -w -A input_ignore_nodes_vlan -s $_ddmesh_nonprimary_ip -j DROP -m comment --comment 'ddmesh:ignore-nodes'
	fi

	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
}

setup_ignored_nodes() {
	logger -s -t $TAG "setup_ignored_nodes"

	$NFT -w -N input_ignore_nodes_wifi2m
	$NFT -w -N input_ignore_nodes_wifi5m
	$NFT -w -N input_ignore_nodes_lan
	$NFT -w -N input_ignore_nodes_wan
	$NFT -w -N input_ignore_nodes_vlan
	$NFT -w -N input_ignore_nodes_tbb # fastd+wg

	# use uci to get ifname because "ubus call" returnes only when interface is detected which is to late for wifi
	wifi_mesh2g_ifname="$(uci -q get wireless.wifi_mesh2g.ifname)"
	wifi_mesh5g_ifname="$(uci -q get wireless.wifi_mesh5g.ifname)"
	mesh_lan_ifname="$(uci -q get network.mesh_lan.device)"
	mesh_wan_ifname="$(uci -q get network.mesh_wan.device)"
	mesh_vlan_ifname="$(uci -q get network.mesh_vlan.device)"
	tbb_wg_ifname="$(uci -q get network.tbb_wg.device)"
	tbb_fastd_ifname="$(uci -q get network.tbb_fastd.device)"

	[ -n "$wifi_mesh2g_ifname" ] && $NFT -w -I input_mesh_rule -i $wifi_mesh2g_ifname -j input_ignore_nodes_wifi2m -m comment --comment 'ddmesh:ignore-nodes'
	[ -n "$wifi_mesh5g_ifname" ] && $NFT -w -I input_mesh_rule -i $wifi_mesh5g_ifname -j input_ignore_nodes_wifi5m -m comment --comment 'ddmesh:ignore-nodes'
	[ -n "$mesh_lan_ifname" ] && $NFT -w -I input_mesh_rule -i $mesh_lan_ifname -j input_ignore_nodes_lan -m comment --comment 'ddmesh:ignore-nodes'
	[ -n "$mesh_wan_ifname" ] && $NFT -w -I input_mesh_rule -i $mesh_wan_ifname -j input_ignore_nodes_wan -m comment --comment 'ddmesh:ignore-nodes'
	[ -n "$mesh_vlan_ifname" ] && $NFT -w -I input_mesh_rule -i $mesh_vlan_ifname -j input_ignore_nodes_vlan -m comment --comment 'ddmesh:ignore-nodes'
	[ -n "$tbb_fastd_ifname" ] && $NFT -w -I input_mesh_rule -i $tbb_fastd_ifname -j input_ignore_nodes_tbb -m comment --comment 'ddmesh:ignore-nodes'
	[ -n "$tbb_wg_ifname" ] && $NFT -w -I input_mesh_rule -i $tbb_wg_ifname -j input_ignore_nodes_tbb -m comment --comment 'ddmesh:ignore-nodes'


	config_load ddmesh
	config_list_foreach ignore_nodes node callback_add_ignored_nodes
}

update_ignored_nodes() {
	$NFT -w -F input_ignore_nodes_wifi2m
	$NFT -w -F input_ignore_nodes_wifi5m
	$NFT -w -F input_ignore_nodes_lan
	$NFT -w -F input_ignore_nodes_wan
	$NFT -w -F input_ignore_nodes_vlan
	$NFT -w -F input_ignore_nodes_tbb

	config_load ddmesh
	config_list_foreach ignore_nodes node callback_add_ignored_nodes
}

_init()
{
	#init all rules that can not be set by openwrt-firewall
	setup_ipv6_rules
	#setup_custom_rules
	#
	setup_ignored_nodes
}

_update()
{
	# ips are not valid if iface went down -> clear tables
	# use reject instead of DROP, else it is possible to scan for ip timeout
	$NFT -w -F input_wan_deny
	$NFT -w -F input_lan_deny
	$NFT -w -F input_mesh_deny
	$NFT -w -F input_wifi2_deny
	$NFT -w -F input_ffgw_deny
	$NFT -w -F input_vpn_deny

	if [ "$lan_up" = "1" -a -n "$lan_network" -a -n "$lan_mask" ]; then
		for n in wan mesh wifi2 ffgw vpn
		do
			for cmd in D A
			do
				$NFT -w -$cmd "input_"$n"_deny" -d $lan_network/$lan_mask -j reject -m comment --comment 'ddmesh' 2>/dev/null
			done
		done

		# remove/add SNAT rule when iface becomes available
		for cmd in D A
		do
			$NFT -w -t nat -$cmd postrouting_lan_rule -d $lan_ipaddr/$lan_mask -j SNAT --to-source $lan_ipaddr -m comment --comment 'ddmesh:snat:lan' 2>/dev/null
			$NFT -w -t nat -$cmd postrouting_mesh_rule -s $lan_network/$lan_mask -j SNAT --to-source $_ddmesh_ip -m comment --comment 'ddmesh:snat:mesh' 2>/dev/null
		done
	fi

	if [ "$wan_up" = "1" -a -n "$wan_network" -a -n "$wan_mask" ]; then
		for n in lan mesh wifi2 ffgw vpn
		do
			for cmd in D A
			do
				$NFT -w -$cmd "input_"$n"_deny" -d $wan_network/$wan_mask -j reject  -m comment --comment 'ddmesh' 2>/dev/null
			done
		done
	fi

	if [ "$wifi2_up" = "1" -a -n "$wifi2_ipaddr" -a -n "$wifi2_mask" ]; then
		# remove/add SNAT rule when iface becomes available
		for cmd in D A
		do
			$NFT -w -t nat -$cmd postrouting_wifi2_rule -d $wifi2_ipaddr/$wifi2_mask -j SNAT --to-source $wifi2_ipaddr -m comment --comment 'ddmesh:snat:wifi2' 2>/dev/null
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

	update-ignore)
		update_ignored_nodes
		;;
	*)
		echo "invalid arg"
		;;

esac
