#!/bin/sh

test -x /usr/sbin/rdate || exit 0

#set date from version-file only on start. else time is reset on every call
#needed if I use openvpn certs for backbone
#d=$(date -Iminutes -r /etc/version | sed 's#\([0-9]\+\)-\([0-9]\+\)-\([0-9]\+\)T\([0-9]\+\):\([0-9]\+\).*#\2\3\4\5\1#')
#test "$1" = "start" && date -s $d

if [ "$1" = "update" ] || [ "$1" = "start" ] ; then

	pool="ntp.freifunk-dresden.de ptbtime1.ptb.de ptbtime2.ptb.de 0.openwrt.pool.ntp.org 1.openwrt.pool.ntp.org 2.openwrt.pool.ntp.org 3.openwrt.pool.ntp.org ntp1.fau.de ntp2.fau.de ntp.probe-networks.de india.colorado.edu cassandra.stanford.edu cilantro.stanford.edu"
	for i in $pool
	do
	 if rdate -s $i >/dev/null 2>&1;then
	 	logger -t "rdate: " "update by $i successful [$(date)]"
		break
	 fi
	done
fi


