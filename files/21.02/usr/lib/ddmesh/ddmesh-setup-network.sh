#!/bin/ash
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
		if [ -n "$(uci -q get network.${NET})" ]; then

			# ------- configure device -------
			dev_name=$(uci -q get network.${NET}.device)
			dev_config=$(get_device_section "$dev_name")
echo dev_name=$dev_name
echo dev_config=$dev_config

			# check if we have a device section for lan/wan.
			# In this case the device is normal interface (not a bridge)
			if [ -z "$(uci -q get network.${dev_config})" ]; then
				dev_config="dev_${NET}"
				echo "create device section ${dev_config} for ${NET}"
				uci add network device
				uci rename network.@device[-1]="${dev_config}"
				# use devname as bridge interface names
				uci add_list network.${dev_config}.ports="${dev_name}"
			fi

			uci set network.${dev_config}.name="br-${NET}"
			uci set network.${dev_config}.type='bridge'
			uci set network.${dev_config}.stp=1
			uci set network.${dev_config}.bridge_empty=1

			# ------- create devices for all physical eth ports -------
			for phy_name in $(uci get network.${dev_config}.ports)
			do
				phydev_config=$(get_device_section "${phy_name}")
				if [ -z "$(uci -q get network.${phydev_config})" ]; then
					phydev_config="dev_${phy_name/./_}"
					echo "create device section ${phydev_config}"
					uci add network device
					uci rename network.@device[-1]="${phydev_config}"
					uci set network.${phydev_config}.name="${phy_name}"
				fi

				if [ -z "$(uci set network.${phydev_config}.macaddr)" ]; then
					# get real mac and modify it. some how does netifd use eth mac for
					# wifi interfaces. so I can not use those (when lan+wifi are bridged).
					# google for: U/L bit of mac address (https://de.wikipedia.org/wiki/MAC-Adresse#Vergabestelle)
					# So I change the first and last
					mac="$(ip link show dev ${phy_name} | awk '/ether/{print $2}')"

					if [ "${NET}" = "lan" ]; then
						mac="22:${mac:3:14}"
					else
						mac="66:${mac:3:14}"
					fi
					uci set network.${phydev_config}.macaddr="$mac"
				fi

			done

			# ------- configure interface (after device sections) ------
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

		fi
	done



}

setup_mesh()
{
	# create empty bridges
	for NET in mesh_lan mesh_wan
	do
		uci add network interface
		uci rename network.@interface[-1]="${NET}"
		uci set network.${NET}.device="br-${NET}"
		uci set network.${NET}.ipaddr="$_ddmesh_nonprimary_ip"
		uci set network.${NET}.netmask="$_ddmesh_netmask"
		uci set network.${NET}.broadcast="$_ddmesh_broadcast"
		uci set network.${NET}.proto='static'
		uci set network.${NET}.force_link=1

		# configure as bridge (dev_name is lowlevel name)
		dev_config="device_${NET}"
		uci add network device
		uci rename network.@device[-1]="${dev_config}"
		uci set network.${dev_config}.name="br-${NET}"
		uci set network.${dev_config}.type='bridge'
		uci set network.${dev_config}.stp=1
		uci set network.${dev_config}.bridge_empty=1
	done
}

setup_wwan()
{
	# add network modem with qmi protocol
	uci add network interface
	uci rename network.@interface[-1]='wwan'

	# must be wwan0
	uci set network.wwan.device='wwan0'
	uci set network.wwan.proto='qmi'
	uci set network.wwan.apn="$(uci -q get ddmesh.network.wwan_apn)"
	uci set network.wwan.pincode="$(uci -q get ddmesh.network.wwan_pincode)"
	uci set network.wwan.autoconnect='1'
	uci set network.wwan.pdptype='IP'	# IPv4 only
	uci set network.wwan.delay='30' 	# wait for SIMCard being ready
	uci set network.wwan.metric='50'	# avoids overwriting WAN default route

	wwan_modes=""
	test "$(uci -q get ddmesh.network.wwan_4g)" = "1" && wwan_modes="$wwan_modes,lte"
	test "$(uci -q get ddmesh.network.wwan_3g)" = "1" && wwan_modes="$wwan_modes,umts"
	test "$(uci -q get ddmesh.network.wwan_2g)" = "1" && wwan_modes="$wwan_modes,gsm"
	wwan_modes="${wwan_modes#,}"
	wwan_modes="${wwan_modes:-lte,umts}"
	uci set network.wwan.modes="$wwan_modes"

	wwan_mode_preferred="$(uci -q get ddmesh.network.wwan_mode_preferred)"
	uci set network.wwan.preference="$wwan_mode_preferred"

	dev_config="device_wwan"
	uci add network interface
	uci rename network.@interface[-1]="${dev_config}"
	uci set network.${dev_config}.name="wwan0" # must be wwan0
	uci set network.${dev_config}.device='/dev/cdc-wdm0'

	# helper network, to setup firewall rules for wwan network.
	# openwrt is not relible to setup wwan0 rules in fw
	uci add network interface
	uci rename network.@interface[-1]='wwan_helper'
	uci set network.wwan_helper.device="wwan+"
	uci set network.wwan_helper.proto='static'
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

	dev_config="device_${NET}"
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

	# wireguard tunnel
	uci add network interface
	uci rename network.@interface[-1]='tbbwg'
	uci set network.tbbwg.device='tbbwg+'
	uci set network.tbbwg.ipaddr="$_ddmesh_wireguard_ip"
	uci set network.tbbwg.netmask="$_ddmesh_netmask"
	uci set network.tbbwg.proto='static'

	# wireguard ipip
	uci add network interface
	uci rename network.@interface[-1]='tbb_wg'
	# "+" is needed to create firewall rules for all tbb_wg+... ifaces
	uci set network.tbb_wg.device='tbb_wg+'
	uci set network.tbb_wg.proto='static'
}

# physical if created by bmxd
setup_bmxd()
{
	#bmxd bat zone
	uci add network interface
	uci rename network.@interface[-1]='bat'
	uci set network.bat.device="bat+"
	uci set network.bat.proto='static'
}

# physical if created by openvpn
setup_vpn()
{
	#openvpn zone
	uci add network interface
	uci rename network.@interface[-1]='vpn'
	uci set network.vpn.device="vpn+"
	uci set network.vpn.proto='static'
}

# physical if created by fastd/wg
setup_privnet()
{
	#privnet zone: it is bridged to br-lan (see /etc/fastd/privnet-cmd.sh)
	uci add network interface
	uci rename network.@interface[-1]='privnet'
	uci set network.privnet.device="priv"
	uci set network.privnet.proto='static'
}

setup_network()
{
 rm -f /etc/config/network
 /bin/config_generate

 for f in setup_ethernet setup_mesh setup_wwan setup_wifi setup_backbone setup_bmxd setup_vpn setup_privnet
 do
	echo "call ${f}()"
	${f}
 done
}

# called from ddmesh-bootconfig.sh (boot step 3)
setup_mesh_on_wire()
{
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
				# avoid ip conflicts when wan is in same network as lan (getting ip from dhcp server)
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
	$1
fi

exit 0
