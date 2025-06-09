#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

CONF_DIR=/var/etc/fastd
FASTD_CONF=$CONF_DIR/privnet-fastd.conf
CONF_PEERS=privnet-peers
PID_FILE=/var/run/privnet-fastd.pid
LOGGER_TAG="fastd-privnet"
FASTD_RUNNING_STATE="/var/state/privnet-fastd.running"

DEFAULT_PORT=$(uci -q get ddmesh.privnet.default_fastd_port)
privnet_server_port=$(uci -q get ddmesh.privnet.fastd_port)
privnet_server_port=${privnet_server_port:-$DEFAULT_PORT}

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh privnet)

# priv interface is added to br-lan. a bridge derives
# its mtu from lowest mtu of added interfaces.
# if this lan is also used to carry fastd pakets of
# priv (e.g. gateway over lan), those pakets would not fit into mtu.
# Therefore leave mtu 1500 and let kernel fragment this paket.
# note: fastd packets use mesh_mtu as this iface
# is not bridged.
MTU=1500

TAG="ddmesh-privnet.sh"

fwprint()
{
 logger -s -t "$TAG" "nft $*"
 nft $*
}
export NFT=fwprint
#export NFT=nft

genkey()
{
	test -z "$(uci -q get credentials.privnet_secret)" && {
		uci -q add credentials privnet_secret
		uci -q rename credentials.@privnet_secret[-1]='privnet_secret'
	}
	uci -q set credentials.privnet_secret.key="$(fastd --machine-readable --generate-key)"
	uci commit
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

	if [ -n "$key" ]; then
		#echo "[$key:$comment]"
		FILE=$CONF_DIR/$CONF_PEERS/accept_$key.conf
		echo "# $comment" > $FILE
		echo "key \"$key\";" >> $FILE
		config_count=$((config_count + 1))
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
#echo "cfg[$node:$port:$key]"
	if [ -n "$node" -a -n "$port" -a -n "$key" -a -n "$key" ]; then

		FILE=$CONF_DIR/$CONF_PEERS/"connect_"$node"_"$port".conf"
		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
		echo "key \"$key\";" > $FILE
		echo "remote ipv4 \"$_ddmesh_ip\":$port;" >> $FILE
    config_count=$((config_count + 1))
	fi
}

setup_firewall()
{
	logger -s -t $TAG "setup_firewall"

	# check if setup was already done
	present="$(nft --json list ruleset | jsonfilter -e '@.nftables[@.chain.name="ddmesh_privnet_input_accept"].chain.name')"
	if [ -z "$present" ]; then
	  logger -s -t $TAG "setup_firewall:init"

		# create chains (with counter, but do not register with standard hooks because chain is added
		# to specific openwrt chain
		$NFT add chain inet fw4 "ddmesh_privnet_input_accept" "{counter;}"
		$NFT add chain inet fw4 "ddmesh_privnet_output_accept" "{counter;}"
		$NFT add chain inet fw4 "ddmesh_privnet_input_reject" "{counter;}"
		$NFT add chain inet fw4 "ddmesh_privnet_output_reject" "{counter;}"

		# insert my chains into openwrt chains
		MARKER="ddmesh-privnet-in"
		$NFT insert rule inet fw4 input_wan position 0 counter jump ddmesh_privnet_input_reject comment "\"${MARKER}-wan-jump\""
		$NFT insert rule inet fw4 input_lan position 0 counter jump ddmesh_privnet_input_reject comment "\"${MARKER}-lan-jump\""
		$NFT insert rule inet fw4 input_mesh position 0 counter jump ddmesh_privnet_input_accept comment "\"${MARKER}-mesh-jump\""
		$NFT insert rule inet fw4 input_ffgw position 0 counter jump ddmesh_privnet_input_reject comment "\"${MARKER}-ffgw-jump\""
		$NFT insert rule inet fw4 input_wifi2 position 0 counter jump ddmesh_privnet_input_reject comment "\"${MARKER}-wifi2-jump\""

		MARKER="ddmesh-privnet-out"
		$NFT insert rule inet fw4 output_wan position 0 counter jump ddmesh_privnet_output_reject comment "\"${MARKER}-wan-jump\""
		$NFT insert rule inet fw4 output_lan position 0 counter jump ddmesh_privnet_output_reject comment "\"${MARKER}-lan-jump\""
		$NFT insert rule inet fw4 output_mesh position 0 counter jump ddmesh_privnet_output_accept comment "\"${MARKER}-mesh-jump\""
		$NFT insert rule inet fw4 output_ffgw position 0 counter jump ddmesh_privnet_output_reject comment "\"${MARKER}-ffgw-jump\""
		$NFT insert rule inet fw4 output_wifi2 position 0 counter jump ddmesh_privnet_output_reject comment "\"${MARKER}-wifi2-jump\""
	fi
}

callback_firewall_outgoing()
{
	local config="$1"
	local node
	local port
	local key

	config_get node "$config" node
	config_get port "$config" port
	config_get key "$config" public_key
	#echo "fw[$node:$port:$key]"
	if [ -n "$node" -a -n "$port" -a -n "$key" -a -n "$key" ]; then
		MARKER="ddmesh-privnet-out"
		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
		$NFT add rule inet fw4 ddmesh_privnet_output_accept ip daddr ${_ddmesh_ip} udp dport ${port} counter accept comment "\"${MARKER}-accept\""
		$NFT add rule inet fw4 ddmesh_privnet_output_reject ip daddr ${_ddmesh_ip} udp dport ${port} counter goto handle_reject comment "\"${MARKER}-reject\""
	fi
}

update_firewall()
{
	logger -s -t $TAG "update_firewall"

	# clear all rules
	$NFT flush chain inet fw4 ddmesh_privnet_input_accept
	$NFT flush chain inet fw4 ddmesh_privnet_input_reject
	$NFT flush chain inet fw4 ddmesh_privnet_output_accept
	$NFT flush chain inet fw4 ddmesh_privnet_output_reject

	# re-add input rules
	MARKER="ddmesh-privnet-in"
	$NFT add rule inet fw4 ddmesh_privnet_input_accept udp dport ${privnet_server_port} counter accept comment "\"${MARKER}-accept\""
	$NFT add rule inet fw4 ddmesh_privnet_input_reject udp dport ${privnet_server_port} counter goto handle_reject comment "\"${MARKER}-reject\""

	# re-add output rules
	config_load ddmesh
	config_foreach callback_firewall_outgoing privnet_client
}

case "$1" in

  restart_firewall)
		setup_firewall
		update_firewall
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
		update_firewall

		config_count=0

		# accept clients
	 	config_load ddmesh
 		config_foreach callback_accept_config privnet_accept

		# outgoing clients
	 	config_load ddmesh
	 	config_foreach callback_outgoing_config privnet_client

		if [ ${config_count} -gt 0 ]; then
			fastd --config $FASTD_CONF --pid-file $PID_FILE --daemon
			touch ${FASTD_RUNNING_STATE}
		fi
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
	rm -f ${FASTD_RUNNING_STATE}
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
	if [ -f ${FASTD_RUNNING_STATE} -a "$(uci -q get ddmesh.network.mesh_on_lan)" != "1" ]; then
		[ -f $PID_FILE ] && present="$(grep $FASTD_CONF /proc/$(cat $PID_FILE)/cmdline 2>/dev/null)"
		if [ -z "$present" ]; then
			logger -t $LOGGER_TAG "fastd not running -> restarting"
			$0 start
		fi
	fi
	;;

   *)
	echo "usage: $0 start|stop|restart|gen_secret_key|get_public_key|runcheck|restart_firewall"
esac
