#!/bin/sh

#test "$(uci -q get freifunk.system.disable_gateway)" = "1" && exit 0 

RESOLV_CONF="/tmp/resolv.conf.auto"
RESOLV_CONF_SAVED="/tmp/resolv.conf.auto.bmxd.saved"

case $1 in
	del)
		cp $RESOLV_CONF_SAVED $RESOLV_CONF
	;;
	*)
		cp $RESOLV_CONF $RESOLV_CONF_SAVED
		echo "nameserver $1" >$RESOLV_CONF

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

