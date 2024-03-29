#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

OUTPUT=/var/sysinfo.json.tmp
FINAL_OUTPUT=/var/sysinfo.json
SYSINFO_MOBILE_GEOLOC=/var/geoloc-mobile.json

#empty
> $OUTPUT

BMXD_DB_PATH=/var/lib/ddmesh/bmxd
RESOLV_PATH="/tmp/resolv.conf.d"
RESOLV_FINAL="${RESOLV_PATH}/resolv.conf.final"

eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
test -z "$_ddmesh_node" && exit

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)
eval $(/usr/lib/ddmesh/ddmesh-utils-wifi-info.sh)
eval $(cat /etc/built_info | sed 's#:\(.*\)$#="\1"#')
eval $(cat /etc/openwrt_release)

avail_flash_size=$(df -k -h /overlay | sed -n '2,1{s# \+# #g; s#[^ ]\+ [^ ]\+ [^ ]\+ \([^ ]\+\) .*#\1#;p}')

if [ "$(uci -q get ddmesh.system.email_notification)" = "1" ]; then
	email_notification=1
else
	email_notification=0
fi

if [ "$(uci -q get ddmesh.system.firmware_autoupdate)" = "1" ]; then
	autoupdate=1
else
	autoupdate=0
fi

case "$(uci -q get ddmesh.system.node_type)" in
	node)	node_type="node" ;;
	mobile)	node_type="mobile" ;;
	server)	node_type="server" ;;
	*) node_type="node";;
esac

if [ $node_type = "mobile" -a -f "$SYSINFO_MOBILE_GEOLOC" ]; then
	eval $(cat $SYSINFO_MOBILE_GEOLOC | jsonfilter \
		-e gps_lat='@.location.lat' \
		-e gps_lng='@.location.lng' )
	gps_alt=0
else
	gps_lat=$(uci -q get ddmesh.gps.latitude)
	gps_lng=$(uci -q get ddmesh.gps.longitude)
	gps_alt=$(uci -q get ddmesh.gps.altitude)
fi
gps_lat=$(printf '%f' ${gps_lat:=0} 2>/dev/null)
gps_lng=$(printf '%f' ${gps_lng:=0} 2>/dev/null)
gps_alt=$(printf '%d' ${gps_alt:=0} 2>/dev/null)

# get model
eval $(cat /etc/board.json | jsonfilter -e model='@.model.id' -e model2='@.model.name')
model="$(echo $model | sed 's#[ 	]*\(\1\)[ 	]*#\1#')"
model2="$(echo $model2 | sed 's#[ 	]*\(\1\)[ 	]*#\1#')"

# first search system type. if not use model name. exit after first cpu core
cpu_info="$(cat /proc/cpuinfo | sed -n '/system type/s#[^:]\+:[ 	]*##p')"

if [ "$(uci -q get ddmesh.network.wifi2_roaming_enabled)" = "1" -a "$_ddmesh_wifi2roaming" = "1" ]; then
	roaming=1
else
	roaming=0
fi

if [ "$wifi_status_radio2g_present" == "1" ]; then
  wifi_2g_channel="$(iwinfo wifi2ap info | grep 'Channel:' | tr -s ' ' | cut -d' ' -f5 | sed 's#unknown#0#')"
  [ -z "$wifi_2g_channel" ] && wifi_2g_channel=0
fi

if [ "$wifi_status_radio5g_present" == "1" ]; then
  wifi_5g_channel="$(iwinfo wifi5ap info | grep 'Channel:' | tr -s ' ' | cut -d' ' -f5 | sed 's#unknown#0#')"
  [ -z "$wifi_5g_channel" ] && wifi_5g_channel=0
fi


if [ -n "$(which wg)" ]; then
	wg_public_key=$(uci get credentials.backbone_secret.wireguard_key | wg pubkey)
fi

function parseWifiDump()
{
 statfile="$1"
 touch $statfile

 awk -v statfile=$statfile '
        function uptime()
	{
		cmd = "cat /proc/uptime"
		cmd | getline line
		split(line, arr, ".")
		# add '0' to convert string to integer, else comparision wont work correctly
		return arr[1]+0
	}
	BEGIN {
		while(getline line < statfile > 0)
		{
			split(line,a," ");
			mac[a[1]]=a[2]
		};
		close(statfile);

		timekey[1] = "1min"
		timekey[2] = "5min"
		timekey[3] = "15min"
		timekey[4] = "1h"
		timekey[5] = "6h"
		timekey[6] = "12h"
		timekey[7] = "1d"
		timekey[8] = "7d"
		timekey[9] = "14d"
		timekey[10] = "30d"
		timekey[11] = "90d"
		timekey[12] = "infinity"
	}
	/Station/{
			m=$2
			mac[m]=systime()
	}
	END {
		cur = systime()
		up = uptime()

		for(i=1;i<=12;i++)
		{ count[i]=0 }

#printf("\"debugging\",\n")

		for(m in mac)
		{
			expired="-"
			seen="+"
			d = cur - mac[m]

			# init for debugging
			for(i=1;i<=12;i++)
			{ s[i]="0" }

			# default mark all stat columns
			s[1]=seen
			if( up > 60) s[2]=seen
			if( up > 300) s[3]=seen
			if( up > 900) s[4]=seen
			if( up > 3600) s[5]=seen
			if( up > (3600*6)) s[6]=seen
			if( up > (3600*12)) s[7]=seen
			if( up > (86400)) s[8]=seen
			if( up > (86400*7)) s[9]=seen
			if( up > (86400*14)) s[10]=seen
			if( up > (86400*30)) s[11]=seen
			if( up > (86400*90)) s[12]=seen

			# printf("\"debug-A\":\"%s (up:%s,diff:%s) %s %s %s %s %s %s %s %s %s %s %s %s\",\n", m, up, d, s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11], s[12])

			# s1 expired 1min
			if( d > 60) s[1]=expired
			# s2 expired 5min
			if( d > 300) s[2]=expired
			# s3 expired 15min
			if( d > 900) s[3]=expired
			# s4 expired 1h
			if( d > 3600) s[4]=expired
			# s5 expired 6h
			if( d > (3600*6)) s[5]=expired
			# s6 expired 12h
			if( d > (3600*12)) s[6]=expired
			# s7 expired 1d
			if( d > (86400)) s[7]=expired
			# s8 expired 7d
			if( d > (86400*7)) s[8]=expired
			# s9 expired 14d
			if( d > (86400*14)) s[9]=expired
			# s10 expired 30d
			if( d > (86400*30)) s[10]=expired
			# s11 expired 3m
			if( d > (86400*90)) s[11]=expired
			# s12 counts unlimited time, dont set to expired

			# write back statfile
			printf("%s %d\n", m, mac[m]) > statfile

			# printf("\"debug-B\":\"%s (up:%s,diff:%s) %s %s %s %s %s %s %s %s %s %s %s %s\",\n", m, up, d, s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11], s[12])

			# count each column
			for(i=1;i<=12;i++)
			{
				if(match(s[i],seen))
					count[i]++
			}
		}
		close(statfile)

		# output json
		printf("{\n");
		for(i=1;i<=12;i++)
		{
			if(i>1) printf(",\n");
			printf("\"%s\": %d", timekey[i], count[i])
		}
		printf("\n}\n");
	}
'
}

cat << EOM >> $OUTPUT
{
 "version":"17",
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
			"git-openwrt-rev":"$git_openwrt_rev",
			"git-openwrt-branch":"$git_openwrt_branch",
			"git-ddmesh-rev":"$git_ddmesh_rev",
			"git-ddmesh-branch":"$git_ddmesh_branch"
		},
		"system":{
			"uptime":"$(cat /proc/uptime)",
			"uptime_string":"$(uptime)",
			"uname":"$(uname -a)",
			"nameserver": [
$(cat ${RESOLV_FINAL} | sed -n '/nameserver[ 	]\+10\.200/{s#[ 	]*nameserver[ 	]*\(.*\)#\t\t\t\t"\1",#;p}' | sed '$s#,[ 	]*$##')
			],
			"date":"$(date)",
			"board":"$(cat /var/sysinfo/board_name 2>/dev/null)",
			"model":"$model",
			"model2":"$model2",
			"cpuinfo":"$cpu_info",
			"cpucount":"$(grep -c ^processor /proc/cpuinfo)",
			"bmxd" : "$(cat $BMXD_DB_PATH/status)",
			"essid":"$(uci get wireless.wifi2_2g.ssid)",
			"wifi_roaming" : "$roaming",
			$([ "$wifi_status_radio2g_present" == "1" ] && echo "\"wifi_2g_channel\": ${wifi_2g_channel},")
			$([ "$wifi_status_radio5g_present" == "1" ] && echo "\"wifi_5g_channel\": ${wifi_5g_channel},")
			"wifi_htmode" : {
EOM
			comma=0
			for ifname in mesh2g-80211s mesh5g-80211s wifi2ap wifi5ap wifi-client5g
			do
				htmode="$(iwinfo ${ifname} info  2>/dev/null | sed -n 's#.*HT Mode: \(.*\)#\1#p')"
				[ $comma = 1 ] && echo -n "," >> $OUTPUT
				comma=1
				echo "\"${ifname}\":\"${htmode}\"" >> $OUTPUT
			done

cat << EOM >> $OUTPUT
			},
			"wifi_bitrate" : {
EOM
			comma=0
			for ifname in mesh2g-80211s mesh5g-80211s wifi2ap wifi5ap wifi-client5g
			do
				htmode="$(iwinfo ${ifname} info 2>/dev/null | sed -n 's#.*Bit Rate: \(.*\)#\1#p')"
				[ $comma = 1 ] && echo -n "," >> $OUTPUT
				comma=1
				echo "\"${ifname}\":\"${htmode}\"" >> $OUTPUT
			done

cat << EOM >> $OUTPUT
			},
			"node_type":"$node_type",
			"email_notification":$email_notification,
			"autoupdate":$autoupdate,
			"available_flash_size":"$avail_flash_size",
			"overlay_md5sum": $(/usr/lib/ddmesh/ddmesh-overlay-md5sum.sh -json)
		},
		"opkg":{
$(/usr/lib/ddmesh/ddmesh-installed-ipkg.sh json '		')
		},
		"common":{
			"community":"$(uci -q get ddmesh.system.community)",
			"group_id":"$(uci -q get ddmesh.system.group_id)",
			"node":"$_ddmesh_node",
			"domain":"$_ddmesh_domain",
			"ip":"$_ddmesh_ip",
			"network_id":"$(uci get ddmesh.system.mesh_network_id)"
		},
		"backbone":{
			"fastd_pubkey":"$(/usr/lib/ddmesh/ddmesh-backbone.sh get_public_key)",
			"wg_pubkey":"$wg_public_key"
		},
		"gps":{
			"latitude":$gps_lat,
			"longitude":$gps_lng,
			"altitude":$gps_alt
		},
		"contact":{
			"name":"$(uci -q get ddmesh.contact.name)",
			"location":"$(uci -q get ddmesh.contact.location)",
			"email":"$(uci -q get ddmesh.contact.email)",
			"note":"$(uci -q get ddmesh.contact.note)"
		},
		"statistic" : {
EOM
		# devel: process lan clients
		# tmp_ifname="br-lan"
		# echo "\"client2g\" :" >> $OUTPUT
		# cat /proc/net/arp | awk '/'${tmp_ifname}'/{if(match("0x2",$3)){printf("Station %s\n",$4);}}' | parseWifiDump /var/statistic/${tmp_ifname}.stat >> $OUTPUT
		# echo "," >> $OUTPUT

		if [ "$wifi_status_radio2g_present" = "1" ]; then
			for wifi in 2g 5g
			do
				ifname=$(uci -q get wireless.wifi2_${wifi}.ifname)
				if [ -n "$ifname" ]; then
					echo "\"client${wifi}\" :" >> $OUTPUT
					iw dev $ifname station dump | parseWifiDump /var/statistic/wifi${wifi}.stat >> $OUTPUT
					echo "," >> $OUTPUT
				fi
			done
		fi
cat<<EOM >> $OUTPUT
		"interfaces" : {
EOM

		comma=0
		for entry in $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh list)
		do
			net=${entry%%=*}
			net=${net#net_}

			case "$net" in
				# use tbbwg main wireguard interface to cover all ipip tunnels
				mesh_lan|mesh_wan|mesh_vlan|tbbwg|tbb_fastd|bat|ffgw|vpn|wifi2|wifi_adhoc|wifi_mesh2g|wifi_mesh5g)

					ifname=${entry#*=}
					ifname=${ifname/+/}

					[ -n "$ifname" ] && ifname="$(basename /sys/class/net/${ifname}*)"
					ifpath="/sys/class/net/${ifname}"

					if [ -n "${ifname}" -a -d ${ifpath} ]; then
						[ $comma = 1 ] && echo -n "," >> $OUTPUT
						comma=1
						rx="$(cat ${ifpath}/statistics/rx_bytes)"
						tx="$(cat ${ifpath}/statistics/tx_bytes)"
						# fix fastd statistic
						test ${net} = "tbb_fastd" -a "$rx" = "0" && tx="0"
						test ${net} = "tbbwg" && net="tbb_wg"

						echo "\"${net}_rx\":\"$rx\"" >> $OUTPUT
						echo ",\"${net}_tx\":\"$tx\"" >> $OUTPUT
					fi
				;;
			esac

		done

cat<<EOM >> $OUTPUT
		},
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
					BEGIN {
						# map iface to net type (set by ddmesh-utils-network-info.sh)
						nettype_lookup[ENVIRON["wifi_adhoc_ifname"]]="wifi_adhoc";
						nettype_lookup[ENVIRON["wifi_mesh2g_ifname"]]="wifi_mesh";
						nettype_lookup[ENVIRON["wifi_mesh5g_ifname"]]="wifi_mesh";
						nettype_lookup[ENVIRON["mesh_lan_ifname"]]="lan";
						nettype_lookup[ENVIRON["mesh_wan_ifname"]]="lan";
						nettype_lookup[ENVIRON["mesh_vlan_ifname"]]="lan";
						nettype_lookup[ENVIRON["tbb_fastd_ifname"]]="backbone";
						nettype_lookup[ENVIRON["tbb_wg_ifname"]]="backbone";
					}
					{
						if(match($0,"^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]"))
						{
							# check for special tbb_wg interface name (has more than one ifname)
							clean_ifname=gensub(/tbb_wg[0-9]+$/,"tbb_wg+","",$2)
							printf("\t\t\t\t{\"node\":\"%d\", \"ip\":\"%s\", \"interface\":\"%s\",\"rtq\":\"%d\", \"rq\":\"%d\", \"tq\":\"%d\",\"type\":\"%s\"}, \n",
							getnode($1),$3,$2,$4,$5,$6, nettype_lookup[clean_ifname]);
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
		"airtime":{"radio2g":"$(echo $wifi_status_radio2g_airtime)"
		$([ -n "$wifi_status_radio5g_airtime" -a "$wifi_status_radio5g_airtime" != ",,," ] && echo ", \"radio5g\":\"$wifi_status_radio5g_airtime\"" )},
		"network_switch":$(/usr/lib/ddmesh/ddmesh-utils-switch-info.sh json)
EOM


# remove last comma
#$s#,[ 	]*$##

cat << EOM >> $OUTPUT
  }
}
EOM

mv $OUTPUT $FINAL_OUTPUT
