#!/bin/bash

VERSION="uci V1.0"

wg_ifname=tbb_wg
port=5003
peers_dir="/etc/wireguard-backbone/peers"

if [ -z "$(which uci)" ]; then
	echo "Error: command 'uci' not found"
	exit 1
fi


local_node=$(uci get ffdd.sys.ddmesh_node)
eval $(ddmesh-ipcalc.sh -n $local_node)

echo "DEVEL: manuall calculation of _ddmesh_wireguard_ip"
local_wireguard_ip=${_ddmesh_ip/10\.200\./10.203.}
local_wgX_ip="$_ddmesh_nonprimary_ip/$_ddmesh_netpre"

start_wg()
{
	# create config section
	if [ -z "$(uci -q get ffdd.wireguard)" ]; then
		uci -q add ffdd wireguard
		uci -q rename ffdd.@wireguard[-1]='wireguard'
	fi

	# create key
	secret=$(uci -q get ffdd.wireguard.secret)
	if [ -z "$secret" ]; then
		echo "create wireguard key"
		secret=$(wg genkey)
		uci -q set ffdd.wireguard.secret="$secret"
	fi

	# store public
	public=$(echo $secret | wg pubkey)
	uci -q set ffdd.wireguard.public="$public"

	# save config
	uci commit

	secret_file=$(tempfile)
	echo $secret > $secret_file

	# create interface
	echo "create wireguard interface [$wg_ifname]"
	
echo	ip link add $wg_ifname type wireguard
	ip link add $wg_ifname type wireguard
echo	ip addr add "$local_wireguard_ip/32" dev $wg_ifname
	ip addr add "$local_wireguard_ip/32" dev $wg_ifname
echo	wg set $wg_ifname private-key $secret_file
	wg set $wg_ifname private-key $secret_file
echo	wg set $wg_ifname listen-port $port
	wg set $wg_ifname listen-port $port
echo	ip link set $wg_ifname up
	ip link set $wg_ifname up
	rm $secret_file

	ip rule add to 10.203.0.0/16 table main prio 304
	ip route add 10.203.0.0/16 dev tbb_wg src $local_wireguard_ip
	WAN_DEV="$(uci get ffdd.sys.ifname)"
	iptables -w -D INPUT -i $WAN_DEV -p udp --dport $port -j ACCEPT
	iptables -w -I INPUT -i $WAN_DEV -p udp --dport $port -j ACCEPT
	iptables -w -D INPUT -i tbb_wg+ -j ACCEPT
	iptables -w -I INPUT -i tbb_wg+ -j ACCEPT
}


stop_wg()
{
	LS=$(which ls)
	IFS='
'
	for i in $($LS -1d  /sys/class/net/$wg_ifname* 2>/dev/null | sed 's#.*/##')
	do
		[ "$i" != "$wg_ifname" ] && bmxd -c dev=-$i 
		ip link del $i 2>/dev/null
	done
	unset IFS

	ip rule del to 10.203.0.0/16 table main prio 304
}

accept_peer()
{
	node=$1
	key=$2
	store=$3	# if 1 it will write config


	eval $(ddmesh-ipcalc.sh -n $node)
	echo "DEVEL: manuall calculation of _ddmesh_wireguard_ip"
	remote_wireguard_ip=${_ddmesh_ip/10\.200\./10.203.}

	wg set $wg_ifname  peer $key persistent-keepalive 25 allowed-ips $remote_wireguard_ip/32

	# add ipip tunnel
	sub_ifname="$wg_ifname$node"
	#ip link add $sub_ifname type ipip remote $remote_wireguard_ip local $local_wireguard_ip
	ip link add $sub_ifname type ipip remote $remote_wireguard_ip local $local_wireguard_ip
	ip addr add $local_wgX_ip broadcast $_ddmesh_broadcast dev $sub_ifname
	ip link set $sub_ifname up

	bmxd -c dev=$sub_ifname /linklayer 1

	if [ "$store" = "1" ]; then
		echo "node $node" > $peers_dir/accept_$node
		echo "key $key" >> $peers_dir/accept_$node
	fi
}

remove_peer()
{
	node=$1
	key=$2
	wg set tbb_wg peer "$key" remove
	rm "$peers_dir/accept_$node"
}

load_accept_peers()
{
	for peer in $(ls $peers_dir/accept_* 2>/dev/null)
	do
		eval "$(awk '/^node/{printf("node=%s\n",$2)} /^key/{printf("key=%s\n",$2)}' $peer)"
		accept_peer $node $key 0
	done
}

case $1 in
	start)
		mkdir -p $peers_dir
		start_wg
		load_accept_peers
		;;

	stop)
		stop_wg
		;;

	reload)
		load_accept_peers
		;;

	accept)
		node=$2
		key=$3
		if [ -z "$3" ]; then
			echo "missing parameters"
			exit 1
		fi
		# check if we have already accepted for this node
		# It prevents accidential overwriting working configs
		if [ -f "$peers_dir/accept_$node" ]; then
			echo "Error: node already accepted"
			exit 1
		fi
		accept_peer $node $key 1
		;;

	delete)
		node=$2
		if [ -z "$2" ]; then
			echo "missing parameters"
			exit 1
		fi
		
		eval "$(awk '/^node/{printf("node=%s\n",$2)} /^key/{printf("key=%s\n",$2)}' $peers_dir/accept_$node )"

		read -s -p "delete $node [y/N]: " -n 1 -a input && echo ${input[0]}
		if [ "${input[0]}" = "y" ]; then
			remove_peer $node $key
			echo "peer $node deleted"
		else
			echo "keep peer $node"
		fi
		;;

	status)
		wg show $wg_ifname 
		;;

	*)
		echo "$(basename $0) Version $VERSION"
		echo "$(basename $0) [start | stop | reload | status | accept <node> <pubkey> | delete <node> ]"
		echo ""
		;;
esac
