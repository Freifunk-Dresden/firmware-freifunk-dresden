#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

#usage: gateway-check.sh

DEBUG='true'
LOGGER_TAG='GW_CHECK'
OVPN='/etc/init.d/openvpn'


. /lib/functions/network.sh

ping_check() {
	local ifname="$1"
	local ping_ip="$2"

	[ -z "$ping_ip" ] && local ping_ip='8.8.8.8'
	ping -c1 -W5 -I "$ifname" "$ping_ip" >/dev/null
}

setup_fallback_gateway()
{
	gateway_table='fallback_gateway'

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
	local dev="$1"
	local via="$2"
	local gateway_table="$3"

	#check if changed
	unset d
	unset v
	eval $(ip ro lis ta $gateway_table | awk '/default/ {print "d="$5";v="$3}')
	printf 'old: dev=%s, via=%s\n' "$d" "$v"
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
	if [ -n "$local_gateway_present" -a -x $OVPN -a -f /etc/openvpn/openvpn.conf ]; then
		#logger -s -t "$LOGGER_TAG" "restart openvpn"
		$OVPN restart 2>/dev/null
	fi
}

stop_openvpn()
{
	 test -x $OVPN && $OVPN stop 2>/dev/null
}


#kill running instance
mypid="$$"
pname="${0##*/}"
IFS=' '
printf '%s,%s\n' "$pname" "$mypid"
for i in $(pidof "$pname")
do
	[ "$i" != "$mypid" ] && printf 'kill %s\n' "$i" && kill -9 "$i"
done

setup_fallback_gateway 	# for safety reasons always store updated gw

#dont use vpn server (or any openvpn server), it could interrupt connection
# cloudflare, google, quad9, freifunk-dresden.de
ping_hosts='1.1.1.1 8.8.8.8 9.9.9.9 89.163.140.199'
$DEBUG && printf 'hosts:[%s]\n' "$ping_hosts"


#determine all possible gateways
network_is_up wwan  && {
	#get network infos using /lib/functions/network.sh
	network_get_device default_wwan_ifname wwan
	default_wwan_gateway=$(ip route | sed -n "/default via [0-9.]\+ dev $default_wwan_ifname/{s#.*via \([0-9.]\+\).*#\1#p}")
	if [ -n "$default_wwan_gateway" -a -n "$default_wwan_ifname" ]; then
		wwan_default_route="$default_wwan_gateway:$default_wwan_ifname"
	fi
}
printf 'WWAN:%s via %s\n' "$default_wwan_ifname" "$default_wwan_gateway"

network_is_up wan  && {
	#get network infos using /lib/functions/network.sh
	network_get_device default_wan_ifname wan
	default_wan_gateway=$(ip route | sed -n "/default via [0-9.]\+ dev $default_wan_ifname/{s#.*via \([0-9.]\+\).*#\1#p}")
	if [ -n "$default_wan_gateway" -a -n "$default_wan_ifname" ]; then
		wan_default_route="$default_wan_gateway:$default_wan_ifname"
	fi
}
printf 'WAN:%s via %s\n' "$default_wan_ifname" "$default_wan_gateway"

network_is_up lan && {
	#get network infos using /lib/functions/network.sh
	network_get_device default_lan_ifname lan
	network_get_gateway default_lan_gateway lan
	if [ -n "$default_lan_gateway" -a -n "$default_lan_ifname" ]; then
		lan_default_route="$default_lan_gateway:$default_lan_ifname"
	fi
}
printf 'LAN:%s via %s\n' "$default_lan_ifname" "$default_lan_gateway"

#network_is_up vpn && {
true && {
	_ifname=$(uci get network.vpn.ifname | sed 's#+##')
	default_vpn_ifname=$(ip route | sed -n "/default via [0-9.]\+ dev $_ifname/{s#.*dev \([^ 	]\+\).*#\1#p}")
	default_vpn_gateway=$(ip route | sed -n "/default via [0-9.]\+ dev $_ifname/{s#.*via \([0-9.]\+\).*#\1#p}")
	if [ -n "$default_vpn_gateway" -a -n "$default_vpn_ifname" ]; then
		vpn_default_route="$default_vpn_gateway:$default_vpn_ifname"
	fi
}
printf 'VPN:%s via %s\n' "$default_vpn_ifname" "$default_vpn_gateway"

#try each gateway
ok=0
IFS=' '
# start with vpn, because this is prefered gateway, then WAN and lates LAN
# (there is no forwarding to lan allowed by firewall)
# wwan after wan: assume wan is faster than wwan
for g in $vpn_default_route $wan_default_route $wwan_default_route $lan_default_route
do
	printf '===========\n'
	printf 'try: %s\n' "$g"
	dev="${g#*:}"
	via="${g%:*}"

	$DEBUG && printf 'via=%s, dev=%s\n' "$via" "$dev"

	#run check
	ok=0
	countSuccessful='0'
	minSuccessful='1'

	IFS=' '
	for ip in $ping_hosts
	do
		$DEBUG && printf 'ping to: %s via dev %s\n' "$ip" "$dev"
		# specify interface is needed when there is no route yet
		# And count successful pings
		ping_check "$dev" "$ip" 2>&1 && countSuccessful="$((countSuccessful+1))"

		if [ "$countSuccessful" -ge "$minSuccessful" ]; then
			ok=1
			break
		fi
	done
	if [ "$ok" = "1" ]; then
		printf 'gateway found: via [%s] dev [%s]\n' "$via" "$dev"
		printf 'landev: [%s], wandev=[%s], vpndev=[%s], wwan=[%s]\n' "$default_lan_ifname" "$default_wan_ifname" "$default_vpn_ifname" "$default_wwan_ifname"

		#always add wan/wwan or lan to local gateway
		if [ "$dev" = "$default_lan_ifname" -o "$dev" = "$default_wan_ifname" -o "$dev" = "$default_wwan_ifname" ]; then
			printf 'Set local gateway: dev:%s, ip:%s\n' "$dev" "$via"
			setup_gateway_table $dev $via local_gateway
			#if lan/wan is tested, then we have no vpn which is working. so clear public gateway
			#if not announced
			if [ ! "$(uci -q get ddmesh.system.announce_gateway)" = "1" ]; then

				$DEBUG && printf 'remove public gateway: dev:%s, ip:%s\n' "$dev" "$via"

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
		break
	else
		printf 'gateway NOT found: via [%s] dev [%s]\n' "$via" "$dev"
		printf 'landev: [%s], wandev=[%s], vpndev=[%s], wwan=[%s]\n' "$default_lan_ifname" "$default_wan_ifname" "$default_vpn_ifname" "$default_wwan_ifname"

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


#in case no single gateway was working but gateway was announced, clear gateways
if [ "$ok" != "1" ]; then
	#remove all in default route from public_gateway table
	printf 'no gateway found\n'
	ip route flush table local_gateway 2>/dev/null
	ip route flush table public_gateway 2>/dev/null
	/usr/lib/ddmesh/ddmesh-bmxd.sh no_gateway

	stop_openvpn

	# try to restart openvpn, in case connection is dead, but active ($ok was 1)
	# also if no vpn was active ($ok was 0)
	#but only if no "no-ovpn-restart" was passed
	if [ -z "$1" ]; then
		start_openvpn
	fi
fi

exit 0
