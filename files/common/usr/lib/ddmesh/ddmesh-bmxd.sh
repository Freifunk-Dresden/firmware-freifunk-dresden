#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
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
BMXD_GW_STATUS_FILE="/tmp/state/bmxd.gw"

# maximal parallel instances (used internally and gui)
# for running check
bmxd_max_instances=5

mkdir -p $DB_PATH
mkdir -p $STAT_DIR

touch $DB_PATH/links
touch $DB_PATH/gateways
touch $DB_PATH/originators
touch $DB_PATH/status
touch $DB_PATH/networks	# network ids
touch $STAT_DIR/gateway_usage

GATEWAY_HYSTERESIS="20"

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

		# clear gw state, to ensure creating interface and setting up dns
		> ${BMXD_GW_STATUS_FILE}

		MESH_NETWORK_ID="$(uci -q get ddmesh.system.mesh_network_id)"
		MESH_NETWORK_ID="${MESH_NETWORK_ID:-0}"

		PREFERRED_GATEWAY="$(uci -q get ddmesh.bmxd.preferred_gateway | sed -n '/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$/p')"
		test -n "$PREFERRED_GATEWAY" && PREFERRED_GATEWAY="-p $PREFERRED_GATEWAY"

		ONLY_COMMUNITY="$(uci -q get ddmesh.bmxd.only_community_gateways)"
		test "$ONLY_COMMUNITY" != 1 && ONLY_COMMUNITY=0

		# create a virtual interface for primary interface. loopback has
		# 127er IP which would be broadcasted

		PRIMARY_IF="bmx_prime"
		FASTD_IF="tbb_fastd"
		LAN_IF="$(uci get network.mesh_lan.device)"
		WAN_IF="$(uci get network.mesh_wan.device)"
		VLAN_IF="$(uci get network.mesh_vlan.device)"

		brctl addbr $PRIMARY_IF
		ip addr add $_ddmesh_ip/32 broadcast $_ddmesh_broadcast dev $PRIMARY_IF
		ip link set dev $PRIMARY_IF up

		_IF="--dev=$PRIMARY_IF /linklayer 0"
		_IF="${_IF} --dev=$FASTD_IF /linklayer 1"
		_IF="${_IF} --dev=$LAN_IF /linklayer 1"
		_IF="${_IF} --dev=$WAN_IF /linklayer 1"

		if [ "$(uci -q get ddmesh.network.mesh_on_vlan)" = "1" ]; then
			_IF="${_IF} --dev=$VLAN_IF /linklayer 1"
		fi

		# needed during async boot, state changes then
		/usr/lib/ddmesh/ddmesh-utils-network-info.sh update

		#add wifi, not using/waiting for wifi
		_IF="$_IF --dev=mesh2g-80211s /linklayer 2"
		_IF="$_IF --dev=mesh5g-80211s /linklayer 2"

		#add dyn backbone interfaces (add_if_wire)
		if [ -f "${DYN_IFACES_FILE}" ]; then
			IFS='
'
			for line in $(cat ${DYN_IFACES_FILE})
			do
				# split ifname and linklayer
				_IF="$_IF --dev=${line%,*} /linklayer ${line#*,}"
			done
			unset IFS
		fi

		#default start with no gatway.will be updated by gateway_check.sh
		# devel info:
		# --fast_path_hysteresis has not changed frequency of root setting in bat_route
		# --path_hysteresis should be less than 5, else dead routes are hold to long
		OPTS="${OPTS} --network $_ddmesh_meshnet --netid $MESH_NETWORK_ID --only_community-gw $ONLY_COMMUNITY"
		OPTS="${OPTS} --gateway_hysteresis $GATEWAY_HYSTERESIS --path_hysteresis 3  --script /usr/lib/bmxd/bmxd-gateway.sh"
		OPTS="${OPTS} ${ROUTING_CLASS} ${PREFERRED_GATEWAY}"
		# 10s OGM interval, purge timeout 35 -> 3 OGM
		# 5s OGM interval, purge timeout 35 -> 7 OGM
		OPTS="${OPTS} --hop_penalty 5 --lateness_penalty 10 --wireless_ogm_clone 100 --udp_data_size 512 --ogm_interval 5000 --purge_timeout 35"
		DAEMON_OPTS="${OPTS} ${_IF}"

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

	add_if_wire)
		if [ -n "$ARG2" ]; then
			$DAEMON_PATH/$DAEMON -c dev=$ARG2 /linklayer 1
			echo "${ARG2},1" >> $DYN_IFACES_FILE
		fi
		;;

	del_if)
		if [ -n "$ARG2" ]; then
			$DAEMON_PATH/$DAEMON -c dev=-$ARG2
			# remove interface
			sed -i "/^${ARG2},/d" $DYN_IFACES_FILE
		fi
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
			$TIMEOUT -s 9 10 $DAEMON -c --status >/dev/null
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

	netid)
		$DAEMON_PATH/$DAEMON -c --netid ${ARG2}
		;;

	prefered_gateway)
		$DAEMON_PATH/$DAEMON -cp ${ARG2:--0.0.0.0}
		;;

	only_community_gateway)
		$DAEMON_PATH/$DAEMON -c --only_community_gw ${ARG2:-0}
		;;

	*)
		echo "Usage: $0 {start|stop|restart|gateway|no_gateway|runcheck|update_infos|add_if_wire|del_if|prefered_gateway|netid|only_community_gateway}" >&2
		exit 1
		;;
esac

exit 0
