#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

if [ -z "$1" ]; then
	echo "usage $(basename $0) restart_firewall | update-ignore"
	exit 1
fi

. /lib/functions.sh

#firewall rules that can not be created

eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
/usr/lib/ddmesh/ddmesh-utils-network-info.sh update
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh list)

TAG="ddmesh-firewall-addons.sh"

fwprint()
{
 logger -s -t "$TAG" "nft $*"
 nft $*
}

export NFT=fwprint
#export NFT=nft

export CHAIN_NAME="ddmesh_ignore_nodes"

setup_ipv6_rules()
{
	logger -s -t $TAG "setup_ipv6_rules"
  MARKER="ddmesh-block-ipv6"

	# check if setup was already done (only check one rule to speed-up)
	present="$(nft --json list ruleset | jsonfilter -e "@.nftables[@.rule.chain=\"input\" && @.rule.comment=\"${MARKER}\"].rule.chain")"
	if [ -z "$present" ]; then
		# block any ipv6
		for chain in input forward output
		do
			# insert chains in standard chains (input,output,forward)
			$NFT insert rule inet fw4 "$chain" position 0 meta l4proto ipv6 counter drop comment "\"${MARKER}\""
		done
	fi
}

# these rules prevent access router via ip addresses from different interfaces.
# function flushs chain and re-adds rules. it is save to call this anytime
#setup_blocked_iface_ip()
#{
#	logger -s -t $TAG "setup_blocked_iface_ip"
#	MARKER="ddmesh-block-iface-ip"
#
#	#add tables that are later filled with IPs that should be blocked.
#	# loop through zones
#	for i in mesh wifi2 ffgw lan wan vpn
#	do
#		chain="ddmesh_input_${i}_deny"
#		# create chains (with counter, but do not register with standard hooks because chain is added
#		# to specific openwrt chain
#		$NFT create chain inet fw4 ${chain} '{counter;}' 2>/dev/null
#		$NFT flush chain inet fw4 ${chain}
#
#		# insert my chains into openwrt chains
#		present="$(nft --json list ruleset | jsonfilter -e "@.nftables[@.rule.comment=\"${MARKER}-${i}-jump\"].rule.handle")"
#		if [ -z "$present" ]; then
#			$NFT insert rule inet fw4 input_${i} position 0 counter jump ${chain} comment "\"${MARKER}-${i}-jump\""
#		fi
#	done
#
#	# -- lan --
#	if [ "$lan_up" = "1" -a -n "$lan_network" -a -n "$lan_mask" ]; then
#		for i in mesh wifi2 ffgw wan vpn
#		do
#			chain="ddmesh_input_${i}_deny"
#			$NFT add rule inet fw4 ${chain} ip daddr "${lan_network}/${lan_mask}" counter goto handle_reject comment "\"${MARKER}-${i}-reject\""
#		done
#	fi
#
#	# -- wan --
#	if [ "$wan_up" = "1" -a -n "$wan_network" -a -n "$wan_mask" ]; then
#		for i in mesh wifi2 ffgw lan vpn
#		do
#			chain="ddmesh_input_${i}_deny"
#			$NFT add rule inet fw4 ${chain} ip daddr "${wan_network}/${wan_mask}" counter goto handle_reject comment "\"${MARKER}-${i}-reject\""
#		done
#	fi
#}

setup_nat_rules()
{
	logger -s -t $TAG "setup_nat_rules"

	# /etc/config/firewall defines zones with and without 'masq'. only when 'masq=1' then
	# a chain with srcnat_xxxx is created and inserted into chain 'srcnat'
	# Zones mesh,lan,wifi2  do not use masquerade rules (masq=0), but I have configured masq=1
	# for those zones to get the missing chains: srcnat_lan, srcnat_mesh, srcnat_wifi2
	# This means I can safely flush those chains and add my SNAT rules.
	# Means also, I can call this function (setup_nat_rules) anytime

	# flush chains
	$NFT flush chain inet fw4 srcnat_lan
	$NFT flush chain inet fw4 srcnat_mesh
	$NFT flush chain inet fw4 srcnat_wifi2


	# never change bmxd IPs
	MARKER="ddmesh-nat-bmxd"
	$NFT add rule inet fw4 srcnat_mesh udp dport 4305 counter accept comment "\"${MARKER}-accept\""

	# don't snat icmp to debug tbb links with ping
	MARKER="ddmesh-nat_icmp"
	$NFT add rule inet fw4 srcnat_mesh ip protocol icmp ip saddr ${_ddmesh_fullnet} counter accept comment "\"${MARKER}-accept\""

	# snat mesh from 10.201.xxx to 10.200.xxxx
	MARKER="ddmesh-nat"
	$NFT add rule inet fw4 srcnat_mesh ip saddr ${_ddmesh_linknet} counter snat to ${_ddmesh_ip} comment "\"${MARKER}-mesh\""

	# allow access to freifunk ip from wifi2 device
	$NFT add rule inet fw4 srcnat_mesh ip saddr ${_ddmesh_wifi2net} counter snat to ${_ddmesh_ip} comment "\"${MARKER}-wifi2-to-mesh\""

	if [ "$lan_up" = "1" -a -n "$lan_network" -a -n "$lan_mask" ]; then
		# allow access to freifunk ip from wifi2 device
		$NFT add rule inet fw4 srcnat_mesh ip saddr "${lan_network}/${lan_mask}" counter snat to ${_ddmesh_ip} comment "\"${MARKER}-lan-to-mesh\""

		# allow portforwarding to lan zone
		$NFT add rule inet fw4 srcnat_lan ip daddr "${lan_network}/${lan_mask}" counter snat to ${lan_ipaddr} comment "\"${MARKER}-portforward-lan\""
	fi

	if [ "$wifi2_up" = "1" -a -n "$wifi2_ipaddr" -a -n "$wifi2_mask" ]; then
		# allow portforwarding to wifi2 zone
		$NFT add rule inet fw4 srcnat_wifi2 ip daddr "${wifi2_ipaddr}/${wifi2_mask}" counter snat to ${wifi2_ipaddr} comment "\"${MARKER}-portforward-wifi2\""
	fi

}

callback_add_ignored_nodes()
{
	local entry="$1"
	IFS=':'
	set $entry
	unset IFS
	local node=$1
	local opt_lan=$2
	local opt_tbb=$3
	local opt_wifi_mesh2g=$5
	local opt_wifi_mesh5g=$6
	local opt_vlan=$7

	# if no flag is set, only node is given (old format)
	# -> enable wifi only

	MARKER="ddmesh-ignore-nodes"
	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
	if [ "$opt_lan" = "1" ]; then
		for i in mesh_lan mesh_wan
		do
			$NFT add rule inet fw4 "ddmesh_ignore_nodes_${i}" ip daddr ${_ddmesh_nonprimary_ip} counter reject comment "\"${MARKER}-${i}-reject\""
		done
	fi
	if [ "$opt_tbb" = "1" ]; then
		for i in tbb_wg tbb_fastd
		do
			$NFT add rule inet fw4 "ddmesh_ignore_nodes_${i}" ip daddr ${_ddmesh_nonprimary_ip} counter reject comment "\"${MARKER}-${i}-reject\""
		done
	fi
	if [ "$opt_wifi_mesh2g" = "1" ]; then
		i="wifi_mesh2g"
		$NFT add rule inet fw4 "ddmesh_ignore_nodes_${i}" ip daddr ${_ddmesh_nonprimary_ip} counter reject comment "\"${MARKER}-${i}-reject\""
	fi
	if [ "$opt_wifi_mesh5g" = "1" ]; then
		i="wifi_mesh5g"
		$NFT add rule inet fw4 "ddmesh_ignore_nodes_${i}" ip daddr ${_ddmesh_nonprimary_ip} counter reject comment "\"${MARKER}-${i}-reject\""
	fi
	if [ "$opt_vlan" = "1" ]; then
		i="mesh_vlan"
		$NFT add rule inet fw4 "ddmesh_ignore_nodes_${i}" ip daddr ${_ddmesh_nonprimary_ip} counter reject comment "\"${MARKER}-${i}-reject\""
	fi
}

setup_ignored_nodes() {
	logger -s -t $TAG "setup_ignored_nodes"

	for i in wifi_mesh2g wifi_mesh5g mesh_lan mesh_wan mesh_vlan tbb_wg tbb_fastd
	do
		chain="ddmesh_ignore_nodes_${i}"
		$NFT create chain inet fw4 ${chain} '{counter;}' 2>/dev/null
		$NFT flush chain inet fw4 ${chain}

		# insert my chains into openwrt chains
		MARKER="ddmesh-ignore-nodes-${i}-jump"
		present="$(nft --json list ruleset | jsonfilter -e "@.nftables[@.rule.comment=\"${MARKER}\"].rule.handle")"
		if [ -z "$present" ]; then
			iface="$(eval echo "\$net_${i}")"
			# replace '+' with '*'
			iface="${iface/+/*}"
			# udp dport 4305
			$NFT insert rule inet fw4 input_mesh position 0 iifname ${iface} counter jump ${chain} comment "\"${MARKER}\""
		fi
  done

	config_load ddmesh
	config_list_foreach ignore_nodes node callback_add_ignored_nodes
  # reset back (was temporarily changed)
	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
}

case "$1" in
	restart_firewall)
		setup_ipv6_rules
#		setup_blocked_iface_ip
		setup_nat_rules
		setup_ignored_nodes

		;;

#  firewall-update)
#    # used for hotplug wan port
#    setup_blocked_iface_ip
#    ;;

	update-ignore)
		setup_ignored_nodes
		;;

	*)
		echo "invalid arg"
		;;

esac
