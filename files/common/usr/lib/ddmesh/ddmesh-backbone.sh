#!/bin/sh

. /lib/functions.sh

WG_BIN=$(which wg)

FASTD_CONF_DIR=/var/etc/fastd
FASTD_CONF=$FASTD_CONF_DIR/backbone-fastd.conf
FASTD_BIN=$(which fastd)
FASTD_LOGGER_TAG="fastd-backbone"
FASTD_PID_FILE=/var/run/backbone-fastd.pid
FASTD_CONF_PEERS=backbone-peers

FASTD_DEFAULT_PORT=$(uci get ddmesh.backbone.default_server_port)
backbone_server_port=$(uci get ddmesh.backbone.server_port)
backbone_server_port=${backbone_server_port:-$FASTD_DEFAULT_PORT}
MTU=$(uci get ddmesh.network.mesh_mtu)

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
bind any:$backbone_server_port;
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

	if [ -n "$key" -a -n "$comment" ]; then
		#echo "[$key:$comment]"
		FILE=$FASTD_CONF_DIR/$FASTD_CONF_PEERS/accept_$key.conf
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

	if [ "$type" == "fastd" -a -n "$host" -a -n "$port" -a -n "$key" -a -n "$key" ]; then
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

callback_outgoing_wireguard_config ()
{
	local config="$1"
	local local_wg_ip=$2
  local local_gre_ip=$3

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

	if [ "$type" == "wireguard" -a -n "$host" -a -n "$port" -a -n "$key" -a -n "$key" -n "$node"]; then

		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
		local remote_wg_ip=$_ddmesh_wireguard_ip

		#dont use hostnames, can not be resolved
		iptables -D output_backbone_accept -p udp --dport $port -j ACCEPT 2>/dev/null
		iptables -D output_backbone_reject -p udp --dport $port -j reject 2>/dev/null
		iptables -A output_backbone_accept -p udp --dport $port -j ACCEPT
		iptables -A output_backbone_reject -p udp --dport $port -j reject

		# allow client ip
		wg set $wg_ifname peer $key persistent-keepalive 25 allowed-ips $remote_wg_ip/32 endpoint $host:$port

		# create gre interface
		gre_ifname="tbb_gre$wg_config_counter"
		ip link add $gre_ifname type gretap remote $remote_wg_ip local $local_wg_ip
		ip addr add $local_gre_ip broadcast $_ddmesh_broadcast dev $gre_ifname
		ip link set $gre_ifname up
		wg_config_counter=$((wg_config_counter + 1))

		# Insert GRETAP interface
		bmxd -c dev=$gre_ifname /linklayer 1
	fi
}

case "$1" in

	start)
		iptables -F input_backbone_accept
		iptables -F input_backbone_reject
		iptables -A input_backbone_accept -p udp --dport $backbone_server_port -j ACCEPT
		iptables -A input_backbone_reject -p udp --dport $backbone_server_port -j reject
		iptables -F output_backbone_accept
		iptables -F output_backbone_reject

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
			eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
			eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh tbb_wg wg)

			# create tbb_wg
			$(/sbin/uci get credentials.backbone_secret.wireguard_key) > /tmp/wg.pki
			ip link add dev $wg_ifname type wireguard
			ip addr add "$_ddmesh_wireguard_ip/$_ddmesh_netpre" dev $wg_ifname
			wg set $wg_ifname private-key /tmp/wg.pki; rm /tmp/wg.pki
			ip link set $wg_ifname up

			# add outgoing clients to wg and bmxd (sollte hier nicht aufgerufen werden)
			# pass local ip addresses to callback
			wg_config_counter=0 #incremented in callback to create greX interfaces
			config_load ddmesh
			config_foreach callback_outgoing_wireguard_config backbone_client $_ddmesh_wireguard_ip "$_ddmesh_nonprimary_ip/$_ddmesh_netpre"
		fi
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
			ifconfig | grep tbb_wg | cut -f1 -d' ' | xargs -n 1 ip link del
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
