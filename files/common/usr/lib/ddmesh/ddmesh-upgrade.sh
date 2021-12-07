#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

# script is called during boot process before config_update.
# It updates changes in persistent files (e.g.: /etc/config/network, firewall)

previous_version=$(uci get ddmesh.boot.upgrade_version 2>/dev/null)
current_version=$(cat /etc/version)
upgrade_running=$(uci -q get ddmesh.boot.upgrade_running)
nightly_upgrade_running=$(uci -q get ddmesh.boot.nightly_upgrade_running)

echo "previous_version=$previous_version"
echo "current_version=$current_version"
echo "upgrade_running=$upgrade_running"
echo "nightly_upgrade_running=$nightly_upgrade_running"

# if no previous version then set initial version; needed for correct behavior
previous_version=${previous_version:-$current_version}

test "$nightly_upgrade_running" = "1" && MESSAGE=" (Auto-Update)"

# check if upgrade is needed
test "$previous_version" = "$current_version" && {
	echo "nothing to upgrade"
	exit 0
}

node=$(uci get ddmesh.system.node)
eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)

run_upgrade()
{
 #grep versions from this file (see below)
 local upgrade_version_list=$(sed -n '/^[ 	]*upgrade_[0-9_]/{s#^[ 	]*upgrade_\([0-9]\+\)_\([0-9]\+\)_\([0-9]\+\).*#\1.\2.\3#;p}' $0)

 local previous_version_found=0
 local ignore=1
 local v=0

 for v in $upgrade_version_list
 do
 	echo -n $v

 	#if I find current version before previous_version -> error
	test "$ignore" = "1" -a "$v" = "$current_version" && echo " ERROR: current version found before previous version" && break

 	#ignore all versions upto firmware previous_version
	test "$ignore" = "1" -a "$v" != "$previous_version" && echo " ignored" && continue
	ignore=0
	previous_version_found=1

	#ignore if already on same version
	test "$v" = "$previous_version" && echo " ignored (same)" && continue

	#create name of upgrade function (version depended)
	function_suffix=$(echo $v|sed 's#\.#_#g')
	echo " upgrade to $v"
	upgrade_${function_suffix};

 	# force config update after next boot
	# in case this script is called from terminal (manually)
 	uci set ddmesh.boot.boot_step=2

	#save current state in case of later errors
	uci set ddmesh.boot.upgrade_version="${v}"
	uci add_list ddmesh.boot.upgraded="$previous_version to ${v}${MESSAGE}"

	#stop if we have reached "current version" (ignore other upgrades)
	test "$v" = "$current_version" && echo "last valid upgrade finished" && uci_commit.sh && break;
 done

 test "$previous_version_found" = "0" && echo "ERROR: missing upgrade function for previous version $previous_version" && exit 1
 test "$current_version" != "$v" && echo "ERROR: no upgrade function found for current version $current_version" && exit 1
}

#############################################
### keep ORDER - only change below
### uci_commit.sh is called after booting via ddmesh.boot_step=2
# a function for current version is needed for this algorithm

upgrade_4_2_2()
{
 uci set ddmesh.network.speed_network='lan'
 uci rename ddmesh.network.wan_speed_down='speed_down'
 uci rename ddmesh.network.wan_speed_up='speed_up'
 uci del ddmesh.network.lan_speed_down
 uci del ddmesh.network.lan_speed_up
 uci del_list ddmesh.system.communities="Freifunk Pirna"
 uci del_list ddmesh.system.communities="Freifunk Freiberg"
 uci del_list ddmesh.system.communities="Freifunk OL"
 uci add_list ddmesh.system.communities="Freifunk Pirna"
 uci add_list ddmesh.system.communities="Freifunk Freiberg"
 uci add_list ddmesh.system.communities="Freifunk OL"
 uci set firewall.zone_bat.mtu_fix=1
 uci set firewall.zone_tbb.mtu_fix=1
 uci set firewall.zone_lan.mtu_fix=1
 uci set firewall.zone_wifi.mtu_fix=1
 uci set firewall.zone_wifi2.mtu_fix=1
 sed -i '/.*icmp_type.*/d' /etc/config/firewall

 uci set ddmesh.network.mesh_mtu=1426
 uci set network.wifi.mtu=1426
 uci set ddmesh.backbone.default_server_port=5001

 cp /rom/etc/config/credentials /etc/config/credentials
 for i in $(seq 0 4)
 do
	host="$(uci -q get ddmesh.@backbone_client[$i].host)"
	fastd_pubkey="$(uci -q get ddmesh.@backbone_client[$i].public_key)"
	if [ -n "$host" -a -z "$fastd_pubkey" ]; then
		uci -q del ddmesh.@backbone_client[$i].password
 		uci -q set ddmesh.@backbone_client[$i].port="5001"
		#lookup key
		for k in $(seq 1 10)
		do
			kk=$(( $k - 1))
			h=$(uci -q get credentials.@backbone[$kk].host)
			if [ "$h" = "$host" ]; then
	 			uci set ddmesh.@backbone_client[$i].public_key="$(uci get credentials.@backbone[$kk].key)"
				break;
			fi
		done
 	fi
 done

 uci -q set ddmesh.network.mesh_network_id=1206
}

upgrade_4_2_3()
{
 # unsicher ob fruehere Konvertierung funktioniert hatte
 uci set credentials.registration.register_service_url="$(uci get credentials.registration.register_service_url | sed 's#ddmesh.de#freifunk-dresden.de#')"
 uci delete ddmesh.network.wifi2_ip
 uci delete ddmesh.network.wifi2_dns
 uci delete ddmesh.network.wifi2_netmask
 uci delete ddmesh.network.wifi2_broadcast
 uci delete ddmesh.network.wifi2_dhcpstart
 uci delete ddmesh.network.wifi2_dhcpend
 # update privnet config
 uci delete ddmesh.vpn
 uci add ddmesh privnet
 uci rename ddmesh.@privnet[-1]='privnet'
 uci set ddmesh.privnet.fastd_port=4000
 uci set ddmesh.privnet.default_server_port=4000
 uci set ddmesh.privnet.number_of_clients=5
 uci set network.wifi2.stp=1
 uci set network.lan.stp=1

 #new mtu
 uci set ddmesh.network.mesh_mtu=1200
 uci del network.wifi.mtu
 uci set ddmesh.backbone.default_server_port=5002
 for i in $(seq 0 4)
 do
	host="$(uci -q get ddmesh.@backbone_client[$i].host)"
	if [ -n "$host" ]; then
 		uci -q set ddmesh.@backbone_client[$i].port="5002"
 	fi
 done

 uci del_list ddmesh.system.communities="Freifunk Meißen"
 uci del_list ddmesh.system.communities="Freifunk Meissen"
 uci add_list ddmesh.system.communities="Freifunk Meissen"
 #traffic shaping for upgrade only
 uci set ddmesh.network.wifi_country="DE"
 for nt in node mobile server
 do
	uci del_list ddmesh.system.node_types=$nt
	uci add_list ddmesh.system.node_types=$nt
 done
}

upgrade_4_2_4()
{
 for n in wifi tbb bat; do
   for p in tcp udp; do
	if [ -z "$(uci -q get firewall.iperf3_"$n"_"$p")" ]; then
		uci add firewall rule
	        uci rename firewall.@rule[-1]="iperf3_"$n"_"$p
		uci set firewall.@rule[-1].name="Allow-iperf3-$p"
	        uci set firewall.@rule[-1].src="$n"
        	uci set firewall.@rule[-1].proto="$p"
	        uci set firewall.@rule[-1].dest_port="5201"
        	uci set firewall.@rule[-1].target="ACCEPT"
	 fi
   done
 done
 #geoloc
 uci add credentials geoloc
 uci rename credentials.@geoloc[-1]='geoloc'
 uci set credentials.geoloc.host="$(uci -c /rom/etc/config get credentials.geoloc.host)"
 uci set credentials.geoloc.port="$(uci -c /rom/etc/config get credentials.geoloc.port)"
 uci set credentials.geoloc.uri="$(uci -c /rom/etc/config get credentials.geoloc.uri)"
 #https
 uci set credentials.url.firmware_download_release="$(uci -c /rom/etc/config get credentials.url.firmware_download_release)"
 uci set credentials.url.firmware_download_testing="$(uci -c /rom/etc/config get credentials.url.firmware_download_testing)"
 uci set credentials.url.opkg="$(uci -c /rom/etc/config get credentials.url.opkg)"
 uci set credentials.registration.register_service_url="$(uci -c /rom/etc/config get credentials.registration.register_service_url)"
}


upgrade_4_2_5()
{
	#add network to fw zone tbb, to create rules with br-tbb_lan
	uci delete firewall.zone_tbb.network
        uci add_list firewall.zone_tbb.network='tbb'
        uci add_list firewall.zone_tbb.network='tbb_fastd'
	uci -q delete network.tbb_lan
}


upgrade_4_2_6()
{
 true
}

upgrade_4_2_7()
{
 true
}

upgrade_4_2_8()
{
	echo dummy
	uci delete ddmesh.system.bmxd_nightly_restart
	cp /rom/etc/config/dhcp /etc/config/
}

upgrade_4_2_9()
{
	uci rename overlay.@overlay[0]='data'
}

upgrade_4_2_10()
{
	if [ -z "$(uci -q get credentials.backbone_secret)" ]; then
		uci -q add credentials backbone_secret
		uci -q rename credentials.@backbone_secret[-1]='backbone_secret'
	fi
	secret="$(uci -q get credentials.backbone.secret_key)"
	if [ -n "$secret" ]; then
		uci -q set credentials.backbone_secret.key="$secret"
		uci -q delete credentials.backbone.secret_key
	fi
	uci -q delete credentials.backbone

	if [ -z "$(uci -q get credentials.privnet_secret)" ]; then
		uci -q add credentials privnet_secret
		uci -q rename credentials.@privnet_secret[-1]='privnet_secret'
	fi
	secret="$(uci -q get credentials.privnet.secret_key)"
	if [ -n "$secret" ]; then
		uci -q set credentials.privnet_secret.key="$secret"
		uci -q delete credentials.privnet.secret_key
	fi
	uci -q delete credentials.privnet

	uci -q rename ddmesh.system.wifissh='meshssh'
	uci -q rename ddmesh.system.wifisetup='meshsetup'
	uci -q delete network.tbb # will be created with 'meshwire' on next boot
	cp /rom/etc/config/firewall /etc/config/firewall
}

upgrade_4_2_11()
{
 true
}

upgrade_4_2_12()
{
	cp /rom/etc/config/firewall /etc/config/firewall
	uci set credentials.registration.register_service_url="$(uci -c /rom/etc/config get credentials.registration.register_service_url)"
}

upgrade_4_2_13()
{
 true
}

upgrade_4_2_14()
{
 true
}

upgrade_4_2_15()
{
	rm /etc/config/wireless
	ln -s /var/etc/config/wireless /etc/config/wireless
	uci -q set dropbear.@dropbear[0].SSHKeepAlive=30
}

upgrade_4_2_16()
{
	uci -q delete credentials.url.firmware_download_server
}

upgrade_4_2_17()
{
 	uci set network.wan.stp=1
	cp /rom/etc/config/firewall /etc/config/firewall
}


upgrade_4_2_18()
{
	uci set dhcp.dnsmasq.quietdhcp=1
}

upgrade_4_2_19()
{
	uci -q delete network.meshwire # mesh_lan/wan will be created on next boot
	uci set network.tbb_fastd.ifname='tbb_fastd'
	cp /rom/etc/config/firewall /etc/config/firewall
	uci set dhcp.dnsmasq.logqueries=0
}

upgrade_5_0_1()
{
	uci -q set ddmesh.network.wifi2_dhcplease='5m'
}

upgrade_5_0_2()
{
	uci -q delete network.meshwire # mesh_lan/wan will be created on next boot
	uci set network.tbb_fastd.ifname='tbb_fastd'
	cp /rom/etc/config/firewall /etc/config/firewall
	uci set dhcp.dnsmasq.logqueries=0
}

upgrade_5_0_3()
{
	uci add_list ddmesh.system.communities="Freifunk Waldheim"
	# convert security
	security=0 # default
	if [ "$(uci -q get ddmesh.network.wifi3_enabled)" = "1" ]; then
		if [ "$(uci -q get ddmesh.network.wifi3_security_open)" = "1" ]; then
			security=0
		else
			security=1
		fi
	fi
	uci -q set ddmesh.network.wifi3_security=$security
	uci -q delete ddmesh.network.wifi3_security_open
}

upgrade_5_0_4()
{
 uci set ddmesh.system.firmware_autoupdate=1
}

upgrade_5_0_5()
{
 true
}

upgrade_6_0_6()
{
 uci add_list ddmesh.system.communities="Freifunk Freital"
 uci set ddmesh.network.wifi_country="DE"
 uci set ddmesh.network.wifi_channel_5Ghz="44"
 uci set ddmesh.network.wifi_txpower_5Ghz="18"
}

upgrade_6_0_7()
{
 uci -q set ddmesh.network.mesh_network_id=1206
 uci -q delete system.ntp.server
 uci -q add_list system.ntp.server=0.de.pool.ntp.org
 uci -q add_list system.ntp.server=1.de.pool.ntp.org
 uci -q add_list system.ntp.server=2.de.pool.ntp.org
 uci -q add_list system.ntp.server=3.de.pool.ntp.org
 uci -q set ddmesh.network.essid_adhoc='Freifunk-Mesh-Net'
}

upgrade_6_0_8()
{
 true
}

upgrade_6_0_9()
{
 true
}

upgrade_6_0_10()
{
 cp /rom/etc/iproute2/rt_tables /etc/iproute2/rt_tables
 rm /etc/config/wireless # delete symlink
}

upgrade_6_0_11()
{
 true
}

upgrade_6_0_12()
{
 true
}

upgrade_6_0_13()
{
 cp /rom/etc/iproute2/rt_tables /etc/iproute2/rt_tables
 rm /etc/config/wireless # delete symlink
 uci rename ddmesh.network.internal_dns='internal_dns1'
 uci set ddmesh.network.internal_dns1='10.200.0.4'
 uci set ddmesh.network.internal_dns2='10.200.0.16'
 uci set ddmesh.network.speed_enabled='0'
}

upgrade_6_0_14()
{
 true
}

upgrade_6_0_15()
{
 uci add_list ddmesh.system.communities='Freifunk Tharandt'
 uci rename ddmesh.network.wifi_channel_5Ghz=wifi_channel_5g
 uci rename ddmesh.network.wifi_txpower_5Ghz=wifi_txpower_5g
 uci add ddmesh geoloc
 uci rename ddmesh.@geoloc[-1]='geoloc'
 uci add_list ddmesh.geoloc.ignore_macs=''
 uci delete credentials.url.opkg
 uci set ddmesh.system.mesh_sleep='1'
}

upgrade_6_1_1()
{
 uci rename credentials.backbone_secret.key='fastd_key'
 uci add_list firewall.zone_mesh.network='tbb_wg'
}

upgrade_6_1_2()
{
 uci -q rename ddmesh.network.wifi3_network='wifi3_2g_network'
 uci -q rename ddmesh.network.wifi3_enabled='wifi3_2g_enabled'
 uci -q rename ddmesh.network.wifi3_security='wifi3_2g_security'
 uci rename credentials.wifi='wifi_2g'
 uci add credentials wifi
 uci rename credentials.@wifi[-1]='wifi_5g'
 uci set credentials.wifi_5g.private_ssid='private5g'
 uci set ddmesh.network.wifi3_5g_network='0'
 uci set ddmesh.network.wifi3_5g_enabled='0'
 uci set ddmesh.network.wifi3_5g_security='0'
}

upgrade_6_1_3()
{
 true
}

upgrade_6_1_4()
{
 uci -q rename ddmesh.backbone.default_server_port='default_fastd_port'
 uci -q rename ddmesh.backbone.server_port='fastd_port'
 uci -q rename ddmesh.privnet.default_server_port='default_fastd_port'
 uci -q rename ddmesh.privnet.server_port='fastd_port'
 uci set ddmesh.backbone.default_wg_port='5003'
 uci set ddmesh.backbone.wg_port='5003'
 uci set system.@system[0].cronloglevel=9
 uci add ddmesh log
 uci rename ddmesh.@log[-1]='log'
 uci -q set ddmesh.log.tasks=0
}


upgrade_6_1_5()
{
 true
}

upgrade_6_3_1()
{
 true
}


upgrade_6_4_2()
{
 uci set ddmesh.network.wifi_channel_5g=44
 uci set ddmesh.network.wifi_indoor_5g=0
 uci set ddmesh.network.wifi_channels_5g_outdoor='100-140'
 uci set ddmesh.network.wifi_ch_5g_outdoor_min=100
 uci set ddmesh.network.wifi_ch_5g_outdoor_max=140
 uci set ddmesh.network.mesh_mode='adhoc+mesh'
 if [ -n "$(uci -q get network.wifi)" ]; then
	uci -q rename network.wifi='wifi_adhoc'
 fi
 if [ -z "$(uci -q get credentials.network)" ]; then
	uci add credentials network
	uci rename credentials.@network[-1]='network'
	uci set credentials.network.wifi_mesh_id='mesh-64:64:6d:65:73:68'
 fi
 uci del network.wifi_mesh
}

upgrade_6_4_3()
{
 cp /rom/etc/config/firewall /etc/config/firewall
 cp /rom/etc/firewall.user /etc/firewall.user
}

upgrade_6_4_4()
{
 cp /rom/etc/config/firewall /etc/config/firewall
 uci rename network.wifi2_mesh='wifi_mesh2g'
 uci rename network.wifi5_mesh='wifi_mesh5g'
}

upgrade_6_4_5()
{
 uci set credentials.url.firmware_download_release="$(uci -c /rom/etc/config get credentials.url.firmware_download_release)"
 uci set credentials.url.firmware_download_testing="$(uci -c /rom/etc/config get credentials.url.firmware_download_testing)"
 uci set credentials.registration.register_service_url="$(uci -c /rom/etc/config get credentials.registration.register_service_url)"
 uci set ddmesh.system.mesh_sleep='1'
}

upgrade_6_4_6()
{
 true
}

upgrade_7_0_1()
{
 uci set ddmesh.system.firmware_autoupdate=1
}

upgrade_7_0_2()
{
 cp /rom/etc/config/firewall /etc/config/firewall
}

upgrade_7_0_3()
{
 true
}

upgrade_7_1_0()
{
	uci del_list firewall.zone_wifi.subnet
	uci add_list firewall.zone_wifi.subnet="$_ddmesh_wifi2net"
}

upgrade_7_1_1()
{
	for option in lan.ipaddr lan.netmask lan.gateway lan.dns wan.proto wan.ipaddr wan.netmask wan.gateway wan.dns
	do
		local v="$(uci -q get network.${option})"
		if [ -n "$v" ]; then
			local n="${option/./_}"
			uci set ddmesh.network.${n}="${v}"
		fi
	done
	rm /etc/config/uhttpd
	cp /rom/etc/config/uhttpd /etc/config/uhttpd
	rm /etc/config/wshaper

	uci add_list firewall.zone_mesh.network="mesh_vlan"
	uci set ddmesh.network.mesh_on_vlan='0'
	uci set ddmesh.network.mesh_vlan_id='9'

	uci set ddmesh.network.lan_ipaddr="$(uci get network.lan.ipaddr)"
	uci set ddmesh.network.lan_netmask="$(uci get network.lan.netmask)"
	uci set ddmesh.network.lan_gateway="$(uci get network.lan.gateway)"
	uci set ddmesh.network.lan_dns="$(uci get network.lan.dns)"
	uci set ddmesh.network.lan_proto="$(uci get network.lan.proto)"
	uci -q delete ddmesh.network.wwan_4g
	uci -q delete ddmesh.network.wwan_3g
	uci -q delete ddmesh.network.wwan_2g
}

upgrade_7_1_2()
{
	true
}

upgrade_7_1_3()
{
	true
}

upgrade_7_1_4()
{
	uci -q set ddmesh.network.mesh_network_id='0'
	uci -q delete ddmesh.network.speed_enabled
	uci -q delete ddmesh.network.speed_up
	uci -q delete ddmesh.network.speed_down
	uci -q delete ddmesh.network.speed_network
	uci set ddmesh.network.wifi_country='DE'
	uci set uhttpd.px5g.country='DE'
	uci set uhttpd.px5g.state='Saxony'
	uci set uhttpd.px5g.location='Dresden'
	uci set uhttpd.px5g.commonname='Freifunk Dresden Communities'
	uci set uhttpd.px5g.organisation='Freifunk Dresden'
}

upgrade_7_1_5()
{
 	uci set ddmesh.system.firmware_autoupdate=1
	cp /rom/etc/config/firewall /etc/config/firewall
}

##################################

run_upgrade
