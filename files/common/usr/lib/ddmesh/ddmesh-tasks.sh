#!/bin/ash

TAG="ddmesh task"

MINUTE_COUNTER=0

call_task()
{ # $1 - interval in min
  # $x - function or script with arguments
 interval=$1
 shift
 args=$*

 test $(expr $MINUTE_COUNTER % $interval) -eq 0 && { 
	[ "$(uci -q get ddmesh.log.tasks)" = "1" ] && logger -t "$TAG" "CALL interval:$interval [$args]"
	$args 2>/dev/null >/dev/null
 }
}



#--------- user functions ----

task_wifi_scanfix()
{
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi)
	/usr/sbin/iw dev $net_ifname scan >/dev/null
}

task_bmxd()
{
	# bmxd mit fehler hat folgenden status
	# BMX 0.3-freifunk-dresden rv, 10.200.4.123, LWS 20, PWS 100, OGI 1000ms, UT 49:17:02:22 (ms= ffffffff.ffff9f63), CPU 1.1

	#check if bmxd is running several times, then it is likely bmxd is dead
	test $(pidof bmxd | wc -w) -gt 5 && kill -9 $(pidof bmxd) && logger -t $TAG "bmxd: ERROR bmxd dead - bmxd killed"

}

task_routing()
{
	rules="$(ip rule | grep bat_route)"
	if [ -z "$rules" ]; then
		logger -t $TAG "routing: restore routing rules"
		/usr/lib/ddmesh/ddmesh-routing.sh restart
	fi
}

#--------- task definitions ----

logger -t $TAG "start service"

# task loop
while true;
do
	sleep 60 # must be exact 60s
 	MINUTE_COUNTER=$((MINUTE_COUNTER + 1))
	[ "$MINUTE_COUNTER" -gt 10000 ] && MINUTE_COUNTER=0

	# call task scripts
	# call_task <interval-minutes> <script | function> [arguments...]

	call_task 3 task_routing
	call_task 2 task_bmxd
	call_task 5 task_wifi_scanfix
	call_task 5 /usr/lib/ddmesh/ddmesh-backbone.sh runcheck
	call_task 5 /usr/lib/ddmesh/ddmesh-privnet.sh runcheck
	call_task 1 /usr/lib/ddmesh/ddmesh-sysinfo.sh
	call_task 1 /usr/lib/ddmesh/ddmesh-bmxd.sh check
	call_task 1 /usr/lib/ddmesh/ddmesh-backbone.sh update
	call_task 3 /usr/lib/ddmesh/ddmesh-gateway-check.sh
	call_task 5 /usr/lib/ddmesh/ddmesh-splash.sh autodisconnect
done

logger -t $TAG "crashed."
