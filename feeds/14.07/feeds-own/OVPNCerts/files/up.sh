#!/bin/ash

#make a point-to-point connection with "route_vpn_gateway" because this was working for
#ovpn.to; Freie Netze e.V.;CyberGhost
ifconfig $dev $ifconfig_local dstaddr $route_vpn_gateway

#dont use "uci -P /var/state.." because statefile grows up with each connection/disconnection
#add a default route instead with metric 1 to allow multiple default routes
ip route add default dev $dev via $route_vpn_gateway table main metric 9999

#update gateway infos and routing tables, fast after openvpn closes connection
#Run in background, else openvpn blocks
/usr/bin/ddmesh-gateway-check.sh&

#tell always "ok" to openvpn;else in case of errors of "ip route..." openvpn exits
exit 0

