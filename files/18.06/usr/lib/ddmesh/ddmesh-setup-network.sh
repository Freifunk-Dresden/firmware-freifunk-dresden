#!/bin/ash
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

LOGGER_TAG="ddmesh-network"

node=$(uci get ddmesh.system.node)
eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)

setup_ethernet()
{
	#############################################################################
	# setup lan
	# Interface for "lan" is initially  set in /etc/config/network
	# tbb is a bridge used by mesh-on-lan
	#############################################################################
	# reconfigure lan as bridge if needed
	for NET in lan wan
	do
		if [ -n "$(uci -q get network.${NET})" ]; then

			# ------- configure interface (after device sections) ------
			# overwrite device name (after the previous name was extracted and used for device section (wan))
			uci set network.${NET}.type='bridge'
			uci set network.${NET}.stp=1
			uci set network.${NET}.bridge_empty=1

			# force_link always up. else netifd reconfigures wan/mesh_wan because of hotplug events
			uci set network.${NET}.force_link=1

			# set interface parameter (copy from ddmesh)
			for option in ipaddr netmask gateway dns proto
			do
				v="$(uci -q get ddmesh.network.${NET}_${option})"
				test -n "$v" && uci set network.${NET}.${option}="${v}"
			done

			# if mesh on wan, we need to disable udhcpc to avoid flooding syslog
			if [ "${NET}" = "wan" -a "$(uci -q get ddmesh.network.mesh_on_wan)" = "1" ]; then
				uci set network.wan.proto='static'
				uci set ddmesh.network.wan_proto='static'
			fi
		fi
	done
}

setup_mesh()
{
	enable_vlan="$(uci -q get ddmesh.network.mesh_on_vlan)"

	# setup mesh vlan
	if [ "${enable_vlan}" = "1" ]; then

		# setup mesh vlan
		mesh_vlan_id="$(uci -q get ddmesh.network.mesh_vlan_id)"
		if [ -z "${mesh_vlan_id}" ]; then
			mesh_vlan_id="9"	# default, hope it doesn't conflict with private vlans
			uci set ddmesh.network.mesh_vlan_id="${mesh_vlan_id}"
		fi

		# collect all ports
		local tmp_switch_ports=""
		cb_switch_vlan()
		{
			local config="$1"
			local var_ports
			config_get var_ports "$config" ports
			# remove any tags (t,u,*)
			var_ports="${var_ports//u/}"
			var_ports="${var_ports//t/}"
			var_ports="${var_ports//\*/}"
			tmp_switch_ports="${tmp_switch_ports} ${var_ports}"
		}
		config_load network
		config_foreach cb_switch_vlan switch_vlan

		# add tag to each port
		for p in ${tmp_switch_ports}
		do
			# check if already added
			if [ "${switch_ports}" = "${switch_ports//${p}t/}" ]; then
				switch_ports="${switch_ports} ${p}t"
			fi
		done

		# vlan config
		vlan_dev_config="switch_vlan_mesh"
		uci add network switch_vlan
		uci rename network.@switch_vlan[-1]="${vlan_dev_config}"
		uci set network.${vlan_dev_config}.device='switch0'
		uci set network.${vlan_dev_config}.vlan="${mesh_vlan_id}"
		uci set network.${vlan_dev_config}.ports="${switch_ports# }" #remove leading space

	fi # if mesh_on_vlan

	# create interfaces (bridges)
	for NET in mesh_lan mesh_wan mesh_vlan
	do
		device="br-${NET}"

		# create interface
		uci add network interface
		uci rename network.@interface[-1]="${NET}"
		uci set network.${NET}.ipaddr="$_ddmesh_nonprimary_ip"
		uci set network.${NET}.netmask="$_ddmesh_netmask"
		uci set network.${NET}.broadcast="$_ddmesh_broadcast"
		uci set network.${NET}.proto='static'
		uci set network.${NET}.type='bridge'
		uci set network.${NET}.stp=1
		uci set network.${NET}.bridge_empty=1
		uci set network.${NET}.force_link=1

		# add vlan ports
		if [ "${enable_vlan}" = "1" -a "${NET}" = "mesh_vlan" ]; then
				phy_lan_name=$(uci -q get network.lan.ifname)
				eth_lan=${phy_lan_name%.*}
				phy_wan_name=$(uci -q get network.wan.ifname)
				eth_wan=${phy_wan_name%.*}

				vlan_lan_device="${eth_lan}.${mesh_vlan_id}"
				vlan_wan_device="${eth_wan}.${mesh_vlan_id}"
				uci set network.${NET}.ifname="${vlan_lan_device} ${vlan_wan_device}"
		fi
	done
}

setup_wwan()
{
	# add network modem with qmi protocol
	uci add network interface
	uci rename network.@interface[-1]='wwan'

	# must be wwan0
	uci set network.wwan.ifname='wwan0'
	uci set network.wwan.device='/dev/cdc-wdm0'
	uci set network.wwan.proto='qmi'
	uci set network.wwan.apn="$(uci -q get ddmesh.network.wwan_apn)"
	uci set network.wwan.pincode="$(uci -q get ddmesh.network.wwan_pincode)"
	uci set network.wwan.autoconnect='1'
	uci set network.wwan.pdptype='IP'	# IPv4 only
	uci set network.wwan.delay='30' 	# wait for SIMCard being ready
	uci set network.wwan.metric='50'	# avoids overwriting WAN default route
	uci set network.wwan.modes="lte"

	# helper network, to setup firewall rules for wwan network.
	# openwrt is not relible to setup wwan0 rules in fw
	uci add network interface
	uci rename network.@interface[-1]='wwan_helper'
	uci set network.wwan_helper.ifname='wwan+'
	uci set network.wwan_helper.proto='static'
	uci set network.wwan_helper.force_link='1'
}

setup_wifi()
{
	#############################################################################
	# setup wifi networks
	# Interfaces for "wifi" and "wifi2" are created by wireless subsystem and
	# assigned to this networks
	#############################################################################
	uci add network interface
	uci rename network.@interface[-1]='wifi_adhoc'
	uci set network.wifi_adhoc.ipaddr="$_ddmesh_nonprimary_ip"
	uci set network.wifi_adhoc.netmask="$_ddmesh_netmask"
	uci set network.wifi_adhoc.broadcast="$_ddmesh_broadcast"
	uci set network.wifi_adhoc.proto='static'

	uci add network interface
	uci rename network.@interface[-1]='wifi_mesh2g'
	uci set network.wifi_mesh2g.ipaddr="$_ddmesh_nonprimary_ip"
	uci set network.wifi_mesh2g.netmask="$_ddmesh_netmask"
	uci set network.wifi_mesh2g.broadcast="$_ddmesh_broadcast"
	uci set network.wifi_mesh2g.proto='static'

	uci add network interface
	uci rename network.@interface[-1]='wifi_mesh5g'
	uci set network.wifi_mesh5g.ipaddr="$_ddmesh_nonprimary_ip"
	uci set network.wifi_mesh5g.netmask="$_ddmesh_netmask"
	uci set network.wifi_mesh5g.broadcast="$_ddmesh_broadcast"
	uci set network.wifi_mesh5g.proto='static'

	# wifi ap bridge (wireless will add interfaces to this bridge)
	NET="wifi2"
	uci add network interface
	uci rename network.@interface[-1]="${NET}"
	uci set network.${NET}.ipaddr="$_ddmesh_wifi2ip"
	uci set network.${NET}.netmask="$_ddmesh_wifi2netmask"
	uci set network.${NET}.broadcast="$_ddmesh_wifi2broadcast"
	uci set network.${NET}.proto='static'
	uci set network.${NET}.force_link=1
	uci set network.${NET}.type='bridge'
	uci set network.${NET}.stp=1
	uci set network.${NET}.bridge_empty=1
	#don't store dns for wifi2 to avoid adding it to resolv.conf
}

setup_backbone()
{
	#############################################################################
	# setup tbb_fastd/wg network assigned to a firewall zone (mesh) for an interface
	# that is not controlled by openwrt.
	# Bringing up tbb+ failes, but firewall rules are created anyway
	# got this information by testing, because openwrt feature to add non-controlled
	# interfaces (via netifd) was not working.
	#############################################################################
	uci add network interface
	uci rename network.@interface[-1]='tbb_fastd'
	uci set network.tbb_fastd.ifname='tbb_fastd'
	uci set network.tbb_fastd.proto='static'
	uci set network.tbb_fastd.force_link='1'
}

# physical if created by bmxd
setup_bmxd()
{
	#bmxd bat zone
	uci add network interface
	uci rename network.@interface[-1]='bat'
	uci set network.bat.ifname='bat+'
	uci set network.bat.proto='static'
	uci set network.bat.force_link='1'
}

setup_ffgw()
{
	# protocol handler ipip needs valid peeraddr
	# and requires some wan interface or another fix
	# interface. but this is not possible because
	# ipip packets can go out on every mesh interface
	# -> create an fake network to setup firewall rules
	# and create tunnel by bmxd-gateway.sh
	uci add network interface
	uci rename network.@interface[-1]='ffgw'
	uci set network.ffgw.ifname='ffgw+'
	uci set network.ffgw.proto='static'
	uci set network.ffgw.force_link='1'
}

# physical if created by openvpn
setup_vpn()
{
	#openvpn zone
	uci add network interface
	uci rename network.@interface[-1]='vpn'
	uci set network.vpn.ifname='vpn+'
	uci set network.vpn.proto='static'
	uci set network.vpn.force_link='1'
}

# physical if created by fastd/wg
setup_privnet()
{
	#privnet zone: it is bridged to br-lan (see /etc/fastd/privnet-cmd.sh)
	uci add network interface
	uci rename network.@interface[-1]='privnet'
	uci set network.privnet.ifname='priv'
	uci set network.privnet.proto='static'
	uci set network.privnet.force_link='1'
}

setup_network()
{
 rm -f /etc/config/network
 /bin/config_generate

 # setup_mesh AFTER setup_ethernet (setup_mesh needs lan network)
 for f in setup_ethernet setup_mesh setup_wwan setup_wifi setup_backbone setup_bmxd setup_ffgw setup_vpn setup_privnet
 do
	echo "call ${f}()"
	${f}
 done
}

# called from ddmesh-bootconfig.sh (boot step 3)
setup_mesh_on_wire()
{
#	# vlan mesh and mesh-on-lan/wan are alternative because
#	# some switch devices can not use vlan 1 and vlan 9 with same
#	# ports but different tagging
#	enable_vlan="$(uci -q get ddmesh.network.mesh_on_vlan)"
#	if [ "${enable_vlan}" != 1 ]; then

		for NET in lan wan
		do
			if [ "$(uci -q get ddmesh.network.mesh_on_${NET})" = "1" ]; then

				# only sleep for lan
				if [ ${NET} = "lan" -a "$(uci get ddmesh.system.mesh_sleep)" = '1' ]; then
					sleep 300
				fi

				logger -s -t "$LOGGER_TAG" "activate mesh-on-${NET}"
				ifname="$(uci -q get network.${NET}.ifname)"
				br_name="br-${NET}"
				mesh_bridge="br-mesh_${NET}"

				# avoid ip conflicts when wan is in same network as lan (getting ip from dhcp server)
				# disable br-wan and br-lan
				ip link set ${br_name} down
				brctl delif ${br_name} ${ifname}
				brctl addif ${mesh_bridge} ${ifname}
			fi
		done
#	fi
}

# called from  bmxd-gateway.sh
setup_ffgw_tunnel()
{
 gatewayIP="$1"

	ifname="$(uci -q get network.ffgw.ifname)"
	ifname="${ifname/+/}"

	setup_ffwg_if()
	{
		ip addr add ${_ddmesh_ip}/32 dev "${ifname}"
		# wg mtu - 20 = 1280
		ip link set "${ifname}" mtu 1280
		ip link set "${ifname}" up
		ip route add default dev "${ifname}" table ff_gateway src ${_ddmesh_ip} 2>/dev/null
	}

	if [ "${gatewayIP}" = "gateway" ]; then
		ip tunnel del "${ifname}" 2>/dev/null
		ip tunnel add "${ifname}" mode ipip local $_ddmesh_ip
		setup_ffwg_if
	else
		ip tunnel del "${ifname}" 2>/dev/null
		ip tunnel add "${ifname}" mode ipip local $_ddmesh_ip remote ${gatewayIP}
		setup_ffwg_if
	fi

}


#boot_step is empty for new devices
boot_step="$(uci get ddmesh.boot.boot_step)"

if [ "$boot_step" = "2" -o ! -f /etc/config/network ];
then
	logger -s -t "$LOGGER_TAG" "setup network config"
	setup_network
	uci commit
fi

# call function passed as parameter (e.g.: setup_mesh_on_wire)
if [ -n "$1" ]; then
	$1 $2
fi

exit 0
