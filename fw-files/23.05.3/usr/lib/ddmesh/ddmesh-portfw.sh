#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

TAG="ddmesh-portfw.sh"

eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)

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

callback_rules() {
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

	MARKER="ddmesh-forwarding-rules"

	#correct port range
	vsrc_dport=${vsrc_dport/-/:}

	if [ -n "$vsrc_dport" -a -n "$vdest_ip" -a -n "$vdest_port" ]; then
		if [ "$vproto" = "tcp" -o "$vproto" = "tcpudp" ]; then
			$NFT add rule inet fw4 "ddmesh_forwarding_nat_rules" tcp dport ${vsrc_dport} counter dnat ip to ${vdest_ip}:${vdest_port} comment "\"${MARKER}\""
		fi

		if [ "$vproto" = "udp" -o "$vproto" = "tcpudp" ]; then
			$NFT add rule inet fw4 "ddmesh_forwarding_nat_rules" udp dport ${vsrc_dport} counter dnat ip to ${vdest_ip}:${vdest_port} comment "\"${MARKER}\""
		fi
	fi
}

setup_forwarding()
{
	logger -s -t $TAG "setup_forwarding"

	# nft type 'nat' -> use chain 'dstnat'
	# keep order !!!
	for i in protect rules
	do
		chain="ddmesh_forwarding_nat_${i}"
		$NFT create chain inet fw4 ${chain} '{counter;}' 2>/dev/null
		$NFT flush chain inet fw4 ${chain}

		# insert my chains into openwrt chains
		# Any package with destination _ddmesh_ip
		MARKER="ddmesh-forwarding-nat-${i}-ip-jump"
		present="$(nft --json list ruleset | jsonfilter -e "@.nftables[@.rule.comment=\"${MARKER}\"].rule.handle")"
		if [ -z "$present" ]; then
			$NFT add rule inet fw4 "dstnat" ip daddr ${_ddmesh_ip} counter jump ${chain} comment "\"${MARKER}\""
		fi

		# forward incomming packets from lan to lan ip
		# interface might not be ready yet (wait for other hotplug updates)
		if [ "$lan_up" = "1" -a -n "$lan_ipaddr" ]; then
			MARKER="ddmesh-forwarding-nat-${i}-lan-jump"
			present="$(nft --json list ruleset | jsonfilter -e "@.nftables[@.rule.comment=\"${MARKER}\"].rule.handle")"
			if [ -z "$present" ]; then
				$NFT add rule inet fw4 "dstnat" ip saddr ${lan_network}/${lan_mask} ip daddr ${lan_ipaddr} counter jump ${chain} comment "\"${MARKER}\""
			fi
		fi

		# forward incomming packets from wan to wan ip
		# interface might not be ready yet (wait for other hotplug updates)
		if [ "$wan_up" = "1" -a -n "$wan_ipaddr" ]; then
			MARKER="ddmesh-forwarding-nat-${i}-wan-jump"
			present="$(nft --json list ruleset | jsonfilter -e "@.nftables[@.rule.comment=\"${MARKER}\"].rule.handle")"
			if [ -z "$present" ]; then
				$NFT add rule inet fw4 "dstnat" ip saddr ${wan_network}/${wan_mask} ip daddr ${wan_ipaddr} counter jump ${chain} comment "\"${MARKER}\""
			fi
		fi
	done

	# nft type 'filter' -> use chain 'dstnat'
	# allow port forwarding when request comes from lan,mesh,wifi2
	# no need to check for dest ip and interface, as user adds its with intention
	for i in mesh wifi2 lan wan
	do
		MARKER="ddmesh-forwarding-${i}-jump"
		# insert before rules form /etc/config/firewall
		present="$(nft --json list ruleset | jsonfilter -e "@.nftables[@.rule.comment=\"${MARKER}\"].rule.handle")"
		if [ -z "$present" ]; then
			$NFT insert rule inet fw4 "forward_${i}" position 0 ct status dnat counter accept comment "\"${MARKER}\""
		fi
	done

	# (re)fill in protected ports
	MARKER="ddmesh-forwarding-protect-ports"
	for p in $PROTECTED_PORTS
	do
		$NFT add rule inet fw4 "ddmesh_forwarding_nat_protect" tcp dport ${p} counter accept comment "\"${MARKER}\""
		$NFT add rule inet fw4 "ddmesh_forwarding_nat_protect" udp dport ${p} counter accept comment "\"${MARKER}\""
	done

	# (re)fill in forwarding rules
	config_load ddmesh
	config_foreach callback_rules
}



case "$1" in
	load)	setup_forwarding ;;
	ports)  echo $PROTECTED_PORTS ;;
	*) echo "usage: $1  load | ports" ;;
esac
