#!/bin/sh
# script is called during boot process before config_update.
# It updates changes in persistent files (e.g.: /etc/config/network, firewall)

previous_version=$(uci get ddmesh.boot.upgrade_version 2>/dev/null)
current_version=$(cat /etc/version)

echo "previous_version=$previous_version"
echo "current_version=$current_version"

#set initial version; needed for correct behavior
previous_version=${previous_version:-2.1.2}
test "$previous_version" = "$current_version" && {
	echo "nothing to upgrade"
	exit 0
}

run_upgrade()
{
 #grep versions from this file (see below)
 upgrade_version_list=$(sed -n '/^[ 	]*upgrade_[0-9_]/{s#^[ 	]*upgrade_\([0-9]\+\)_\([0-9]\+\)_\([0-9]\+\).*#\1.\2.\3#;p}' $0)

 previous_version_found=0
 ignore=1
 for v in $upgrade_version_list
 do
 	echo -n $v

 	#if I find current version before previous_version -> error
	test "$ignore" = "1" -a "$v" = "$current_version" && echo " ERROR: current version found before previous version" && break

 	#ignore all versions upto firmware previous_version
	test "$ignore" = "1" -a "$v" != "$previous_version" && echo " ignored" && continue
	ignore=0
	previous_version_found=1

	#ignore if already on same version (safety check)
	test "$v" = "$previous_version" && echo " ignored (same)" && continue

	#create name of upgrade function (version dependet)
	function_suffix=$(echo $v|sed 's#\.#_#g')
	echo " upgrade to $v"
	upgrade_$function_suffix;

 	#force config update after each upgrade or firmware flash
 	uci set ddmesh.boot.boot_step=2

	#save current state in case of later errors
	uci set ddmesh.boot.upgrade_version=$v
	uci add_list ddmesh.boot.upgraded="$previous_version to $v"

	#stop if we have reached "current version" (ignore other upgrades)
	test "$v" = "$current_version" && echo "last valid upgrade finished" && uci commit && break;
 done

 test "$previous_version_found" = "0" && echo "ERROR: missing upgrade function for previous version $previous_version" && exit 1
 test "$current_version" != "$v" && echo "ERROR: no upgrade function found for current version $current_version" && exit 1
}

#############################################
### keep ORDER - only change below
### uci commit is called after booting via ddmesh.boot_step=2


upgrade_2_1_3() {
 #scroll register_key to get new node
 x="$(uci get ddmesh.system.register_key)"
 uci set ddmesh.system.register_key="${x#*:}:${x%%:*}"
 uci set ddmesh.network.wifi2_dhcplease='2h'
 uci set ddmesh.bmxd.gateway_class='1024/1024'
 uci set network.wifi.ipaddr="$_ddmesh_nonprimary_ip"
}
upgrade_2_1_4() {
 cp /rom/etc/firewall.user /etc/
 uci set ddmesh.network.wifi_htmode="HT20"
}
upgrade_2_1_5() {
 cp /rom/etc/config/credentials /etc/config/
 rm -rf /etc/crontabs/root
 ln -s /var/etc/crontabs/root /etc/crontabs/root
}
upgrade_3_1_6() {
 uci set wireless.@wifi-iface[1].isolate='1'
 rm -rf /etc/hosts
 ln -s /var/etc/dnsmasq.hosts /etc/hosts
 #clear firewall, moved to ddmesh-firewall.sh
 >/etc/firewall.user
 uci set system.@system[0].log_prefix="freifunk.$_ddmesh_node"
 uci set ddmesh.network.wifi2_dhcplease='5m'
 uci set ddmesh.network.client_disconnect_timeout=0
 uci del ddmesh.system.disable_gateway
 uci sel ddmesh.system.announce_gateway=0
}
upgrade_3_1_7() {
 uci set ddmesh.network.wan_speed_down=100000
 uci set ddmesh.network.wan_speed_up=10000
 uci set ddmesh.network.lan_speed_down=100000
 uci set ddmesh.network.lan_speed_up=10000
 uci set ddmesh.system.firmware_autoupdate=0
 uci add credentials url
 uci rename credentials.@url[-1]='url'
 uci set credentials.url.firmware_download_release='http://download.freifunk-dresden.de/firmware/latest'
 uci set credentials.url.firmware_download_testing='http://download.freifunk-dresden.de/firmware/testing'
}
upgrade_3_1_8() {
 essid="Freifunk Mesh-Net"
 uci -q set ddmesh.network.essid_adhoc="$essid"
 uci set wireless.@wifi-iface[0].ssid="${essid:0:32}"
 uci add_list ddmesh.system.communities="Freifunk Radebeul"
 uci set ddmesh.network.internal_dns='10.200.0.4'
 uci set ddmesh.network.wifi2_ip='192.168.252.1'
 uci set ddmesh.network.wifi2_dns='192.168.252.1'
 uci set ddmesh.network.wifi2_netmask='255.255.252.0'
 uci set ddmesh.network.wifi2_broadcast='192.168.255.255'
 uci set ddmesh.network.wifi2_dhcpstart='192.168.252.2'
 uci set ddmesh.network.wifi2_dhcpend='192.168.255.254'
 uci set firewall.zone_wifi.masq='0'
 uci set firewall.zone_tbb.masq='0'
}
upgrade_3_1_9() {
 uci set network.wifi2.type='bridge'
 uci set credentials.url.firmware_download_server='download.freifunk-dresden.de'
 uci set ddmesh.system.bmxd_nightly_restart='0'
 test -n "$(uci get ddmesh.network.essid_ap)" && uci set ddmesh.network.custom_essid=1
 uci set credentials.registration.register_service_url="$(uci get credentials.registration.register_service_url | sed 's#ddmesh.de#freifunk-dresden.de#')"
}

upgrade_4_2_0() {
 echo dummy
}

upgrade_4_2_2() {
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

upgrade_4_2_3() {
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
 uci set ddmesh.privnet.server_port=4000
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
 uci set ddmesh.network.speed_enabled=1
 uci set ddmesh.network.wifi_country="BO"
 for nt in node mobile server
 do
	uci del_list ddmesh.system.node_types=$nt
	uci add_list ddmesh.system.node_types=$nt
 done
}

upgrade_4_2_4() {
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
 uci set credentials.geoloc.host="$(uci get -c /rom/etc/config credentials.geoloc.host)"
 uci set credentials.geoloc.port="$(uci get -c /rom/etc/config credentials.geoloc.port)"
 uci set credentials.geoloc.uri="$(uci get -c /rom/etc/config credentials.geoloc.uri)"
 #https
 uci set credentials.url.firmware_download_release="$(uci get -c /rom/etc/config credentials.url.firmware_download_release)"
 uci set credentials.url.firmware_download_testing="$(uci get -c /rom/etc/config credentials.url.firmware_download_testing)"
 uci set credentials.url.opkg="$(uci get -c /rom/etc/config credentials.url.opkg)"
 uci set credentials.registration.register_service_url="$(uci get -c /rom/etc/config credentials.registration.register_service_url)"
}


upgrade_4_2_5() {
	#add network to fw zone tbb, to create rules with br-tbb_lan
	uci delete firewall.zone_tbb.network
        uci add_list firewall.zone_tbb.network='tbb'
        uci add_list firewall.zone_tbb.network='tbb_fastd'
	uci -q delete network.tbb_lan
}



##################################

run_upgrade

