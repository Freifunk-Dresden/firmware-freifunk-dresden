#!/bin/ash

. /lib/functions.sh

#firewall rules that can not be created
eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)

fwprint()
{
 #echo iptables $*
 iptables -w $*
}

export IPT=fwprint


setup_splash() {
	# prepare splash

	WIFIADR=$_ddmesh_wifi2ip
	eval $(ipcalc.sh $WIFIADR $_ddmesh_wifi2netmask)
	WIFIPRE=$PREFIX

	# table: nat
	$IPT -t nat -N SPLASH
	$IPT -t nat -N SPLASH_AUTH_USERS
	$IPT -t nat -N SPLASH_PUBLIC_SERVICES
	$IPT -t nat -A SPLASH -j SPLASH_AUTH_USERS
	$IPT -t nat -A SPLASH_AUTH_USERS -j SPLASH_PUBLIC_SERVICES

	$IPT -t nat -A SPLASH_AUTH_USERS -p tcp --dport 80 -j DNAT --to $WIFIADR:81
	#force any manuell configured dns to this local dns
	$IPT -t nat -A SPLASH_AUTH_USERS -p udp --dport 53 -j DNAT --to $WIFIADR:53

	$IPT -t nat -A prerouting_wifi2_rule -s $WIFIADR/$WIFIPRE -j SPLASH

	# table: filter
	$IPT -N SPLASH
	$IPT -N SPLASH_AUTH_USERS
	$IPT -N SPLASH_PUBLIC_SERVICES

	$IPT -A SPLASH -j SPLASH_AUTH_USERS
	$IPT -A SPLASH_AUTH_USERS -j SPLASH_PUBLIC_SERVICES
	$IPT -A SPLASH_PUBLIC_SERVICES -p icmp -j RETURN
	$IPT -A SPLASH_PUBLIC_SERVICES -p udp -j REJECT --reject-with icmp-port-unreachable
	$IPT -A SPLASH_PUBLIC_SERVICES -p tcp -j REJECT --reject-with tcp-reset
	$IPT -A SPLASH_PUBLIC_SERVICES -j DROP

	#$IPT -A forwarding_wifi2_rule -s $WIFIADR/$WIFIPRE -j SPLASH
	#before iptable rule ctstate ESTABLISHED
	$IPT -A forwarding_rule -i $wifi2_ifname -s $WIFIADR/$WIFIPRE -j SPLASH
}

setup_custom_rules() {
# temp firewall rules (fw uci can not add custom chains)

	# gateway check
	$IPT -t mangle -N output_gateway_check
	$IPT -t mangle -A OUTPUT -p icmp -j output_gateway_check

	#input rules for backbone/firewall ( to restrict tunnel pakets only via allowed interfaces )
	#tbb traffic is controlled by zone rules tbb+
	$IPT -N input_backbone_accept
	$IPT -N input_backbone_reject
	$IPT -A input_wan_rule -j input_backbone_accept
	$IPT -A input_lan_rule -j input_backbone_accept
	$IPT -A input_tbb_rule -j input_backbone_reject
	$IPT -A input_bat_rule -j input_backbone_reject
	$IPT -A input_wifi_rule -j input_backbone_reject
	$IPT -A input_wifi2_rule -j input_backbone_reject

	$IPT -N output_backbone_accept
	$IPT -N output_backbone_reject
	$IPT -A output_wan_rule -j output_backbone_accept
	$IPT -A output_lan_rule -j output_backbone_accept
	$IPT -A output_tbb_rule -j output_backbone_reject
	$IPT -A output_bat_rule -j output_backbone_reject
	$IPT -A output_wifi_rule -j output_backbone_reject
	$IPT -A output_wifi2_rule -j output_backbone_reject

	#input rules for privnet/ifirewall ( to restrict tunnel pakets only via allowed interfaces )
	#private data traffic is controlled by zone rules lan (br-lan)
	$IPT -N input_privnet_accept
	$IPT -N input_privnet_reject
	$IPT -A input_wan_rule -j input_privnet_reject
	$IPT -A input_lan_rule -j input_privnet_reject
	$IPT -A input_tbb_rule -j input_privnet_accept
	$IPT -A input_bat_rule -j input_privnet_reject
	$IPT -A input_wifi_rule -j input_privnet_accept
	$IPT -A input_wifi2_rule -j input_privnet_reject

	#add rules to avoid access node via lan/wan ip; insert at start
	#to consider other tables (backbone)
	# loop through zones
	for i in wifi wifi2 tbb bat lan wan vpn
	do
	        $IPT -N input_"$i"_deny
	        $IPT -I input_"$i"_rule -j input_"$i"_deny
	done

	# allow dhcp because "subnet" definition. client has no ip yet.
	$IPT -A input_rule -i $wifi2_ifname -p udp --dport 67 -j ACCEPT -m comment --comment 'dhcp-wifi2-request'
	$IPT -A output_rule -o $wifi2_ifname -p udp --dport 68 -j ACCEPT -m comment --comment 'dhcp-wifi2-response'
	$IPT -A input_rule -i $lan_ifname -p udp --dport 67 -j ACCEPT -m comment --comment 'dhcp-lan-request'
	$IPT -A output_rule -o $lan_ifname -p udp --dport 68 -j ACCEPT -m comment --comment 'dhcp-lan-response'

	#snat tbb and wifi fro 10.201.xxx to 10.200.xxxx
	$IPT -t nat -A postrouting_wifi_rule -p udp --dport 4305:4307 -j ACCEPT
	$IPT -t nat -A postrouting_wifi_rule -p tcp --dport 4305:4307 -j ACCEPT
	test "$lan_up" = "1" && $IPT -t nat -A postrouting_wifi_rule -s $lan_ipaddr/$lan_mask -j SNAT --to-source $_ddmesh_ip
	test "$wifi2_up" = "1" && $IPT -t nat -A postrouting_wifi_rule -s $wifi2_ipaddr/$wifi2_mask -j SNAT --to-source $_ddmesh_ip

	$IPT -t nat -A postrouting_tbb_rule -p udp --dport 4305:4307 -j ACCEPT
	$IPT -t nat -A postrouting_tbb_rule -p tcp --dport 4305:4307 -j ACCEPT
	test "$lan_up" = "1" && $IPT -t nat -A postrouting_tbb_rule -s $lan_ipaddr/$lan_mask -j SNAT --to-source $_ddmesh_ip
	test "$wifi2_up" = "1" && $IPT -t nat -A postrouting_tbb_rule -s $wifi2_ipaddr/$wifi2_mask -j SNAT --to-source $_ddmesh_ip

	test "$lan_up" = "1" && $IPT -t nat -A postrouting_lan_rule -d $lan_ipaddr/$lan_mask -j SNAT --to-source $lan_ipaddr -m comment --comment 'portfw-lan'
	test "$wifi2_up" = "1" && $IPT -t nat -A postrouting_wifi2_rule -d $wifi2_ipaddr/$wifi2_mask -j SNAT --to-source $wifi2_ipaddr -m comment --comment 'portfw-wifi2'

	#add rules if gateway is on lan
	if [ -n "$lan_gateway" -a "$lan_up" = "1" ]; then
		$IPT -A forwarding_bat_rule -o $lan_ifname ! -d $lan_ipaddr/$lan_mask -j ACCEPT
		$IPT -A forwarding_wifi2_rule -o $lan_ifname ! -d $lan_ipaddr/$lan_mask -j ACCEPT
		$IPT -t nat -A postrouting_lan_rule ! -d $lan_ipaddr/$lan_mask -j SNAT --to-source $lan_ipaddr -m comment --comment 'lan-gateway'
	fi
}

setup_openvpn_rules() {

	CONF=/etc/openvpn/openvpn.conf
	$IPT -N output_openvpn_reject
	$IPT -A output_tbb_rule -j output_openvpn_reject
	$IPT -A output_bat_rule -j output_openvpn_reject
	$IPT -A output_wifi_rule -j output_openvpn_reject
	$IPT -A output_wifi2_rule -j output_openvpn_reject
	$IPT -A output_vpn_rule -j output_openvpn_reject

	IFS='
'
	if [ -f "$CONF" ]; then
		for opt in $(cat $CONF | awk '/remote/{print $4","$3}')
		do
			proto=${opt%,*}
			port=${opt#*,}
			$IPT -A output_openvpn_reject -p $proto --dport $port -j reject
		done
	fi
	unset IFS
}

setup_statistic_rules() {


	$IPT -N statistic
	$IPT -F statistic
	$IPT -D input_rule -j statistic 2>/dev/null
	$IPT -D forwarding_rule -j statistic 2>/dev/null
	$IPT -D output_rule -j statistic 2>/dev/null

	$IPT -A input_rule -j statistic
	$IPT -A forwarding_rule -j statistic
	$IPT -A output_rule -j statistic

	$IPT -N statistic_bat_input
	$IPT -A statistic -i $bat_ifname -j statistic_bat_input
	$IPT -N statistic_bat_output
	$IPT -A statistic -o $bat_ifname -j statistic_bat_output

	$IPT -N statistic_wan_input
	$IPT -A statistic -i $wan_ifname -j statistic_wan_input
	$IPT -N statistic_wan_output
	$IPT -A statistic -o $wan_ifname -j statistic_wan_output

	$IPT -N statistic_lan_input
	$IPT -A statistic -i $lan_ifname -j statistic_lan_input
	$IPT -N statistic_lan_output
	$IPT -A statistic -o $lan_ifname -j statistic_lan_output

	$IPT -N statistic_wifi_input
	$IPT -A statistic -i $wifi_ifname -j statistic_wifi_input
	$IPT -N statistic_wifi_output
	$IPT -A statistic -o $wifi_ifname -j statistic_wifi_output

	$IPT -N statistic_wifi2_input
	$IPT -A statistic -i $wifi2_ifname -j statistic_wifi2_input
	$IPT -N statistic_wifi2_output
	$IPT -A statistic -o $wifi2_ifname -j statistic_wifi2_output

	$IPT -N statistic_vpn_input
	$IPT -A statistic -i $vpn_ifname -j statistic_vpn_input
	$IPT -N statistic_vpn_output
	$IPT -A statistic -o $vpn_ifname -j statistic_vpn_output
}

callback_add_ignored_nodes() {
	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $1)
	$IPT -A input_ignore_nodes -s $_ddmesh_nonprimary_ip -j DROP
}

setup_ignored_nodes() {

	#add rules to deny some nodes to prefer backbone connections
	$IPT -N input_ignore_nodes
	$IPT -I input_wifi_rule -j input_ignore_nodes

	config_load ddmesh
	config_list_foreach ignore_nodes node callback_add_ignored_nodes
}


case "$1" in
	once)
		#init all rules that can not be set by openwrt-firewall
		test "$(uci get ddmesh.system.disable_splash 2>/dev/null)" != "1" && setup_splash
		;;
	post)
		setup_custom_rules
		setup_statistic_rules
		setup_ignored_nodes
		setup_openvpn_rules
		;;

	#hotplug.d event after which wan/lan have ip addresses assigned
	update)
		# ips are not valid if iface went down -> clear tables
		# use reject instead of DROP, else it is possible to scan for ip timeout
		$IPT -F input_wan_deny
		$IPT -F input_wifi_deny
		$IPT -F input_wifi2_deny
		$IPT -F input_tbb_deny
		$IPT -F input_bat_deny
		$IPT -F input_vpn_deny

		if [ "$lan_up" = "1" ]; then
			$IPT -A input_wan_deny -d $lan_network/$lan_mask -j reject
			$IPT -A input_wifi_deny -d $lan_network/$lan_mask -j reject
			$IPT -A input_wifi2_deny -d $lan_network/$lan_mask -j reject
			$IPT -A input_tbb_deny -d $lan_network/$lan_mask -j reject
			$IPT -A input_bat_deny -d $lan_network/$lan_mask -j reject
			$IPT -A input_vpn_deny -d $lan_network/$lan_mask -j reject
		fi

		if [ "$wan_up" = "1" ]; then
			$IPT -A input_lan_deny -d $wan_network/$wan_mask -j reject
			$IPT -A input_wifi_deny -d $wan_network/$wan_mask -j reject
			$IPT -A input_wifi2_deny -d $wan_network/$wan_mask -j reject
			$IPT -A input_tbb_deny -d $wan_network/$wan_mask -j reject
			$IPT -A input_bat_deny -d $wan_network/$wan_mask -j reject
			$IPT -A input_vpn_deny -d $wan_network/$wan_mask -j reject
		fi

		#update port forwarding on hotplug.d/iface (wan rules)
		/usr/lib/ddmesh/ddmesh-portfw.sh init
		;;

esac


