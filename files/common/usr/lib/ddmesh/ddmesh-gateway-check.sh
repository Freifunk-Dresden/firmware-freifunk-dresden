#!/bin/ash
#usage: gateway-check.sh

ip_rule_priority=98
ip_rule_priority_unreachable=99
ip_fwmark=0x7	# restrict gwcheck to icmp only.firewall marks icmp traffic to allow registration to same ip

DEBUG=true
LOGGER_TAG="GW_CHECK"
OVPN=/etc/init.d/openvpn

. /lib/functions/network.sh

setup_gateway_table ()
{
	dev=$1
	via=$2
	gateway_table=$3

	#check if changed
	unset d
	unset v
	eval $(ip ro lis ta $gateway_table | awk ' /default/ {print "d="$5";v="$3} ')
	echo "old: dev=$d, via=$v"
	if [ "$dev" = "$d" -a "$via" = "$v" ]; then
		return
	fi

	#clear table
	ip route flush table $gateway_table 2>/dev/null

	#redirect gateway ip directly to gateway interface
	ip route add $via/32 dev $dev table $gateway_table 2>/dev/null

	#jump over freifunk ranges
	ip route add throw 10.0.0.0/8 table $gateway_table 2>/dev/null
	ip route add throw 172.16.0.0/12 table $gateway_table 2>/dev/null

	#jump over private ranges
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
		$OVPN restart
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
echo	$pname,$mypid
for i in $(pidof $pname)
do
  test "$i" != "$mypid" && echo kill $i && kill -9 $i
done

$DEBUG && echo "start"

#dont use vpn server (or any openvpn server), it could interrupt connection
ping_vpn_hosts="85.114.135.114 178.254.18.30 85.14.253.99 46.38.243.230 5.45.106.241 84.200.50.17 46.105.31.203 84.200.85.38 109.73.51.35 178.63.61.147"
#ping_vpn_hosts="85.14.253.99 46.38.243.230 5.45.106.241 84.200.50.17 46.105.31.203 84.200.85.38 109.73.51.35 178.63.61.147"
ping_hosts="$ping_vpn_hosts 8.8.8.8"
#process max 3 user ping
cfg_ping="$(uci -q get ddmesh.network.gateway_check_ping)"
gw_ping="$(echo "$cfg_ping" | sed 's#[ ,;/	]\+# #g' | cut -d' ' -f1-3 ) $ping_hosts"
$DEBUG && echo "hosts:[$gw_ping]"

#determine all possible gateways

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
#start with vpn, because this is prefered gateway, then WAN and lates LAN
#(there is no forwarding to lan allowed by firewall)
for g in $vpn_default_route $wan_default_route $lan_default_route
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
		$DEBUG && echo "route:$(ip route get $ip)"
		$DEBUG && echo "route via:$(ip route get $via)"

		# mark only tested ip addresses
		iptables -t mangle -A output_gateway_check -p icmp -d $ip -j MARK --set-mark $ip_fwmark
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
	minSuccessful=$(( (numIPs+1)/2 ))
	if [ $minSuccessful -lt 4 ]; then minSuccessful=4; fi
	echo "minSuccessful: $minSuccessful"

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
		$DEBUG && echo "gateway found: via [$via] dev [$dev] (landev: [$default_lan_ifname], wandev=[$default_wan_ifname, vpndev=[$default_vpn_ifname]])"

		#always add wan or lan to local gateway
		if [ "$dev" = "$default_lan_ifname" -o "$dev" = "$default_wan_ifname" ]; then
			#logger -s -t "$LOGGER_TAG" "Set local gateway: dev:$dev, ip:$via"
			setup_gateway_table $dev $via local_gateway
			#if lan/wan is tested, then we have no vpn which is working. so clear public gateway
			#if not announced
			if [ ! "$(uci -q get ddmesh.system.announce_gateway)" = "1" ]; then
				#logger -s -t "$LOGGER_TAG" "remove public gateway: dev:$dev, ip:$via"
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
		$DEBUG && echo "gateway not found: via $via dev $dev (landev:$default_lan_ifname, wandev=$default_wan_ifname)"

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
iptables -t mangle -F output_gateway_check

#in case no single gateway was working but gateway was announced, clear gateways
if ! $ok; then
	#remove all in default route from public_gateway table
	$DEBUG && echo "no gateway found"
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

if [ "$(uci -q get ddmesh.network.bypass)" = '1' ] && [ "$(ip ro list ta bypass | wc -l)" -le 1 ]; then
	logger -s -t "$LOGGER_TAG" "check bypass"
	/usr/lib/ddmesh/ddmesh-routing.sh bypass
fi

$DEBUG && echo "end."
exit 0
