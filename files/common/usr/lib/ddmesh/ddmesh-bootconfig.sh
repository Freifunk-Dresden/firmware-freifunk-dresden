#!/bin/ash

#Freifunk Router Setup
#ddmesh-boot.sh [firewall]
#  - Resets router settings to default freifunk settings depending on NODE
#  firewall - only restarts firewall. (is needed after interface hotplug events)
#             is called from /etc/hotplug.d/iface/50-bootconfig
#
# boot sequence for  flash with factory reset:
# boot1	-> reboot after flash, openwrt creates jffs2 -> reboot
# boot2	-> openwrt creates initial configs
#	-> ddmesh-bootconfig.sh: check if ddmesh config is already there
#		-> yes -> firmware running
#		-> no -> delete all config to clear firmware settings in case other firmware was replaced, create /etc/config/ddmesh -> reboot
# boot3 -> ddmesh_bootconfig.sh: create rest ddmesh config with temp node number -> reboot
# boot4 -> ddmesh-bootconfig.sh: update ddmesh config -> firmware running
#  firmware is ready and running: update config depending on node number -> reboot
# boot5 -> firmware running with updated node number

#use alias to be silent
#alias uci='uci -q'

LOGGER_TAG="ddmesh-boot"

config_boot_step1() {

cat <<EOM >/etc/config/overlay
config overlay
	option	md5sum '0'
EOM

cat <<EOM >/etc/config/ddmesh
#generated/overwritten by $0
config system 'system'
	option	community	'Freifunk Dresden'
	list	communities	'Freifunk Dresden'	
	list	communities	'Freifunk Meißen'	
	list	communities	'Freifunk Radebeul'	
#	option 	node			0
	option 	tmp_min_node		16
	option	tmp_max_node		99
#	option 	register_key		''
	option	announce_gateway	0
	option  wanssh                  1
	option  wanhttp                 1
	option  wanhttps                1
	option  wanicmp                 1
	option  wansetup                1
	option  wifissh                 1
	option  wifisetup               1
	option	firmware_autoupdate     0

config boot 'boot'
	option boot_step                0
	option upgrade_version		$(cat /etc/version)	

config gps 'gps'
	option 	latitude
	option  longitude
	option  altitude

config contact 'contact'
	option	name			''
	option  email			''
	option	location		''
	option	note			''

config network 'network'
	list 	gateway_check_ping	''
	list	splash_mac		''
#0-disable; in minutes;
	option	client_disconnect_timeout 0
	option	dhcp_lan_offset		100
	option	dhcp_lan_limit		150
	option	dhcp_lan_lease		'12h'
	option	essid_adhoc		'Freifunk Mesh-Net'
#	option	essid_ap		''
	option  bssid_adhoc		$(uci get credentials.wifi.bssid)
	option	wifi_country		'DE'
	option	wifi_channel		13
	option  wifi_txpower		18
#	option	wifi_diversity		1
#	option	wifi_rxantenna		1
#	option	wifi_txantenna		1
	option	wifi2_ip		'192.168.252.1'
	option	wifi2_dns		'192.168.252.1'
	option	wifi2_netmask		'255.255.252.0'
	option	wifi2_broadcast		'192.168.255.255'
	option	wifi2_dhcpstart		'192.168.252.2'
	option	wifi2_dhcpend		'192.168.255.254'
	option	wifi2_dhcplease		'5m'
	option	lan_local_internet	'0'
	option	wan_speed_down		'100000'
	option	wan_speed_up		'10000'
	option	internal_dns		'10.200.0.4'

config bmxd 'bmxd'
	option  routing_class           3
	option  gateway_class           '1024/1024'
	option  prefered_gateway        ''


config backbone 'backbone'
	option  clients_enabled         1
	option  server_enabled          0
	option  server_port		'5000'
	option  default_server_port	'5000'
	option	number_of_clients	5

#config backbone_accept
#	option	name			''
#	option	password		''

config backbone_client
	option 	host			'vpn1.freifunk-dresden.de'
	option 	port			'5000'
#	option	password 		''

config backbone_client
	option 	host			'vpn2.freifunk-dresden.de'
	option 	port			'5000'
#	option	password 		''

config backbone_client
	option 	host			'vpn3.freifunk-dresden.de'
	option 	port			'5000'
#	option	password 		''

config privnet 'privnet'
	option  clients_enabled         1
	option  server_enabled          0
	option  server_port		'4000'
	option	server_passwd		''
	option  default_server_port	'4000'
	option	number_of_clients	5

#config privnet_accept
#	option	name			''
#	option	password		''

#config privnet_client
#	option	name			''
#	option	port			''
#	option	password		''

config nodegroup 'nodegroup'
	option  clients_enabled         1
	option  server_enabled          0
	option  server_port		'4000'
	option	server_passwd		''
	option  default_server_port	'4000'
	option	number_of_clients	5

#config nodegroup_accept
#	option	name			''
#	option	password		''

#config nodegroup_client
#	option	name			''
#	option	port			''
#	option	password		''
EOM

	#almost disable crond logging (only errors)
	uci set system.@system[0].cronloglevel=9

	#no key -> generate key
	test  -z "$(uci -q get ddmesh.system.register_key)" && {
		#check if we have a ssh key; should not happen, because is created before running S80register
		key1=$(dropbearkey -y -f /etc/dropbear/dropbear_dss_host_key | sed -n '/Fingerprint/{s#.* \([a-f0-9:]\+\)#\1#;p}')
		test -z "$key1" && {
			echo "no ssh key, yet"
			logger -t "$LOGGER_TAG" "ERROR: no dropbear fingerprint (no ssh key)!"
			return
		}
		#use ip link instead of addr (avoid changes if ip change and key must be regenerated)
		key2=$(ip link | grep ether | md5sum | cut -d' ' -f1 | sed 's#\(..\)#\1:#g')
		key="$key2$key1"
		echo "key2: $key2"
		echo "key1: $key1"
		echo "save key [$key]"
		uci set ddmesh.system.register_key=$key
		logger -t "$LOGGER_TAG" "key=[$key] stored."
	}

	#no node -> generate dummy node. if router was registered already with a different node and has just
	#deleted the node locally or is using node out of rage (like temporary node), the stored node or a
	#new node will be returnd by registrator
	TMP_MIN_NODE="$(uci get ddmesh.system.tmp_min_node)"
	TMP_MAX_NODE="$(uci get ddmesh.system.tmp_max_node)"
	test -z "$(uci -q get ddmesh.system.node)" && {
		echo "no local node -> create dummy node"
		a=$(cat /proc/uptime);a=${a%%.*}
		b=$(ip addr | md5sum | sed 's#[a-f:0 \-]##g' | dd bs=1 count=6 2>/dev/null) #remove leading '0'
		node=$((((a+b)%($TMP_MAX_NODE-$TMP_MIN_NODE+1))+$TMP_MIN_NODE))
		echo "commit node [$node]"
		logger -t "$LOGGER_TAG" "INFO: generated temorary node is $node"
		uci set ddmesh.system.node=$node
	}
} # config_boot_step1

#############################################################################
# update configuration depending on new ddmesh settings
config_update() {

 #ONLY uci settings, to ensure not flashing on every boot
 #function called when node is valid, to setup all settings depending on node
 #or other updates of system generated configs

 #set hostname
 uci set system.@system[0].hostname="$_ddmesh_hostname"
 uci set system.@system[0].timezone="CET-1CEST,M3.5.0,M10.5.0/3"

 #syslog
 uci set system.@system[0].log_prefix="freifunk.$_ddmesh_node"

 #update uhttpd certs
 uci set uhttpd.@cert[0].commonname="$(uci get ddmesh.system.community) ($_ddmesh_node)"
 uci set uhttpd.@cert[0].organisation="$(uci get ddmesh.system.community)"
 uci set uhttpd.@cert[0].node="Node $_ddmesh_node"
 rm -f /etc/uhttpd.crt /etc/uhttpd.key

 #############################################################################
 # setup wifi
 #############################################################################
 test -z "$(uci -q get network.wifi)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='wifi'
 }
 uci set network.wifi.ipaddr="$_ddmesh_nonprimary_ip"
 uci set network.wifi.netmask="$_ddmesh_netmask"
 uci set network.wifi.broadcast="$_ddmesh_broadcast"
 uci set network.wifi.proto='static'

 test -z "$(uci -q get network.wifi2)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='wifi2'
 }
 uci set network.wifi2.ipaddr="$(uci get ddmesh.network.wifi2_ip)"
 uci set network.wifi2.netmask="$(uci get ddmesh.network.wifi2_netmask)"
 uci set network.wifi2.broadcast="$(uci get ddmesh.network.wifi2_broadcast)"
 uci set network.wifi2.proto='static'
 uci set network.wifi2.type='bridge'
 #don't store dns for wifi2 to avoid adding it to resolv.conf

#wireless
 test ! -f /etc/config/wireless && wifi detect > /etc/config/wireless

 uci set wireless.@wifi-device[0].disabled=0
 uci set wireless.@wifi-device[0].channel="$(uci get ddmesh.network.wifi_channel)"

 #ensure we have valid country,with supportet channel and txpower
 test -z "$(uci -q get ddmesh.network.wifi_country)" && uci set ddmesh.network.wifi_country="DE"
 uci set wireless.@wifi-device[0].country="$(uci get ddmesh.network.wifi_country)"

 #txpower in dBm without unit
 test -n "$(uci -q get ddmesh.network.wifi_txpower)" && uci set wireless.@wifi-device[0].txpower="$(uci get ddmesh.network.wifi_txpower)"
 test -n "$(uci -q get ddmesh.network.wifi_diversity)" && uci set wireless.@wifi-device[0].diversity="$(uci get ddmesh.network.wifi_diversity)"
 test -n "$(uci -q get ddmesh.network.wifi_rxantenna)" && uci set wireless.@wifi-device[0].rxantenna="$(uci get ddmesh.network.wifi_rxantenna)"
 test -n "$(uci -q get ddmesh.network.wifi_txantenna)" && uci set wireless.@wifi-device[0].txantenna="$(uci get ddmesh.network.wifi_txantenna)"

 test -z "$(uci -q get ddmesh.network.wifi_htmode)" && uci set ddmesh.network.wifi_htmode="HT20"
 uci set wireless.@wifi-device[0].htmode="$(uci get ddmesh.network.wifi_htmode)"

 uci set wireless.@wifi-iface[0].device='radio0'
 uci set wireless.@wifi-iface[0].network='wifi'
 uci set wireless.@wifi-iface[0].mode='adhoc'
 uci set wireless.@wifi-iface[0].bssid="$(uci get ddmesh.network.bssid_adhoc)"
 uci set wireless.@wifi-iface[0].encryption='none'

 essid="$(uci -q get ddmesh.network.essid_adhoc)"
 essid="${essid:-Freifunk Mesh-Net}"
 uci set wireless.@wifi-iface[0].ssid="${essid:0:32}"

 test -z "$(uci -q get wireless.@wifi-iface[1])" && uci add wireless wifi-iface
 uci set wireless.@wifi-iface[1].device='radio0'
 uci set wireless.@wifi-iface[1].network='wifi2'
 uci set wireless.@wifi-iface[1].mode='ap'
 #disable n-support (WirelessMultiMedia) to allow android devices to connect
 uci set wireless.@wifi-iface[1].wmm='0'
 uci set wireless.@wifi-iface[1].encryption='none'
 uci set wireless.@wifi-iface[1].isolate='1'

 if [ "$(uci get ddmesh.network.custom_essid)" = "1" ]; then
	custom="$(uci get ddmesh.network.essid_ap)"
	if [ -n "$(echo "$custom" | sed 's#^ *$##')" ]; then
 		essid="$(uci get ddmesh.system.community):$(uci get ddmesh.network.essid_ap)"
	else
 		essid="$(uci get ddmesh.system.community)"
	fi
 else
 	essid="$(uci get ddmesh.system.community) [$_ddmesh_node]"
 fi
 uci set wireless.@wifi-iface[1].ssid="${essid:0:32}"

 #############################################################################
 # setup tbb to have a firewall zone for a interface that is not controlled
 # by openwrt. Bringing up tbb+ failes, but firewall rules are created anyway
 # got this information by testing, because openwrt feature to add non-controlled
 # interfaces (via netifd) was not working.
 #############################################################################
 test -z "$(uci -q get network.tbb)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='tbb'
 }
 uci set network.tbb.ifname="tbb+"
 uci set network.tbb.proto='static'
 #next line fakes the interface up/down state, so firewall will setup rules with interface names
 #see uci_get_state() in /lib/config/uci.sh
 uci set network.tbb.up='1'

 #bmxd bat zone, to a masq rules to firewall
 test -z "$(uci -q get network.bat)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='bat'
 }
 uci set network.bat.ifname="bat+"
 uci set network.bat.proto='static'
 #next line fakes the interface up/down state, so firewall will setup rules with interface names
 #see uci_get_state() in /lib/config/uci.sh
 uci set network.bat.up='1'

 #openvpn zone, to a masq rules to firewall
 test -z "$(uci -q get network.vpn)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='vpn'
 }
 uci set network.vpn.ifname="vpn+"
 uci set network.vpn.proto='static'
 #next line fakes the interface up/down state, so firewall will setup rules with interface names
 #see uci_get_state() in /lib/config/uci.sh
 uci set network.vpn.up='1'

 #############################################################################
 # setup firewall
 #############################################################################

 # update lan,wifi2 ip ranges in forwarding rules
 #uci set firewall.forward_lan_mesh.src_ip="$lan_net/$lan_pre"

 eval $(ipcalc.sh $(uci get network.lan.ipaddr) $(uci get network.lan.netmask))
 lan_net=$NETWORK
 lan_pre=$PREFIX

 eval $(ipcalc.sh $(uci get ddmesh.network.wifi2_ip) $(uci get ddmesh.network.wifi2_netmask))
 wifi2_net=$NETWORK
 wifi2_pre=$PREFIX

 # firewall rules for user enabled services
 uci -q del firewall.wanssh
 test "$(uci -q get ddmesh.system.wanssh)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='wanssh'
 	uci set firewall.@rule[-1].name="Allow-wan-ssh"
	uci set firewall.@rule[-1].src="wan"
	uci set firewall.@rule[-1].proto="tcp"
	uci set firewall.@rule[-1].dest_port="22"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }
 uci -q del firewall.wifissh
 test "$(uci -q get ddmesh.system.wifissh)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='wifissh'
 	uci set firewall.@rule[-1].name="Allow-wifi-ssh"
	uci set firewall.@rule[-1].src="wifi"
	uci set firewall.@rule[-1].proto="tcp"
	uci set firewall.@rule[-1].dest_port="22"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }
 #tbb same as wifi (no extra switch)
 uci -q del firewall.tbbssh
 test "$(uci -q get ddmesh.system.wifissh)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='tbbssh'
 	uci set firewall.@rule[-1].name="Allow-tbb-ssh"
	uci set firewall.@rule[-1].src="tbb"
	uci set firewall.@rule[-1].proto="tcp"
	uci set firewall.@rule[-1].dest_port="22"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }
 uci -q del firewall.wifi2ssh
 test "$(uci -q get ddmesh.system.wifissh)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='wifi2ssh'
 	uci set firewall.@rule[-1].name="Allow-wifi2-ssh"
	uci set firewall.@rule[-1].src="wifi2"
	uci set firewall.@rule[-1].proto="tcp"
	uci set firewall.@rule[-1].dest_port="22"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }
 uci -q del firewall.wanhttp
 test "$(uci -q get ddmesh.system.wanhttp)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='wanhttp'
 	uci set firewall.@rule[-1].name="Allow-wan-http"
	uci set firewall.@rule[-1].src="wan"
	uci set firewall.@rule[-1].proto="tcp"
	uci set firewall.@rule[-1].dest_port="80"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }
 uci -q del firewall.wanhttps
 test "$(uci -q get ddmesh.system.wanhttps)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='wanhttps'
 	uci set firewall.@rule[-1].name="Allow-wan-https"
	uci set firewall.@rule[-1].src="wan"
	uci set firewall.@rule[-1].proto="tcp"
	uci set firewall.@rule[-1].dest_port="443"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }
 uci -q del firewall.wanicmp
 test "$(uci -q get ddmesh.system.wanicmp)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='wanicmp'
 	uci set firewall.@rule[-1].name="Allow-wan-icmp"
	uci set firewall.@rule[-1].src="wan"
	uci set firewall.@rule[-1].proto="icmp"
	uci set firewall.@rule[-1].icmp_type="echo-request"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }


}

config_temp_configs() {
#create directory to calm dnsmasq
mkdir -p /tmp/hosts
mkdir -p /var/etc
cat<<EOM >/var/etc/dnsmasq.hosts
127.0.0.1 localhost
$(uci get ddmesh.network.wifi2_ip) hotspot
EOM


# generate temporary configurations
	mkdir -p /var/etc/config

	# update /etc/opkg.conf
	eval $(cat /etc/openwrt_release)
	version="$(cat /etc/version)"
	platform="${DISTRIB_TARGET%/*}"
	cat <<EOM >/tmp/opkg.conf
src/gz ddmesh http://download.freifunk-dresden.de/firmware/$version/$platform/packages
dest root /
dest ram /tmp
lists_dir ext /var/opkg-lists
option overlay_root /overlay
EOM

cat <<EOM >/var/etc/config/uhttpd
#generated/overwritten by $0
config uhttpd main
	list listen_http	0.0.0.0:80
	list listen_http	0.0.0.0:81
	list listen_https	0.0.0.0:443
	option home		/www
	option rfc1918_filter 1
	option max_requests	250
	option cert		/etc/uhttpd.crt
	option key		/etc/uhttpd.key
	list interpreter	".cgi=/bin/sh"
EOM
test -f /usr/lib/lua/uhttpd-handler.lua &&
{
cat <<EOM >>/var/etc/config/uhttpd
	list interpreter	".lua=/usr/bin/lua"
	option lua_prefix	/cgilua/
	option lua_handler	/usr/lib/lua/uhttpd-handler.lua
EOM
}
cat <<EOM >>/var/etc/config/uhttpd
	option script_timeout	300	
	option network_timeout	300	
	option tcp_keepalive	0
	option http_keepalive	0
	option realm		'$(uci get ddmesh.system.community)'
	option index_page	index.cgi
	option error_page	/index.cgi

# Certificate defaults for px5g key generator
config cert px5g
	option days		7300
	option bits		1024
	option country		DE
	option state		Dresden
	option location		Dresden
	option commonname	'$(uci get ddmesh.system.community)'
	option node		'-'

EOM

 #traffic shaping
cat <<EOM >/var/etc/config/wshaper
config 'wshaper' 'wan_settings'
  option network 'wan'
  option downlink "$(uci get ddmesh.network.wan_speed_down)"
  option uplink "$(uci get ddmesh.network.wan_speed_up)"

config 'wshaper' 'lan_settings'
  option network 'lan'
  option downlink "$(uci get ddmesh.network.lan_speed_down)"
  option uplink "$(uci get ddmesh.network.lan_speed_up)"
EOM

 #setup cron.d
mkdir -p /var/etc/crontabs
m=$(( $_ddmesh_node % 60))
cat<<EOM > /var/etc/crontabs/root
#every 1 minutes batman run check
*/1 * * * *  /usr/lib/ddmesh/ddmesh-bmxd.sh check >/dev/null 2>/dev/null

#every 3 minutes start (after killing)
*/3 * * * *  /usr/bin/ddmesh-gateway-check.sh >/dev/null 2>/dev/null &

#every 2h
$m */2 * * *  /usr/bin/ddmesh-register-node.sh >/dev/null 2>/dev/null

#forced user disconnection
*/5 * * * *  /usr/lib/ddmesh/ddmesh-splash.sh autodisconnect >/dev/null 2>/dev/null

#watchdog
*/5 * * * *  /usr/lib/ddmesh/ddmesh-watchdog.sh >/dev/null 2>/dev/null

EOM

if [ "$(uci get ddmesh.system.bmxd_nightly_restart)" = "1" ];then
cat<<EOM >> /var/etc/crontabs/root
0 4 * * *  /usr/lib/ddmesh/ddmesh-bmxd.sh nightly >/dev/null 2>/dev/null
EOM
fi

if [ "$(uci get ddmesh.system.firmware_autoupdate)" = "1" ];then
cat<<EOM >> /var/etc/crontabs/root
$m 3 * * *  /usr/lib/ddmesh/ddmesh-firmware-autoupdate.sh run >/dev/null 2>/dev/null
EOM
fi
}

wait_for_wifi()
{
	c=0
	max=20
	while [ $c -lt $max ]
	do
		eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi wifi)
		eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi2 wifi2)
		if [ "$wifi_up" = 1 -a "$wifi2_up" = 1 ]; then
			logger -s -t "$LOGGER_TAG" "WIFI is up - continue"
			/usr/lib/ddmesh/ddmesh-led.sh wifi alive
			break;
		fi
		logger -s -t "$LOGGER_TAG" "Wait for WIFI up: $c/$max"
		sleep 1
		c=$((c+1))
	done
}

#boot_step is empty for new devices
boot_step="$(uci get ddmesh.boot.boot_step)"
test -z "$boot_step" && boot_step=1

#check for old version that do use 'firstboot'
if [ "$(uci -q get ddmesh.boot.firstboot)" = "1" ]; then
	boot_step=3
	uci -q del ddmesh.boot.firstboot
fi

case "$boot_step" in
	1) # initial boot step
		/usr/lib/ddmesh/ddmesh-led.sh status boot1
		logger -s -t "$LOGGER_TAG" "boot step 1"
		config_boot_step1
		uci set ddmesh.boot.boot_step=2
		uci commit
		logger -s -t "$LOGGER_TAG" "reboot boot step 1"
		reboot
		#stop boot process
		exit 1
		;;
	2) # update config
		/usr/lib/ddmesh/ddmesh-led.sh status boot2
		logger -s -t "$LOGGER_TAG" "boot step 2"
		#node valid after boot_step >= 2
		node=$(uci get ddmesh.system.node)
		eval $(/usr/bin/ddmesh-ipcalc.sh -n $node)

		logger -t $LOGGER_TAG "run ddmesh upgrade"
		/usr/lib/ddmesh/ddmesh-upgrade.sh

		config_update

		uci set ddmesh.boot.boot_step=3
		/usr/lib/ddmesh/ddmesh-overlay-md5sum.sh write

		uci commit
		logger -s -t "$LOGGER_TAG" "reboot boot step 2"

		sync
		reboot
		#stop boot process
		exit 1
		;;
	3) # temp config
		/usr/lib/ddmesh/ddmesh-led.sh status boot3
		logger -s -t "$LOGGER_TAG" "boot step 3"
		node=$(uci get ddmesh.system.node)
		eval $(/usr/bin/ddmesh-ipcalc.sh -n $node)
		if [ "$1"  != "firewall" ]; then
			#restart fw, because sometimes fw was not setup correctly by openwrt
			wait_for_wifi
			fw3 restart
			/usr/lib/ddmesh/ddmesh-firewall-addons.sh once
			config_temp_configs
			wifi
			/etc/init.d/uhttpd restart
			/etc/init.d/wshaper restart
			/etc/init.d/cron restart
		fi
		/usr/lib/ddmesh/ddmesh-firewall-addons.sh post
		/usr/lib/ddmesh/ddmesh-firewall-addons.sh update
esac
#continue boot-process
exit 0

