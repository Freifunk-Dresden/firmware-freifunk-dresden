#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

#Freifunk Router Initial-Setup
#
# boot sequence for  flash with factory reset:
# boot1	-> reboot after flash, openwrt creates jffs2 -> reboot
# boot2	-> openwrt creates initial configs
#	-> start ddmesh-bootconfig.sh:
#		no boot_step or boot_step=1 -> create /etc/config/ddmesh,sshkey,regkey,temp node
#		-> reboot (boot_step 2)
# boot3		boot_step 2 -> update persistent configs from /etc/config/ddmesh
#		-> reboot (boot_step 3)
#		boot_step 3 -> update temp-configs
#		-> firmware is up (running temp node number)
# boot4 -> later reboot after registration with new node number

#use alias to be silent
#alias uci='uci -q'

LOGGER_TAG="ddmesh-boot"

. /lib/functions.sh

/usr/lib/ddmesh/ddmesh-utils-network-info.sh update
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)

config_boot_step1() {

cat <<EOM >/etc/config/overlay
config overlay 'data'
	option	md5sum '0'
EOM

cat <<EOM >/etc/config/ddmesh
# mesh_network_id % community name
config communities 'communities'
	list	community '0%Dresden'
	list	community '1000%Dresden'
	list	community '1001%Dresden NO'
	list	community '1002%Dresden NW'
	list	community '1003%Dresden SO'
	list	community '1004%Dresden SW'
	list	community '1020%Pirna'
	list	community '1021%OL'
	list	community '2000%Leipzig'

config system 'system'
	option	mesh_network_id '0'
	option	community 'Dresden'
#	option 	node 0
	option	group_id 0
	option 	tmp_min_node 900
	option	tmp_max_node 999
#	option 	register_key ''
	option	announce_gateway 0
	option  wanssh 1
	option  wanhttp 1
	option  wanhttps 1
	option  wanicmp 1
	option  wansetup 1
	option  meshssh 1
	option  meshsetup 1
	option	disable_splash 1
	option	firmware_autoupdate 1
	option	fwupdate_always_allow_testing 0
	option	email_notification 0
	option	node_type 'node'
	list	node_types 'node'
	list	node_types 'mobile'
	list	node_types 'server'
	option	nightly_reboot 0
	option	ignore_factory_reset_button 0
	option	mesh_sleep 1

config boot 'boot'
	option boot_step 0
	option upgrade_version $(cat /etc/version)
	option nightly_upgrade_running 0
	option upgrade_running 0

# on,off,status
config led 'led'
	option wwan ''
	option status ''
	option wifi ''

config log 'log'
	option tasks 0

config gps 'gps'
	option 	latitude '0'
	option  longitude '0'
	option  altitude '0'

config geoloc 'geoloc'
	list	ignore_macs ''

config contact 'contact'
	option	name ''
	option	email ''
	option	location ''
	option	note ''

config network 'network'
	option	client_disconnect_timeout 0
	option	dhcp_lan_offset 100
	option	dhcp_lan_limit 0
	option	dhcp_lan_lease '12h'
	option	essid_adhoc 'Freifunk-Mesh-Net'
#	option	essid_ap '' #custom essid
	option	wifi_country 'DE'
	option	wifi_channel 13
	option	wifi_txpower 18
	option	disable_wifi_5g 0
	option	wifi_channel_5g 44
	option	wifi_txpower_5g 18
	option	wifi_indoor_5g 0
# multiple of 20,40,80 Mhz !!!
	option	wifi_channels_5g_outdoor '52-144'
	option	wifi_ch_5g_outdoor_min 52
	option	wifi_ch_5g_outdoor_max 144
	option	wifi_slow_rates 0
	option	wifi2_dhcplease '5m'
	option	wifi2_isolate '1'
	option	wifi2_roaming_enabled '1'
	option	mesh_mode 'mesh' #adhoc,mesh,adhoc+mesh
	option	lan_local_internet '0'
	option	internal_dns1 '10.200.0.4'
	option	internal_dns2 '10.200.0.16'
	option	force_ether_100mbit 0

	option	mesh_mtu 1200
	option	mesh_on_lan 0
	option	mesh_on_wan 0
	option	mesh_on_vlan 0
	option	mesh_vlan_id 9
	option	wifi3_2g_enabled 0
	option	wifi3_2g_network 'lan'
	option	wifi3_2g_security 1
	option	wifi3_5g_enabled 0
	option	wifi3_5g_network 'lan'
	option	wifi3_5g_security 1
	option	wwan_apn 'internet'
	option	wwan_pincode ''
	option	wwan_syslog 0
	option	fallback_dns ''
	option	lan_ipaddr '192.168.222.1'
	option	lan_netmask '255.255.255.0'
	option	lan_gateway ''
	option	lan_dns ''
	option	lan_proto 'static'
	option	wan_proto 'dhcp'
	#option	wan_ipaddr
	#option	wan_netmask
	#option	wan_gateway
	#option	wan_dns

config bmxd 'bmxd'
	option routing_class	3
	option gateway_class	'1024/1024'
	option prefered_gateway	''
	option only_community_gateways '1'


config backbone 'backbone'
	option  fastd_port		'5002'
	option  default_fastd_port	'5002'
	option  default_wg_port	'5003'
	option	number_of_clients	5

#config backbone_accept
#	option	key			''
#	option	comment			''

config backbone_client
	option 	host			'vpn7.freifunk-dresden.de'
	option	type			'fastd'
	option	disabled		'0'
	option 	port			'5002'
	option	public_key 		''

config backbone_client
	option 	host			'vpn6.freifunk-dresden.de'
	option	type			'fastd'
	option	disabled		'0'
	option 	port			'5002'
	option	public_key 		''

config backbone_client
	option 	host			'vpn1.freifunk-dresden.de'
	option	type			'fastd'
	option	disabled		'0'
	option 	port			'5002'
	option	public_key 		''

config backbone_client
	option 	host			'vpn14.freifunk-dresden.de'
	option	type			'fastd'
	option	disabled		'0'
	option 	port			'5002'
	option	public_key 		''

config privnet 'privnet'
	option  fastd_port		'4000'
	option  default_fastd_port	'4000'
	option	number_of_clients	5

#config privnet_accept
#	option	key			''
#	option	comment			''

#config privnet_client
#	option	host			''
#	option	port			''
#	option	public_key		''

EOM

	#almost disable crond logging (only errors)
	uci set system.@system[0].cronloglevel='9'

	#  initial correct ntp
	uci -q delete system.ntp.server
	uci -q add_list system.ntp.server=0.de.pool.ntp.org
	uci -q add_list system.ntp.server=1.de.pool.ntp.org
	uci -q add_list system.ntp.server=2.de.pool.ntp.org
	uci -q add_list system.ntp.server=3.de.pool.ntp.org

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

	# update uhttpd certificates in case user has changed community or node
	commonname="Freifunk Dresden"
	organisation="$(uci get ddmesh.system.community)"
	node="Node $(uci -q get ddmesh.system.node)"

	if [ "${commonname}" != "$(uci -q get uhttpd.px5g.commonname)" -o "${organisation}" != "$(uci -q get uhttpd.px5g.organisation)" -o "${node}" != "$(uci -q get uhttpd.px5g.node)" ]; then
		uci set uhttpd.px5g.commonname="${commonname}"
		uci set uhttpd.px5g.organisation="${organisation}"
		uci set uhttpd.px5g.node="${node}"
		rm -f /etc/uhttpd.key
		rm -f /etc/uhttpd.crt
		# restart needed to generate certificates in boot_step 2
		/etc/init.d/uhttpd restart
	fi

	#############################################################################
	# setup backbone clients
	#############################################################################
	for i in $(seq 0 4)
	do
		disabled="$(uci -q get ddmesh.@backbone_client[$i].disabled)"
		if [ "$disabled" != "1" ]; then
			type="$(uci -q get ddmesh.@backbone_client[$i].type)"
			host="$(uci -q get ddmesh.@backbone_client[$i].host)"
			port="$(uci -q get ddmesh.@backbone_client[$i].port)"
			pubkey="$(uci -q get ddmesh.@backbone_client[$i].public_key)"
			logger -s -t "$LOGGER_TAG" "update backbone {$type, $host, $port, $pubkey}"
			case "$type" in
			 fastd)
				if [ -n "$host" -a -z "$pubkey" ]; then
					#lookup key
					for k in $(seq 1 30)
					do
						kk=$(($k - 1))
						h=$(uci -q get credentials.@backbone[$kk].host)
						if [ "$h" = "$host" ]; then
							uci set ddmesh.@backbone_client[$i].public_key="$(uci get credentials.@backbone[$kk].key)"
							break;
						fi
					done
				fi
			 ;;
			esac
		fi
	done



	#############################################################################
	# setup firewall
	#############################################################################

	eval $(ipcalc.sh $(uci get ddmesh.network.lan_ipaddr) $(uci get ddmesh.network.lan_netmask))
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

config_temp_configs() {
	# create directory to calm dnsmasq
	mkdir -p /tmp/hosts
	mkdir -p /var/etc

	# create temporary config dir (use for storing temp configs)
	mkdir -p /var/etc/tmp_config

	# uci -c option mixes up /etc/config/... with /var/etc/config...
	# result: options are stored uncontrolled at wrong locations.
	# -> NEVER use this option

	cat<<EOM >/var/etc/dnsmasq.hosts
127.0.0.1 localhost
$_ddmesh_wifi2ip hotspot
EOM

# setup cron.d
mkdir -p /var/etc/crontabs
# mod 50 avoids wrap when adding 5min (nightly_min)
reg_min=$(( $_ddmesh_node % 50 ))
nightly_min=$((reg_min + 5))
nightly_hour="$(uci -q get ddmesh.system.maintenance_time)"
nightly_hour="${nightly_hour:=4}"

cat<<EOM > /var/etc/crontabs/root
* * * * * /usr/lib/ddmesh/ddmesh-tasks.sh watchdog
* */6 * * * /usr/lib/ddmesh/ddmesh-backbone-regwg.sh refresh >/dev/null 2>/dev/null
${reg_min} */1 * * * /usr/lib/ddmesh/ddmesh-register-node.sh >/dev/null 2>/dev/null
${nightly_min} ${nightly_hour} * * *  [ "$(uci -q get ddmesh.system.firmware_autoupdate)" = "1" ] && /usr/lib/ddmesh/ddmesh-firmware-autoupdate.sh run nightly >/dev/null 2>/dev/null || ([ "$(uci -q get ddmesh.system.nightly_reboot)" = "1" ] && /sbin/reboot)
EOM

# set eth ifaces to 100 mbit wehn selected
if [ -n "$(which ethtool)" -a "$(uci -q get ddmesh.network.force_ether_100mbit)" = "1" ]; then
for ifname in /sys/class/net/*
do
	ifname=$(basename $ifname)
	# only consider "external" interfaces (assuming those are lan ports)
	if [ -n "$(ethtool $ifname | grep -i 'Transceiver:.*external')" ]; then
		logger -s -t "$LOGGER_TAG" "set speed for $ifname to 100Mbit/s"
		ethtool -s $ifname speed 100 duplex full
	fi
done
fi

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
		if [ -z "$node" ]; then
			logger -s -t $LOGGER_TAG "ERROR: no node number"
		else
			eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)

			logger -s -t $LOGGER_TAG "run ddmesh upgrade"
			/usr/lib/ddmesh/ddmesh-upgrade.sh

			logger -s -t "$LOGGER_TAG" "update config"
			config_update

			# regenerate network/wireless config after firmware update or
			# config update.
			logger -s -t "$LOGGER_TAG" "update network"
			/usr/lib/ddmesh/ddmesh-setup-network.sh

			logger -s -t "$LOGGER_TAG" "update wifi"
			# hotplug event ieee80211 is not reliable before rebooting
			/usr/lib/ddmesh/ddmesh-setup-wifi.sh

			upgrade_running=$(uci -q get ddmesh.boot.upgrade_running)
			uci set ddmesh.boot.boot_step=3
			uci set ddmesh.boot.nightly_upgrade_running=0
			uci set ddmesh.boot.upgrade_running=0

			uci commit
			sync

			# after uci commit and only when fw was upgraded
			if [ "$upgrade_running" = "1" ]; then
				logger -t $LOGGER_TAG "firmware upgrade finished"
				# to find changes in directories easier
				find /overlay/upper -exec touch {} \;
				/usr/lib/ddmesh/ddmesh-overlay-md5sum.sh write
			fi

			logger -s -t "$LOGGER_TAG" "reboot boot step 2"

			sleep 5
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

			config_temp_configs
			# cron job is started from ddmesh-init.sh after bmxd

			# delay start mesh_on_wire, to allow access router config via lan/wan ip
			/usr/lib/ddmesh/ddmesh-setup-network.sh setup_mesh_on_wire &
		fi
esac
#continue boot-process
exit 0
