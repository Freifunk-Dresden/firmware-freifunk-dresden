#!/bin/sh

RESOLV_CONF_FINAL="/tmp/resolv.conf.final"
RESOLV_CONF_AUTO="/tmp/resolv.conf.auto"

case $1 in
	gateway)
		cp $RESOLV_CONF_AUTO $RESOLV_CONF_FINAL
		/usr/lib/ddmesh/ddmesh-led.sh wifi gateway
	;;
	del)
		cp $RESOLV_CONF_AUTO $RESOLV_CONF_FINAL
		/usr/lib/ddmesh/ddmesh-led.sh wifi alive
	;;
	*)
		# delete initial symlink
		rm $RESOLV_CONF_FINAL
		echo "nameserver $1" >$RESOLV_CONF_FINAL
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

