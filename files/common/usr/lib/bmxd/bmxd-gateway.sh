#!/bin/sh

RESOLV_CONF="/tmp/resolv.conf.auto"
RESOLV_CONF_SAVED="/tmp/resolv.conf.auto.bmxd.saved"

case $1 in
	gateway)
		cp $RESOLV_CONF_SAVED $RESOLV_CONF
		/usr/lib/ddmesh/ddmesh-led.sh wifi gateway 
	;;
	del)
		cp $RESOLV_CONF_SAVED $RESOLV_CONF
		/usr/lib/ddmesh/ddmesh-led.sh wifi alive
	;;
	*)
		cp $RESOLV_CONF $RESOLV_CONF_SAVED
		echo "nameserver $1" >$RESOLV_CONF
		/usr/lib/ddmesh/ddmesh-led.sh wifi freifunk 
	;;
esac

GW_STAT="/var/statistic/gateway_usage"
count=$(sed -n "/$1:/s#.*:##p" $GW_STAT)        
if [ -z $count ]; then
	echo "$1:1" >> $GW_STAT
else
	count=$(( $count + 1 ))
	sed -i "/$1/s#:.*#:$count#" $GW_STAT
fi

