#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

CONF_DIR=/var/etc/fastd
FASTD_CONF=$CONF_DIR/privnet-fastd.conf
CONF_PEERS=privnet-peers
PID_FILE=/var/run/privnet-fastd.pid
LOGGER_TAG="fastd-privnet"

DEFAULT_PORT=$(uci -q get ddmesh.privnet.default_fastd_port)
privnet_server_port=$(uci -q get ddmesh.privnet.fastd_port)
privnet_server_port=${privnet_server_port:-$DEFAULT_PORT}

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh privnet)

# priv interface is added to br-lan. a bridge derives
# its mtu from lowest mtu of added interfaces.
# if this lan is also used to carry fastd pakets of
# priv (e.g. gateway over lan), those pakets would not fit into mtu.
# Therefore leave mtu 1500 and let kernel fragment this paket.
# note: backbone fastd pakets use mesh_mtu as this iface
# is not bridged.
MTU=1500

genkey()
{
	test -z "$(uci -q get credentials.privnet_secret)" && {
		uci -q add credentials privnet_secret
		uci -q rename credentials.@privnet_secret[-1]='privnet_secret'
	}
	uci -q set credentials.privnet_secret.key="$(fastd --machine-readable --generate-key)"
	uci_commit.sh
}

generate_fastd_conf()
{
 # sources: https://projects.universe-factory.net/projects/fastd/wiki
 # docs: http://fastd.readthedocs.org/en/v17/

 secret="$(uci -q get credentials.privnet_secret.key)"
 if [ -z "$secret" ]; then
	logger -t $LOGGER_TAG "no secret key - generating..."
	genkey
	secret="$(uci -q get credentials.privnet_secret.key)"
 fi

 cat << EOM > $FASTD_CONF
log level error;
log to syslog level error;
mode tap;
interface "$net_ifname";
method "salsa2012+umac";
bind any:$privnet_server_port;
secret "$secret";
mtu $MTU;
include peers from "$CONF_PEERS";
forward no;
on up sync "/etc/fastd/privnet-cmd.sh up";
on down sync "/etc/fastd/privnet-cmd.sh down";
on connect sync "/etc/fastd/privnet-cmd.sh connect";
on establish sync "/etc/fastd/privnet-cmd.sh establish";
on disestablish sync "/etc/fastd/privnet-cmd.sh disestablish";

#only enable verify if I want to ignore peer config files
#on verify sync "/etc/fastd/privnet-cmd.sh verify";

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
	local node
	local port
	local key

	config_get node "$config" node
	config_get port "$config" port
	config_get key "$config" public_key

	if [ -n "$node" -a -n "$port" -a -n "$key" -a -n "$key" ]; then
		#echo "[$node:$port:$key]"
		FILE=$CONF_DIR/$CONF_PEERS/"connect_"$node"_"$port".conf"
		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
		echo "key \"$key\";" > $FILE
		echo "remote ipv4 \"$_ddmesh_ip\":$port;" >> $FILE
	fi
}

setup_firewall()
{
	iptables -F input_privnet_accept
	iptables -F input_privnet_reject
	iptables -A input_privnet_accept -p udp --dport $privnet_server_port -j ACCEPT
  	iptables -A input_privnet_reject -p udp --dport $privnet_server_port -j reject
}

case "$1" in

 firewall-update)
	setup_firewall
	;;
 start)
	echo "Starting privnet..."

	if [ "$(uci -q get ddmesh.network.mesh_on_lan)" != "1" ]; then

		mkdir -p $CONF_DIR
		mkdir -p $CONF_DIR/$CONF_PEERS

		rm -f $FAST_CONF
		rm -f $CONF_DIR/$CONF_PEERS/*

		generate_fastd_conf

		setup_firewall

		# accept clients
	 	config_load ddmesh
 		config_foreach callback_accept_config privnet_accept


	 	config_load ddmesh
	 	config_foreach callback_outgoing_config privnet_client

		fastd --config $FASTD_CONF --pid-file $PID_FILE --daemon
	fi
	;;

  stop)
	echo "Stopping privnet ..."
	if [ "$(uci -q get ddmesh.network.mesh_on_lan)" != "1" ]; then
		if [ -f $PID_FILE ]; then
			kill $(cat $PID_FILE)
			rm -f $PID_FILE
		fi
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
	if [ "$(uci -q get ddmesh.network.mesh_on_lan)" != "1" ]; then
		present="$(grep $FASTD_CONF /proc/$(cat $PID_FILE)/cmdline 2>/dev/null)"
		if [ -z "$present" ]; then
			logger -t $LOGGER_TAG "fastd not running -> restarting"
			$0 start
		fi
	fi
	;;

   *)
	echo "usage: $0 start|stop|restart|gen_secret_key|get_public_key|runcheck"
esac
