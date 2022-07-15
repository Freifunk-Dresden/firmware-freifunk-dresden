#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

WG_BIN=$(which wg)
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh tbbwg tbbwg)
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh tbb_wg wg)
WG_LOGGER_TAG="wg-backbone"

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh tbb_fastd fastd)
FASTD_CONF_DIR=/var/etc/fastd
FASTD_CONF=$FASTD_CONF_DIR/backbone-fastd.conf
FASTD_BIN=$(which fastd)
FASTD_LOGGER_TAG="fastd-backbone"
FASTD_PID_FILE=/var/run/backbone-fastd.pid
FASTD_CONF_PEERS=backbone-peers

DEFAULT_FASTD_PORT=$(uci -q get ddmesh.backbone.default_fastd_port)
DEFAULT_WG_PORT=$(uci -q get ddmesh.backbone.default_wg_port)
backbone_local_fastd_port=$(uci -q get ddmesh.backbone.fastd_port)
backbone_local_fastd_port=${backbone_local_fastd_port:-$DEFAULT_FASTD_PORT}
backbone_local_wg_port=$(uci -q get ddmesh.backbone.wg_port)
backbone_local_wg_port=${backbone_local_wg_port:-$DEFAULT_WG_PORT}
MTU=$(uci -q get ddmesh.network.mesh_mtu)

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
	test -z "$(uci -q get credentials.backbone_secret)" && {
		uci -q add credentials backbone_secret
		uci -q rename credentials.@backbone_secret[-1]='backbone_secret'
	}

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
	logger -t $FASTD_LOGGER_TAG "no fastd secret key - generating..."
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
	local disabled

	config_get key "$config" public_key
	config_get comment "$config" comment
	config_get disabled "$config" disabled

	#echo "fastd process accept: disabled:$disabled, $key # $comment"
	if [ "$disabled" != "1" -a -n "$key" ]; then
		FILE=$FASTD_CONF_DIR/$FASTD_CONF_PEERS/accept_$key.conf
		echo "fastd accept peer: [$key:$comment] ($FILE)"

		echo "# $comment" > $FILE
		echo "key \"$key\";" >> $FILE
		config_count=$((config_count + 1))
	fi
}

callback_outgoing_fastd_config ()
{
	local config="$1"
	local host  #hostname or ip
	local port
	local key
	local type
	local disabled

	config_get host "$config" host
	config_get port "$config" port
	config_get key "$config" public_key
	config_get type "$config" type
	[ -z "$type" ] && type="fastd"
	config_get disabled "$config" disabled

	#echo "fastd process out: disabled:$disabled, cfgtype:$type, host:$host, port:$port, key:$key"
	if [ "$disabled" != "1" -a "$type" == "fastd" -a -n "$host" -a -n "$port" -a -n "$key" ]; then
		FILE=$FASTD_CONF_DIR/$FASTD_CONF_PEERS/"connect_"$host"_"$port".conf"
		#echo "fastd out: add peer ($FILE)"
		echo "key \"$key\";" > $FILE
		echo "remote ipv4 \"$host\":$port;" >> $FILE
		config_count=$((config_count + 1))
	fi
}

# outgoing: only ipip tunnel
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
	local disabled

	config_get host "$config" host
	config_get port "$config" port
	config_get key "$config" public_key
	config_get type "$config" type
	config_get node "$config" node
	config_get disabled "$config" disabled

	#echo "wg process out: disabled:$disabled, cfgtype:$type, host:$host, port:$port, key:$key, target node:$node"
	if [ "$disabled" != "1" -a "$type" == "wireguard" -a -n "$host" -a -n "$port" -a -n "$key" -a -n "$node" ]; then

		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
		local remote_wg_ip=$_ddmesh_wireguard_ip

		#echo "wg out: add peer ($node)"

		# create sub interface
		sub_ifname="${wg_ifname/+/}${node}"
		ip link add $sub_ifname type ipip remote $remote_wg_ip local $local_wg_ip
		ip addr add $local_wgX_ip broadcast $_ddmesh_broadcast dev $sub_ifname
		ip link set $sub_ifname up

		/usr/lib/ddmesh/ddmesh-bmxd.sh add_if_wire $sub_ifname
	fi
}

# outgoing: only wg tunnel
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
	local disabled

	config_get host "$config" host
	config_get port "$config" port
	config_get key "$config" public_key
	config_get type "$config" type
	config_get node "$config" node
	config_get disabled "$config" disabled

	#echo "wg process out: disabled:$disabled, cfgtype:$type, host:$host, port:$port, key:$key, target node:$node"
	if [ "$disabled" != "1" -a "$type" == "wireguard" -a -n "$host" -a -n "$port" -a -n "$key" -a -n "$node" ]; then

		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
		local remote_wg_ip=$_ddmesh_wireguard_ip
		wg set $tbbwg_ifname peer $key persistent-keepalive 25 allowed-ips $remote_wg_ip/32 endpoint $host:$port

	fi
}

# incoming: wg tunnel + ipip tunnel
callback_incoming_wireguard ()
{
	local config="$1"
	local local_wg_ip=$2
	local local_wgX_ip=$3

	local key
	local type
	local node
	local disabled

	config_get key "$config" public_key
	config_get type "$config" type
	config_get node "$config" node
	config_get disabled "$config" disabled

	#echo "wg process out: disabled:$disabled, cfgtype:$type, key:$key, target node:$node]"
	if [ "$disabled" != "1" -a "$type" == "wireguard" -a -n "$key" -a -n "$node" ]; then

		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
		local remote_wg_ip=$_ddmesh_wireguard_ip

		echo "wg in: add peer ($node) $local_wg_ip -> $remote_wg_ip"

		# create sub interface
		sub_ifname="${wg_ifname/+/}${node}"
		ip link add $sub_ifname type ipip remote $remote_wg_ip local $local_wg_ip
		ip addr add $local_wgX_ip broadcast $_ddmesh_broadcast dev $sub_ifname
		ip link set $sub_ifname up

		/usr/lib/ddmesh/ddmesh-bmxd.sh add_if_wire $sub_ifname

		wg set $tbbwg_ifname peer $key persistent-keepalive 25 allowed-ips $remote_wg_ip/32
	fi
}


callback_firewall()
{
	local config="$1"
	local host  #hostname or ip
	local port

	config_get host "$config" host
	config_get port "$config" port

	if [ -n "$host" -a -n "$port" ]; then
		#dont use hostnames, can not be resolved
		iptables -w -D output_backbone_accept -p udp --dport $port -j ACCEPT 2>/dev/null
		iptables -w -D output_backbone_reject -p udp --dport $port -j reject 2>/dev/null
		iptables -w -A output_backbone_accept -p udp --dport $port -j ACCEPT
		iptables -w -A output_backbone_reject -p udp --dport $port -j reject
	fi
}

setup_firewall()
{
	iptables -w -F input_backbone_accept
	iptables -w -F input_backbone_reject
	iptables -w -A input_backbone_accept -p udp --dport $backbone_local_fastd_port -j ACCEPT
	iptables -w -A input_backbone_reject -p udp --dport $backbone_local_fastd_port -j reject
	iptables -w -A input_backbone_accept -p udp --dport $backbone_local_wg_port -j ACCEPT
	iptables -w -A input_backbone_reject -p udp --dport $backbone_local_wg_port -j reject
	iptables -w -F output_backbone_accept
	iptables -w -F output_backbone_reject
	config_load ddmesh
	config_foreach callback_firewall backbone_client
}

case "$1" in

	firewall-update)
		setup_firewall
		;;

	start)
		# FastD Backbone
		if [ -n "$FASTD_BIN" ]; then
			echo "Starting fastd backbone ..."
			mkdir -p $FASTD_CONF_DIR
			mkdir -p $FASTD_CONF_DIR/$FASTD_CONF_PEERS

			rm -f $FASTD_CONF
			rm -f $FASTD_CONF_DIR/$FASTD_CONF_PEERS/*

			generate_fastd_conf $fastd_ifname

			config_count=0

			# accept fastd clients
			config_load ddmesh
			config_foreach callback_accept_fastd_config backbone_accept

			# outgoing
			config_load ddmesh
			config_foreach callback_outgoing_fastd_config backbone_client

			[ ${config_count} -gt 0 ] && fastd --config $FASTD_CONF --pid-file $FASTD_PID_FILE --daemon
		fi

		if [ -n "$WG_BIN" ]; then
			echo "Starting wg backbone ..."

			eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
			local_wg_ip=$_ddmesh_wireguard_ip
			local_wg_ip_nonprimary=$_ddmesh_nonprimary_ip
			local_wg_ip_netpre=$_ddmesh_netpre
			local_wg_net=$_ddmesh_wireguard_network

			# create key
			secret=$(/sbin/uci -q get credentials.backbone_secret.wireguard_key)
			if [ -z "$secret" ]; then
				logger -t $WG_LOGGER_TAG "no wg secret key - generating..."
				gen_wg_key
				secret=$(/sbin/uci -q get credentials.backbone_secret.wireguard_key)
			fi

			# create tbbwg
			if [ -n "$secret" ]; then

				# refresh registration in case node has changed
				/usr/lib/ddmesh/ddmesh-backbone-regwg.sh refresh >/dev/null 2>/dev/null

				# setup local wg interface. this is used to receive/transmit data for/from
				# all peers (hosts)
				secret_file="/tmp/wg.pki"
				echo $secret > $secret_file
				ip link add $tbbwg_ifname type wireguard
				ip link set $tbbwg_ifname mtu 1320
				ip addr add "$local_wg_ip/32" dev $tbbwg_ifname
				wg set $tbbwg_ifname private-key $secret_file

				wg set $tbbwg_ifname listen-port $backbone_local_wg_port

				ip link set $tbbwg_ifname up
				rm $secret_file

				ip route add $local_wg_net/$local_wg_ip_netpre dev $tbbwg_ifname src $local_wg_ip

				# pass local ip addresses to callback
				# wg provides tunnels to all peers via one interface.
				# through this tunnel an ipip tunnel is setup from node to node, because of some
				# wg restrictions (no broacast possible). ipip tunnel has its own interface for
				# each peer. this iface is added to bmxd

				# add outgoing clients only interfaces (rest is done below "update" only if dns is working)
				config_load ddmesh
				config_foreach callback_outgoing_wireguard_interfaces backbone_client $local_wg_ip "$local_wg_ip_nonprimary/$local_wg_ip_netpre"

				# add incoming clients
				config_load ddmesh
				config_foreach callback_incoming_wireguard backbone_accept $local_wg_ip "$local_wg_ip_nonprimary/$local_wg_ip_netpre"
			fi
		fi

		# try to resolve host names and setup wg tunnel
		# wg command only resolves host name once. if no connection is available during
		# boot, wg gives up. we need to retry it later (via cron). I can

		# setup wireguard outgoing
		$0 update
		;;

	update) # called by ddmesh-tasks.sh

		# try to resolv and update wg config. wg does not interrupt connection
		# when there is no change

		# check for working dns to avoid delays created by wg-tool trying to resolve
		nslookup "freifunk-dresden.de" >/dev/null && {
			eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
			config_load ddmesh
			config_foreach callback_outgoing_wireguard_connection backbone_client $_ddmesh_wireguard_ip "$_ddmesh_nonprimary_ip/$_ddmesh_netpre"
		}
		;;

	stop)
		if [ -n "$FASTD_BIN" ]; then
			echo "Stopping backbone network..."
			if [ -f $FASTD_PID_FILE ]; then
				kill $(cat $FASTD_PID_FILE)
				rm -f $FASTD_PID_FILE
			fi
		fi
		if [ -n "$WG_BIN" -a -n "$wg_ifname" ]; then
			# delete all ipip tunnels
			LS=$(which ls)
			ifname="${wg_ifname/+/}"

			#ensure ifname is NOT empty
			if [ -n "$ifname" ]; then
				IFS='
'
				for i in $($LS -1d  "/sys/class/net/$ifname"* 2>/dev/null | sed 's#.*/##')
				do
					bmxd -c dev=-$i >/dev/null
					ip link del $i 2>/dev/null
				done
				unset IFS
			fi
			# remove peers
			for peer in $(wg show tbbwg+ | sed -n '/^peer:/s#peer:[ ]*##p')
			do
				wg set $tbbwg_ifname peer $peer remove
			done
		fi
		;;

	restart)
		$0 stop
		sleep 2
		$0 start
		;;

	gen_secret_key)
		if [ -n "$FASTD_BIN" ]; then
			gen_fastd_key
		fi
		;;

		gen_wgsecret_key)
		if [ -n "$WG_BIN" ]; then
						gen_wg_key
		fi
					;;

		get_public_key)
		if [ -n "$FASTD_BIN" ]; then
			fastd --machine-readable --show-key --config $FASTD_CONF
		fi
		;;

	runcheck)
		if [ -n "$FASTD_BIN" ]; then
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
