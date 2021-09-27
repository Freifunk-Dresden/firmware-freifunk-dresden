#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

ARG1=$1
ARG2=$2

DAEMON=bmxd
DAEMON_PATH=/usr/bin
TIMEOUT="$(which timeout)"

test -x $DAEMON_PATH/$DAEMON || exit 0

DB_PATH=/var/lib/ddmesh/bmxd
STAT_DIR=/var/statistic
WD_FILE=/tmp/state/bmxd.watchdog
DYN_IFACES_FILE=/tmp/state/bmxd.dyn-ifaces
TAG="bmxd"
# maximal parallel instances (used internally and gui)
bmxd_max_instances=5

mkdir -p $DB_PATH
mkdir -p $STAT_DIR

touch $DB_PATH/links
touch $DB_PATH/gateways
touch $DB_PATH/originators
touch $DB_PATH/status
touch $DB_PATH/networks	# network ids
touch $STAT_DIR/gateway_usage

GATEWAY_HYSTERESIS="100"

eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

if [ "$ARG1" = "start" -o "$ARG1" = "no_gateway" ]; then
	ROUTING_CLASS="$(uci -q get ddmesh.bmxd.routing_class)"
	ROUTING_CLASS="${ROUTING_CLASS:-3}"
	ROUTING_CLASS="-r $ROUTING_CLASS --gateway_hysteresis $GATEWAY_HYSTERESIS"
fi

if [ "$ARG1" = "start" -o "$ARG1" = "gateway" ]; then
	GATEWAY_CLASS="$(uci -q get ddmesh.bmxd.gateway_class)"
	GATEWAY_CLASS="${GATEWAY_CLASS:-512/512}"
	GATEWAY_CLASS="-g $GATEWAY_CLASS"
fi


case "$ARG1" in

  start)
	MESH_NETWORK_ID="$(uci -q get ddmesh.network.mesh_network_id)"
	MESH_NETWORK_ID="${MESH_NETWORK_ID:-0}"

	PREFERRED_GATEWAY="$(uci -q get ddmesh.bmxd.preferred_gateway | sed -n '/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$/p')"
	test -n "$PREFERRED_GATEWAY" && PREFERRED_GATEWAY="-p $PREFERRED_GATEWAY"

	# create a virtual interface for primary interface. loopback has
	# 127er IP which would be broadcasted

	PRIMARY_IF="bmx_prime"
	FASTD_IF="tbb_fastd"
	LAN_IF="$(uci get network.mesh_lan.device)"
	WAN_IF="$(uci get network.mesh_wan.device)"
	[ "$(uci -q get ddmesh.network.mesh_on_vlan)" = "1" ] && VLAN_IF="$(uci get network.mesh_vlan.device)"

	brctl addbr $PRIMARY_IF
	ip addr add $_ddmesh_ip/32 broadcast $_ddmesh_broadcast dev $PRIMARY_IF
	ip link set dev $PRIMARY_IF up

	_IF="dev=$PRIMARY_IF /linklayer 0"
	_IF="${_IF} dev=$FASTD_IF /linklayer 1"
	_IF="${_IF} dev=$LAN_IF /linklayer 1"
	_IF="${_IF} dev=$WAN_IF /linklayer 1"

	if [ "$(uci -q get ddmesh.network.mesh_on_vlan)" = "1" ]; then
		_IF="$_IF dev="$(uci get network.mesh_vlan.device)" /linklayer 1"
	fi

	# needed during async boot, state changes then
	/usr/lib/ddmesh/ddmesh-utils-network-info.sh update

	#add wifi, if hotplug event did occur before starting bmxd
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi_adhoc)
	if [ -n "$net_ifname" ]; then
		_IF="$_IF dev=$net_ifname /linklayer 2"
	fi
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi_mesh2g)
	if [ -n "$net_ifname" ]; then
		_IF="$_IF dev=$net_ifname /linklayer 2"
	fi
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi_mesh5g)
	if [ -n "$net_ifname" ]; then
		_IF="$_IF dev=$net_ifname /linklayer 2"
	fi

	#add dyn interfaces (add_if_wifi, add_if_wire)
	IFS='
	'
	for line in $(cat ${DYN_IFACES_FILE})
	do
		# split ifname and linklayer
		_IF="$_IF dev=${line%,*} /linklayer ${line#*,}"
	done
	unset IFS

	#default start with no gatway.will be updated by gateway_check.sh
	#SPECIAL_OPTS="--throw-rules 0 --prio-rules 0 --meshNetworkIdPreferred $MESH_NETWORK_ID"
	NETWORK_OPTS="--network $_ddmesh_fullnet"
	SPECIAL_OPTS="--throw-rules 0 --prio-rules 0"
	TUNNEL_OPTS="--gateway_tunnel_network $_ddmesh_network/$_ddmesh_netpre"
	TUNING_OPTS="--purge_timeout 20 --gateway_hysteresis $GATEWAY_HYSTERESIS --script /usr/lib/bmxd/bmxd-gateway.sh"

	DAEMON_OPTS="$NETWORK_OPTS $SPECIAL_OPTS $TUNNEL_OPTS $TUNING_OPTS $ROUTING_CLASS $PREFERRED_GATEWAY $_IF"



	# set initial wifi ssid to "FF no-inet"
	/usr/lib/bmxd/bmxd-gateway.sh init

	echo "Starting $DAEMON: opt: $DAEMON_OPTS"
	$DAEMON_PATH/$DAEMON $DAEMON_OPTS
	;;

  stop)
	echo "Stopping $DAEMON: "
	killall -9 $DAEMON
	# reset dns back to local, else not reachable dns will still be used
	/usr/lib/bmxd/bmxd-gateway.sh del
	;;

  restart)
	$0 stop
	sleep 1
	$0 start
	;;

  gateway)
	echo $DAEMON -c $GATEWAY_CLASS
	$DAEMON_PATH/$DAEMON -c $GATEWAY_CLASS
	;;

  no_gateway)
	echo $DAEMON -c $ROUTING_CLASS
	$DAEMON_PATH/$DAEMON -c $ROUTING_CLASS
	;;
  add_if_wifi)
	$DAEMON_PATH/$DAEMON -c dev=$ARG2 /linklayer 2
	echo "${ARG2},2" >> $DYN_IFACES_FILE
	;;
  add_if_wire)
	$DAEMON_PATH/$DAEMON -c dev=$ARG2 /linklayer 1
	echo "${ARG2},1" >> $DYN_IFACES_FILE
	;;
  del_if)
	$DAEMON_PATH/$DAEMON -c dev=-$ARG2
	# remove interface
	sed -i "/^${ARG2},/d" $DYN_IFACES_FILE
	;;
  runcheck)
	bmxd_restart=0

	# watchdog timestamp check: bmxd present as process, but dead
	# or present as zombi process "[bmxd]"
	# devel: run "bmxd -lcd4&" more than 12 times will create this situation
	MAX_BMXD_TIME=300
	cur=$(date '+%s')
	wd=$cur # default,keep diff small after start

	if [ -f $WD_FILE ]; then
		wd=$(cat $WD_FILE)
	fi

	d=$(( $cur - $wd))

	if [ "$d" -gt $MAX_BMXD_TIME ]; then
		logger -s -t "$TAG" "bmxd: kill bmxd (diff $d, cur=$cur, wd=$wd)"
		# delete file, to reset timeout
		rm $WD_FILE
		killall -9 $DAEMON
		bmxd_restart=1


	fi

 	# connection check; if bmxd hangs, kill it
	# check for existance of "timeout" cmd, else bmxd will be killed every time
	if [ -n "$TIMEOUT" ]; then
		$TIMEOUT -t 10 -s 9 $DAEMON -c --status >/dev/null
		if [ $? != 0 ]; then
			logger -s -t "$TAG" "bmxd: connection failed"
			killall -9 $DAEMON
			bmxd_restart=1
		fi
	fi

	# too many instances running (count no zombies)
	bmxd_count=$(ps | awk '{ if(match($4,"Z")==0 && (match($5,"^bmxd$") || match($5,"^/usr/bin/bmxd$")) ){print $5}}' | wc -l)
	test "$bmxd_count" -gt $bmxd_max_instances && logger -s -t "$TAG" "bmxd: too many instances ($bmxd_count/$bmxd_max_instances)" && bmxd_restart=1

	if [ "$bmxd_restart" = 1 ]; then
		logger -s -t "$TAG" "$DAEMON not running - restart"
		$0 restart
	fi

	;;

  update_infos)

	$DAEMON_PATH/$DAEMON -c --gateways > $DB_PATH/gateways
	$DAEMON_PATH/$DAEMON -c --links > $DB_PATH/links
	$DAEMON_PATH/$DAEMON -c --originators > $DB_PATH/originators
	$DAEMON_PATH/$DAEMON -c --status > $DB_PATH/status
#	$DAEMON_PATH/$DAEMON -c --networks > $DB_PATH/networks
	$DAEMON_PATH/$DAEMON -ci > $DB_PATH/info

	;;

  *)
	echo "Usage: $0 {start|stop|restart|gateway|no_gateway|runcheck|update_infos|add_if_wifi|add_if_wire|del_if}" >&2
	exit 1         ;;


esac

exit 0
