#!/bin/ash
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

TAG="fastd-privnet"

#commands $1: up, down, connect, establish, disestablish, verify
if [ "$(uci -q get ddmesh.network.mesh_on_lan)" = "1" ]; then
	logger -s -t $TAG "privnet disabled. mesh-on-lan is active"
	exit 0
fi

case $1 in

 up)
  ip link set $INTERFACE down
  ip link set $INTERFACE promisc off
  ip link set $INTERFACE multicast off mtu $INTERFACE_MTU
  brctl addif br-lan $INTERFACE
  ip link set br-lan mtu $INTERFACE_MTU
  ip link set $INTERFACE up
 ;;

 down)
  ip link set $INTERFACE down
  brctl delif br-lan $INTERFACE
 ;;

 establish)
	mkdir -p /var/privnet_status
	touch /var/privnet_status/$PEER_KEY
 ;;

 disestablish)
	rm -f /var/privnet_status/$PEER_KEY
 ;;

 #if verify-cmd was registerred in fastd.conf
 verify)
  logger -s -t $TAG "deny connection from $PEER_ADDRESS:$PEER_PORT key $PEER_KEY"
  exit 1;
 ;;

esac

exit 0
