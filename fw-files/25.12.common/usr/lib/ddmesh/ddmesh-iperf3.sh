#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

test -x /usr/bin/iperf3 || exit 1

host=$1
proto=${2:-dummyprotokol}
json=$3

test -z "$host" && echo "host missing" && exit 1
test -n "$json" && json="--json"

duration=5

case "$proto" in
	rxtcp) iperf3 -t $duration -c $host -R $json ;;
	txtcp) iperf3 -t $duration -c $host $json ;;
	rxudp) iperf3 -t $duration -c $host -u -b 1000M $json ;;
	txudp) iperf3 -t $duration -c $host -u -b 1000M --get-server-output $json ;;
	*)	echo "protocols: rxtcp, txtcp, rxudp, txudp"

esac
