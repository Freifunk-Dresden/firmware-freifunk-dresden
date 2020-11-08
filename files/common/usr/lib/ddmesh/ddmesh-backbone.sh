#!/bin/sh

. /lib/functions.sh

WG_BIN=$(which wg)
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh tbb_wg wg)
WG_LOGGER_TAG="wg-backbone"

FASTD_CONF_DIR=/var/etc/fastd
FASTD_CONF=$FASTD_CONF_DIR/backbone-fastd.conf
FASTD_BIN=$(which fastd)
FASTD_LOGGER_TAG="fastd-backbone"
FASTD_PID_FILE=/var/run/backbone-fastd.pid
FASTD_CONF_PEERS=backbone-peers

DEFAULT_FASTD_PORT=$(uci get ddmesh.backbone.default_fastd_port)
DEFAULT_WG_PORT=$(uci get ddmesh.backbone.default_wg_port)
backbone_local_fastd_port=$(uci get ddmesh.backbone.fastd_port)
backbone_local_fastd_port=${backbone_local_fastd_port:-$DEFAULT_FASTD_PORT}
backbone_local_wg_port=$(uci get ddmesh.backbone.wg_port)
backbone_local_wg_port=${backbone_local_wg_port:-$DEFAULT_WG_PORT}
MTU=$(uci get ddmesh.network.mesh_mtu)

NUMBER_OF_CLIENTS="$(uci get ddmesh.backbone.number_of_clients)"

gen_fastd_key()
{
	test -z "$(uci -q get credentials.backbone_secret)" && {
		uci -q add credentials backbone_secret
		uci -q rename credentials.@backbone_secret[-1]='backbone_secret'
	}
	uci -q set credentials.backbone_secret.fastd_key="$(fastd --machine-readable --generate-key)"
	uci_commit.sh
}

gen_wg_key()
{
	WG_PRIV=$(wg genkey)
	uci set credentials.backbone_secret.wireguard_key="$WG_PRIV"
	uci_commit.sh
}

generate_fastd_conf()
{
 # sources: https://projects.universe-factory.net/projects/fastd/wiki
 # docs: http://fastd.readthedocs.org/en/v17/
 local ifname=$1

 echo "generate fastd config"
 secret="$(uci -q get credentials.backbone_secret.fastd_key)"
 if [ -z "$secret" ]; then
	logger -t $FASTD_LOGGER_TAG "no secret key - generating..."
	gen_fastd_key
	secret="$(uci -q get credentials.backbone_secret.fastd_key)"
 fi

 cat << EOM > $FASTD_CONF
log level error;
log to syslog level error;
mode tap;
interface "$ifname";
method "null";
#method "salsa2012+umac";
secure handshakes yes;
bind any:$backbone_local_fastd_port;
secret "$secret";
mtu $MTU;
packet mark 0x5002;
include peers from "$FASTD_CONF_PEERS";
forward no;
on up sync "/etc/fastd/backbone-cmd.sh up";
on down sync "/etc/fastd/backbone-cmd.sh down";
on connect sync "/etc/fastd/backbone-cmd.sh connect";
on establish sync "/etc/fastd/backbone-cmd.sh establish";
on disestablish sync "/etc/fastd/backbone-cmd.sh disestablish";

#only enable verify if I want to ignore peer config files
#on verify sync "/etc/fastd/backbone-cmd.sh verify";

EOM
}

callback_accept_fastd_config ()
{
	local config="$1"
	local key
	local comment

	config_get key "$config" public_key
	config_get comment "$config" comment

	echo "fastd process accept: $key # $comment"
	if [ -n "$key" -a -n "$comment" ]; then
		FILE=$FASTD_CONF_DIR/$FASTD_CONF_PEERS/accept_$key.conf
		echo "fastd accept peer: [$key:$comment] ($FILE)"

		echo "# $comment" > $FILE
		echo "key \"$key\";" >> $FILE
	fi
}

callback_outgoing_fastd_config ()
{
	local config="$1"
	local host  #hostname or ip
	local port
	local key
	local type

	config_get host "$config" host
	config_get port "$config" port
	config_get key "$config" public_key
	config_get type "$config" type
	[ -z "$type" ] && type="fastd"

	#echo "fastd process out: cfgtype:$type, host:$host, port:$port, key:$key]"
	if [ "$type" == "fastd" -a -n "$host" -a -n "$port" -a -n "$key" ]; then
		FILE=$FASTD_CONF_DIR/$FASTD_CONF_PEERS/"connect_"$host"_"$port".conf"
		#echo "fastd out: add peer ($FILE)"
		echo "key \"$key\";" > $FILE
		echo "remote ipv4 \"$host\":$port;" >> $FILE

		#dont use hostnames, can not be resolved
		iptables -w -D output_backbone_accept -p udp --dport $port -j ACCEPT 2>/dev/null
		iptables -w -D output_backbone_reject -p udp --dport $port -j reject 2>/dev/null
		iptables -w -A output_backbone_accept -p udp --dport $port -j ACCEPT
		iptables -w -A output_backbone_reject -p udp --dport $port -j reject
	fi
}

callback_outgoing_wireguard_interfaces ()
{
	local config="$1"
	local local_wg_ip=$2
	local local_wgX_ip=$3

	local host  #hostname or ip
	local port
	local key
	local type
	local node

	config_get host "$config" host
	config_get port "$config" port
	config_get key "$config" public_key
	config_get type "$config" type
	config_get node "$config" node

	#echo "wg process out: cfgtype:$type, host:$host, port:$port, key:$key, target node:$node]"
	if [ "$type" == "wireguard" -a -n "$host" -a -n "$port" -a -n "$key" -a -n "$node" ]; then

		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
		local remote_wg_ip=$_ddmesh_wireguard_ip

		#echo "wg out: add peer ($node)"

		#dont use hostnames, can not be resolved
		iptables -w -D output_backbone_accept -p udp --dport $port -j ACCEPT 2>/dev/null
		iptables -w -D output_backbone_reject -p udp --dport $port -j reject 2>/dev/null
		iptables -w -A output_backbone_accept -p udp --dport $port -j ACCEPT
		iptables -w -A output_backbone_reject -p udp --dport $port -j reject

		# create sub interface
		sub_ifname="$wg_ifname$node"
		ip link add $sub_ifname type ipip remote $remote_wg_ip local $local_wg_ip
		ip addr add $local_wgX_ip broadcast $_ddmesh_broadcast dev $sub_ifname
		ip link set $sub_ifname up

		bmxd -c dev=$sub_ifname /linklayer 1
	fi
}

callback_incomming_wireguard_interfaces ()
{
	local config="$1"
	local local_wg_ip=$2
	local local_wgX_ip=$3

	local key
	local type
	local node

	config_get key "$config" public_key
	config_get type "$config" type
	config_get node "$config" node

	echo "wg process out: cfgtype:$type, key:$key, target node:$node]"
	if [ "$type" == "wireguard" -a -n "$key" -a -n "$node" ]; then

		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
		local remote_wg_ip=$_ddmesh_wireguard_ip

		echo "wg in: add peer ($node)"

		# create sub interface
		sub_ifname="$wg_ifname$node"
		ip link add $sub_ifname type ipip remote $remote_wg_ip local $local_wg_ip
		ip addr add $local_wgX_ip broadcast $_ddmesh_broadcast dev $sub_ifname
		ip link set $sub_ifname up

		bmxd -c dev=$sub_ifname /linklayer 1
	fi
}

callback_outgoing_wireguard_connection ()
{
	local config="$1"
	local local_wg_ip=$2
	local local_wgX_ip=$3

	local host  #hostname or ip
	local port
	local key
	local type
	local node

	config_get host "$config" host
	config_get port "$config" port
	config_get key "$config" public_key
	config_get type "$config" type
	config_get node "$config" node

	#echo "wg process out: cfgtype:$type, host:$host, port:$port, key:$key, target node:$node]"
	if [ "$type" == "wireguard" -a -n "$host" -a -n "$port" -a -n "$key" -a -n "$node" ]; then

		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
		local remote_wg_ip=$_ddmesh_wireguard_ip
		wg set $wg_ifname peer $key persistent-keepalive 25 allowed-ips $remote_wg_ip/32 endpoint $host:$port
	fi
}

case "$1" in

	start)
		iptables -w -F input_backbone_accept
		iptables -w -F input_backbone_reject
		iptables -w -A input_backbone_accept -p udp --dport $backbone_local_fastd_port -j ACCEPT
		iptables -w -A input_backbone_reject -p udp --dport $backbone_local_fastd_port -j reject
		iptables -w -A input_backbone_accept -p udp --dport $backbone_local_wg_port -j ACCEPT
		iptables -w -A input_backbone_reject -p udp --dport $backbone_local_wg_port -j reject
		iptables -w -F output_backbone_accept
		iptables -w -F output_backbone_reject

		# FastD Backbone
		if [ -f $FASTD_BIN ]; then
			echo "Starting fastd backbone ..."
			mkdir -p $FASTD_CONF_DIR
			mkdir -p $FASTD_CONF_DIR/$FASTD_CONF_PEERS

			rm -f $FASTD_CONF
			rm -f $FASTD_CONF_DIR/$FASTD_CONF_PEERS/*

			eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh tbb_fastd fastd)
			generate_fastd_conf $fastd_ifname

			# accept fastd clients
			config_load ddmesh
			config_foreach callback_accept_fastd_config backbone_accept

			# outgoing
			config_load ddmesh
			config_foreach callback_outgoing_fastd_config backbone_client

			fastd --config $FASTD_CONF --pid-file $FASTD_PID_FILE --daemon
		fi

		if [ -f $WG_BIN ]; then
			echo "Starting wg backbone ..."
			eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

			# create tbb_wg
			secret=$(/sbin/uci -q get credentials.backbone_secret.wireguard_key)
			if [ -n "$secret" ]; then
				# setup local wg interface. this is used to receive/transmit data for/from
				# all peers (hosts)
				secret_file="/tmp/wg.pki"
				echo $secret > $secret_file
				ip link add $wg_ifname type wireguard
				ip addr add "$_ddmesh_wireguard_ip/32" dev $wg_ifname
				wg set $wg_ifname private-key $secret_file

				wg set $wg_ifname listen-port $backbone_local_wg_port

				ip link set $wg_ifname up
				rm $secret_file

				ip route add $_ddmesh_wireguard_network/$_ddmesh_netpre dev $wg_ifname src $_ddmesh_wireguard_ip

				# pass local ip addresses to callback
				# wg provides tunnels to all peers via one interface.
				# through this tunnel an ipip tunnel is setup from node to node, because of some
				# wg restrictions (no broacast possible). ipip tunnel has its own interface for
				# each peer. this iface is added to bmxd

				# add outgoing clients
				config_load ddmesh
				config_foreach callback_outgoing_wireguard_interfaces backbone_client $_ddmesh_wireguard_ip "$_ddmesh_nonprimary_ip/$_ddmesh_netpre"

				# add incomming clients
				config_load ddmesh
				config_foreach callback_incomming_wireguard_interfaces backbone_accept $_ddmesh_wireguard_ip "$_ddmesh_nonprimary_ip/$_ddmesh_netpre"
			fi
		fi

		# try to resolve host names and setup wg tunnel
		# wg command only resolves host name once. if no connection is available during
		# boot, wg gives up. we need to retry it later (via cron). I can

		$0 update
		;;

	update)
		# try to resolv and update wg config. wg does not interrupt connection
		# when there is no change

		# check for working dns to avoid delays created by wg-tool trying to resolve
		nslookup "freifunk-dresden.de" && {
			logger -t "$WG_LOGGER_TAG" "DNS resolv ok - update wg config"
			eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
			config_load ddmesh
			config_foreach callback_outgoing_wireguard_connection backbone_client $_ddmesh_wireguard_ip "$_ddmesh_nonprimary_ip/$_ddmesh_netpre"
		}
		;;

	stop)
		if [ -f $FASTD_BIN ]; then
			echo "Stopping backbone network..."
			if [ -f $FASTD_PID_FILE ]; then
				kill $(cat $FASTD_PID_FILE)
				rm -f $FASTD_PID_FILE
			fi
		fi
		if [ -f $WG_BIN ]; then
			# delete all ipip tunnels
			LS=$(which ls)
			IFS='
'
			for i in $($LS -1d  /sys/class/net/$wg_ifname* 2>/dev/null | sed 's#.*/##')
			do
				[ "$i" != "$wg_ifname" ] && bmxd -c dev=-$i >/dev/null
				ip link del $i 2>/dev/null
			done
			unset IFS
		fi
		;;

	restart)
		$0 stop
		sleep 2
		$0 start
		;;

	gen_secret_key)
		if [ -f $FASTD_BIN ]; then
			gen_fastd_key
		fi
		;;

		gen_wgsecret_key)
		if [ -f $WG_BIN ]; then
						gen_wg_key
		fi
					;;

		get_public_key)
		if [ -f $FASTD_BIN ]; then
			fastd --machine-readable --show-key --config $FASTD_CONF
		fi
		;;

	runcheck)
		if [ -f $FASTD_BIN ]; then
			present="$(grep $FASTD_CONF /proc/$(cat $FASTD_PID_FILE)/cmdline 2>/dev/null)"
			if [ -z "$present" ]; then
				logger -t $FASTD_LOGGER_TAG "fastd not running -> restarting"
				$0 start
			fi
		fi
		;;

	*)
		echo "usage: $0 start|stop|restart|gen_secret_key|get_public_key|runcheck"
esac
