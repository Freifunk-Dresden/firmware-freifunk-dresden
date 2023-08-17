#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

LOGGER_TAG="ddmesh-network"

node=$(uci get ddmesh.system.node)
eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)

# returns device section for device name (==interface)
get_device_section()
{
	local device="$1"
	cb_device()
	{
		local config="$1"
		local var_devname
		config_get var_devname "$config" name
		if [ "$2" = "$var_devname" ]; then
			echo "$config"
		fi
	}

	config_load network
	config_foreach cb_device device "$device"
}

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
		echo "check NET: $NET"
		if [ -n "$(uci -q get network.${NET})" ]; then
			echo "$NET found"

			# ------- configure device -------
			dev_name=$(uci -q get network.${NET}.device)
			dev_config=$(get_device_section "$dev_name")
			echo "[$NET] dev_name:$dev_name"
			echo "[$NET] dev_config:$dev_config"

			# use name that can not conflict with exisings
			dev_config_name="bridge_${NET}"
			echo "[$NET] dev_config_name:$dev_config_name"

			# check if we have a device section for lan/wan.
			# and create one
			if [ -z "$(uci -q get network.${dev_config})" ]; then
				echo "create device section ${dev_config_name} for ${NET}"
				uci add network device
				uci rename network.@device[-1]="${dev_config_name}"
			else
			  # give this section a valid name for easier access
				uci rename network.${dev_config}="${dev_config_name}"
			fi
			dev_config=${dev_config_name}

			# device section will become a bridge (if not already)
			# add ports if not present and use devname as bridge interface names
			if [ -z "$(uci -q get network.${dev_config}.ports)" ]; then
				echo "[$NET] set ports: ${dev_name}"
				uci add_list network.${dev_config}.ports="${dev_name}"
			fi

			echo "[$NET] set type: bridge"
			# overwrite if device config was already present
			stp="$(uci -q get ddmesh.network.${NET}_stp)"
			[ -z "$stp" ] && stp=1
			uci set network.${dev_config}.name="br-${NET}"
			uci set network.${dev_config}.type='bridge'
			uci set network.${dev_config}.stp=${stp}
			uci set network.${dev_config}.bridge_empty=1

			# ------- create devices for all physical eth ports -------
			echo "[$NET] create device sections for phy eth ports"
			local count=0
			for phy_name in $(uci -q get network.${dev_config}.ports)
			do
				phydev_config=$(get_device_section "${phy_name}")
				if [ -z "$(uci -q get network.${phydev_config})" ]; then

					phydev_config="phydev_${phy_name/./_}"
					echo "create phy-device section ${phydev_config}"

					uci add network device
					uci rename network.@device[-1]="${phydev_config}"
					uci set network.${phydev_config}.name="${phy_name}"
				fi

				if [ -z "$(uci -q get network.${phydev_config}.macaddr)" ]; then

					# get real mac and modify it. some how does netifd use eth mac for
					# wifi interfaces. so I can not use those (when lan+wifi are bridged).
					# google for: U/L bit of mac address (https://de.wikipedia.org/wiki/MAC-Adresse#Vergabestelle)
					# So I change the first and last
					mac="$(ip link show dev ${phy_name} | awk '/ether/{print $2}')"
					if [ -n "${mac}" ]; then
						if [ "${NET}" = "lan" ]; then
							mac="${count:0:1}2:${mac:3:14}"
						else
							mac="${count:0:1}6:${mac:3:14}"
						fi
						echo "set mac $mac for ${phydev_config}"
						uci set network.${phydev_config}.macaddr="$mac"
					fi
				fi
				count=$((count + 1))
			done

			# ------- configure interface (after device sections) ------
			echo "[$NET] configure interface: br-${NET}"

			# overwrite device name (after the previous name was extracted and used for device section (wan))
			uci set network.${NET}.device="br-${NET}"

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
	# determine switch type configuration
	if /usr/lib/ddmesh/ddmesh-utils-switch-info.sh isdsa >/dev/null; then
		dsa=true
	else
		dsa=false
	fi
	echo "DSA: $dsa"

	enable_vlan="$(uci -q get ddmesh.network.mesh_on_vlan)"
	echo "enable_vlan=$enable_vlan"

	# setup mesh vlan
	if [ "${enable_vlan}" = "1" ]; then

		mesh_vlan_id="$(uci -q get ddmesh.network.mesh_vlan_id)"
		if [ -z "${mesh_vlan_id}" ]; then
			mesh_vlan_id="9"	# default, hope it doesn't conflict with private vlans
			uci set ddmesh.network.mesh_vlan_id="${mesh_vlan_id}"
		fi

		if ! $dsa ; then

			# collect all ports (normally only lan, but can be wan too. can not distinguish between lan/wan)
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

			# add tag to each port (normally only lan, but can be wan too. can not distinguish between lan/wan)
			for p in ${tmp_switch_ports}
			do
				# check if already added
				if [ "${switch_ports}" = "${switch_ports//${p}t/}" ]; then
					switch_ports="${switch_ports} ${p}t"
				fi
			done

			# vlan config (lan and wan possible, can not distinguish between lan/wan)
			vlan_dev_config="switch_vlan_mesh"
			uci add network switch_vlan
			uci rename network.@switch_vlan[-1]="${vlan_dev_config}"
			uci set network.${vlan_dev_config}.device='switch0'
			uci set network.${vlan_dev_config}.vlan="${mesh_vlan_id}"
			uci set network.${vlan_dev_config}.ports="${switch_ports# }" #remove leading space

			vlan_ports=""
			for NET in lan wan
			do
				br_dev_name=$(uci -q get network.${NET}.device)
				br_dev_config=$(get_device_section "$br_dev_name")

				# get eth name (assuming switch always is connected to lan interface)
				phy_name=$(uci -q get network.${br_dev_config}.ports)
				eth=${phy_name%.*}

				# check if valid and if already created
				if [ -n "${eth}" -a "${vlan_ports}" = "${vlan_ports//${eth}/}" ]; then
					# create interface
					vlan_device="${eth}.${mesh_vlan_id}"
					uci add network interface
					uci set network.@interface[-1].device="${vlan_device}"
					vlan_ports="${vlan_ports} ${vlan_device}"
				fi
			done

		else
			# create two different vlan configs, one for lan one for wan.
			# if wan and lan are on switch, then it is possible to put wan and lan dsa interfaces
			# into one config. but if we have different physical interfaces eth0 and eth1 (futro)
			# I can not put those interfaces together, as openwrt requires the vlan basename
			# br-lan or br-wan (vlan bound to those)
			for NET in lan wan
			do
				br_dev_name=$(uci -q get network.${NET}.device)
				br_dev_config=$(get_device_section "$br_dev_name")
				echo "vlan:[$NET] br_dev_name=$br_dev_name"
				echo "vlan:[$NET] br_dev_config=$br_dev_config"

				# create bridge-vlan (similar to device section)
				vlan_dev_config="bridge_vlan_${NET}"
				echo "vlan: add bridge: $vlan_dev_config"

				uci add network bridge-vlan
				uci rename network.@bridge-vlan[-1]="${vlan_dev_config}"
				uci set network.${vlan_dev_config}.name="${br_dev_name}"
				uci set network.${vlan_dev_config}.vlan="${mesh_vlan_id}"
				# copy all ports from lan or wan and tag them
				ports="$(uci -q get network.${br_dev_config}.ports)"
				for port in ${ports}
				do
					echo "vlan: add ports: ${port}:t"
					uci add_list network.${vlan_dev_config}.ports="${port}:t"
				done

				echo "vlan: create interface: vlan_iface_${NET}"
				# create vlan interface
				vlan_if_config="vlan_iface_${NET}"
				uci add network interface
				uci rename network.@interface[-1]="${vlan_if_config}"
				uci set network.${vlan_if_config}.device="${br_dev_name}.${mesh_vlan_id}"
				uci set network.${vlan_if_config}.force_link='1'

				vlan_ports="${vlan_ports} ${br_dev_name}.${mesh_vlan_id}"
			done
		fi
	fi # if mesh_on_vlan

	# create interfaces (bridges)
	for NET in mesh_lan mesh_wan mesh_vlan
	do
		device="br-${NET}"
		echo "create mesh bridges device :$device"

		# configure as bridge (dev_name is lowlevel name)
		dev_config="bridge_${NET}"
		uci add network device
		uci rename network.@device[-1]="${dev_config}"
		uci set network.${dev_config}.name="${device}"
		uci set network.${dev_config}.type='bridge'
		uci set network.${dev_config}.stp=1
		uci set network.${dev_config}.bridge_empty=1

		# add vlan ports
		if [ "${enable_vlan}" = "1" -a "${NET}" = "mesh_vlan" ]; then
				# need to "for" vlan_ports to remove spaces
				for p in ${vlan_ports}
				do
					uci add_list network.${dev_config}.ports="${p}"
				done
		fi

		# create interface
		echo "create mesh bridge interface: ${NET} attached to device ${device}"
		uci add network interface
		uci rename network.@interface[-1]="${NET}"
		uci set network.${NET}.device="${device}"
		uci set network.${NET}.ipaddr="$_ddmesh_nonprimary_ip"
		uci set network.${NET}.netmask="$_ddmesh_netmask"
		uci set network.${NET}.broadcast="$_ddmesh_broadcast"
		uci set network.${NET}.proto='static'
		uci set network.${NET}.force_link=1

	done
}

setup_wwan()
{
	# Note: the new network configuration scheme does not work for WWAN modems.
	# but the old way does.

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
	uci set network.wwan.metric='50'	# avoids overwriting WAN/LAN default route
	uci set network.wwan.modes="lte"

	# helper network, to setup firewall rules for wwan network.
	# openwrt is not relible to setup wwan0 rules in fw
	uci add network interface
	uci rename network.@interface[-1]='wwan_helper'
	uci set network.wwan_helper.device='wwan+'
	uci set network.wwan_helper.proto='static'
	uci set network.wwan_helper.force_link='1'
}

# tether
setup_twan()
{
	dev_config="bridge_twan"
	uci add network device
	uci rename network.@device[-1]="${dev_config}"

	uci set network.${dev_config}.name="br-twan"
	uci set network.${dev_config}.type='bridge'
	uci set network.${dev_config}.stp=1
	uci set network.${dev_config}.bridge_empty=1

	# /etc/hotplug.d/usb/02-ddmesh-tether will
	# add rename new interfaces to teth. needed this way to make coldplug
	# reliable
	uci add_list network.${dev_config}.ports="teth"

	uci add network interface
	uci rename network.@interface[-1]='twan'
	uci set network.twan.device='br-twan'
	uci set network.twan.proto='dhcp'
	uci set network.twan.force_link='1'
	uci set network.twan.metric='70' # avoids overwriting WAN/LAN default route
}

setup_cwan()
{
	uci add network interface
	uci rename network.@interface[-1]='cwan'
	uci set network.cwan.proto='dhcp'
	uci set network.cwan.metric='60' # avoids overwriting WAN/LAN default route
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
	uci set network.${NET}.device="br-${NET}"
	uci set network.${NET}.ipaddr="$_ddmesh_wifi2ip"
	uci set network.${NET}.netmask="$_ddmesh_wifi2netmask"
	uci set network.${NET}.broadcast="$_ddmesh_wifi2broadcast"
	uci set network.${NET}.proto='static'
	uci set network.${NET}.force_link=1
	#don't store dns for wifi2 to avoid adding it to resolv.conf

	dev_config="bridge_${NET}"
	uci add network device
	uci rename network.@device[-1]="${dev_config}"

	# configure as bridge (dev_name is lowlevel name)
	uci set network.${dev_config}.name="br-${NET}"
	uci set network.${dev_config}.type='bridge'
	uci set network.${dev_config}.stp=1
	uci set network.${dev_config}.bridge_empty=1
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
	uci set network.tbb_fastd.device='tbb_fastd'
	uci set network.tbb_fastd.proto='static'
	uci set network.tbb_fastd.force_link='1'

	# wireguard tunnel
	uci add network interface
	uci rename network.@interface[-1]='tbbwg'
	uci set network.tbbwg.device='tbbwg+'
	uci set network.tbbwg.ipaddr="$_ddmesh_wireguard_ip"
	uci set network.tbbwg.netmask="$_ddmesh_netmask"
	uci set network.tbbwg.proto='static'
	uci set network.tbbwg.force_link='1'

	# wireguard ipip
	uci add network interface
	uci rename network.@interface[-1]='tbb_wg'
	# "+" is needed to create firewall rules for all tbb_wg+... ifaces
	uci set network.tbb_wg.device='tbb_wg+'
	uci set network.tbb_wg.proto='static'
	uci set network.tbb_wg.force_link='1'
}

# physical if created by bmxd
setup_bmxd()
{
	#bmxd bat zone
	uci add network interface
	uci rename network.@interface[-1]='bat'
	uci set network.bat.device='bat+'
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
	uci set network.ffgw.device='ffgw+'
	uci set network.ffgw.proto='static'
	uci set network.ffgw.force_link='1'
}

# physical if created by openvpn
setup_vpn()
{
	#openvpn zone
	uci add network interface
	uci rename network.@interface[-1]='vpn'
	uci set network.vpn.device='vpn+'
	uci set network.vpn.proto='static'
	uci set network.vpn.force_link='1'
}

# physical if created by fastd/wg
setup_privnet()
{
	#privnet zone: it is bridged to br-lan (see /etc/fastd/privnet-cmd.sh)
	uci add network interface
	uci rename network.@interface[-1]='privnet'
	uci set network.privnet.device='priv'
	uci set network.privnet.proto='static'
	uci set network.privnet.force_link='1'
}

setup_network()
{
 rm -f /etc/config/network
 /bin/config_generate

 # add marker that we have generated this file
	if [ -z "$(uci -q get network.ddmesh)" ]; then
				echo "create maker section 'ddmesh'"
				uci add network ddmesh
				uci rename network.@ddmesh[-1]="ddmesh"
	fi
	uci set network.ddmesh.comment="network config generated by $(basename $0)"
	uci set network.ddmesh.generated='1'

#cat /etc/config/network >/tmp/devel-network-initial

 # setup_mesh AFTER setup_ethernet (setup_mesh needs lan network)
 for f in setup_ethernet setup_mesh setup_wwan setup_cwan setup_twan setup_wifi setup_backbone setup_bmxd setup_ffgw setup_vpn setup_privnet
 do
	echo "call ${f}()"
	${f}
#uci commit && cat /etc/config/network >/tmp/devel-network-${f}
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
				dev_name=$(uci -q get network.${NET}.device)
				dev_config=$(get_device_section "$dev_name")
				mesh_bridge=$(uci -q get network.mesh_${NET}.device)

				if [ -n "${dev_config}" ]; then
					# avoid ip conflicts (outgoing) when wan is in same network as lan (getting ip from dhcp server)
					# disable br-wan and br-lan
					ip link set ${dev_name} down

					# remove all interfaces from br-lan/wan and add those to br-mesh_lan/wan
					for ifname in $(uci get network.${dev_config}.ports)
					do
						brctl delif ${dev_name} ${ifname}
						brctl addif ${mesh_bridge} ${ifname}
					done
				fi
			fi
		done
#	fi
}

# called from  bmxd-gateway.sh
setup_ffgw_tunnel()
{
 gatewayIP="$1"

	ifname="$(uci -q get network.ffgw.device)"
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
# if I just delete network config and reboot, openwrt will create its own config which then
# only allows to access router via lan openwrt IP address. To restore freifunk network,
# I check for "generated"
generated="$(uci -q get network.ddmesh.generated)"
if [ "${boot_step}" = "2" -o ! -f /etc/config/network -o "${generated:=0}" = '0' ];
then
	logger -s -t "$LOGGER_TAG" "setup network config (boot_step:${boot_step}, generated:${generated:=0})"
	setup_network
	uci commit
fi

# call function passed as parameter (e.g.: setup_mesh_on_wire)
if [ -n "$1" ]; then
	$1 $2
fi

exit 0
