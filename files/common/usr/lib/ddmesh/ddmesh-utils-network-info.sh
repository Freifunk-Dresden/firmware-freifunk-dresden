#!/bin/sh
#$1 -network name
#$2 -variable prefix

test -z "$1" && {
	echo "$0 <list> | <network-name>"
	echo "  network name (wan,wifi,wifi2,mesh_lan,mesh_wan,vpn,...) or all"
	exit 1
}

 #get network info as json struct and rename key (workaround for jsonfilter)
 json="$(ubus call network.interface dump | sed 's#ipv\([46]\)-address#ipv\1_address#g;s#dns-server#dns_server#g')"

 idx=0
 while true
 do

	ifdata=$(echo "$json" | jsonfilter  -e "@.interface[$idx]")
	if [ -z "$ifdata" ]; then
		break
	fi

	unset net_name
	unset net_iface_present
	unset net_mask
	unset net_ipaddr
	unset net_netmask
	unset net_broadcast
	unset net_gateway
	unset net_dns
	unset net_connect_time
	unset net_ifname
	unset net_up
	unset net_network

	eval $(echo "$ifdata" | jsonfilter \
		-e net_name='@.interface' \
		-e net_ifname='@.device' \
		-e net_up='@.up' \
		-e net_connect_time='@.uptime' \
		-e net_dns='@.dns_server[0]' \
		-e net_ipaddr='@.ipv4_address[0].address' \
		-e net_mask='@.ipv4_address[0].mask' \
		-e net_gateway='@.route[0].target' \
	)

	#if net_name matches requested network, stay in this entry
	if [ "$net_name" = "$1" -o "$1" = "list" -o "$1" = "all" ]; then

		if [ "$1" = "list" ]; then
			echo "$net_name:$net_ifname"
			continue
		fi	

		if [ -n "$net_ifname" ]; then
			if [ -n "$(cat /proc/net/dev | grep $net_ifname)" ]; then
				net_iface_present=1
			fi
		fi

		#calculate rest
		[ "$net_up" = "1" ] &&  [ -n "$net_ipaddr" ] && {
				eval $(ipcalc.sh $net_ipaddr/$net_mask)
				net_broadcast=$BROADCAST
				net_netmask=$NETMASK
				net_network=$NETWORK
		}

		if [ "$1" = "all" ]; then
			prefix=$net_name
		else
			prefix=${2:-net}
		fi

		# replace "-" with "_" to allow network names with "-" in there names
		# but have valid variable names
		prefix=${prefix/-/_}

		echo export $prefix"_iface_present=$net_iface_present"
		echo export $prefix"_mask=$net_mask"
		echo export $prefix"_ipaddr=$net_ipaddr"
		echo export $prefix"_netmask=$net_netmask"
		echo export $prefix"_broadcast=$net_broadcast"
		echo export $prefix"_gateway=$net_gateway"
		echo export $prefix"_dns=$net_dns"
		echo export $prefix"_connect_time=$net_connect_time"
		echo export $prefix"_ifname=$net_ifname"
		echo export $prefix"_up=$net_up"
		echo export $prefix"_network=$net_network"
#geht nicht mit allen
#		echo export $prefix"_device=$(uci -P /var/state get network.$1.device)"

	fi
	idx=$(( idx + 1 ))
 done



