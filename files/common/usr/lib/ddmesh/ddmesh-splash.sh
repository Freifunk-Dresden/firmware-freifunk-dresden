#!/bin/ash

. /lib/functions.sh

SELF=$0
AD=/tmp/dhcp.autodisconnect.db
STORED=/tmp/dhcp.stored.db

test -d $AD || mkdir -p $AD
test -d $STORED || mkdir -p $STORED

config_splash_mac_check_exit() {
 #exit will exit not just this function, will exit the script
 test "$1" = "$2" && logger -t splash "mac $2 was added permanently. not deleted" && exit
 return 0
}

config_splash_addmac() {
# 1 mac
# 2 do-not-add-to-db flag to avoid adding mac to autodisconnect.db
 if [ -n "$1" ]; then
	echo "" > $STORED/$1
	$SELF addmac $1 $2
 fi
}

case "$1" in
	getmac)
		test -z "$2" && echo "arg 2 (IP) missing" && exit 1
		cat /tmp/dhcp.leases | grep "[ 	]$2[ 	]" | cut -d' ' -f2 | sed 'y#ABCDEF#abcdef#'
	;;
	addmac)
		test -z "$2" && echo "arg 2 (MAC) missing" && exit 1
		test -z "$(iptables -t nat -L -n | grep SPLASH_AUTH_USERS)" && exit 1
 		mac=$(echo $2 | sed 'y#ABCDEF#abcdef#')
		logger -t splash "addmac $mac"
		iptables -t nat -D SPLASH_AUTH_USERS -m mac --mac-source $mac -j RETURN -m comment --comment 'accepted client' >/dev/null 2>&1
		iptables -t nat -I SPLASH_AUTH_USERS -m mac --mac-source $mac -j RETURN -m comment --comment 'accepted client' >/dev/null 2>&1
		iptables -D SPLASH_AUTH_USERS -m mac --mac-source $mac -j RETURN -m comment --comment 'accepted client' >/dev/null 2>&1
		iptables -I SPLASH_AUTH_USERS -m mac --mac-source $mac -j RETURN -m comment --comment 'accepted client' >/dev/null 2>&1
		#add mac to auto disconnect db only if do-not-add-to-db flag was added.
		test -z "$3" && echo "$(date +%s)" > $AD/$mac
	;;
  	delmac)
		test -z "$2" && echo "arg 2 (MAC) missing" && exit 1
		test -z "$(iptables -t nat -L -n | grep SPLASH_AUTH_USERS)" && exit 1
 		mac=$(echo $2 | sed 'y#ABCDEF#abcdef#')
 		echo "process $mac"

		config_load ddmesh
		#call splash_mac_check for each mac and abort if found
		config_list_foreach network splash_mac config_splash_mac_check_exit $mac

  		echo "del: $mac"
		logger -t splash "delmac $mac"
		iptables -t nat -D SPLASH_AUTH_USERS -m mac --mac-source $mac -j RETURN -m comment --comment 'accepted client' >/dev/null 2>&1
		iptables -D SPLASH_AUTH_USERS -m mac --mac-source $mac -j RETURN -m comment --comment 'accepted client' >/dev/null 2>&1

		#remove mac from auto disconnect db.
		rm $AD/$mac

  	;;
	listmac)
		test -z "$(iptables -t nat -L -n | grep SPLASH_AUTH_USERS)" && exit 1
		iptables -t nat -L SPLASH_AUTH_USERS | sed 's/ \+/ /g' | grep MAC | cut -d' ' -f7 | sed 'y#ABCDEF#abcdef#'
	;;
	checkmac)
		test -z "$2" && echo "arg 2 (MAC) missing" && exit 1
		test -z "$(iptables -t nat -L -n | grep SPLASH_AUTH_USERS)" && exit 1
		m=$(echo $2 | sed 'y#ABCDEF#abcdef#')
		iptables -t nat -L SPLASH_AUTH_USERS | sed 's/ \+/ /g' | grep MAC | cut -d' ' -f7 | sed 'y#ABCDEF#abcdef#' | grep $m >/dev/null
	;;
  	loadconfig)
		rm -f $STORED/*
		config_load ddmesh
		config_list_foreach network splash_mac config_splash_addmac do-not-add-to-db
  	;;
	autodisconnect)
		test "$(uci get ddmesh.system.disable_splash 2>/dev/null)" = "1" && exit 0
		AUTO_DISCONNECT_TIME_M=$(uci get ddmesh.network.client_disconnect_timeout)
		AUTO_DISCONNECT_TIME_S=$(( ${AUTO_DISCONNECT_TIME_M:-0} * 60 ))
		echo "timeout: $AUTO_DISCONNECT_TIME_S"
		if [ $AUTO_DISCONNECT_TIME_S -gt 0 ]; then
			current="$(date +%s)"
			IFS='
'
			for i in $(ls -1 $AD/* 2>/dev/null)
			do
echo $i
				mac=${i##*/}
				start=$(cat $i)
echo $mac
echo $start
				end=$(( $start+$AUTO_DISCONNECT_TIME_S ))
				logger -st "splash auto disconnect" "start=[$start], current=[$current], end=[$end], mac=[$mac]"
				if [ $current -gt $end ]; then
				  logger -st splash "Client Auto disconnect $mac"
				  $SELF delmac $mac
				fi
			done
		fi
	;;
	*)
		echo "splash.sh islan ip | getmac ip | addmac mac | delmac mac | listmac | checkmac mac | loadconfig | autodisconnect"
		echo " Version: 5 08/2018"
		echo "  getmac         gets the mac from dhcp leases"
		echo "  addmac         add mac to iptable SPLASH_AUTH"
		echo "  delmac         deletes mac from iptable SPLASH_AUTH (only if not stored in config)"
		echo "  listmac        lists all mac of iptable SPLASH_AUTH"
		echo "  checkmac       checks mac if present in SPLASH_AUTH, returns 0 if yes"
		echo "  loadconfig     loads the mac from config"
		echo "  autodisconnect check and disconnect client after specific time"
		exit 1
	;;
esac
