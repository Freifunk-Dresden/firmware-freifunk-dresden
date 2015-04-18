#!/bin/sh


test "$1" != "add" && test "$1" != "del" && echo "usage $0 [add|del]" && exit 1

#priority 99 is used for ping gateway check

ip rule $1 to 169.254.0.0/16 table main priority 301

#route local and lan traffic through own internet gateway
#route public traffic via second table (KEEP ORDER!)
ip rule $1 iif $(uci get network.loopback.ifname) table local_gateway priority 400
test "$(uci get ddmesh.network.lan_local_internet)" = "1" && ip rule $1 iif br-lan table local_gateway priority 401
ip rule $1 table public_gateway priority 402

#byepass private ranges (not freifunk ranges) after processing specific default route 
ip rule $1 to 192.168.0.0/16 table main priority 450

ip rule $1 to 10.200.0.0/15 table bat_route priority 500
ip rule $1 to 10.0.0.0/8 table bat_hna priority 501
ip rule $1 to 172.16.0.0/12 table bat_hna priority 502

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


