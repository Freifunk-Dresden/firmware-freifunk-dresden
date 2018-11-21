#!/bin/ash

#Freifunk Router Setup
#
# boot sequence for  flash with factory reset:
# boot1	-> reboot after flash, openwrt creates jffs2 -> reboot
# boot2	-> openwrt creates initial configs
#	-> ddmesh-bootconfig.sh: check if ddmesh config is already there
#		-> yes -> firmware running
#		-> no -> delete all config to clear firmware settings in 
#			case other firmware was replaced, create /etc/config/ddmesh -> reboot
# boot3 -> ddmesh_bootconfig.sh: create rest ddmesh config with temp node number -> reboot
# boot4 -> ddmesh-bootconfig.sh: update ddmesh config -> firmware running
#  firmware is ready and running: update config depending on node number -> reboot
# boot5 -> firmware running with updated node number

#use alias to be silent
#alias uci='uci -q'

LOGGER_TAG="ddmesh-boot"

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)

config_boot_step1() {

cat <<EOM >/etc/config/overlay
config overlay 'data'
	option	md5sum '0'
EOM

cat <<EOM >/etc/config/ddmesh
#generated/overwritten by $0
config system 'system'
	option	community	'Freifunk Dresden'
	list	communities	'Freifunk Dresden'
	list	communities	'Freifunk Freiberg'
	list	communities	'Freifunk Meissen'
	list	communities	'Freifunk OL'
	list	communities	'Freifunk Pirna'
	list	communities	'Freifunk Radebeul'
	list	communities	'Freifunk Waldheim'
#	option 	node			0
	option 	tmp_min_node		900
	option	tmp_max_node		999
#	option 	register_key		''
	option	announce_gateway	0
	option  wanssh                  1
	option  wanhttp                 1
	option  wanhttps                1
	option  wanicmp                 1
	option  wansetup                1
	option  meshssh                 1
	option  meshsetup               1
	option	disable_splash		1
	option	firmware_autoupdate     0
	option	email_notification	0
	option	node_type		'node'
	list	node_types		'node'
	list	node_types		'mobile'
	list	node_types		'server'
	option	nightly_reboot		0

config boot 'boot'
	option boot_step                0
	option upgrade_version		$(cat /etc/version)
	option nightly_upgrade_running	0
	option upgrade_running		0

config gps 'gps'
	option 	latitude		'51.054741'
	option  longitude		'13.742642'
	option  altitude		'0'

config contact 'contact'
	option	name			''
	option  email			''
	option	location		''
	option	note			''

config network 'network'
	list 	gateway_check_ping	''
#	list	splash_mac		''
#0-disable; in minutes;
	option	client_disconnect_timeout 0
	option	dhcp_lan_offset		100
	option	dhcp_lan_limit		0
	option	dhcp_lan_lease		'12h'
	option	essid_adhoc		'Freifunk Mesh-Net'
#	option	essid_ap		'' #custom essid
	option	wifi_country		'BO'
	option	wifi_channel		13
	option  wifi_txpower		18
#	option	wifi_diversity		1
#	option	wifi_rxantenna		1
#	option	wifi_txantenna		1
	option	wifi_slow_rates		0
	option	wifi2_dhcplease		'5m'
	option	wifi2_isolate		'1'
	option	lan_local_internet	'0'
	option	speed_down		'200000'
	option	speed_up		'50000'
	option	speed_network		'lan'
	option	speed_enabled		0
	option	internal_dns		'10.200.0.4'
	option	mesh_network_id		'1206'
	option	mesh_mtu		1200
	option	mesh_on_lan		0
	option	wifi3_enabled		0
	option	wifi3_network		'lan'

config bmxd 'bmxd'
	option  routing_class           3
	option  gateway_class           '1024/1024'
	option  prefered_gateway        ''


config backbone 'backbone'
	option  server_port		'5002'
	option  default_server_port	'5002'
	option	number_of_clients	5

#config backbone_accept
#	option	key			''
#	option	comment			''

config backbone_client
	option 	host			'vpn1.freifunk-dresden.de'
	option 	port			'5002'
	option	public_key 		''

config backbone_client
	option 	host			'vpn2.freifunk-dresden.de'
	option 	port			'5002'
	option	public_key 		''

config backbone_client
	option 	host			'vpn3.freifunk-dresden.de'
	option 	port			'5002'
	option	public_key 		''

config backbone_client
	option 	host			'vpn7.freifunk-dresden.de'
	option 	port			'5002'
	option	public_key 		''

config privnet 'privnet'
	option  server_port		'4000'
	option  default_server_port	'4000'
	option	number_of_clients	5

#config privnet_accept
#	option	key			''
#	option	comment			''

#config privnet_client
#	option	host			''
#	option	port			''
#	option	public_key		''

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
		key1=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | hexdump -e '16/1 "%02x:"' | sed 's#:$##')
		key2=$(ip link | grep ether | md5sum | cut -d' ' -f1 | sed 's#\(..\)#\1:#g;s#:$##')
		key="$key1:$key2"
		echo "key1: $key1"
		echo "key2: $key2"
		echo "save key [$key]"
		uci set ddmesh.system.register_key=$key
		logger -s -t "$LOGGER_TAG" "key=[$key] stored."
	}

	#no node -> generate dummy node. if router was registered already with a different node and has just
	#deleted the node locally or is using node out of rage (like temporary node), the stored node or a
	#new node will be returnd by registrator
	test -z "$(uci -q get ddmesh.system.node)" && {
		TMP_MIN_NODE="$(uci get ddmesh.system.tmp_min_node)"
		TMP_MAX_NODE="$(uci get ddmesh.system.tmp_max_node)"
		echo "no local node -> create dummy node"
		a=$(cat /proc/uptime);a=${a%%.*}
		b=$(ip addr | md5sum | sed 's#[a-f:0 \-]##g' | dd bs=1 count=6 2>/dev/null) #remove leading '0'
		node=$((((a+b)%($TMP_MAX_NODE-$TMP_MIN_NODE+1))+$TMP_MIN_NODE))
		logger -s -t "$LOGGER_TAG" "INFO: generated temorary node is $node"
		uci set ddmesh.system.node=$node
	}
	
	# dropbear ssh
	uci -q set dropbear.@dropbear[0].SSHKeepAlive=30

} # config_boot_step1

setup_wireless()
{
 #wireless, regenerate config in case wifi usb stick plugged into different usb port
 rm /var/etc/config/wireless
 wifi config

 uci set wireless.@wifi-device[0].disabled=0
 uci set wireless.@wifi-device[0].hwmode=11n
 uci set wireless.@wifi-device[0].channel="$(uci get ddmesh.network.wifi_channel)"

 #ensure we have valid country,with supportet channel and txpower
 test -z "$(uci -q get ddmesh.network.wifi_country)" && uci set ddmesh.network.wifi_country="BO"
 uci set wireless.@wifi-device[0].country="$(uci get ddmesh.network.wifi_country)"

 #setup wifi rates
 uci delete wireless.@wifi-device[0].basic_rate
 uci delete wireless.@wifi-device[0].supported_rates
 
 if [ "$(uci -q get ddmesh.network.wifi_slow_rates)" != "1" ]; then
	uci add_list wireless.@wifi-device[0].basic_rate='6000 9000 12000 18000 24000 36000 48000 54000'
	uci add_list wireless.@wifi-device[0].supported_rates='6000 9000 12000 18000 24000 36000 48000 54000'
 fi

 #txpower in dBm without unit
 test -n "$(uci -q get ddmesh.network.wifi_txpower)" && uci set wireless.@wifi-device[0].txpower="$(uci get ddmesh.network.wifi_txpower)"
 test -n "$(uci -q get ddmesh.network.wifi_diversity)" && uci set wireless.@wifi-device[0].diversity="$(uci get ddmesh.network.wifi_diversity)"
 test -n "$(uci -q get ddmesh.network.wifi_rxantenna)" && uci set wireless.@wifi-device[0].rxantenna="$(uci get ddmesh.network.wifi_rxantenna)"
 test -n "$(uci -q get ddmesh.network.wifi_txantenna)" && uci set wireless.@wifi-device[0].txantenna="$(uci get ddmesh.network.wifi_txantenna)"

# wird auf HT20 gesetzt oder bei usbsticks auf nix, wenn kein support da ist.
# falsche werte sorgen fuer nicht funktionieren von wifi
 #test -z "$(uci -q get ddmesh.network.wifi_htmode)" && uci set ddmesh.network.wifi_htmode="HT20"
 #uci set wireless.@wifi-device[0].htmode="$(uci get ddmesh.network.wifi_htmode)"

 #delete all other interfaces if any
 while uci delete wireless.@wifi-iface[0]; do echo ok; done

 test -z "$(uci -q get wireless.@wifi-iface[0])" && uci add wireless wifi-iface
 uci set wireless.@wifi-iface[0].device='radio0'
 uci set wireless.@wifi-iface[0].network='wifi'
 uci set wireless.@wifi-iface[0].mode='adhoc'
 uci set wireless.@wifi-iface[0].bssid="$(uci get credentials.wifi.bssid)"
 uci set wireless.@wifi-iface[0].encryption='none'
 test "$(uci -q get ddmesh.network.wifi_slow_rates)" != "1" && uci set wireless.@wifi-iface[0].mcast_rate='6000'

 essid="$(uci -q get ddmesh.network.essid_adhoc)"
 essid="${essid:-Freifunk Mesh-Net}"
 uci set wireless.@wifi-iface[0].ssid="${essid:0:32}"

 #check if usb stick is used. mostly do not support AP beside Adhoc
 if [ -z "$(uci get wireless.@wifi-device[0].path | grep '/usb')" ]; then
	test -z "$(uci -q get wireless.@wifi-iface[1])" && uci add wireless wifi-iface
	uci set wireless.@wifi-iface[1].device='radio0'
	uci set wireless.@wifi-iface[1].network='wifi2'
	uci set wireless.@wifi-iface[1].mode='ap'
	uci set wireless.@wifi-iface[1].encryption='none'

	isolate="$(uci -q get ddmesh.network.wifi2_isolate)"
	isolate="${isolate:-1}" #default isolate
	uci set wireless.@wifi-iface[1].isolate="$isolate"

	#uci set wireless.@wifi-iface[2].wpa_disable_eapol_key_retries='1'
	#uci set wireless.@wifi-iface[2].tdls_prohibit='1'
	#uci set wireless.@wifi-iface[1].ieee80211w='1'
	

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
 	test "$(uci -q get ddmesh.network.wifi_slow_rates)" != "1" && uci set wireless.@wifi-iface[1].mcast_rate='6000'

	# add encrypted access point
	 if [ "$(uci -q get ddmesh.network.wifi3_enabled)" = "1" -a -n "$(uci -q get credentials.wifi.private_ssid)" -a -n "$(uci -q get credentials.wifi.private_key)" ]; then
		test -z "$(uci -q get wireless.@wifi-iface[2])" && uci add wireless wifi-iface
		uci set wireless.@wifi-iface[2].device='radio0'
		uci set wireless.@wifi-iface[2].network="$(uci -q get ddmesh.network.wifi3_network)"
		uci set wireless.@wifi-iface[2].mode='ap'
		if [ "$(uci -q get ddmesh.network.wifi3_security_open)" = "1" ]; then
			uci set wireless.@wifi-iface[2].encryption='none'
		else
			uci set wireless.@wifi-iface[2].encryption='psk2'
			uci set wireless.@wifi-iface[2].key="$(uci -q get credentials.wifi.private_key)"
		fi
		uci set wireless.@wifi-iface[2].isolate='0'
		ssid="$(uci -q get credentials.wifi.private_ssid)"
		uci set wireless.@wifi-iface[2].ssid="${ssid:0:32}"
		#uci set wireless.@wifi-iface[2].wpa_disable_eapol_key_retries='1'
		#uci set wireless.@wifi-iface[2].tdls_prohibit='1'
		#uci set wireless.@wifi-iface[2].ieee80211w='1'
	fi
 fi

 # only wireless should be commited. if overlay-md5sum changes we have
 # an error
 uci_commit.sh
}

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

 #############################################################################
 # setup backbone clients
 #############################################################################
 for i in $(seq 0 4)
 do
	host="$(uci -q get ddmesh.@backbone_client[$i].host)"
	fastd_pubkey="$(uci -q get ddmesh.@backbone_client[$i].public_key)"
	if [ -n "$host" -a -z "$fastd_pubkey" ]; then
		uci -q del ddmesh.@backbone_client[$i].password
		uci -q set ddmesh.@backbone_client[$i].port="5002"
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

 #############################################################################
 # setup lan
 # Interface for "lan" is initally  set in /etc/config/network
 # tbb is a bridge used by mesh-on-lan
 #############################################################################
 uci set network.lan.stp=1
 uci set network.lan.bridge_empty=1

 #wan as bridge for mesh_on_wan support
 test -n "$(uci -q get network.wan)" && {
	uci set network.wan.type='bridge'
 	uci set network.wan.stp=1
	uci set network.wan.bridge_empty=1
 }

 test -z "$(uci -q get network.mesh_lan)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='mesh_lan'
 }
 uci set network.mesh_lan.bridge_empty=1
 uci set network.mesh_lan.ipaddr="$_ddmesh_nonprimary_ip"
 uci set network.mesh_lan.netmask="$_ddmesh_netmask"
 uci set network.mesh_lan.broadcast="$_ddmesh_broadcast"
 uci set network.mesh_lan.proto='static'
 uci set network.mesh_lan.type='bridge'
 uci set network.mesh_lan.stp=1

 test -z "$(uci -q get network.mesh_wan)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='mesh_wan'
 }
 uci set network.mesh_wan.bridge_empty=1
 uci set network.mesh_wan.ipaddr="$_ddmesh_nonprimary_ip"
 uci set network.mesh_wan.netmask="$_ddmesh_netmask"
 uci set network.mesh_wan.broadcast="$_ddmesh_broadcast"
 uci set network.mesh_wan.proto='static'
 uci set network.mesh_wan.type='bridge'
 uci set network.mesh_wan.stp=1

 #############################################################################
 # setup wifi
 # Interfaces for "wifi" and "wifi2" are created by wireless subsystem and
 # assigned to this networks
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
 uci set network.wifi2.ipaddr="$_ddmesh_wifi2ip"
 uci set network.wifi2.netmask="$_ddmesh_wifi2netmask"
 uci set network.wifi2.broadcast="$_ddmesh_wifi2broadcast"
 uci set network.wifi2.proto='static'
 uci set network.wifi2.type='bridge'
 uci set network.wifi2.stp=1
 #don't store dns for wifi2 to avoid adding it to resolv.conf

# setup_wireless

 #############################################################################
 # setup tbb_fastd network assigned to a firewall zone (mesh) for a interface that is not controlled
 # by openwrt. Bringing up tbb+ failes, but firewall rules are created anyway
 # got this information by testing, because openwrt feature to add non-controlled
 # interfaces (via netifd) was not working.
 #############################################################################
 test -z "$(uci -q get network.tbb_fastd)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='tbb_fastd'
 }
 uci set network.tbb_fastd.ifname='tbb_fastd'
 uci set network.tbb_fastd.proto='static'

 #bmxd bat zone, to a masq rules to firewall
 test -z "$(uci -q get network.bat)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='bat'
 }
 uci set network.bat.ifname="bat+"
 uci set network.bat.proto='static'

 #openvpn zone, to a masq rules to firewall
 test -z "$(uci -q get network.vpn)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='vpn'
 }
 uci set network.vpn.ifname="vpn+"
 uci set network.vpn.proto='static'

 #######################################################################
 # add other interfaces to system but do not create firewall rules for them.
 # this allows to request all interfaces via ddmesh-utils-network-info.sh
 # Interfaces "priv" and "tbb_fastd" are created by fastd
 #
 #######################################################################

 #privnet zone: it is bridged to br-lan (see /etc/fastd/privnet-cmd.sh)
 test -z "$(uci -q get network.privnet)" && {
 	uci add network interface
 	uci rename network.@interface[-1]='privnet'
 }
 uci set network.privnet.ifname="priv"
 uci set network.privnet.proto='static'


 #############################################################################
 # setup firewall
 #############################################################################

 eval $(ipcalc.sh $(uci get network.lan.ipaddr) $(uci get network.lan.netmask))
 lan_net=$NETWORK
 lan_pre=$PREFIX

 # add source net to zone to avoid fake source ip attacks
 # except for lan and wan, to allow internet ip going to gw
 # if bmxd one-way-tunnel is used, we must accept inet
 uci delete firewall.zone_wifi2.subnet
 uci add_list firewall.zone_wifi2.subnet="$_ddmesh_wifi2net"

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
 uci -q del firewall.meshssh
 test "$(uci -q get ddmesh.system.meshssh)" = "1" && {
 	uci add firewall rule
 	uci rename firewall.@rule[-1]='meshssh'
 	uci set firewall.@rule[-1].name="Allow-mesh-ssh"
	uci set firewall.@rule[-1].src="mesh"
	uci set firewall.@rule[-1].proto="tcp"
	uci set firewall.@rule[-1].dest_port="22"
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }
 uci -q del firewall.wifi2ssh
 test "$(uci -q get ddmesh.system.meshssh)" = "1" && {
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
	uci set firewall.@rule[-1].target="ACCEPT"
#	uci set firewall.@rule[-1].family="ipv4"
 }


 /usr/lib/ddmesh/ddmesh-dnsmasq.sh configure

}

# uci needs valid symlinks
config_create_symlink_files()
{
	mkdir -p /var/etc/config

	#ensure we use temporarily created config after sysupgrade has restored config as file instead of symlink   
	[ -L /etc/config/uhttpd ] || ( rm -f /etc/config/uhttpd && ln -s /var/etc/config/uhttpd /etc/config/uhttpd )
	touch /var/etc/config/uhttpd

	#ensure we use temporarily created config after sysupgrade has restored config as file instead of symlink   
	[ -L /etc/config/wshaper ] || ( rm -f /etc/config/wshaper && ln -s /var/etc/config/wshaper /etc/config/wshaper )
	touch /var/etc/config/wshaper

}

config_temp_configs() {
# dnsmasq
	# create directory to calm dnsmasq
	mkdir -p /tmp/hosts
	mkdir -p /var/etc

	setup_wireless
	
	cat<<EOM >/var/etc/dnsmasq.hosts
127.0.0.1 localhost
$_ddmesh_wifi2ip hotspot
EOM


# generate temporary configurations
	mkdir -p /var/etc/config

	# update /etc/opkg.conf
	eval $(cat /etc/openwrt_release)
	version="$(cat /etc/version)"
	platform="$DISTRIB_TARGET"
	url="$(uci -q get credentials.url.opkg)"
	cat <<EOM >/tmp/opkg.conf
src/gz ddmesh $url/$version/$platform/packages
dest root /
dest ram /tmp
lists_dir ext /var/opkg-lists
#option overlay_root /overlay
EOM

cat <<EOM >/var/etc/config/uhttpd
#generated/overwritten by $0
config uhttpd main
	list listen_http	0.0.0.0:80
	list listen_http	0.0.0.0:81
	list listen_https	0.0.0.0:443
	option home		/www
	option rfc1918_filter 1
	option max_requests	20	
	option max_connections	100
	option tcp_keepalive    1
	option http_keepalive   60
	option cert		/etc/uhttpd.crt
	option key		/etc/uhttpd.key
	list interpreter	".cgi=/bin/sh"
	list interpreter	".json=/bin/sh"
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
	option script_timeout	600
	option network_timeout	600
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
	option commonname	'$(uci -q get ddmesh.system.community)'
	option node		'Node $(uci -q get ddmesh.system.node)'
EOM

#traffic shaping

cat <<EOM >/var/etc/config/wshaper
config 'wshaper' 'settings'
  option network "$(uci get ddmesh.network.speed_network)"
  option downlink "$(uci get ddmesh.network.speed_down)"
  option uplink "$(uci get ddmesh.network.speed_up)"
EOM

 #setup cron.d
mkdir -p /var/etc/crontabs
m=$(( $_ddmesh_node % 60))
cat<<EOM > /var/etc/crontabs/root
#every 1 minutes batman run check
*/1 * * * *  /usr/lib/ddmesh/ddmesh-bmxd.sh check >/dev/null 2>/dev/null

#every 3 minutes start (after killing)
*/3 * * * *  /usr/lib/ddmesh/ddmesh-gateway-check.sh >/dev/null 2>/dev/null &

#every 2h
$m */2 * * *  /usr/lib/ddmesh/ddmesh-register-node.sh >/dev/null 2>/dev/null

#forced user disconnection
*/5 * * * *  /usr/lib/ddmesh/ddmesh-splash.sh autodisconnect >/dev/null 2>/dev/null

#watchdog
* * * * *  /usr/lib/ddmesh/ddmesh-watchdog.sh >/dev/null 2>/dev/null

#sysinfo
* * * * * /usr/lib/ddmesh/ddmesh-sysinfo.sh >/dev/null 2>/dev/null

#internet
*/15 * * * * /usr/lib/ddmesh/freifunk-gateway-info.sh >/dev/null 2>/dev/null

EOM

if [ "$(uci -q get ddmesh.system.nightly_reboot)" = "1" ];then
cat<<EOM >> /var/etc/crontabs/root
0 4 * * *  /sbin/reboot
EOM
fi

# ALWAYS update check AFTER nightly reboot
if [ "$(uci -q get ddmesh.system.firmware_autoupdate)" = "1" ];then
cat<<EOM >> /var/etc/crontabs/root
$m 5 * * *  /usr/lib/ddmesh/ddmesh-firmware-autoupdate.sh run nightly >/dev/null 2>/dev/null
EOM
fi

if [ "$(uci -q get ddmesh.network.bypass)" = '1' ]; then
cat<<EOM >> /var/etc/crontabs/root
$m */12 * * *  /usr/lib/ddmesh/ddmesh-routing.sh bypass >/dev/null 2>/dev/null
EOM
fi

}

setup_mesh_on_wire()
{
 mesh_on_lan="$(uci -q get ddmesh.network.mesh_on_lan)"
 mesh_on_wan="$(uci -q get ddmesh.network.mesh_on_wan)"

 # give user time to change configs via lan/wan IP
 if [ "$mesh_on_lan" = "1" -o "$mesh_on_wan" = "1" ]; then
	sleep 300

 	# mesh-on-lan: move phys ethernet to br-mesh_lan/br-mesh_wan
	 lan_phy="$(uci -q get network.lan.ifname)"
	 wan_phy="$(uci -q get network.wan.ifname)"

	 if [ "$mesh_on_lan" = "1" ]; then
 		brctl delif $lan_ifname $lan_phy
	 	brctl addif $mesh_lan_ifname $lan_phy
	 fi

	 if [ "$mesh_on_wan" = "1" -a "$wan_iface_present" = "1" ]; then
 		brctl delif $wan_ifname $wan_phy
	 	brctl addif $mesh_wan_ifname $wan_phy
	 fi
 fi
}

wait_for_wifi()
{
	logger -s -t "$LOGGER_TAG" "check  for WIFI"
	#check if usb stick is used. mostly do not support AP beside Adhoc
	if [ -n "$(uci -q get wireless.@wifi-device[0].path | grep '/usb')" ]; then
		only_adhoc=1
	fi

	c=0
	max=30
	while [ $c -lt $max ]
	do
		# use /tmp/state  instead of ubus because up-state is wrong.
		# /tmp/state is never set back (but this can be ignored here. if needed use /etc/hotplug.d/iface)
		wifi_up="$(uci -q -P /tmp/state get network.wifi.up)"
		wifi2_up="$(uci -q -P /tmp/state get network.wifi2.up)"

		logger -s -t "$LOGGER_TAG" "Wait for WIFI up: $c/$max (only_adhoc=$only_adhoc, wifi:$wifi_up, wifi2:$wifi_up)"

		if [ -n "$only_adhoc" ]; then
			wifi_is_up="$wifi_up"
		else
			if [ "$wifi_up" = 1 -a "$wifi2_up" = 1 ]; then
				wifi_is_up=1
			fi
		fi
		if [ "$wifi_is_up" = 1 ]; then
			logger -s -t "$LOGGER_TAG" "WIFI is up - continue"
			/usr/lib/ddmesh/ddmesh-led.sh wifi alive
			break;
		fi
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

config_create_symlink_files

case "$boot_step" in
	1) # initial boot step
		/usr/lib/ddmesh/ddmesh-led.sh status boot1
		logger -s -t "$LOGGER_TAG" "boot step 1"
		config_boot_step1
		uci set ddmesh.boot.boot_step=2
		uci_commit.sh
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
		if [ -z "$node" ]; then                                                     
			logger -t $LOGGER_TAG "ERROR: no node number"
                else 
			eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)

			logger -t $LOGGER_TAG "run ddmesh upgrade"
			/usr/lib/ddmesh/ddmesh-upgrade.sh

			config_update

			upgrade_running=$(uci -q get ddmesh.boot.upgrade_running)
			uci set ddmesh.boot.boot_step=3
			uci set ddmesh.boot.nightly_upgrade_running=0
			uci set ddmesh.boot.upgrade_running=0

			uci_commit.sh

			# after uci commit and only when fw was upgraded
			if [ "$upgrade_running" = "1" ]; then
				logger -t $LOGGER_TAG "firmware upgrade finished"

				/usr/lib/ddmesh/ddmesh-overlay-md5sum.sh write
			fi

			logger -s -t "$LOGGER_TAG" "reboot boot step 2"

			sleep 5 # no sync, it might modify flash
			reboot

			#stop boot process
			exit 1
		fi
		;;
	3) # temp config
		/usr/lib/ddmesh/ddmesh-led.sh status boot3
		logger -s -t "$LOGGER_TAG" "boot step 3"
		node=$(uci get ddmesh.system.node)
		if [ -z "$node" ]; then                                                     
			logger -t $LOGGER_TAG "ERROR: no node number"
                else 
			eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)
			if [ "$1"  != "firewall" ]; then
				config_temp_configs
				logger -s -t "$LOGGER_TAG" "start wifi"
				wifi &
				#restart fw, because sometimes fw was not setup correctly by openwrt
				wait_for_wifi
				fw3 restart
				/usr/lib/ddmesh/ddmesh-firewall-addons.sh once
				/etc/init.d/uhttpd restart
				/etc/init.d/wshaper restart
				# cron job is started from ddmesh-init.sh after bmxd
			fi
			/usr/lib/ddmesh/ddmesh-firewall-addons.sh post
			/usr/lib/ddmesh/ddmesh-firewall-addons.sh update
			# delay start mesh_on_wire, to allow access routeri config via lan/wan ip
			setup_mesh_on_wire &
		fi
esac
#continue boot-process
exit 0

