#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

# set when called from commmand line
test -z "$_ddmesh_ip" && eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

setup()
{ # $1 - add | del

# priority 99 is used for ping gateway check

ip rule $1 to 169.254.0.0/16 table main priority 300

# byepass private ranges (not freifunk ranges)
ip rule $1 to 192.168.0.0/16 table main priority 310
ip rule $1 to 172.16.0.0/12 table main priority 320
ip rule add to $_ddmesh_wireguard_network/$_ddmesh_netpre lookup main prio 330

# byepass wifi2
ip rule $1 to $_ddmesh_wifi2net table main priority 350

# public dns is filled by openvpn up.sh
ip rule $1 lookup public_dns priority 360

# route local and lan traffic through own internet gateway
# route public traffic via second table (KEEP ORDER!)
ip rule $1 iif $(uci get network.loopback.device) table local_gateway priority 400
test "$(uci -q get ddmesh.network.lan_local_internet)" = "1" && ip rule $1 iif br-lan table local_gateway priority 401
ip rule $1 table public_gateway priority 410

# avoid fastd going through mesh/bat (in case WAN dhcp did not get ip)
# see fastd.conf
ip rule add fwmark 0x5002 table unreachable prio 460

ip rule $1 to $_ddmesh_fullnet table bat_route priority 500

#at this point only let inet ips go further. let all other network ips (10er) be unreachable
#to speed up routing and avoid loops within same node.
# Also forbit going in private ranges. that can happen when wan/lan interface bridge
# does not contain an interface (because mesh-on-lan/wan). then no route is present
# in table main.
ip rule $1 to 10.0.0.0/8 table unreachable priority 503
ip rule $1 to 192.168.0.0/16 table unreachable priority 504
ip rule $1 to 172.16.0.0/12 table unreachable priority 505

# bmxd-gateway.sh setups ipip tunnel
ip rule $1 table ff_gateway priority 506
ip rule $1 table bat_default priority 507

# put fallback after bat_default. If lan was configured and mesh-on-lan is active
# local_gateway would be empty and any local internet communication (registration)
# will be routed to dead ip
ip rule $1 iif $(uci get network.loopback.device) table fallback_gateway priority 508

#stop any routing here, to avoid using default gatways in default routing table
#those gateways are checked and added to gateway table if valid
ip rule $1 table unreachable priority 600
ip route $1 unreachable default table unreachable

#return a quick answer instead running in timeout
#(will disturb adding default gateway)
#ip route $1 prohibit default

}

clean()
{
	# search freifunk routing rules
	for i in $(ip rule | sed 's#:.*##')
	do
		[ $i -gt 10 ] && [ $i -lt 30000 ] && {
			ip rule del prio $i
		}
	done

	ip route del unreachable default table unreachable
}

case "$1" in
	start | restart)
		clean
		setup add
		;;

	stop)
		clean
		;;

	*)	echo "usage $0 [ start | stop | restart ]"
		;;
esac
