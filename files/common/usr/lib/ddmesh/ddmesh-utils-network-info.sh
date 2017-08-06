#!/bin/sh
#$1 -network name
#$2 -variable prefix

test -z "$1" && {
	echo "$0 <list> | <network-name>"
	echo "  network name (wan,wifi,wifi2,tbb,vpn,...) or all"
	exit 1
}

 #json parser functions
 . /usr/share/libubox/jshn.sh

 #get network info as json struct
 ni="$(ubus call network.interface dump)"

 #load json to json parser
 json_load "$ni"

 #search if interface is present
 json_select "interface"
 idx=1
 while true
 do
	#get type to detect end of array
	json_get_type type $idx
	if [ "$type" != "object" ]; then
		break
	fi

	#select first array object
	json_select $idx
	json_get_var net_name "interface"

	#if net_name matches requested network, stay in this entry
	if [ "$net_name" = "$1" -o "$1" = "list" -o "$1" = "all" ]; then
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

		#extract values from json

                json_get_var net_ifname "device"

		if [ "$1" = "list" ]; then
			echo "$net_name:$net_ifname"
			json_select ..
			idx=$(( idx + 1 ))
			continue
		fi	

		if [ -n "$net_ifname" ]; then
			if [ -n "$(cat /proc/net/dev | grep $net_ifname)" ]; then
				net_iface_present=1
			fi
		fi

		json_get_var net_up "up"	# check if physical interface is up. tbb/vpn always down, to avoid automatic netifd handling
		[ "$net_up" = "1" ] && {
			json_get_var net_connect_time "uptime"

			#select object/array;get array entry 1;go one level up
			json_select "dns-server"
			json_get_type type "1"
			if [ "$type" = "string" ]; then
				json_get_var net_dns 1
			fi
			json_select ..

			json_select "ipv4-address"
			json_get_type type "1"
			if [ "$type" = "object" ]; then
				json_select 1
				json_get_var net_ipaddr "address"
				json_get_var net_mask "mask"
				json_select ..
			fi
			json_select ..

			json_select "route"
			json_get_type type "1"
			if [ "$type" = "object" ]; then
				json_select 1
				json_get_var net_gateway "target"
				json_select ..
			fi
			json_select ..

			#calculate rest
			[ -n "$net_ipaddr" ] && {
				eval $(ipcalc.sh $net_ipaddr/$net_mask)
				net_broadcast=$BROADCAST
				net_netmask=$NETMASK
				net_network=$NETWORK
			}
		}

		if [ "$1" = "all" ]; then
			prefix=$net_name
		else
			prefix=${2:-net}
		fi
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
	json_select ..
	idx=$(( idx + 1 ))
 done



