#!/bin/sh

OUTPUT=/tmp/sysinfo.json.tmp
FINAL_OUTPUT=/tmp/sysinfo.json

#empty
> $OUTPUT

BMXD_DB_PATH=/var/lib/ddmesh/bmxd
eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
test -z "$_ddmesh_node" && exit

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)
vpn=vpn0
gwt=bat0

eval $(cat /etc/built_info | sed 's#:\(.*\)$#="\1"#')
eval $(cat /etc/openwrt_release)
tunnel_info="$(/usr/lib/ddmesh/freifunk-gateway-info.sh cache)"
gps_lat=$(uci -q get ddmesh.gps.latitude)
gps_lat=${gps_lat:=0}
gps_lon=$(uci -q get ddmesh.gps.longitude)
gps_lon=${gps_lon:=0}
gps_alt=$(uci -q get ddmesh.gps.altitude)
gps_alt=${gps_alt:=0}
avail_flash_size=$(df -k -h /overlay | sed -n '2,1{s# \+# #g; s#[^ ]\+ [^ ]\+ [^ ]\+ \([^ ]\+\) .*#\1#;p}')

if [ "$(uci get ddmesh.system.disable_splash)" = "1" ]; then
	splash=0
else
	splash=1
fi

if [ "$(uci get ddmesh.system.email_notification)" = "1" ]; then
	email_notification=1
else
	email_notification=0
fi

case "$(uci -q get ddmesh.system.node_type)" in
	server)	node_type="server" ;;
	node)	node_type="node" ;;
	mobile)	node_type="mobile" ;;
	*) node_type="node";;
esac

wifi_txpower="-1"
test "$wifi_iface_present" = "1" && wifi_txpower="$(iw $wifi_ifname info | awk '/txpower/{print $2}')"

device_model="$(cat /var/sysinfo/model 2>/dev/null | sed 's#[ ]\+$##')"
test -z "$device_model" && device_model="$(cat /proc/cpuinfo | grep 'model name' | cut -d':' -f2)"

cpu_info="$(cat /proc/cpuinfo | sed -n '/system type/s#.*:[ 	]*##p')"
test -z "$cpu_info" && cpu_info="$(cat /proc/cpuinfo | grep 'model name' | cut -d':' -f2)"

cat << EOM >> $OUTPUT
{
 "version":"13",
 "timestamp":"$(date +'%s')",
 "data":{

EOM

#node info
cat << EOM >> $OUTPUT
		"firmware":{
			"version":"$(cat /etc/version)",
			"DISTRIB_ID":"$DISTRIB_ID",
			"DISTRIB_RELEASE":"$DISTRIB_RELEASE",
			"DISTRIB_REVISION":"$DISTRIB_REVISION",
			"DISTRIB_CODENAME":"$DISTRIB_CODENAME",
			"DISTRIB_TARGET":"$DISTRIB_TARGET",
			"DISTRIB_DESCRIPTION":"$DISTRIB_DESCRIPTION",
			"git-lede-ref":"$git_lede_ref",
			"git-lede-branch":"$git_lede_branch",
			"git-ddmesh-ref":"$git_ddmesh_ref",
			"git-ddmesh-branch":"$git_ddmesh_branch"
		},
		"system":{
			"uptime":"$(cat /proc/uptime)",
			"uname":"$(uname -a)",
			"nameserver": [
$(cat /tmp/resolv.conf.auto| sed -n '/nameserver[ 	]\+10\.200/{s#[ 	]*nameserver[ 	]*\(.*\)#\t\t\t\t"\1",#;p}' | sed '$s#,[ 	]*$##')
			],
			"date":"$(date)",
			"board":"$(cat /var/sysinfo/board_name 2>/dev/null)",
			"model":"$device_model",
			"model2":"$(cat /proc/diag/model 2>/dev/null)",
			"cpuinfo":"$cpu_info",
			"bmxd" : "$(cat $BMXD_DB_PATH/status)",
			"essid":"$(uci get wireless.@wifi-iface[1].ssid)",
			"node_type":"$node_type",
			"splash":$splash,
			"email_notification":$email_notification,
			"available_flash_size":"$avail_flash_size",
			"bmxd_restart_counter":0,
			"wifi_txpower":"$wifi_txpower"
		},
		"opkg":{
$(/usr/lib/ddmesh/ddmesh-installed-ipkg.sh json '		')
		},
		"common":{
			"city":"$(uci get ddmesh.system.community | awk '{print $2}')",
			"node":"$_ddmesh_node",
			"domain":"$_ddmesh_domain",
			"ip":"$_ddmesh_ip",
			"fastd_pubkey":"$(/usr/lib/ddmesh/ddmesh-backbone.sh get_public_key)",
			"network_id":"$(uci get ddmesh.network.mesh_network_id)"
		},
		"gps":{
			"latitude":$gps_lat,
			"longitude":$gps_lon,
			"altitude":$gps_alt
		},
		"contact":{
			"name":"$(uci -q get ddmesh.contact.name)",
			"location":"$(uci -q get ddmesh.contact.location)",
			"email":"$(uci -q get ddmesh.contact.email)",
			"note":"$(uci -q get ddmesh.contact.note)"
		},
EOM

cat<<EOM >> $OUTPUT
		"statistic" : {
			"accepted_user_count" : $(/usr/lib/ddmesh/ddmesh-splash.sh get_accepted_count),
			"dhcp_count" : $(/usr/lib/ddmesh/ddmesh-splash.sh get_dhcp_count),
			"dhcp_lease" : "$(grep 'dhcp-range=.*wifi2' /etc/dnsmasq.conf | cut -d',' -f4)",
EOM

			# firewall_rule_name:sysinfo_key_name
			for net in wan:wan wifi:adhoc wifi2:ap vpn:ovpn bat:gwt
			do
				first=${net%:*}
				second=${net#*:}
				rx=$(iptables -L statistic -xvn | awk '/statistic_'$first'_input/{print $2}')
				tx=$(iptables -L statistic -xvn | awk '/statistic_'$first'_output/{print $2}')
				[ -z "$rx" ] && rx=0
				[ -z "$tx" ] && tx=0
				echo "			\"traffic_$second\": \"$rx,$tx\"," >> $OUTPUT
			done
			# from /sys
			# iface:sysinfo_key
			for net in priv:privnet tbb-fastd:tbb_fastd br-meshwire:mesh_wire
			do
				first=${net%:*}
				second=${net#*:}
				if [ -f /sys/devices/virtual/net/$first/statistics/rx_bytes ]; then
					rx=$(cat /sys/devices/virtual/net/$first/statistics/rx_bytes)
					tx=$(cat /sys/devices/virtual/net/$first/statistics/tx_bytes)
				fi
				[ -z "$rx" ] && rx=0
				[ -z "$tx" ] && tx=0
				echo "			\"traffic_$second\": \"$rx,$tx\"," >> $OUTPUT
			done

cat<<EOM >> $OUTPUT
$(cat /proc/meminfo | sed -n '/^MemTotal\|^MemFree\|^Buffers\|^Cached/{s#\(.*\):[ 	]\+\([0-9]\+\)[ 	]*\(.*\)#\t\t\t\"meminfo_\1\" : \"\2\ \3\",#p}')
			"cpu_load" : "$(cat /proc/loadavg)",
			"cpu_stat" : "$(cat /proc/stat | sed -n '/^cpu[ 	]\+/{s# \+# #;p}')",
			"gateway_usage" : [
$(cat /var/statistic/gateway_usage | sed 's#\([^:]*\):\(.*\)#\t\t\t\t{"\1":"\2"},#' | sed '$s#,[ 	]*$##') ]
		},
EOM

#bmxd
#$(ip route list table bat_route | sed 's#\(.*\)#			"\1",#; $s#,[ 	]*$##') ],
cat<<EOM >> $OUTPUT
		"bmxd":{
			"links":[
EOM
				cat $BMXD_DB_PATH/links | awk '
					function getnode(ip) {
						split($0,a,".");
						f1=a[3]*255;f2=a[4]-1;
						return f1+f2;
					}
					{
						if(match($0,"^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]"))
						{
							printf("\t\t\t\t{\"node\":\"%d\", \"ip\":\"%s\", \"interface\":\"%s\",\"rtq\":\"%d\", \"rq\":\"%d\", \"tq\":\"%d\"}, \n",getnode($1),$3,$2,$4,$5,$6);
						}
					}
' | sed '$s#,[	 ]*$##' >>$OUTPUT

cat<<EOM >>$OUTPUT
			],
			"gateways":{
				"selected":"$(cat $BMXD_DB_PATH/gateways | sed -n 's#^[	 ]*=>[	 ]\+\([0-9.]\+\).*$#\1#p')",
				"preferred":"$(cat $BMXD_DB_PATH/gateways | sed -n '1,1s#^.*preferred gateway:[	 ]\+\([0-9.]\+\).*$#\1#p')",
				"gateways":[
$(cat $BMXD_DB_PATH/gateways | sed -n '
				/^[	 ]*$/d
				1,1d
				s#^[	 =>]*\([0-9.]\+\).*$#\t\t\t\t{"ip":"\1"},#p
				' | sed '$s#,[	 ]*$##') ]
			},
			"info":[
$(cat $BMXD_DB_PATH/info | sed 's#^[ 	]*\(.*\)$#\t\t\t\t"\1",#; $s#,[ 	]*$##') ]
		},
EOM
		if [ "$(uci -q get ddmesh.network.speed_enabled)" = "1" ]; then
			tc_enabled=1
		else
			tc_enabled=0
		fi
cat<<EOM >>$OUTPUT
		"traffic_shaping":{"enabled":$tc_enabled, "network":"$(uci -q get ddmesh.network.speed_network)", "incomming":"$(uci -q get ddmesh.network.speed_down)", "outgoing":"$(uci -q get ddmesh.network.speed_up)"},
		"internet_tunnel":$tunnel_info
EOM


# remove last comma
#$s#,[ 	]*$##

cat << EOM >> $OUTPUT
  }
}
EOM

mv $OUTPUT $FINAL_OUTPUT

