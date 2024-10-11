#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

PROTECTED_PORTS="22 53 68 80 443 4305"
PROTECTED_PORTS="$PROTECTED_PORTS $(uci -q get ddmesh.backbone.fastd_port)"
PROTECTED_PORTS="$PROTECTED_PORTS $(uci -q get ddmesh.privnet.fastd_port)"

fwprint()
{
 logger -s -t "$TAG" "nft $*"
 nft $*
}
export NFT=fwprint
#export NFT=nft

setup_forwarding()
{
	# prepare "NAT" tables
	$IPT -w -t nat -N PORT_FORWARDING 2>/dev/null
	$IPT -w -t nat -N PORT_FORWARDING_PROTECT 2>/dev/null
	$IPT -w -t nat -N PORT_FORWARDING_RULES 2>/dev/null

	#flush when script is re-started (wan dhcp, delayed)
	$IPT -w -t nat -F PORT_FORWARDING
	$IPT -w -t nat -F PORT_FORWARDING_PROTECT
	$IPT -w -t nat -F PORT_FORWARDING_RULES

	$IPT -w -t nat -A PORT_FORWARDING -j PORT_FORWARDING_PROTECT -m comment --comment 'ddmesh:portfw'
	$IPT -w -t nat -A PORT_FORWARDING -j PORT_FORWARDING_RULES -m comment --comment 'ddmesh:portfw'

	# forward incomming packets to from anywhere to node ip
	for table in prerouting_mesh_rule prerouting_lan_rule prerouting_wifi2_rule
	do
		for cmd in D A
		do
			$IPT -w -t nat -$cmd $table -d $_ddmesh_ip -j PORT_FORWARDING -m comment --comment 'ddmesh:portfw' 2>/dev/null
		done
	done

	# forward incomming packets from lan to lan ip
	# interface might not be ready yet (wait for other hotplug updates)
	if [ "$lan_up" = "1" -a -n "$lan_ipaddr" ]; then
		for cmd in D A
		do
				$IPT -w -t nat -$cmd prerouting_lan_rule -s $lan_network/$lan_mask -d $lan_ipaddr -j PORT_FORWARDING -m comment --comment 'ddmesh:portfw' 2>/dev/null
		done
	fi

	# forward incomming packets from wan to wan ip
	# interface might not be ready yet (wait for other hotplug updates)
	if [ "$wan_up" = "1" -a -n "$wan_ipaddr" ]; then
		for cmd in D A
		do
			$IPT -w -t nat -$cmd prerouting_wan_rule -s $wan_network/$wan_mask -d $wan_ipaddr -j PORT_FORWARDING -m comment --comment 'ddmesh:portfw' 2>/dev/null
		done
	fi

	# allow port forwarding when request comes from lan,mesh,wifi2
	# no need to check for dest ip and interface, as user adds its with intention
	for cmd in D A
	do
		$IPT -w -$cmd forwarding_wifi2_rule -m conntrack --ctstate DNAT -j ACCEPT -m comment --comment 'ddmesh:portfw' 2>/dev/null
		$IPT -w -$cmd forwarding_lan_rule -m conntrack --ctstate DNAT -j ACCEPT -m comment --comment 'ddmesh:portfw' 2>/dev/null
		$IPT -w -$cmd forwarding_mesh_rule -m conntrack --ctstate DNAT -j ACCEPT -m comment --comment 'ddmesh:portfw' 2>/dev/null
	done

}

setup_rules() {
	local config="$1"
	local vname
	local vproto
	local vsrc_dport
	local vdest_ip
	local vdest_port

	config_get vname "$config" name
	config_get vproto "$config" proto
	config_get vsrc_dport "$config" src_dport
	config_get vdest_ip "$config" dest_ip
	config_get vdest_port "$config" dest_port

	#correct port range
	vsrc_dport=${vsrc_dport/-/:}

	if [ -n "$vsrc_dport" -a -n "$vdest_ip" -a -n "$vdest_port" ]; then
		if [ "$vproto" = "tcp" -o "$vproto" = "tcpudp" ]; then
			$IPT -w -t nat -A PORT_FORWARDING_RULES -p tcp --dport $vsrc_dport -j DNAT --to-destination $vdest_ip:$vdest_port -m comment --comment 'ddmesh:portfw'
		fi

		if [ "$vproto" = "udp" -o "$vproto" = "tcpudp" ]; then
			$IPT -w -t nat -A PORT_FORWARDING_RULES -p udp --dport $vsrc_dport -j DNAT --to-destination $vdest_ip:$vdest_port -m comment --comment 'ddmesh:portfw'
		fi
	fi
}


case "$1" in
	load)
		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
		eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)

		setup_forwarding

		for p in $PROTECTED_PORTS
		do
			$IPT -w -t nat -A PORT_FORWARDING_PROTECT -p tcp --dport $p -j ACCEPT -m comment --comment 'ddmesh:portfw'
			$IPT -w -t nat -A PORT_FORWARDING_PROTECT -p udp --dport $p -j ACCEPT -m comment --comment 'ddmesh:portfw'
		done

		config_load ddmesh
		config_foreach setup_rules
		;;

	ports)  echo $PROTECTED_PORTS ;;

	*) echo "usage: $1  load | ports" ;;
esac
