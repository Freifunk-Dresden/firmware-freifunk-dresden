#!/bin/sh

. /lib/functions.sh

IPT=iptables
PROTECTED_PORTS="22 53 68 80 81 443 4305 4306 4307"


setup_forwarding() {
	# prepare forwarding	
	$IPT -t nat -N PORT_FORWARDING
	$IPT -t nat -N PORT_FORWARDING_PROTECT
	$IPT -t nat -N PORT_FORWARDING_RULES
	$IPT -t nat -A PORT_FORWARDING -j PORT_FORWARDING_PROTECT
	$IPT -t nat -A PORT_FORWARDING -j PORT_FORWARDING_RULES
	$IPT -t nat -A prerouting_wifi_rule -d $_ddmesh_ip -j PORT_FORWARDING 
	$IPT -t nat -A prerouting_tbb_rule -d $_ddmesh_ip -j PORT_FORWARDING 
	$IPT -t nat -A prerouting_lan_rule -d $_ddmesh_ip -j PORT_FORWARDING 
	$IPT -t nat -A prerouting_lan_rule -d $lan_ipaddr -j PORT_FORWARDING 
	$IPT -t nat -A prerouting_wifi2_rule -d $_ddmesh_ip -j PORT_FORWARDING 
	
	$IPT -N PORT_FORWARDING
	$IPT -N PORT_FORWARDING_RULES
	$IPT -A PORT_FORWARDING -j PORT_FORWARDING_RULES
	$IPT -A forwarding_wifi_rule -o $lan_device -d $lan_network/$lan_mask -j PORT_FORWARDING 
	$IPT -A forwarding_tbb_rule -o $lan_device -d $lan_network/$lan_mask -j PORT_FORWARDING 
	$IPT -A forwarding_lan_rule -o $lan_device -d $lan_network/$lan_mask -j PORT_FORWARDING 
	$IPT -A forwarding_wifi2_rule -o $lan_device -d $lan_network/$lan_mask -j PORT_FORWARDING 
}

setup_rules() {
	local config="$1"
	local user_arg="$2"
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
	if [ "$vproto" = "tcp" -o "$vproto" = "tcpudp" ]; then
		$IPT -t nat -A PORT_FORWARDING_RULES -p tcp --dport $vsrc_dport -j DNAT --to-destination $vdest_ip:$vdest_port
		$IPT -A PORT_FORWARDING_RULES -p tcp -d $vdest_ip --dport $vdest_port -o $lan_device -j ACCEPT
	fi
	
	if [ "$vproto" = "udp" -o "$vproto" = "tcpudp" ]; then
		$IPT -t nat -A PORT_FORWARDING_RULES -p udp --dport $vsrc_dport -j DNAT --to-destination $vdest_ip:$vdest_port
		$IPT -A PORT_FORWARDING_RULES -p udp -d $vdest_ip --dport $vdest_port -o $lan_device -j ACCEPT
	fi
}

load() {
	$IPT -t nat -F PORT_FORWARDING_RULES
	$IPT -F PORT_FORWARDING_RULES
	config_load ddmesh
	config_foreach setup_rules portforwarding
}

if [ "$1" = "init" -o "$1" = "load" ]; then
	eval $(/usr/bin/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh lan lan)
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
