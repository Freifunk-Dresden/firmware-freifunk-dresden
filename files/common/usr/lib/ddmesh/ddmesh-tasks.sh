#!/bin/ash

TAG="ddmesh task"
TIMESTAMP="/var/run/ddmesh-tasks.time"
PIDFILE="/var/run/ddmesh-tasks.pid"

# watchdog time must be greater than 1min + script runtime
WD_TIME=120

# watchdog check via cron.d
if [ "$1" = "watchdog" ]; then
	pid="$(cat $PIDFILE)"
        tdiff="$(( $(date +'%s') - $(cat $TIMESTAMP) ))"

	# kill check
	if [ $tdiff -gt $WD_TIME ]; then

		kill $pid

		logger -t "WD" "kill hanging ddmesh-tasks.sh (since $tdiff s)"

		# reset timestamp to avoid comparing against old value
		date +'%s' > $TIMESTAMP
	fi
	exit 0
fi


MINUTE_COUNTER=0

echo "$$" > $PIDFILE


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

task_bmxd()
{
	# check 
	WD_FILE=/tmp/state/bmxd.watchdog
	MAX_BMXD_TIME=120

	cur=$(date '+%s')
	wd=$cur # default,keep diff small after start

	if [ -f $WD_FILE ]; then
		wd=$(cat $WD_FILE)
	fi	

	d=$(( $cur - $wd))

	if [ "$d" -gt $MAX_BMXD_TIME ]; then
		logger -t $TAG "bmxd: kill bmxd (diff $d)"
		# delete file, to reset timeout
		rm $WD_FILE
		killall -9 bmxd
	fi
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

	# stop tasks when status file is deleted. this avoids running tasks during
	# firmware update
	test -f /tmp/freifunk-running || continue 

	# call task scripts
	# call_task <interval-minutes> <script | function> [arguments...]

	call_task 3 task_routing
	call_task 1 task_bmxd
	call_task 5 /usr/lib/ddmesh/ddmesh-backbone.sh runcheck
	call_task 5 /usr/lib/ddmesh/ddmesh-privnet.sh runcheck
	call_task 1 /usr/lib/ddmesh/ddmesh-sysinfo.sh
	call_task 1 /usr/lib/ddmesh/ddmesh-bmxd.sh check
	call_task 1 /usr/lib/ddmesh/ddmesh-backbone.sh update
	call_task 3 /usr/lib/ddmesh/ddmesh-gateway-check.sh
	call_task 5 /usr/lib/ddmesh/ddmesh-splash.sh autodisconnect

	# watchdog timestamp
	date +'%s' > $TIMESTAMP
done

logger -t $TAG "crashed."
