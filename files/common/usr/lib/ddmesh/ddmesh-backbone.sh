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

genwgkey()
{
	WG_PRIV=$(wg genkey)
	uci set credentials.wireguard.key="$WG_PRIV"
	uci_commit.sh
}

generate_fastd_conf()
{
 # sources: https://projects.universe-factory.net/projects/fastd/wiki
 # docs: http://fastd.readthedocs.org/en/v17/

 secret="$(uci -q get credentials.backbone_secret.key)"
 if [ -z "$secret" ]; then
	logger -t $FASTD_LOGGER_TAG "no secret key - generating..."
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

callback_accept_config ()
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

callback_outgoing_config ()
{
	local config="$1"
	local host  #hostname or ip
	local port
	local key
	local type
	local node
	local privkey=$(/sbin/uci get credentials.wireguard.key)
	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
	local localwgip=$_ddmesh_wireguard_ip
	local localwgtapip=$_ddmesh_nonprimary_ip
	config_get host "$config" host
	config_get port "$config" port
	config_get key "$config" public_key
	config_get type "$config" type
	config_get node "$config" node

	if [ ! -z $node ]; then
	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
	local remotewgip=$_ddmesh_wireguard_ip
	fi

	if [ -n "$host" -a -n "$port" -a -n "$key" -a -n "$key" ] && [ "$type" != "wireguard" ]; then
		#echo "[$host:$port:$key]"
		FILE=$FASTD_CONF_DIR/$FASTD_CONF_PEERS/"connect_"$host"_"$port".conf"
		echo "key \"$key\";" > $FILE
		echo "remote ipv4 \"$host\":$port;" >> $FILE

		#dont use hostnames, can not be resolved
		iptables -D output_backbone_accept -p udp --dport $port -j ACCEPT 2>/dev/null
		iptables -D output_backbone_reject -p udp --dport $port -j reject 2>/dev/null
		iptables -A output_backbone_accept -p udp --dport $port -j ACCEPT
		iptables -A output_backbone_reject -p udp --dport $port -j reject
	fi

	if [ "$type" == "wireguard" ];then 
		ip rule add to 10.203.0.0/16 lookup main prio 330
		INT_WG=tbb_wg_$node		#WG Interface
		INT_WGTAP=tbb_wg_tap_$node	#TAP Interface
		L_WG_IP=$(echo "$localwgip/16")		#local wg interface with netmask
		R_WG_IP=$(echo "$remotewgip/32")	#remote wg interface, one ip only
		echo $privkey >/tmp/wg.pki
		# Add WG Interface
		ip link add dev $INT_WG type wireguard
		ip addr add $L_WG_IP dev $INT_WG
		wg set $INT_WG private-key /tmp/wg.pki; rm /tmp/wg.pki
		wg set $INT_WG peer $key persistent-keepalive 25 allowed-ips $R_WG_IP endpoint $host:$port
		ip link set $INT_WG up
		# TAP Interface via WG
		ip link add $INT_WGTAP type gretap remote $remotewgip local $localwgip
		ip addr add $localwgtapip broadcast 10.255.255.255 dev $INT_WGTAP
		ip link set $INT_WGTAP up
		# Insert GRETAP interface
		bmxd -c dev=$INT_WGTAP /linklayer 1
	fi
}

case "$1" in

 start)
	iptables -F input_backbone_accept
	iptables -F input_backbone_reject

	# FastD Backbone
	if [ -f $FASTD_BIN ]; then
		echo "Starting fastd backbone ..."
		mkdir -p $FASTD_CONF_DIR
		mkdir -p $FASTD_CONF_DIR/$FASTD_CONF_PEERS

		rm -f $FASTD_CONF
		rm -f $FASTD_CONF_DIR/$FASTD_CONF_PEERS/*

		generate_fastd_conf
	fi
		# accept fastd and wg clients
 		config_load ddmesh
 		config_foreach callback_accept_config backbone_accept

		iptables -A input_backbone_accept -p udp --dport $backbone_server_port -j ACCEPT
  		iptables -A input_backbone_reject -p udp --dport $backbone_server_port -j reject

		# outgoing
		iptables -F output_backbone_accept
		iptables -F output_backbone_reject

 		config_load ddmesh
 		config_foreach callback_outgoing_config backbone_client

	if [ -f $FASTD_BIN ]; then
		fastd --config $FASTD_CONF --pid-file $FASTD_PID_FILE --daemon
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
		genkey
		generate_fastd_conf
	fi
	;;

  gen_wgsecret_key)
	if [ -f $WG_BIN ]; then
	        genwgkey
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
