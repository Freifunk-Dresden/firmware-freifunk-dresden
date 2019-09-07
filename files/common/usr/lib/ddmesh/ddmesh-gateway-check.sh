#!/bin/ash
#usage: gateway-check.sh

ip_rule_priority=98
ip_rule_priority_unreachable=99
ip_fwmark=0x7	# restrict gwcheck to icmp only.firewall marks icmp traffic to allow registration to same ip

DEBUG=true
LOGGER_TAG="GW_CHECK"
OVPN=/etc/init.d/openvpn

. /lib/functions/network.sh

setup_fallback_gateway()
{
	gateway_table=fallback_gateway

	#clear table
	ip route flush table $gateway_table 2>/dev/null

	#jump over freifunk/private ranges
	ip route add throw 10.0.0.0/8 table $gateway_table 2>/dev/null
	ip route add throw 172.16.0.0/12 table $gateway_table 2>/dev/null
	ip route add throw 192.168.0.0/16 table $gateway_table 2>/dev/null

	IFS='
'
	for gw in $(ip route | grep default)
	do
		eval ip route add $gw table $gateway_table

		# extract via and dev
		eval $(echo $gw | awk '/default/ {print "dev="$5";via="$3}')
		# add route to gateway for DNS requests
		ip route add $via/32 dev $dev table $gateway_table 2>/dev/null
	done
	unset IFS
}

setup_gateway_table ()
{
	dev=$1
	via=$2
	gateway_table=$3

	#check if changed
	unset d
	unset v
	eval $(ip ro lis ta $gateway_table | awk '/default/ {print "d="$5";v="$3}')
	echo "old: dev=$d, via=$v"
	if [ "$dev" = "$d" -a "$via" = "$v" ]; then
		return
	fi

	#clear table
	ip route flush table $gateway_table 2>/dev/null

	# add route to gateway for DNS requests
	ip route add $via/32 dev $dev table $gateway_table 2>/dev/null


	#jump over freifunk/private ranges
	ip route add throw 10.0.0.0/8 table $gateway_table 2>/dev/null
	ip route add throw 172.16.0.0/12 table $gateway_table 2>/dev/null
	ip route add throw 192.168.0.0/16 table $gateway_table 2>/dev/null

	#add default route (which has wider range than throw, so it is processed after throw)
	ip route add default via $via dev $dev table $gateway_table
}

start_openvpn()
{
	local_gateway_present="$(ip ro li ta local_gateway)"

	#only start openvpn when we have
	if [ -n "$local_gateway_present" -a -x $OVPN ]; then
		#logger -s -t "$LOGGER_TAG" "restart openvpn"
		test -x $OVPN && $OVPN restart 2>/dev/null
	fi
}

stop_openvpn()
{
	 test -x $OVPN && $OVPN stop
}

#kill running instance
mypid=$$
pname=${0##*/}
IFS=' '
for i in $(pidof $pname)
do
  test "$i" != "$mypid" && echo kill $i && kill -9 $i
done

setup_fallback_gateway 	# for safety reasons always store updated gw

#dont use vpn server (or any openvpn server), it could interrupt connection
ping_vpn_hosts="85.114.135.114 89.163.140.199 82.165.229.138 178.254.18.30 5.45.106.241 178.63.61.147 82.165.230.17"
ping_hosts="$ping_vpn_hosts 9.9.9.9 8.8.8.8 1.1.1.1"
#process max 3 user ping
cfg_ping="$(uci -q get ddmesh.network.gateway_check_ping)"
gw_ping="$(echo "$cfg_ping" | sed 's#[ ,;/	]\+# #g' | cut -d' ' -f1-3 ) $ping_hosts"
$DEBUG && echo "hosts:[$gw_ping]"

#determine all possible gateways
network_is_up wwan  && {
	#get network infos using /lib/functions/network.sh
	network_get_device default_wwan_ifname wwan
	default_wwan_gateway=$(ip route | sed -n "/default via [0-9.]\+ dev $default_wwan_ifname/{s#.*via \([0-9.]\+\).*#\1#p}")
	if [ -n "$default_wwan_gateway" -a -n "$default_wwan_ifname" ]; then
		wwan_default_route="$default_wwan_gateway:$default_wwan_ifname"
	fi
}
echo "WWAN:$default_wwan_ifname via $default_wwan_gateway"

network_is_up wan  && {
	#get network infos using /lib/functions/network.sh
	network_get_device default_wan_ifname wan
	default_wan_gateway=$(ip route | sed -n "/default via [0-9.]\+ dev $default_wan_ifname/{s#.*via \([0-9.]\+\).*#\1#p}")
	if [ -n "$default_wan_gateway" -a -n "$default_wan_ifname" ]; then
		wan_default_route="$default_wan_gateway:$default_wan_ifname"
	fi
}
echo "WAN:$default_wan_ifname via $default_wan_gateway"

network_is_up lan && {
	#get network infos using /lib/functions/network.sh
	network_get_device default_lan_ifname lan
	network_get_gateway default_lan_gateway lan
	if [ -n "$default_lan_gateway" -a -n "$default_lan_ifname" ]; then
		lan_default_route="$default_lan_gateway:$default_lan_ifname"
	fi
}
echo "LAN:$default_lan_ifname via $default_lan_gateway"

#network_is_up vpn && {
true && {
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
# start with vpn, because this is prefered gateway, then WAN and lates LAN
# (there is no forwarding to lan allowed by firewall)
# wwan after wan: assume wan is faster than wwan
for g in $vpn_default_route $wan_default_route $wwan_default_route $lan_default_route
do
	echo "==========="
	echo "try: $g"
	dev=${g#*:}
	via=${g%:*}

	$DEBUG && echo "via=$via, dev=$dev"


	#add ping rule before all others;only pings from this host (no forwards)
	ip rule del iif lo fwmark $ip_fwmark priority $ip_rule_priority table ping 2>/dev/null
	ip rule add iif lo fwmark $ip_fwmark priority $ip_rule_priority table ping

	#no check of gateway, it might not return icmp reply, also
	#it might not be reachable because of routing rules

	#add ping hosts to special ping table
	ip route flush table ping

	#add route to gateway, to avoid routing via freifunk
	ip route add $via/32 dev $dev table ping

	# ping must be working for at least the half of IPs
	IFS=' '
	numIPs=0
	for ip in $gw_ping
	do
		$DEBUG && echo "add ping route ip:$ip"
		ip route add $ip via $via dev $dev table ping
		$DEBUG && echo ip route add $ip via $via dev $dev table ping

		# mark only tested ip addresses
		iptables -w -t mangle -A output_gateway_check -p icmp -d $ip -j MARK --set-mark $ip_fwmark
		numIPs=$((numIPs+1))
	done
	echo "number IPs: $numIPs"

	ip route add unreachable default table ping

	$DEBUG && ip ro li ta ping

	#activate routes
	ip route flush cache

	#run check
	ok=false
	countSuccessful=0
	minSuccessful=1

	IFS=' '
	for ip in $gw_ping
	do
		$DEBUG && echo "ping to: $ip via dev $dev"
		# specify interface is needed when there is no route yet
		# And count successful pings
		ping -I $dev -c 2 -w 5 $ip  2>&1 && countSuccessful=$((countSuccessful+1))

		if [ $countSuccessful -ge $minSuccessful ]; then
			ok=true
			break
		fi
	done
	if $ok; then
		echo "gateway found: via [$via] dev [$dev]"
		echo "landev: [$default_lan_ifname], wandev=[$default_wan_ifname], vpndev=[$default_vpn_ifname], wwan=[$default_wwan_ifname]"

		#always add wan/wwan or lan to local gateway
		if [ "$dev" = "$default_lan_ifname" -o "$dev" = "$default_wan_ifname" -o "$dev" = "$default_wwan_ifname" ]; then
			echo "Set local gateway: dev:$dev, ip:$via"
			setup_gateway_table $dev $via local_gateway
			#if lan/wan is tested, then we have no vpn which is working. so clear public gateway
			#if not announced
			if [ ! "$(uci -q get ddmesh.system.announce_gateway)" = "1" ]; then

				$DEBUG && echo "remove public gateway: dev:$dev, ip:$via"

				ip route flush table public_gateway 2>/dev/null
				/usr/lib/ddmesh/ddmesh-bmxd.sh no_gateway

				# when comming here, no vpn is present -> restart
				stop_openvpn
				start_openvpn
			fi
		fi

		# Add any gateway to public table if internet was enabled.
		# If internet is disabled, add only vpn if detected.
		# When lan/wan gateway gets lost, also vpn get lost
		# If only vpn get lost, remove public gateway
		if [ "$(uci -q get ddmesh.system.announce_gateway)" = "1" -o "$dev" = "$default_vpn_ifname" ]; then
			logger -s -t "$LOGGER_TAG" "Set public gateway: dev:$dev, ip:$via"
			setup_gateway_table $dev $via public_gateway
			/usr/lib/ddmesh/ddmesh-bmxd.sh gateway
		fi

		#dont test other gateways. if vpn is ok then also wan or lan is ok. see comment when testing and setting
		#lan/wan local_gateway
		break;
	else
		echo "gateway NOT found: via [$via] dev [$dev]"
		echo "landev: [$default_lan_ifname], wandev=[$default_wan_ifname], vpndev=[$default_vpn_ifname], wwan=[$default_wwan_ifname]"

		#logger -s -t "$LOGGER_TAG" "remove local/public gateway: dev:$dev, ip:$via"
		# remove default route only for interface that was tested! if wan and lan is set
		# but wan is dead, then default route via lan must not be deleted
		ip route del default via $via dev $dev table local_gateway
		ip route del default via $via dev $dev table public_gateway

		#stop openvpn to avoid outgoing openvpn connection via bat0
		stop_openvpn
	fi

done
unset IFS

ip route flush table ping
ip rule del iif lo fwmark $ip_fwmark priority $ip_rule_priority table ping >/dev/null

# clear iptables used to mark icmp packets
iptables -w -t mangle -F output_gateway_check

#in case no single gateway was working but gateway was announced, clear gateways
if ! $ok; then
	#remove all in default route from public_gateway table
	echo "no gateway found"
	ip route flush table local_gateway 2>/dev/null
	ip route flush table public_gateway 2>/dev/null
	/usr/lib/ddmesh/ddmesh-bmxd.sh no_gateway

	stop_openvpn

	# try to restart openvpn, in case connection is dead, but active ($ok was true)
	# also if no vpn was active ($ok was false)
	#but only if no "no-ovpn-restart" was passed
	if [ -z "$1" ]; then
		start_openvpn
	fi
fi

exit 0
