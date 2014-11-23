#!/bin/sh
# script is called during boot process before config_update.
# It updates changes in persistent files (e.g.: /etc/config/network, firewall)

previous_version=$(uci get ddmesh.boot.upgrade_version 2>/dev/null)
current_version=$(cat /etc/version)

echo "previous_version=$previous_version"
echo "current_version=$current_version"

#set initial version; needed for correct behavior
previous_version=${previous_version:-2.0.02}
test "$previous_version" = "$current_version" && {
	echo "nothing to upgrade"
	exit 0
}

run_upgrade()
{
 #grep versions from this file (see below)
 upgrade_version=$(sed -n '/^[ 	]*upgrade_[0-9_]/{s#^[ 	]*upgrade_\([0-9]\+\)_\([0-9]\+\)_\([0-9]\+\).*#\1.\2.\3#;p}' $0)

 previous_version_found=0
 ignore=1
 for v in $upgrade_version
 do
 	echo -n $v
 	
 	#if I find current version before previous_version -> error
	test "$ignore" = "1" -a "$v" = "$current_version" && echo " ERROR: current version found before previous version" && exit 1
 	
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
	test "$v" = "$current_version" && echo "last valid upgrade finished" && break;
 done

 test "$previous_version_found" = "0" && echo "ERROR: missing upgrade function for previous version $previous_version" && exit 1
 test "$current_version" != "$v" && echo "ERROR: no upgrade function found for current version $current_version" && exit 1
 uci commit
 sync
 sleep 3
 reboot
}

#############################################
### keep ORDER - only change below
### uci commit is called after each upgrade function


upgrade_2_0_02() { echo "nothing todo"; }
upgrade_2_0_03() { echo "nothing todo"; }
upgrade_2_0_04() { echo "nothing todo"; }
upgrade_2_0_05()
{
 cp /rom/etc/config/firewall /etc/config/
 cp /rom/etc/config/dhcp /etc/config/
 rm -f /etc/config/uhttpd
 rm -f /etc/config/wireless
 ln -s /var/etc/config/uhttpd /etc/config/uhttpd
 ln -s /var/etc/config/wireless /etc/config/wireless
 cp /rom/etc/crontabs/root /etc/crontabs/root
 cp /rom/etc/iproute2/rt_tables /etc/iproute2/rt_tables
 cp /rom/etc/firewall.user /etc/firewall.user
 uci del firewall.zone_lan.subnet
 uci del firewall.zone_wifi2.subnet
 uci delete ddmesh.network.essid_adhoc
 uci delete ddmesh.network.essid_ap
 uci delete ddmesh.boot.firstboot
 uci delete ddmesh.boot.convert_nvram
 uci delete ddmesh.boot.config_update
 uci delete ddmesh.boot.config_update_count
 bssid="$(uci get credentials.wifi.bssid)"
 uci set ddmesh.network.bssid_adhoc="$bssid"
 uci set ddmesh.network.wifi_channel=13
 uci set ddmesh.network.wifi_txpower=18
 uci set ddmesh.network.wifi_diversity=1
 uci set ddmesh.network.lan_local_internet=0
 uci get ddmesh.network.wan_speed_down=100000
 uci get ddmesh.network.wan_speed_up=10000
 #change vpn server
 i=0
 while true
 do
  c="$(uci get ddmesh.@backbone_client[$i].host)"
  test -z "$c" && break
  n=""
  test "$c" = "vpn.ddmesh.de" && n="vpn1.freifunk-dresden.de"
  test "$c" = "vpn1.ddmesh.de" && n="vpn1.freifunk-dresden.de"
  test "$c" = "vpn2.ddmesh.de" && n="vpn2.freifunk-dresden.de"
  test "$c" = "vpn.freifunk-dresden.de" && n="vpn1.freifunk-dresden.de"
  echo "[$c] -> [$n]"
  test -n "$n" && uci set ddmesh.@backbone_client[$i].host="$n"
  i=$(($i+1))
 done
}
upgrade_2_0_06() { echo "nothing todo"; }
upgrade_2_0_07() {
 uci set ddmesh.network.client_disconnect_timeout=600
 cp /rom/etc/rc.local /etc/
}
upgrade_2_0_08() {
 cp /rom/etc/config/firewall /etc/config/
 cp /rom/etc/firewall.user /etc/firewall.user
 uci set ddmesh.system.community='Freifunk Dresden'
 uci add_list ddmesh.system.communities='Freifunk Dresden'
 uci add_list ddmesh.system.communities='Freifunk Meißen'
 rm -f /etc/config/wireless
 rm -f /etc/hosts
 ln -s /var/etc/hosts /etc/hosts
}
upgrade_2_1_0() { echo "nothing todo"; }
upgrade_2_1_1() { echo "nothing todo"; }
upgrade_2_1_2() { echo "nothing todo"; }
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


run_upgrade

