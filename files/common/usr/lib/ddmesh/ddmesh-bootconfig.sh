#!/bin/sh

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
#	option 	node			0
	option 	tmp_min_node		16
	option	tmp_max_node		99
#	option 	register_key		''
	option  disable_gateway         1
	option  wanssh                  1
	option  wanhttp                 1
	option  wanhttps                1
	option  wanicmp                 1
	option  wansetup                1
	option  wifissh                 1
	option  wifisetup               1

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
#0-disable; in seconds; default 600 (10h)
	option	client_disconnect_timeout 600
	option	dhcp_lan_offset		100
	option	dhcp_lan_limit		150
	option	dhcp_lan_lease		'12h'
#	option	essid_adhoc		''
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
	option	wifi2_netmask		'255.255.255.0'
	option	wifi2_broadcast		'192.168.252.255'
	option	wifi2_dhcpstart		'192.168.252.2'
	option	wifi2_dhcpend		'192.168.252.254'
	option	wifi2_dhcplease		'2h'
	option	lan_local_internet	'0'
	option	wan_speed_down		'100000'
	option	wan_speed_up		'10000'


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

config vpn 'vpn'
	option  clients_enabled         1
	option  server_enabled          0
	option  server_port		'4000'
	option	server_passwd		''
	option  default_server_port	'4000'
	option	number_of_clients	5

#config vpn_accept
#	option	name			''
#	option	password		''

#config vpn_client
#	option	name			''
#	option	port			''
#	option	password		''

EOM

	#disable crond logging
	uci set system.@system[0].cronloglevel=0

	#no key -> generate key
	test  -z "$(uci get ddmesh.system.register_key)" && {
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
	test -z "$(uci get ddmesh.system.node)" && {
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

 #update uhttpd certs
 uci set uhttpd.@cert[0].commonname="$(uci get ddmesh.system.community) ($_ddmesh_node)"
 uci set uhttpd.@cert[0].organisation="$(uci get ddmesh.system.community)"
 uci set uhttpd.@cert[0].node="Node $_ddmesh_node"
 rm -f /etc/uhttpd.crt /etc/uhttpd.key

 #############################################################################
 # setup wifi
 #############################################################################
 test -z "$(uci get network.wifi)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='wifi'
 }
 uci set network.wifi.ipaddr="$_ddmesh_nonprimary_ip"
 uci set network.wifi.netmask="$_ddmesh_netmask"
 uci set network.wifi.broadcast="$_ddmesh_broadcast"
 uci set network.wifi.proto='static'

 test -z "$(uci get network.wifi2)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='wifi2'
 }
 uci set network.wifi2.ipaddr="$(uci get ddmesh.network.wifi2_ip)"
 uci set network.wifi2.netmask="$(uci get ddmesh.network.wifi2_netmask)"
 uci set network.wifi2.broadcast="$(uci get ddmesh.network.wifi2_broadcast)"
 uci set network.wifi2.proto='static'
 #don't store dns for wifi2 to avoid adding it to resolv.conf

#wireless
 test ! -f /etc/config/wireless && wifi detect > /etc/config/wireless

 uci set wireless.@wifi-device[0].disabled=0
 uci set wireless.@wifi-device[0].channel="$(uci get ddmesh.network.wifi_channel)"

 #ensure we have valid country,with supportet channel and txpower
 test -z "$(uci get ddmesh.network.wifi_country)" && uci set ddmesh.network.wifi_country="DE"
 uci set wireless.@wifi-device[0].country="$(uci get ddmesh.network.wifi_country)"

 #txpower in dBm without unit
 test -n "$(uci get ddmesh.network.wifi_txpower)" && uci set wireless.@wifi-device[0].txpower="$(uci get ddmesh.network.wifi_txpower)"
 test -n "$(uci get ddmesh.network.wifi_diversity)" && uci set wireless.@wifi-device[0].diversity="$(uci get ddmesh.network.wifi_diversity)"
 test -n "$(uci get ddmesh.network.wifi_rxantenna)" && uci set wireless.@wifi-device[0].rxantenna="$(uci get ddmesh.network.wifi_rxantenna)"
 test -n "$(uci get ddmesh.network.wifi_txantenna)" && uci set wireless.@wifi-device[0].txantenna="$(uci get ddmesh.network.wifi_txantenna)"

 test -z "$(uci get ddmesh.network.wifi_htmode)" && uci set ddmesh.network.wifi_htmode="HT20"
 uci set wireless.@wifi-device[0].htmode="$(uci get ddmesh.network.wifi_htmode)"

 uci set wireless.@wifi-iface[0].device='radio0'
 uci set wireless.@wifi-iface[0].network='wifi'
 uci set wireless.@wifi-iface[0].mode='adhoc'
 uci set wireless.@wifi-iface[0].bssid="$(uci get ddmesh.network.bssid_adhoc)"
 uci set wireless.@wifi-iface[0].encryption='none'

 essid="$(uci get ddmesh.network.essid_adhoc)"
 essid="$(uci get ddmesh.system.community) ${essid:-[adhoc-$_ddmesh_node]}"
 uci set wireless.@wifi-iface[0].ssid="${essid:0:32}"

 test -z "$(uci get wireless.@wifi-iface[1])" && uci add wireless wifi-iface
 uci set wireless.@wifi-iface[1].device='radio0'
 uci set wireless.@wifi-iface[1].network='wifi2'
 uci set wireless.@wifi-iface[1].mode='ap'
 #disable n-support (WirelessMultiMedia) to allow android devices to connect
 uci set wireless.@wifi-iface[1].wmm='0'
 uci set wireless.@wifi-iface[1].encryption='none'

 essid="$(uci get ddmesh.network.essid_ap)"
 essid="$(uci get ddmesh.system.community) ${essid:-[$_ddmesh_node]}"
 uci set wireless.@wifi-iface[1].ssid="${essid:0:32}"

 #############################################################################
 # setup tbb to have a firewall zone for a interface that is not controlled
 # by openwrt. Bringing up tbb+ failes, but firewall rules are created anyway
 # got this information by testing, because openwrt feature to add non-controlled
 # interfaces (via netifd) was not working.
 #############################################################################
 test -z "$(uci get network.tbb)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='tbb'
 }
 uci set network.tbb.ifname="tbb+"
 uci set network.tbb.proto='static'
 #next line fakes the interface up/down state, so firewall will setup rules with interface names
 #see uci_get_state() in /lib/config/uci.sh
 uci set network.tbb.up='1'

 #bmxd bat zone, to a masq rules to firewall
 test -z "$(uci get network.bat)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='bat'
 }
 uci set network.bat.ifname="bat+"
 uci set network.bat.proto='static'
 #next line fakes the interface up/down state, so firewall will setup rules with interface names
 #see uci_get_state() in /lib/config/uci.sh
 uci set network.bat.up='1'

 #openvpn zone, to a masq rules to firewall
 test -z "$(uci get network.vpn)" && {
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
 uci del firewall.wanssh
 test "$(uci get ddmesh.system.wanssh)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='wanssh'
 	uci set firewall.@rule[-1].name="Allow-wan-ssh"
	uci set firewall.@rule[-1].src="wan"
	uci set firewall.@rule[-1].proto="tcp"
	uci set firewall.@rule[-1].dest_port="22"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }
 uci del firewall.wifissh
 test "$(uci get ddmesh.system.wifissh)" = "1" && {
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
 uci del firewall.tbbssh
 test "$(uci get ddmesh.system.wifissh)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='tbbssh'
 	uci set firewall.@rule[-1].name="Allow-tbb-ssh"
	uci set firewall.@rule[-1].src="tbb"
	uci set firewall.@rule[-1].proto="tcp"
	uci set firewall.@rule[-1].dest_port="22"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }
 uci del firewall.wifi2ssh
 test "$(uci get ddmesh.system.wifissh)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='wifi2ssh'
 	uci set firewall.@rule[-1].name="Allow-wifi2-ssh"
	uci set firewall.@rule[-1].src="wifi2"
	uci set firewall.@rule[-1].proto="tcp"
	uci set firewall.@rule[-1].dest_port="22"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }
 uci del firewall.wanhttp
 test "$(uci get ddmesh.system.wanhttp)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='wanhttp'
 	uci set firewall.@rule[-1].name="Allow-wan-http"
	uci set firewall.@rule[-1].src="wan"
	uci set firewall.@rule[-1].proto="tcp"
	uci set firewall.@rule[-1].dest_port="80"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }
 uci del firewall.wanhttps
 test "$(uci get ddmesh.system.wanhttps)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='wanhttps'
 	uci set firewall.@rule[-1].name="Allow-wan-https"
	uci set firewall.@rule[-1].src="wan"
	uci set firewall.@rule[-1].proto="tcp"
	uci set firewall.@rule[-1].dest_port="443"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }
 uci del firewall.wanicmp
 test "$(uci get ddmesh.system.wanicmp)" = "1" && {
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


config_temp_firewall() {
# temp firewall rules (fw uci can not add custom chains)

	#input rules for backbone/firewall ( to restrict backbone only going out, I use fmark and routing rules)
	iptables -N input_backbone_accept
	iptables -N input_backbone_reject
	iptables -A input_wan_rule -j input_backbone_accept
	iptables -A input_lan_rule -j input_backbone_accept
	iptables -A input_tbb_rule -j input_backbone_reject
	iptables -A input_bat_rule -j input_backbone_reject
	iptables -A input_wifi_rule -j input_backbone_reject
	iptables -A input_wifi2_rule -j input_backbone_reject

	iptables -N output_backbone_accept
	iptables -N output_backbone_reject
	iptables -A output_wan_rule -j output_backbone_accept
	iptables -A output_lan_rule -j output_backbone_accept
	iptables -A output_tbb_rule -j output_backbone_reject
	iptables -A output_bat_rule -j output_backbone_reject
	iptables -A output_wifi_rule -j output_backbone_reject
	iptables -A output_wifi2_rule -j output_backbone_reject

	iptables -N input_vpn_accept
	iptables -N input_vpn_reject
	iptables -A input_wan_rule -j input_vpn_reject
	iptables -A input_lan_rule -j input_vpn_reject
	iptables -A input_tbb_rule -j input_vpn_accept
	iptables -A input_bat_rule -j input_vpn_reject
	iptables -A input_wifi_rule -j input_vpn_accept
	iptables -A input_wifi2_rule -j input_vpn_reject

	#add rules to avoid access node via lan/wan ip; insert at start
	#to consider other tables (backbone)
	for i in wifi wifi2 tbb bat lan wan vpn
	do
		iptables -N input_"$i"_deny
		iptables -I input_"$i"_rule -j input_"$i"_deny
	done

 	#snat tbb and wifi fro 10.201.xxx to 10.200.xxxx
 	iptables -t nat -A postrouting_wifi_rule -p udp --dport 4305:4307 -j ACCEPT
 	iptables -t nat -A postrouting_wifi_rule -p tcp --dport 4305:4307 -j ACCEPT
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh lan)
 	iptables -t nat -A postrouting_wifi_rule -s $net_ipaddr/$net_mask -j SNAT --to-source $_ddmesh_ip 
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi2)
 	iptables -t nat -A postrouting_wifi_rule -s $net_ipaddr/$net_mask -j SNAT --to-source $_ddmesh_ip 

 	iptables -t nat -A postrouting_tbb_rule -p udp --dport 4305:4307 -j ACCEPT
 	iptables -t nat -A postrouting_tbb_rule -p tcp --dport 4305:4307 -j ACCEPT
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh lan)
 	iptables -t nat -A postrouting_tbb_rule -s $net_ipaddr/$net_mask -j SNAT --to-source $_ddmesh_ip 
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi2)
 	iptables -t nat -A postrouting_tbb_rule -s $net_ipaddr/$net_mask -j SNAT --to-source $_ddmesh_ip 

}

config_temp_configs() {

cat<<EOM >/var/etc/hosts
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
	option script_timeout	20
	option network_timeout	20
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
config 'wshaper' 'settings'
  option network 'wan'
  option downlink "$(uci get ddmesh.network.wan_speed_down)"
  option uplink "$(uci get ddmesh.network.wan_speed_up)"
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

#every 10 minutes
*/10 * * * *  /usr/lib/ddmesh/ddmesh-rdate.sh update >/dev/null 2>/dev/null

#forced user disconnection
*/5 * * * *  /usr/lib/ddmesh/ddmesh-splash.sh autodisconnect >/dev/null 2>/dev/null
EOM
}

#boot_step is empty for new devices
boot_step="$(uci get ddmesh.boot.boot_step)"
test -z "$boot_step" && boot_step=1

#check for old version that do use 'firstboot'
if [ "$(uci get ddmesh.boot.firstboot)" = "1" ]; then
	boot_step=3
	uci del ddmesh.boot.firstboot
fi

case "$boot_step" in
	1) # initial boot step
		logger -s -t "$LOGGER_TAG" "boot step 1"
		config_boot_step1
		uci set ddmesh.boot.boot_step=2
		uci commit
		reboot
		;;
	2) # update config
		logger -s -t "$LOGGER_TAG" "boot step 2"
		#node valid after boot_step >= 2
		node=$(uci get ddmesh.system.node)
		eval $(/usr/bin/ddmesh-ipcalc.sh -n $node)
		config_update
		uci set ddmesh.boot.boot_step=3
		uci set overlay.@overlay[0].md5sum="$(/usr/lib/ddmesh/ddmesh-overlay-md5sum.sh)"
		uci commit
		reboot
		;;
	3) # temp config
		logger -s -t "$LOGGER_TAG" "boot step 3"
		node=$(uci get ddmesh.system.node)
		eval $(/usr/bin/ddmesh-ipcalc.sh -n $node)
		config_temp_firewall
		if [ "$1"  != "firewall" ]; then
			config_temp_configs
			wifi
			/etc/init.d/uhttpd restart
			/etc/init.d/wshaper restart
			/etc/init.d/cron restart
		fi
esac


