#!/bin/sh


test "$1" != "add" && test "$1" != "del" && echo "usage $0 [add|del]" && exit 1

#priority 99 is used for ping gateway check

#don't allow any redirect by hna (or batmand),only to interfaces directly
ip rule $1 to 192.168.0.0/16 table main priority 300
ip rule $1 to 169.254.0.0/16 table main priority 301

#route local and lan traffic through own internet gateway
#route public traffic via second table (KEEP ORDER!)
ip rule $1 iif $(uci get network.loopback.ifname) table local_gateway priority 400
test "$(uci get ddmesh.network.lan_local_internet)" = "1" && ip rule $1 iif br-lan table local_gateway priority 401
ip rule $1 table public_gateway priority 402

ip rule $1 to 10.200.0.0/15 table bat_route priority 500
ip rule $1 to 10.0.0.0/8 table bat_hna priority 501
ip rule $1 to 172.16.0.0/12 table bat_hna priority 502
ip rule $1 table bat_default priority 503

#stop any routing here, to avoid using default gatways in default routing table
#those gateways are checked and added to gateway table if valid
ip rule $1 table unreachable priority 600
ip route $1 unreachable default table unreachable

#return a quick answer instead running in timeout
#(will disturb adding default gateway)
#ip route $1 prohibit default


