#!/bin/ash

TAG=watchdog

call_watchdog()
{ # $1 - interval in min
  # $x - function or script with arguments
 interval=$1
 shift
 args=$*

 ut=$(expr $(cat /proc/uptime | cut -d'.' -f1) / 60)

 test $(expr $ut % $interval) -eq 0 && $args
}

#--------- user functions ----

watchdog_wifi()
{
	#check wifi: read country, try to set reg, verify reg
	current_country="$(iw reg get | sed -n 's#.* \(..\):.*#\1#p')"
	config_country="$(uci get wireless.radio2g.country)"
	logger -t $TAG "wifi: country $current_country"

	if [ ! "$current_country" = "$config_country" ]; then
		logger -t $TAG "wifi: ERROR - country mismatch '$current_country' != '$config_country'"
		iw reg set "$config_country"

		#verify
		current_country="$(iw reg get | sed -n 's#.* \(..\):.*#\1#p')"
		if [ ! "$current_country" = "$config_country" ]; then
			logger -t $TAG "wifi: ERROR - rebooting router"
			sync
			sleep 10
			reboot
		fi
	fi
}

watchdog_wifi_scanfix()
{
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi)
	/usr/sbin/iw dev $net_ifname scan >/dev/null
}

watchdog_bmxd()
{
	# bmxd mit fehler hat folgenden status
	# BMX 0.3-freifunk-dresden rv, 10.200.4.123, LWS 20, PWS 100, OGI 1000ms, UT 49:17:02:22 (ms= ffffffff.ffff9f63), CPU 1.1

	#check if bmxd is running several times, then it is likely bmxd is dead
	test $(pidof bmxd | wc -w) -gt 5 && kill -9 $(pidof bmxd) && logger -t $TAG "bmxd: ERROR bmxd dead - bmxd killed"

}

watchdog_routing()
{
	rules="$(ip rule | grep bat_route)"
	if [ -z "$rules" ]; then
		logger -t $TAG "routing: restore routing rules"
		/usr/lib/ddmesh/ddmesh-routing.sh restart
	fi
}

#--------- watchdog definitions ----

# call watchdog scripts
# call_watchdog <interval-minutes> <script | function> [arguments...]


# "iw reg get" has changed its output format. perhaps wifi-dead bug is solved?
# call_watchdog 2 watchdog_wifi

call_watchdog 3 watchdog_routing
call_watchdog 2 watchdog_bmxd
call_watchdog 5 watchdog_wifi_scanfix
call_watchdog 5 /usr/lib/ddmesh/ddmesh-backbone.sh runcheck
call_watchdog 5 /usr/lib/ddmesh/ddmesh-privnet.sh runcheck
