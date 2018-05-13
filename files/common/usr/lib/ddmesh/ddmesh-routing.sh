#!/bin/sh

# set when called from commmand line                                                              
test -z "$_ddmesh_ip" && eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

setup()
{ # $1 - add | del

#priority 99 is used for ping gateway check

#speedtest through gateway tunnel:
#router is client: 169.254.x.y allow packets going to bat0
#router is gatway: 169.254.x.y allow packets going to bat0
ip rule $1 to 169.254.0.0/16 table bat_default priority 301
ip rule $1 to 169.254.0.0/16 table main priority 302

#bypass wifi2
ip rule $1 to 100.64.0.0/16 table main priority 350

#route local and lan traffic through own internet gateway
#route public traffic via second table (KEEP ORDER!)
ip rule $1 iif $(uci get network.loopback.ifname) table local_gateway priority 400
test "$(uci -q get ddmesh.network.lan_local_internet)" = "1" && ip rule $1 iif br-lan table local_gateway priority 401
ip rule $1 table public_gateway priority 402

#byepass private ranges (not freifunk ranges) after processing specific default route
ip rule $1 to 192.168.0.0/16 table main priority 450

# avoid fastd going through mesh/bat (in case WAN dhcp did not get ip)
ip rule add fwmark 0x5002 table unreachable prio 460

ip rule $1 to $_ddmesh_fullnet table bat_route priority 500

#avoid ip packages go through bmx_gateway if bmx6 has removed entries from its tables
#at this point only let inet ips go further. let all other network ips (10er) be unreachable
#to speed up routing and avoid loops within same node
ip rule $1 to 10.0.0.0/8 table unreachable priority 503
ip rule $1 to 172.16.0.0/12 table unreachable priority 504

ip rule $1 table bat_default priority 505

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

