#!/bin/ash
set >/tmp/set
#make a point-to-point connection with "route_vpn_gateway" because this was working for
#ovpn.to; Freie Netze e.V.;CyberGhost
ifconfig $dev $ifconfig_local dstaddr $route_vpn_gateway

#dont use "uci -P /var/state.." because statefile grows up with each connection/disconnection
#add a default route instead with metric 1 to allow multiple default routes
ip route add default dev $dev via $route_vpn_gateway table main metric 9999

#update gateway infos and routing tables, fast after openvpn open connection
#Run in background, else openvpn blocks. but avoid restarting ovpn by check-script
#if no connection could be made. this would produces a permanent fast restart loop of
#openvpn/usr/lib/ddmesh/ddmesh-gateway-check.sh no-ovpn-restart &

DEFAULT_DNS="8.8.8.8; 8.8.4.4;"		# semicolon is IMPORTANT
# flush public_dns routing table
ip route flush table public_dns

# parse any other foreign options to setup DNS for bind9.
# all local resolv goes via /etc/resolv.conf.
# any other resolving come from freifunk network and are processed by bind9
# here I create a configuration fragment which is included in /etc/bind/named.conf.options
dns_list=""
IFS='
'
for opt in $(set | sed -n 's#^foreign_option_[0-9]\+=\(.\+\)$#\1#p')
do
        if [ -n "$(echo $opt | sed -n '/^dhcp-option DNS/p')" ]; then
                dns="${x#*dhcp-option DNS}"
                dns_list="$dns_list $dns;"

		# add public dns to routing table
		ip route add $dns dev $dev table public_dns
        fi

done

#if openvpn did not deliver DNS, use default DNS
test -z "$dns_list" && dns_list="$DEFAULT_DNS"


#tell always "ok" to openvpn;else in case of errors of "ip route..." openvpn exits
exit 0

