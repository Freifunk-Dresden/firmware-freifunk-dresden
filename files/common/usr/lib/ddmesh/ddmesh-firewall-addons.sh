#!/bin/ash

#firewall rules that can not be created
eval $(/usr/bin/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

IPT=iptables

setup_splash() {
	# prepare splash
	
	WIFIADR=$(uci get ddmesh.network.wifi2_ip)
	eval $(ipcalc.sh $WIFIADR $(uci get ddmesh.network.wifi2_netmask))
	WIFIPRE=$PREFIX
	WIFI_IF=$(uci -P /var/state get network.wifi2.ifname)

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
	$IPT -A SPLASH_PUBLIC_SERVICES -j DROP
	
	$IPT -A forwarding_wifi2_rule -s $WIFIADR/$WIFIPRE -j SPLASH
}

setup_custom_rules() {
# temp firewall rules (fw uci can not add custom chains)

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

        eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh lan lan)
        eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi2 wifi2)

        #snat tbb and wifi fro 10.201.xxx to 10.200.xxxx
        $IPT -t nat -A postrouting_wifi_rule -p udp --dport 4305:4307 -j ACCEPT
        $IPT -t nat -A postrouting_wifi_rule -p tcp --dport 4305:4307 -j ACCEPT
        $IPT -t nat -A postrouting_wifi_rule -s $lan_ipaddr/$lan_mask -j SNAT --to-source $_ddmesh_ip
        $IPT -t nat -A postrouting_wifi_rule -s $wifi2_ipaddr/$wifi2_mask -j SNAT --to-source $_ddmesh_ip

        $IPT -t nat -A postrouting_tbb_rule -p udp --dport 4305:4307 -j ACCEPT
        $IPT -t nat -A postrouting_tbb_rule -p tcp --dport 4305:4307 -j ACCEPT
        $IPT -t nat -A postrouting_tbb_rule -s $lan_ipaddr/$lan_mask -j SNAT --to-source $_ddmesh_ip
        $IPT -t nat -A postrouting_tbb_rule -s $wifi2_ipaddr/$wifi2_mask -j SNAT --to-source $_ddmesh_ip

	#add rules if gateway is on lan
	if [ -n "$lan_gateway" ]; then
		$IPT -A forwarding_bat_rule -o $lan_device ! -d $lan_ipaddr/$lan_mask -j ACCEPT
		$IPT -t nat -A postrouting_lan_rule ! -d $lan_ipaddr/$lan_mask -j SNAT --to-source $lan_ipaddr -m comment --comment 'LAN gateway'
	fi
}

case "$1" in
	once)
		#init all rules that can not be set by openwrt-firewall
		test "$(uci get ddmesh.system.disable_splash 2>/dev/null)" != "1" && setup_splash
		;;
	post)
		setup_custom_rules
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

		eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh lan)
		if [ "$net_up" = "1" ]; then
			$IPT -A input_wan_deny -d $net_network/$net_mask -j reject 
			$IPT -A input_wifi_deny -d $net_network/$net_mask -j reject 
			$IPT -A input_wifi2_deny -d $net_network/$net_mask -j reject 
			$IPT -A input_tbb_deny -d $net_network/$net_mask -j reject 
			$IPT -A input_bat_deny -d $net_network/$net_mask -j reject 
			$IPT -A input_vpn_deny -d $net_network/$net_mask -j reject 
		fi

		eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wan)
		if [ "$net_up" = "1" ]; then
			$IPT -A input_lan_deny -d $net_network/$net_mask -j reject 
			$IPT -A input_wifi_deny -d $net_network/$net_mask -j reject 
			$IPT -A input_wifi2_deny -d $net_network/$net_mask -j reject
			$IPT -A input_tbb_deny -d $net_network/$net_mask -j reject
			$IPT -A input_bat_deny -d $net_network/$net_mask -j reject
			$IPT -A input_vpn_deny -d $net_network/$net_mask -j reject
		fi
		;;

esac




