#!/bin/ash
#cmd tun_dev tun_mtu link_mtu ifconfig_local_ip ifconfig_remote_ip

#dont use "uci -P /var/state.." because statefile grows up with each connection/disconnection
#add a default route instead with metric 1 to allow multiple default routes
ip route add default dev $dev via $route_vpn_gateway table main metric 9999

#iptables -t nat -A POSTROUTING -o $dev -j SNAT --to-source $ifconfig_local

#update gateway infos and routing tables, fast after openvpn closes connection
#Run in background, else openvpn blocks
/usr/bin/ddmesh-gateway-check.sh&

#tell always "ok" to openvpn;else in case of errors of "ip route..." openvpn exits
exit 0

