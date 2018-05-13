#!/bin/sh

. /lib/functions.sh

CONF_DIR=/var/etc/fastd
FASTD_CONF=$CONF_DIR/backbone-fastd.conf
CONF_PEERS=backbone-peers
PID_FILE=/var/run/backbone-fastd.pid
LOGGER_TAG="fastd-backbone"

DEFAULT_PORT=$(uci get ddmesh.backbone.default_server_port)
backbone_server_port=$(uci get ddmesh.backbone.server_port)
backbone_server_port=${backbone_server_port:-$DEFAULT_PORT}
MTU=$(uci get ddmesh.network.mesh_mtu)

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh tbb_fastd)

genkey()
{
	test -z "$(uci -q get credentials.backbone_secret)" && {
		uci -q add credentials backbone_secret
		uci -q rename credentials.@backbone_secret[-1]='backbone_secret'
	}
	uci -q set credentials.backbone_secret.key="$(fastd --machine-readable --generate-key)"
	uci_commit.sh
}

generate_fastd_conf()
{
 # sources: https://projects.universe-factory.net/projects/fastd/wiki
 # docs: http://fastd.readthedocs.org/en/v17/

 secret="$(uci -q get credentials.backbone_secret.key)"
 if [ -z "$secret" ]; then
	logger -t $LOGGER_TAG "no secret key - generating..."
	genkey
	secret="$(uci -q get credentials.backbone_secret.key)"
 fi

 cat << EOM > $FASTD_CONF
log level error;
log to syslog level error;
mode tap;
interface "$net_ifname";
method "null";
#method "salsa2012+umac";
secure handshakes yes;
bind any:$backbone_server_port;
secret "$secret";
mtu $MTU;
packet mark 0x5002;
include peers from "$CONF_PEERS";
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

callback_accept_config ()
{
	local config="$1"
	local key
	local comment

	config_get key "$config" public_key
	config_get comment "$config" comment

	if [ -n "$key" -a -n "$comment" ]; then
		#echo "[$key:$comment]"
		FILE=$CONF_DIR/$CONF_PEERS/accept_$key.conf
		echo "# $comment" > $FILE
		echo "key \"$key\";" >> $FILE
	fi
}


callback_outgoing_config ()
{
	local config="$1"
	local host  #hostname or ip
	local port
	local key

	config_get host "$config" host
	config_get port "$config" port
	config_get key "$config" public_key

	if [ -n "$host" -a -n "$port" -a -n "$key" -a -n "$key" ]; then
		#echo "[$host:$port:$key]"
		FILE=$CONF_DIR/$CONF_PEERS/"connect_"$host"_"$port".conf"
		echo "key \"$key\";" > $FILE
		echo "remote ipv4 \"$host\":$port;" >> $FILE

		#dont use hostnames, can not be resolved
		iptables -D output_backbone_accept -p udp --dport $port -j ACCEPT 2>/dev/null
		iptables -D output_backbone_reject -p udp --dport $port -j reject 2>/dev/null
		iptables -A output_backbone_accept -p udp --dport $port -j ACCEPT
		iptables -A output_backbone_reject -p udp --dport $port -j reject
	fi
}

case "$1" in

 start)
	echo "Starting backbone..."

	mkdir -p $CONF_DIR
	mkdir -p $CONF_DIR/$CONF_PEERS

	rm -f $FAST_CONF
	rm -f $CONF_DIR/$CONF_PEERS/*

	generate_fastd_conf

	iptables -F input_backbone_accept
	iptables -F input_backbone_reject

	# accept clients
 	config_load ddmesh
 	config_foreach callback_accept_config backbone_accept

	iptables -A input_backbone_accept -p udp --dport $backbone_server_port -j ACCEPT
  	iptables -A input_backbone_reject -p udp --dport $backbone_server_port -j reject

	# outgoing
	iptables -F output_backbone_accept
	iptables -F output_backbone_reject

 	config_load ddmesh
 	config_foreach callback_outgoing_config backbone_client

	fastd --config $FASTD_CONF --pid-file $PID_FILE --daemon
	;;

  stop)
	echo "Stopping backbone network..."
	if [ -f $PID_FILE ]; then
		kill $(cat $PID_FILE)
		rm -f $PID_FILE
	fi
	;;

  restart)
	$0 stop
	sleep 2
	$0 start
  	;;

  gen_secret_key)
	genkey
	generate_fastd_conf
	;;

  get_public_key)
	fastd --machine-readable --show-key --config $FASTD_CONF
	;;

  runcheck)
	present="$(grep $FASTD_CONF /proc/$(cat $PID_FILE)/cmdline 2>/dev/null)"
	if [ -z "$present" ]; then
		logger -t $LOGGER_TAG "fastd not running -> restarting"
		$0 start
	fi
	;;

   *)
	echo "usage: $0 start|stop|restart|gen_secret_key|get_public_key|runcheck"
esac


