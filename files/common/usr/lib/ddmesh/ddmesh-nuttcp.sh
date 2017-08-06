#!/bin/sh

test -x /usr/bin/nuttcp || exit 1

host=$1
packetsize=64k
maxtime=6  #in seconds
test -z "$host" && echo "host missing" && exit 1

#number of packets
for p in 5 10 20 30 40 50 100 200 300 400 500
do
	opt="-l$packetsize -n$p"

	echo -n "sende $p x $packetsize  -> "
	out="$(nuttcp $opt -P5010 -p5011 $host)"

	tx_time=$(echo $out | sed 's#^.*/[	 ]*\([0-9]*\).*#\1#')
	tx_rate=$(echo $out | sed 's#^.*=[	 ]*\([0-9.]*\)[ 	]*\([^ ]\+\).*#\1 \2#')
	echo "$tx_rate ($tx_time s)"

	echo -n "empfange $p x $packetsize  -> "
	out="$(nuttcp -r -F $opt -P5010 -p5011 $host)"

	rx_time=$(echo $out | sed 's#^.*/[	 ]*\([0-9]*\).*#\1#')
	rx_rate=$(echo $out | sed 's#^.*=[	 ]*\([0-9.]*\)[ 	]*\([^ ]\+\).*#\1 \2#')
	echo "$rx_rate ($rx_time s)"

	t=$(($tx_time + $rx_time))
	if [ $t -gt $maxtime ]; then break;fi
done
