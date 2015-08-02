#!/bin/sh

echo 'Content-type: text/plain txt'
echo ''

BMXD_DB_PATH=/var/lib/ddmesh/bmxd
eval $(/usr/bin/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
test -z "$_ddmesh_node" && exit

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi)
wifi=$net_device
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi2)
wifi2=$net_device

vpn=vpn0

eval $(cat /etc/openwrt_release)
eval $(/usr/lib/ddmesh/freifunk-gateway-info.sh cache)

cat << EOM
{
 "version":"5",
 "timestamp":"$(date +'%s')",
 "data":{

EOM

#node info
cat << EOM
		"firmware":{
			"version":"$(cat /etc/version)",
			"DISTRIB_ID":"$DISTRIB_ID",
			"DISTRIB_RELEASE":"$DISTRIB_RELEASE",
			"DISTRIB_REVISION":"$DISTRIB_REVISION",
			"DISTRIB_CODENAME":"$DISTRIB_CODENAME",
			"DISTRIB_TARGET":"$DISTRIB_TARGET",
			"DISTRIB_DESCRIPTION":"$DISTRIB_DESCRIPTION"
		},
		"system":{
			"uptime":"$(uptime)",
			"uname":"$(uname -a)",
			"nameserver": [
$(cat /tmp/resolv.conf.auto| sed -n '/nameserver[ 	]\+10\.200/{s#[ 	]*nameserver[ 	]*\(.*\)#\t\t\t\t"\1",#;p}' | sed '$s#,##')
			],
			"date":"$(date)",
			"board":"$(cat /var/sysinfo/board_name)",
			"model":"$(cat /var/sysinfo/model)",
			"model2":"$(cat /proc/diag/model)",
			"cpuinfo":"$(cat /proc/cpuinfo | sed -n '/system type/s#.*:[ 	]*##p')",
			"bmxd" : "$(cat $BMXD_DB_PATH/status)"
		},
		"common":{
			"city":"$(uci get ddmesh.system.community | awk '{print $2}')",
			"node":"$_ddmesh_node",
			"domain":"$_ddmesh_domain",
			"ip":"$_ddmesh_ip"
		},
		"gps":{
			"latitude":"$(uci get ddmesh.gps.latitude)",
			"longitude":"$(uci get ddmesh.gps.longitude)",
			"altitude":"$(uci get ddmesh.gps.altitude)"
		},
		"contact":{
			"name":"$(uci get ddmesh.contact.name)",
			"location":"$(uci get ddmesh.contact.location)",
			"email":"$(uci get ddmesh.contact.email)",
			"note":"$(uci get ddmesh.contact.note)"
		},
EOM

cat<<EOM
		"statistic" : {
EOM
	dhcp_count="$(wc -l /var/dhcp.leases | cut -d' ' -f1)"
	if [ "$(uci get ddmesh.system.disable_splash)" = "1" ]; then
		accepted_user_count="$dhcp_count"
	else
		accepted_user_count="$(ls -l /tmp/dhcp.autodisconnect.db | wc -l )"
	fi
cat<<EOM
			"accepted_user_count" : "$accepted_user_count",
			"dhcp_count" : "$dhcp_count",
			"dhcp_lease" : "$(grep 'dhcp-range=wifi2' /etc/dnsmasq.conf | cut -d',' -f4)",
			"traffic_adhoc": "$(ifconfig $wifi | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
			"traffic_ap": "$(ifconfig $wifi2 | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
			"traffic_ovpn": "$(ifconfig $vpn | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
EOM
			for iface in $(ip link show | sed -n '/^[0-9]\+:/s#^[0-9]\+:[ ]\+\(.*\):.*$#\1#p' | sed "/vpn/d;/lo/d;/$wifi/d;/$wifi2/d")
			do
				echo "			\"traffic_$iface\": \"$(ifconfig $iface | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')\","
			done
cat<<EOM
$(cat /proc/meminfo | sed 's#\(.*\):[ 	]\+\([0-9]\+\)[ 	]*\(.*\)#\t\t\t\"meminfo_\1\" : \"\2\ \3\",#')
			"cpu_load" : "$(cat /proc/loadavg)",
			"cpu_stat" : "$(cat /proc/stat | sed -n '/^cpu[ 	]\+/{s# \+# #;p}')",
			"gateway_usage" : [
$(cat /var/statistic/gateway_usage | sed 's#\([^:]*\):\(.*\)#\t\t\t\t{"\1":"\2"},#' | sed '$s#,[ 	]*$##') ]
		},
EOM

#bmxd
#$(ip route list table bat_route | sed 's#\(.*\)#			"\1",#; $s#,[ 	]*$##') ],
cat<<EOM
		"bmxd":{
			"routing_tables":{
				"route":{
					"link":[
$(ip route list table bat_route | sed -n '/scope[ ]\+link/{s#^\([0-9./]\+\)[	 ]\+dev[	 ]\+\([^	 ]\+\).*#\t\t\t\t\t\t{"target":"\1","interface":"\2"},#;p}' | sed '$s#,[ 	]*$##') ],
		  			"global":[
$(ip route list table bat_route | sed  '/scope[ ]\+link/d;s#^\([0-9./]\+\)[	 ]\+via[	 ]\+\([0-9.]\+\)[	 ]\+dev[	 ]\+\([^	 ]\+\).*#\t\t\t\t\t\t{"target":"\1","via":"\2","interface":"\3"},#p' | sed '$s#,[ 	]*$##') ]
	  		},
			"hna":{
				"link":[
$(ip route list table bat_hna | sed -n '/scope[ ]\+link/{s#^\([0-9./]\+\)[	 ]\+dev[	 ]\+\([^	 ]\+\).*#\t\t\t\t{"target":"\1","interface":"\2"},#;p}' | sed '$s#,[ 	]*$##') ],
		  		"global":[
$(ip route list table bat_hna | sed -n '/scope[ ]\+link/d;s#^\([0-9./]\+\)[	 ]\+via[	 ]\+\([0-9.]\+\)[	 ]\+dev[	 ]\+\([^	 ]\+\).*#\t\t\t\t{"target":"\1","via":"\2","interface":"\3"},#p' | sed '$s#,[ 	]*$##') ]
				}
			},
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
  		"internet_tunnel":{
			"ipv4_address":"$iptest_address4",
			"ipv4_country":"$iptest_country4",
			"ipv4_country_code":"$iptest_country_code4",
			"ipv4_imgurl":"$iptest_imgurl4",
			"ipv6_address":"$iptest_address6",
			"ipv6_country":"$iptest_country6",
			"ipv6_country_code":"$iptest_country_code6",
			"ipv6_imgurl":"$iptest_imgurl6"
		},
		"connections":[
EOM
netstat -tn 2>/dev/null | grep ESTABLISHED | awk '
	{
		split($4,a,":");
		split($5,b,":");
		if(match(a[1],"169.254")) a[1]=ENVIRON["_ddmesh_ip"]
		#allow display node ip
		if(a[1] == ENVIRON["_ddmesh_ip"])
		{
			printf("\t\t\t{\"local\":{\"ip\":\"%s\",\"port\":\"%s\"},\"foreign\":{\"ip\":\"%s\",\"port\":\"%s\"}},\n",a[1],a[2],b[1],b[2]);
		}
	}' | sed '$s#,[ 	]*$##'
cat << EOM
		]
EOM

# remove last comma
#$s#,[ 	]*$##

cat << EOM
  }
}
EOM
