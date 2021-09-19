#!/bin/ash
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

#commands $1: up, down, connect, establish, disestablish, verify

eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

case $1 in

 up)
  ip link set $INTERFACE down
  ip link set $INTERFACE promisc off
  ip link set $INTERFACE multicast off mtu $INTERFACE_MTU
  ip addr add $_ddmesh_nonprimary_ip/$_ddmesh_netpre broadcast $_ddmesh_broadcast dev $INTERFACE
  ip link set $INTERFACE up
 ;;

 down)
  ip link set $INTERFACE down
  ip addr del $_ddmesh_nonprimary_ip/$_ddmesh_netpre broadcast $_ddmesh_broadcast dev $INTERFACE
 ;;

 establish)
	mkdir -p /var/backbone_status
	touch /var/backbone_status/$PEER_KEY
 ;;

 disestablish)
	rm -f /var/backbone_status/$PEER_KEY
 ;;

 #if verify-cmd was registerred in fastd.conf
 verify)
  logger -t fastd "deny connection from $PEER_ADDRESS:$PEER_PORT key $PEER_KEY"
  exit 1;
 ;;

esac

exit 0

