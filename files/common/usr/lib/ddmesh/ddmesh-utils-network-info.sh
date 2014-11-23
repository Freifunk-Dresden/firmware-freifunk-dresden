#!/bin/sh
#$1 -network name
#$2 -varialbe prefix

test -z "$1" && {
	echo "network name missing (wan,wifi,wifi2,tbb,...)"
	exit 1
}

 #json parser functions
 . /usr/share/libubox/jshn.sh

 #get network info as json struct
 ni="$(ubus call network.interface.$1 status)"

 #load json to json parser
 json_load "$ni"

 #extract values from json
 json_get_var net_device "device" # always valid if router has WAN port
 json_get_var net_up "up"
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
		json_get_var net_gateway "nexthop"
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

prefix=${2:-net} 
echo $prefix"_mask=$net_mask"
echo $prefix"_ipaddr=$net_ipaddr"
echo $prefix"_netmask=$net_netmask"
echo $prefix"_broadcast=$net_broadcast"
echo $prefix"_gateway=$net_gateway"
echo $prefix"_dns=$net_dns"
echo $prefix"_connect_time=$net_connect_time"
echo $prefix"_device=$net_device"
echo $prefix"_up=$net_up"
echo $prefix"_network=$net_network"

