#!/bin/ash

# determines ip address/country for tunnel ip of running openvpn (dev vpn)

DATA=/var/lib/ddmesh/tunnel_info

eval $(ip ro list ta public_gateway | sed -n 's#default.*[ ]\([0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\) dev \([^ ]\+\).*#via=\1; dev=\2#p')
if [ -z "$via" ]; then
	echo "{}" > $DATA
	cat $DATA
	exit 1
fi

if [ -f $DATA -a "$1" = "cache" ]; then
	cat $DATA
	exit 0
fi

#default
echo "{}" > $DATA

addr=$(nslookup freegeoip.net | sed -n '1,4d;s#.*: \([0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\).*#\1#p')
test -n "$addr" && {

	for ip in $addr; do
		ip rule add prio 200 to $ip table public_gateway
		ip rule add prio 201 to $ip table unreachable
		ip route add $ip via $via dev $dev table public_gateway
	done

	info="$(uclient-fetch -O - http://freegeoip.net/json/ 2>/dev/null )"

	for ip in $addr; do
		ip rule del prio 200 to $ip table public_gateway
		ip rule del prio 201 to $ip table unreachable
		ip route del $ip via $via dev $dev table public_gateway
	done

	test -n "$info" && echo "$info" > $DATA
}

cat $DATA
