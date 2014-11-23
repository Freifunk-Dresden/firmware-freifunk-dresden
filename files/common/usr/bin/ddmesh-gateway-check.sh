#!/bin/ash
#usage: gateway-check.sh 

ip_rule_priority=98
ip_rule_priority_unreachable=99
DEBUG=true

setup_gateway_table ()
{
	dev=$1
	via=$2
	gateway_table=$3
	
	#redirect gateway ip directly to gateway interface
	ip route add $via/32 dev $dev table $gateway_table 2>/dev/null
	
	#jump over private ranges
	ip route add throw 10.0.0.0/8 table $gateway_table 2>/dev/null
	eval $(ipcalc.sh $(uci get network.lan.ipaddr) $(uci get network.lan.netmask))
	ip route add throw $NETWORK/$PREFIX table $gateway_table 2>/dev/null

	#batman uses 169.254.0.0/16 for gateway tunnel
	ip route add throw 169.254.0.0/16 table $gateway_table 2>/dev/null

	#add default route
	ip route add default via $via dev $dev table $gateway_table  
}

#kill running instance
mypid=$$
pname=${0##*/}
IFS=' '
echo	$pname,$mypid
for i in $(pidof $pname)
do
  test "$i" != "$mypid" && echo kill $i && kill -9 $i
done

$DEBUG && echo "start"

#dont use vpn server (or any openvpn server), it could interrupt connection
ping_hosts="8.8.8.8 88.198.196.6 84.38.79.202 204.79.197.200"
#process max 3 user ping
cfg_ping="$(uci -q get ddmesh.network.gateway_check_ping)"
gw_ping="$(echo "$cfg_ping" | sed 's#[ ,;/	]\+# #g' | cut -d' ' -f1-3 ) $ping_hosts"
$DEBUG && echo "hosts:[$gw_ping]"

#determine all possible gateways

test "$(uci -P /var/state get network.wan.up)" = "1" && {
	default_wan_ifname=$(uci -P /var/state get network.wan.ifname)
	default_wan_gateway=$(ip route | sed -n "/default via [0-9.]\+ dev $default_wan_ifname/{s#.*via \([0-9.]\+\).*#\1#p}")
	if [ -n "$default_wan_gateway" -a -n "$default_wan_ifname" ]; then
		wan_default_route="$default_wan_gateway:$default_wan_ifname"
	fi
}
echo "WAN:$default_wan_ifname via $default_wan_gateway"

test "$(uci -P /var/state get network.lan.up)" = "1" && {
	default_lan_ifname=$(uci -P /var/state get network.lan.ifname)
	default_lan_gateway=$(uci -P /var/state get network.lan.gateway 2>/dev/null)
	if [ -n "$default_lan_gateway" -a -n "$default_lan_ifname" ]; then
		lan_default_route="$default_lan_gateway:$default_lan_ifname"
	fi
}
echo "LAN:$default_lan_ifname via $default_lan_gateway"

test "$(uci -P /var/state get network.vpn.up)" = "1" && {
	_ifname=$(uci get network.vpn.ifname | sed 's#+##')
	default_vpn_ifname=$(ip route | sed -n "/default via [0-9.]\+ dev $_ifname/{s#.*dev \([^ 	]\+\).*#\1#p}")
	default_vpn_gateway=$(ip route | sed -n "/default via [0-9.]\+ dev $_ifname/{s#.*via \([0-9.]\+\).*#\1#p}")
	if [ -n "$default_vpn_gateway" -a -n "$default_vpn_ifname" ]; then
		vpn_default_route="$default_vpn_gateway:$default_vpn_ifname"
	fi
}
echo "VPN:$default_vpn_ifname via $default_vpn_gateway"

#try each gateway
ok=false
IFS=' '
#start with vpn, because this is prefered gateway, then WAN and lates LAN
#(there is no forwarding to lan allowed by firewall)
for g in $vpn_default_route $wan_default_route $lan_default_route
do
	$DEBUG && echo "try: $g"
	dev=${g#*:}
	via=${g%:*}
 
	$DEBUG && echo "via=$via, dev=$dev"

	#add ping rule before all others;only pings from this host (no forwards) 
	ip rule del iif lo priority $ip_rule_priority table ping 2>/dev/null
	ip rule add iif lo priority $ip_rule_priority table ping
	ip rule del iif lo priority $ip_rule_priority_unreachable table ping_unreachable 2>/dev/null
	ip rule add iif lo priority $ip_rule_priority_unreachable table ping_unreachable

	#no check of gateway, it might not return icmp reply, also
	#it might not be reachable because of routing rules 
		
	#add ping hosts to special ping table
	ip route flush table ping
	ip route flush table ping_unreachable
	IFS=' '
	for ip in $gw_ping
	do
		$DEBUG && echo "add ping route ip:$ip"
		ip route add $ip via $via dev $dev table ping
		ip route add unreachable $ip table ping_unreachable
	done
	
	#activate routes
	ip route flush cache

	$DEBUG && {
		echo "---rules---"
		ip rule
		echo "---table ping ---"
		ip ro list table ping
		echo "------"
	}

	#run check
	ok=false
	IFS=' '
	for ip in $gw_ping
	do
		$DEBUG && echo "ping to: $ip"
		ping -c 2 -w 10 $ip  2>&1 && ok=true && break
	done
	if $ok; then
	
		$DEBUG && echo "gateway found: via $via dev $dev table $gateway_table (lan dev: $default_lan_ifname)"
		
		#always add wan or lan to local gateway
		#local_gateway MUST come before public_gateway 
		if [ "$dev" = "$default_lan_ifname" -o "$dev" = "$default_wan_ifname" ]; then	
			#redirect gateway ip directly to gateway interface
			ip route flush table local_gateway 2>/dev/null
			setup_gateway_table $dev $via local_gateway
			/usr/lib/ddmesh/ddmesh-bmxd.sh no_gateway
			break;
		fi
		
		# Add any gateway to public table if internet was enabled.
		# If internet is disabled, add only vpn if detected.
		# When lan/wan gateway gets lost, also vpn get lost and new gateways are detected
		
		if [ "$(uci -q get ddmesh.system.disable_gateway)" != "1" -o "$dev" = "$default_vpn_ifname" ]; then
			#redirect gateway ip directly to gateway interface
			ip route flush table public_gateway 2>/dev/null
			setup_gateway_table $dev $via public_gateway
			/usr/lib/ddmesh/ddmesh-bmxd.sh gateway
			break;
		fi
		
		echo "ERROR: should never come to here!!"		
		break;
	fi


	$DEBUG && {
		echo "---rules---"
		ip rule
		echo "---table ping ---"
		ip ro list table ping
		echo "---table local_gateway---"
		ip ro list table local_gateway 
		echo "---table public_gateway---"
		ip ro list table public_gateway 
		echo "------"
	}

done
unset IFS

ip route flush table ping
ip route flush table ping_unreachable
ip rule del iif lo priority $ip_rule_priority table ping >/dev/null
ip rule del iif lo priority $ip_rule_priority_unreachable table ping_unreachable >/dev/null

if ! $ok; then
	$DEBUG && echo "no gateway"
	#remove all in default route from public_gateway table
	ip route flush table public_gateway 2>/dev/null
	/usr/lib/ddmesh/ddmesh-bmxd.sh no_gateway
else
	# update time
	/usr/lib/ddmesh/ddmesh-rdate.sh update
fi

$DEBUG && echo "end."
exit 0
