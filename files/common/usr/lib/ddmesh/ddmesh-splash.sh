#!/bin/ash

. /lib/functions.sh

SELF=$0
AD=/tmp/dhcp.autodisconnect.db

test -d $AD || mkdir -p $AD

config_splash_mac_check_exit() {
 #exit will exit not just this function, will exit the script
 test "$1" = "$2" && logger -t splash "mac $2 was added permanently. not deleted" && exit
 return 0
}

config_splash_addmac() {
 $SELF addmac $1
}

case "$1" in 
	isclient)
		test -z "$(uci -q get ddmesh.system.node)" && echo no && exit 1

		eval $(ddmesh-ipcalc.sh -n $(uci -q get ddmesh.system.node))
		test -z "$2" && echo "arg 2 (IP) missing" && exit 1
		localnet=$(ipcalc -n $(uci get ddmesh.network.wifi2_ip) $(uci get ddmesh.network.wifi2_netmask))
		localnet=${localnet#NETWORK=}
		clientnet=$(ipcalc -n $2 $(uci get ddmesh.network.wifi2_netmask))
		clientnet=${clientnet#NETWORK=}
		test "$localnet" = "$clientnet" && echo yes && exit 0
		echo no 
	;;
	getmac)
		test -z "$2" && echo "arg 2 (IP) missing" && exit 1
		cat /tmp/dhcp.leases | grep "[ 	]$2[ 	]" | cut -d' ' -f2 | sed 'y#ABCDEF#abcdef#'
	;;
	addmac)
		test -z "$2" && echo "arg 2 (MAC) missing" && exit 1
		test -z "$(iptables -t nat -L -n | grep SPLASH_AUTH_USERS)" && exit 1
 		mac=$(echo $2 | sed 'y#ABCDEF#abcdef#') 
		logger -t splash "addmac $mac"
		iptables -t nat -D SPLASH_AUTH_USERS -m mac --mac-source $mac -j RETURN >/dev/null 2>&1
		iptables -t nat -I SPLASH_AUTH_USERS -m mac --mac-source $mac -j RETURN >/dev/null 2>&1
		iptables -D SPLASH_AUTH_USERS -m mac --mac-source $mac -j RETURN >/dev/null 2>&1
		iptables -I SPLASH_AUTH_USERS -m mac --mac-source $mac -j RETURN >/dev/null 2>&1

		#del old entry and add mac to auto disconnect db.
		echo "$(date +%s)" >> $AD/$mac
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
		iptables -t nat -D SPLASH_AUTH_USERS -m mac --mac-source $mac -j RETURN >/dev/null 2>&1
		iptables -D SPLASH_AUTH_USERS -m mac --mac-source $mac -j RETURN >/dev/null 2>&1

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
		config_load ddmesh
		config_list_foreach network splash_mac config_splash_addmac
  	;;
	autodisconnect)
		test "$(uci get ddmesh.system.disable_splash)" = "1" && exit 0

		AUTO_DISCONNECT_TIME_M=$(uci get ddmesh.network.client_disconnect_timeout)
		AUTO_DISCONNECT_TIME_S=$(( ${AUTO_DISCONNECT_TIME_M:-0} * 60 ))
		echo "timeout: $AUTO_DISCONNECT_TIME_S"
		if [ $AUTO_DISCONNECT_TIME_S -gt 0 ]; then
			current="$(date +%s)"
			IFS='
'
			for i in $(ls -1 $AD/*)
			do
				mac=${i##*/}
				start=$(cat $i)
				end=$(($start+$AUTO_DISCONNECT_TIME_S))
				echo "start=[$start], current=[$current], end=[$end], mac=[$mac]"
				if [ $current -gt $end ]; then
				  logger -t splash "Client Auto disconnect $mac"
				  $0 delmac $mac
				fi
			done
		fi
	;;
	*)
		echo "splash.sh [isclient ip] [islan ip] | | [getmac ip] | [addmac mac] | [delmac mac] | listmac | [checkmac mac] | loadconfig"
		echo " Version: 1.3 4/2014"
		echo "  isclient       check if ip belongs to node net"
		echo "  getmac         gets the mac from dhcp leases"
		echo "  addmac         add mac to iptable SPLASH_AUTH"
		echo "  delmac         deletes mac from iptable SPLASH_AUTH (only if not stored in config)"
		echo "  listmac        lists all mac of iptable SPLASH_AUTH"
		echo "  checkmac       checks mac if present in SPLASH_AUTH, returns 0 if yes"
		echo "  loadconfig     loads the mac from config"
		echo "  autodisconnect check and disconnect client after $AUTO_DISCONNECT_TIME_S s"
		exit 1
	;;
esac

