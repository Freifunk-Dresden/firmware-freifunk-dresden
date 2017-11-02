#!/bin/sh

. /lib/functions.sh

PROTECTED_PORTS="22 53 68 80 81 443 4305 4306 4307"
PROTECTED_PORTS="$PROTECTED_PORTS $(uci -q get ddmesh.backbone.server_port)"
PROTECTED_PORTS="$PROTECTED_PORTS $(uci -q get ddmesh.privnet.server_port)"

fwprint()
{
#	echo iptables $*
	iptables -w $*
}

IPT=fwprint

setup_forwarding() {
	# prepare forwarding
	$IPT -t nat -N PORT_FORWARDING
	$IPT -t nat -N PORT_FORWARDING_PROTECT
	$IPT -t nat -N PORT_FORWARDING_RULES

	#flush when script is re-started (wan dhcp, delayed)
	$IPT -t nat -F PORT_FORWARDING
	$IPT -t nat -F PORT_FORWARDING_PROTECT
	$IPT -t nat -F PORT_FORWARDING_RULES

	$IPT -t nat -A PORT_FORWARDING -j PORT_FORWARDING_PROTECT
	$IPT -t nat -A PORT_FORWARDING -j PORT_FORWARDING_RULES

	for table in prerouting_mesh_rule prerouting_lan_rule prerouting_wifi2_rule
	do
		$IPT -t nat -D $table -d $_ddmesh_ip -j PORT_FORWARDING 2>/dev/null
		$IPT -t nat -A $table -d $_ddmesh_ip -j PORT_FORWARDING
	done
	$IPT -t nat -D prerouting_lan_rule -d $lan_ipaddr -j PORT_FORWARDING 2>/dev/null
	$IPT -t nat -A prerouting_lan_rule -d $lan_ipaddr -j PORT_FORWARDING

	$IPT -N PORT_FORWARDING
	$IPT -N PORT_FORWARDING_RULES

	#flush when script is re-started (wan dhcp, delayed)
	$IPT -F PORT_FORWARDING
	$IPT -F PORT_FORWARDING_RULES

	$IPT -A PORT_FORWARDING -j PORT_FORWARDING_RULES

	for table in forwarding_mesh_rule forwarding_lan_rule forwarding_wifi2_rule
	do
		if [ "$lan_up" = "1" ]; then
			$IPT -D $table -o $lan_ifname -d $lan_network/$lan_mask -j PORT_FORWARDING 2>/dev/null
			$IPT -A $table -o $lan_ifname -d $lan_network/$lan_mask -j PORT_FORWARDING
		fi
		if [ "$wifi2_up" = "1" ]; then
			$IPT -D $table -o $wifi2_ifname -d $wifi2_network/$wifi2_mask -j PORT_FORWARDING 2>/dev/null
			$IPT -A $table -o $wifi2_ifname -d $wifi2_network/$wifi2_mask -j PORT_FORWARDING
		fi
	done

	if [ $wan_up = 1 ]; then
		for table in forwarding_mesh_rule forwarding_lan_rule forwarding_wifi2_rule
		do
			$IPT -D $table -o $wan_ifname -d $wan_network/$wan_mask -j PORT_FORWARDING 2>/dev/null
			$IPT -A $table -o $wan_ifname -d $wan_network/$wan_mask -j PORT_FORWARDING
		done
	fi
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
			$IPT -t nat -A PORT_FORWARDING_RULES -p tcp --dport $vsrc_dport -j DNAT --to-destination $vdest_ip:$vdest_port
			$IPT -A PORT_FORWARDING_RULES -p tcp -d $vdest_ip --dport $vdest_port -o $lan_ifname -j ACCEPT
			test $wan_up = 1 && $IPT -A PORT_FORWARDING_RULES -p tcp -d $vdest_ip --dport $vdest_port -o $wan_ifname -j ACCEPT
			test $wifi2_up = 1 && $IPT -A PORT_FORWARDING_RULES -p tcp -d $vdest_ip --dport $vdest_port -o $wifi2_ifname -j ACCEPT
		fi

		if [ "$vproto" = "udp" -o "$vproto" = "tcpudp" ]; then
			$IPT -t nat -A PORT_FORWARDING_RULES -p udp --dport $vsrc_dport -j DNAT --to-destination $vdest_ip:$vdest_port
			$IPT -A PORT_FORWARDING_RULES -p udp -d $vdest_ip --dport $vdest_port -o $lan_ifname -j ACCEPT
			test $wan_up = 1 && $IPT -A PORT_FORWARDING_RULES -p udp -d $vdest_ip --dport $vdest_port -o $wan_ifname -j ACCEPT
			test $wifi2_up = 1 && $IPT -A PORT_FORWARDING_RULES -p udp -d $vdest_ip --dport $vdest_port -o $wifi2_ifname -j ACCEPT
		fi
	fi
}

load() {
	$IPT -t nat -F PORT_FORWARDING_RULES
	$IPT -F PORT_FORWARDING_RULES
	config_load ddmesh
	config_foreach setup_rules
}

if [ "$1" = "init" -o "$1" = "load" ]; then
	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)
fi

case "$1" in
	init)
		setup_forwarding

		for p in $PROTECTED_PORTS
		do
			$IPT -t nat -A PORT_FORWARDING_PROTECT -p tcp --dport $p -j ACCEPT
			$IPT -t nat -A PORT_FORWARDING_PROTECT -p udp --dport $p -j ACCEPT
		done
		load ;;
	load)	load ;;
	ports)  echo $PROTECTED_PORTS ;;

	*) echo "usage: $1 init|load|ports" ;;
esac
