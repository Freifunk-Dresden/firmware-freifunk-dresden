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
 "version":"1",
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
			$(cat /tmp/resolv.conf.auto| sed -n '/nameserver/{s#[ 	]*nameserver[ 	]*\(.*\)#"\1",#;p}' | sed '$s#,##')
			],
			"date":"$(date)",
			"model":"$(cat /var/sysinfo/model):$(cat /proc/diag/model)"
		},
		"common":{
			"city":"Dresden",
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
		"accepted_user_count" : "$(ls -l /tmp/dhcp.autodisconnect.db | wc -l )",
		"dhcp_count" : "$(wc -l /var/dhcp.leases | cut -d' ' -f1)",
		"dhcp_lease" : "$(grep 'dhcp-range=wifi2' /etc/dnsmasq.conf | cut -d',' -f 6)",
		"traffic_adhoc": "$(ifconfig $wifi | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
		"traffic_ap": "$(ifconfig $wifi2 | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
		"traffic_ovpn": "$(ifconfig $vpn | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
		"traffic_tbb0": "$(ifconfig tbb0 | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
		"traffic_tbb1": "$(ifconfig tbb1 | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
		"traffic_tbb2": "$(ifconfig tbb2 | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
		"traffic_tbb3": "$(ifconfig tbb3 | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
		"traffic_tbb4": "$(ifconfig tbb4 | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
		$(cat /proc/meminfo | sed 's#\(.*\):[ 	]\+\([0-9]\+\)[ 	]\+\(.*\)#\"meminfo_\1\" : \"\2\ \3\",#')
		"cpu_load" : "$(cat /proc/loadavg)",
		"cpu_stat" : "$(cat /proc/stat | sed -n '/^cpu[ 	]\+/{s# \+# #;p}')",
		"gateway_usage" : [ $(cat /var/statistic/gateway_usage | sed 's#\([^:]*\):\(.*\)#{"\1":"\2"},#' | sed '$s#,[ 	]*$##') ]
	},
EOM

#bmxd
#$(ip route list table bat_route | sed 's#\(.*\)#			"\1",#; $s#,[ 	]*$##') ],
cat<<EOM
		"bmxd":{
			"routing_tables":{
				"route":{
					"link":[
$(ip route list table bat_route | sed -n '/scope[ ]\+link/{s#^\([0-9./]\+\)[	 ]\+dev[	 ]\+\([^	 ]\+\).*#			{"target":"\1","interface":"\2"},#;p}' | sed '$s#,[ 	]*$##') ],
		  			"global":[
$(ip route list table bat_route | sed  '/scope[ ]\+link/d;s#^\([0-9./]\+\)[	 ]\+via[	 ]\+\([0-9.]\+\)[	 ]\+dev[	 ]\+\([^	 ]\+\).*#			{"target":"\1","via":"\2","interface":"\3"},#p' | sed '$s#,[ 	]*$##') ]
		  		},
			"hna":{
				"link":[
$(ip route list table bat_hna | sed -n '/scope[ ]\+link/{s#^\([0-9./]\+\)[	 ]\+dev[	 ]\+\([^	 ]\+\).*#			{"target":"\1","interface":"\2"},#;p}' | sed '$s#,[ 	]*$##') ],
		  		"global":[
$(ip route list table bat_hna | sed  '/scope[ ]\+link/d;s#^\([0-9./]\+\)[	 ]\+via[	 ]\+\([0-9.]\+\)[	 ]\+dev[	 ]\+\([^	 ]\+\).*#			{"target":"\1","via":"\2","interface":"\3"},#p' | sed '$s#,[ 	]*$##') ]
				}
			},
			"details": {
				"head":"$(cat $BMXD_DB_PATH/details | sed -n '1,1s#\(^.*$\)#\1#p')",
				"neighbor":[
$(cat $BMXD_DB_PATH/details | sed -n '
				/^Originator/q
				s#^[	 ]*\([0-9.]\+\)[	 ]\+\([^	 ]\+\)[	 ]\+\([0-9.]\+\)[	 ]\+\([0-9]\+\)[	 ]\+\([0-9]\+\)[	 ]\+\([0-9]\+\)[	 ]\+\([0-9]\+\).*#				{"ip":"\1","interface":"\2","originator":"\3","rtq":"\4","rq":"\5","tq":"\6","lseq":"\7"},#p
				' | sed '$s#,[	 ]*$##') ],
				"originator":[
$(cat $BMXD_DB_PATH/details | sed -n '
				/^Originator/!d
				:start
				n
				s#^[	 ]*\([0-9.]\+\)[	 ]\+\([^	 ]\+\)[	 ]\+\([0-9.]\+\)[	 ]\+\([0-9]\+\)[	 ]\+\([0-9]\+\)[	 ]\+\([0-9:]\+\)[	 ]\+\([0-9]\+\).*#				{"ip":"\1","interface":"\2","nexthop":"\3","tq":"\4","rcnt":"\5","knownsince":"\6","lsqn":"\7"},#p
				b start
				' | sed '$s#,[	 ]*$##') ]
			},
			"gateways":{
				"selected":"$(cat $BMXD_DB_PATH/gateways | sed -n 's#^[	 ]*=>[	 ]\+\([0-9.]\+\).*$#\1#p')",
				"preferred":"$(cat $BMXD_DB_PATH/gateways | sed -n '1,1s#^.*preferred gateway:[	 ]\+\([0-9.]\+\).*$#\1#p')",
				"gateways":[
$(cat $BMXD_DB_PATH/gateways | sed -n '
				/^[	 ]*$/d
				1,1d
				s#^[	 =>]*\([0-9.]\+\).*$#			{"ip":"\1"},#p
				' | sed '$s#,[	 ]*$##') ]
			},
			"info":[
$(bmxd -ci | sed 's#^[ 	]*\(.*\)$#			"\1",#; $s#,[ 	]*$##') ]
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
		  }
EOM

# remove last comma
#$s#,[ 	]*$##

cat << EOM
  }
}
EOM
