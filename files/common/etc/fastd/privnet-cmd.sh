#!/bin/ash

TAG="fastd-privnet"

#commands $1: up, down, connect, establish, disestablish, verify
if [ "$(uci -q get ddmesh.network.mesh_on_lan)" != "1" ]; then
	logger -s -t $TAG "privnet disabled. mesh-on-lan is active"
	exit 0
fi

case $1 in

 up)
  /usr/sbin/ip link set $INTERFACE down
  /usr/sbin/ip link set $INTERFACE promisc off
  /usr/sbin/ip link set $INTERFACE multicast off mtu $INTERFACE_MTU
  /usr/sbin/brctl addif br-lan $INTERFACE
  /usr/sbin/ip link set br-lan mtu $INTERFACE_MTU
  /usr/sbin/ip link set $INTERFACE up
 ;;

 down)
  /usr/sbin/ip link set $INTERFACE down
  /usr/sbin/brctl delif br-lan $INTERFACE
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

