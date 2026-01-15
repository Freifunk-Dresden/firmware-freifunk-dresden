#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

TAG="ddmesh task"
TIMESTAMP="/var/run/ddmesh-tasks.time"
PIDFILE="/var/run/ddmesh-tasks.pid"

# watchdog time must be greater than 1min + script runtime
WD_TIME=120

# syslog warning, if task took to long
WARN_CALL_TIME_S=10

# watchdog check via cron.d
if [ "$1" = "watchdog" ]; then

  pid="$(cat $PIDFILE)"
  tdiff="$(( $(date +'%s') - $(cat $TIMESTAMP) ))"

	# kill check
  if [ $tdiff -gt $WD_TIME ]; then

    kill $pid

    logger -t "WD" "kill hanging ddmesh-tasks.sh (since $tdiff s > $WD_TIME s )"

    # reset timestamp to avoid comparing against old value
    date +'%s' > $TIMESTAMP

    # restart in case service has also stopped
    service freifunk-tasks running || service freifunk-tasks restart
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
    tstart="$(date +'%s')"

    [ "$(uci -q get ddmesh.log.tasks)" = "1" ] && logger -s -t "$TAG" "CALL interval:$interval [$args]"
    $args 2>/dev/null >/dev/null
    [ "$(uci -q get ddmesh.log.tasks)" = "1" ] && logger -s -t "$TAG" "RETURN interval:$interval [$args]"

    tdiff="$(( $(date +'%s') - $tstart ))"
    if [ $tdiff -gt $WARN_CALL_TIME_S ]; then
      logger -s -t "$TAG" "WARNING: call took too long: $tdiff > $WARN_CALL_TIME_S [$1]"
    fi
  }



}



#--------- user functions ----
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
	call_task 5 /usr/lib/ddmesh/ddmesh-backbone.sh runcheck
	call_task 5 /usr/lib/ddmesh/ddmesh-privnet.sh runcheck

	# update states
	call_task 1 /usr/lib/ddmesh/ddmesh-sysinfo.sh
	call_task 1 /usr/lib/ddmesh/ddmesh-display.sh update
	#call_task	3 /usr/lib/ddmesh/ddmesh-utils-network-info.sh update

	call_task 1 /usr/lib/ddmesh/ddmesh-bmxd.sh runcheck
	call_task 1 /usr/lib/ddmesh/ddmesh-bmxd.sh update_infos

	# update wg connections if peers IP has changed
	call_task 1 /usr/lib/ddmesh/ddmesh-backbone.sh update
	call_task 1 /usr/lib/ddmesh/ddmesh-gateway-check.sh

	# watchdog timestamp
	date +'%s' > $TIMESTAMP
done

logger -t $TAG "ERROR: crashed."
