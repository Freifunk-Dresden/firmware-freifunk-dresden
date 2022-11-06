#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Infos &gt; Status"

. /usr/share/libubox/jshn.sh
. /usr/lib/www/page-pre.sh

RESOLV_PATH="/tmp/resolv.conf.d"
RESOLV_FINAL="${RESOLV_PATH}/resolv.conf.final"

getairtime() {
if [ -n "$1" -a "$1" != ",,," ]; then
	let ACT=$(echo "$1" | cut -d',' -f1)
	let BUS=$(echo "$1" | cut -d',' -f2)
	let REC=$(echo "$1" | cut -d',' -f3)
	let TRA=$(echo "$1" | cut -d',' -f4)
	busy=$(printf %.2f "$((10000 * $BUS / $ACT ))"e-2 )
	rx=$(printf %.2f "$((10000 * $REC / $ACT ))"e-2 )
	tx=$(printf %.2f "$((10000 * $TRA / $ACT ))"e-2 )
	echo "Busy: "$busy"% Rx: "$rx"% Tx: "$tx"%"
else
	echo "Busy: 0% Rx: 0% Tx: 0%"
fi
}

cat<<EOM
<h2>$TITLE</h2>
<br>
<fieldset class="bubble">
<legend>Allgemeines</legend>
<table>
<tr class="colortoggle1"><th>Knoten-IP-Adresse:</th><td><a href="https://$_ddmesh_ip/">$_ddmesh_ip</a></td></td></tr>
<tr class="colortoggle2"><th>Internet-Gateway:</th><td><a href="https://$INET_GW_IP/">$INET_GW</a></td></td></tr>
EOM
if [ "$wifi_status_radio2g_up" = "1" -o "$wifi_status_radio5g_up" = "1" ]; then
cat<<EOM
<tr class="colortoggle1"><th>Wifi Client IP Bereich (DHCP)</th><td>${_ddmesh_wifi2dhcpstart} - ${_ddmesh_wifi2dhcpend}</td></tr>
<tr class="colortoggle2"><th>Wifi Client IP Bereich (fest)</th><td>${_ddmesh_wifi2FixIpStart} - ${_ddmesh_wifi2FixIpEnd}</td></tr>
EOM
[ "$wifi_status_radio2g_up" = "1" ] && echo "<tr class=\"colortoggle1\"><th>Wifi 2G SSID</th><td>$(uci get wireless.wifi2_2g.ssid)</td></tr>"
[ "$wifi_status_radio5g_up" = "1" ] && echo "<tr class=\"colortoggle1\"><th>Wifi 5G SSID</th><td>$(uci get wireless.wifi2_5g.ssid)</td></tr>"
fi
cat<<EOM

<tr class="colortoggle2"><th>Nameserver:</th><td>$(grep nameserver ${RESOLV_FINAL} | sed 's#nameserver##g')</td></tr>
<tr class="colortoggle1"><th>Ger&auml;telaufzeit:</th><td>$(uptime)</td></tr>
<tr class="colortoggle2"><th>System:</th><td>$(uname -m) $(cat /proc/cpuinfo | sed -n '/system type/s#system[ 	]*type[ 	]*:##p')</td></tr>
<tr class="colortoggle1"><th>Ger&auml;teinfo:</th><td><b>Model:</b> $model ($model2) - <b>CPU:</b> $(cat /proc/cpuinfo | sed -n '/system type/s#[^:]\+:[ 	]*##p') - <b>Board:</b> $(cat /tmp/sysinfo/board_name)</td></tr>
<tr class="colortoggle2"><th>Firmware-Version:</th><td>Freifunk Dresden Edition $(cat /etc/version) / $DISTRIB_DESCRIPTION</td></tr>
<tr class="colortoggle1"><th>Freier Speicher:</th><td>$(cat /proc/meminfo | grep MemFree | cut -d':' -f2) von $(cat /proc/meminfo | grep MemTotal | cut -d':' -f2)</td></tr>
EOM
 if [ "$wifi_status_radio2g_up" = "1" ];then
	echo "<tr  class=\"colortoggle2\"><th>WiFi Airtime 2GHz</th><td>"
	getairtime $wifi_status_radio2g_airtime
	echo "</td></tr>"
 fi
 if [ "$wifi_status_radio5g_up" = "1" ];then
	echo "<tr class=\"colortoggle1\"><th>WiFi Airtime 5GHz</th><td>"
	getairtime $wifi_status_radio5g_airtime
	echo "</td></tr>"
 fi
cat<<EOM
</table>
</fieldset>
EOM

. /usr/lib/www/page-post.sh
