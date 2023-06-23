#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

PROTECTED_PORTS="22 53 68 80 443 4305 4306 4307"
PROTECTED_PORTS="$PROTECTED_PORTS $(uci -q get ddmesh.backbone.fastd_port)"
PROTECTED_PORTS="$PROTECTED_PORTS $(uci -q get ddmesh.privnet.fastd_port)"

fwprint()
{
	echo iptables $*
	iptables $*
}

# export IPT=fwprint
export IPT=iptables

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

	$IPT -w -t nat -A PORT_FORWARDING -j PORT_FORWARDING_PROTECT
	$IPT -w -t nat -A PORT_FORWARDING -j PORT_FORWARDING_RULES

	# forward incomming packets to PORT_FORWARDING rules (from wifi range to _ddmesh_ip)
	for table in prerouting_mesh_rule prerouting_lan_rule prerouting_wifi2_rule
	do
		$IPT -w -t nat -D $table -s $_ddmesh_network/$_ddmesh_netpre -d $_ddmesh_ip -j PORT_FORWARDING 2>/dev/null
		$IPT -w -t nat -A $table -s $_ddmesh_network/$_ddmesh_netpre -d $_ddmesh_ip -j PORT_FORWARDING
	done

	# forward incomming packets to PORT_FORWARDING rules (from lan range to lan ip)
	# interface might not be ready yet (wait for other hotplug updates)
	if [ "$lan_up" = "1" -a -n "$lan_ipaddr" ]; then
		$IPT -w -t nat -D prerouting_lan_rule -s $lan_network/$lan_mask -d $lan_ipaddr -j PORT_FORWARDING 2>/dev/null
		$IPT -w -t nat -A prerouting_lan_rule -s $lan_network/$lan_mask -d $lan_ipaddr -j PORT_FORWARDING
	fi

	# forward incomming packets to PORT_FORWARDING rules (to wan ip)
	# interface might not be ready yet (wait for other hotplug updates)
	if [ "$wan_up" = "1" -a -n "$wan_ipaddr" ]; then
		$IPT -w -t nat -D prerouting_wan_rule -s $wan_network/$wan_mask -d $wan_ipaddr -j PORT_FORWARDING 2>/dev/null
		$IPT -w -t nat -A prerouting_wan_rule -s $wan_network/$wan_mask -d $wan_ipaddr -j PORT_FORWARDING
	fi

	# prepare "filter" table
	$IPT -w -N PORT_FORWARDING 2>/dev/null
	$IPT -w -N PORT_FORWARDING_RULES 2>/dev/null

	#flush when script is re-started (wan dhcp, delayed)
	$IPT -w -F PORT_FORWARDING
	$IPT -w -F PORT_FORWARDING_RULES

	$IPT -w -A PORT_FORWARDING -j PORT_FORWARDING_RULES

	# allow forwarding via rules in PORT_FORWARDING (security: restrict to interface ip range only)
	for table in forwarding_mesh_rule forwarding_lan_rule forwarding_wifi2_rule
	do
		if [ "$lan_up" = "1" -a -n "$lan_network" -a -n "$lan_mask" ]; then
			$IPT -w -D $table -o $lan_ifname -d $lan_network/$lan_mask -j PORT_FORWARDING 2>/dev/null
			$IPT -w -A $table -o $lan_ifname -d $lan_network/$lan_mask -j PORT_FORWARDING
		fi
		if [ "$wifi2_up" = "1" -a -n "$wifi2_network" -a -n "$wifi2_mask" ]; then
			$IPT -w -D $table -o $wifi2_ifname -d $wifi2_network/$wifi2_mask -j PORT_FORWARDING 2>/dev/null
			$IPT -w -A $table -o $wifi2_ifname -d $wifi2_network/$wifi2_mask -j PORT_FORWARDING
		fi
		if [ "$wan_up" = 1 -a -n "$wan_network" -a -n "$wan_mask" ]; then
			$IPT -w -D $table -o $wan_ifname -d $wan_network/$wan_mask -j PORT_FORWARDING 2>/dev/null
			$IPT -w -A $table -o $wan_ifname -d $wan_network/$wan_mask -j PORT_FORWARDING
		fi
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
			$IPT -w -t nat -A PORT_FORWARDING_RULES -p tcp --dport $vsrc_dport -j DNAT --to-destination $vdest_ip:$vdest_port
			$IPT -w -A PORT_FORWARDING_RULES -p tcp -d $vdest_ip --dport $vdest_port -o $lan_ifname -j ACCEPT
			test "$wan_up" = 1 && $IPT -w -A PORT_FORWARDING_RULES -p tcp -d $vdest_ip --dport $vdest_port -o $wan_ifname -j ACCEPT
			test "$wifi2_up" = 1 && $IPT -w -A PORT_FORWARDING_RULES -p tcp -d $vdest_ip --dport $vdest_port -o $wifi2_ifname -j ACCEPT
		fi

		if [ "$vproto" = "udp" -o "$vproto" = "tcpudp" ]; then
			$IPT -w -t nat -A PORT_FORWARDING_RULES -p udp --dport $vsrc_dport -j DNAT --to-destination $vdest_ip:$vdest_port
			$IPT -w -A PORT_FORWARDING_RULES -p udp -d $vdest_ip --dport $vdest_port -o $lan_ifname -j ACCEPT
			test "$wan_up" = 1 && $IPT -w -A PORT_FORWARDING_RULES -p udp -d $vdest_ip --dport $vdest_port -o $wan_ifname -j ACCEPT
			test "$wifi2_up" = 1 && $IPT -w -A PORT_FORWARDING_RULES -p udp -d $vdest_ip --dport $vdest_port -o $wifi2_ifname -j ACCEPT
		fi
	fi
}


if [ "$1" = "init" -o "$1" = "load" ]; then
	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)
fi

case "$1" in
	load)
		setup_forwarding

		for p in $PROTECTED_PORTS
		do
			$IPT -w -t nat -A PORT_FORWARDING_PROTECT -p tcp --dport $p -j ACCEPT
			$IPT -w -t nat -A PORT_FORWARDING_PROTECT -p udp --dport $p -j ACCEPT
		done

		config_load ddmesh
		config_foreach setup_rules
		;;

	ports)  echo $PROTECTED_PORTS ;;

	*) echo "usage: $1 init|load|ports" ;;
esac
