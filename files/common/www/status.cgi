#!/bin/sh

export TITLE="Infos &gt; Status"

. /usr/share/libubox/jshn.sh
. /usr/lib/www/page-pre.sh
eval $(/usr/lib/ddmesh/ddmesh-utils-wifi-info.sh)

getairtime() {
let ACT=$(echo "$1" | cut -d',' -f1)
let BUS=$(echo "$1" | cut -d',' -f2)
let REC=$(echo "$1" | cut -d',' -f3)
let TRA=$(echo "$1" | cut -d',' -f4)
busy=$(printf %.2f "$((10000 * $BUS / $ACT ))"e-2 )
rx=$(printf %.2f "$((10000 * $REC / $ACT ))"e-2 )
tx=$(printf %.2f "$((10000 * $TRA / $ACT ))"e-2 )
echo "Busy: "$busy"% Rx: "$rx"% Tx: "$tx"%"
}

cat<<EOF
<h2>$TITLE</h2>
<br>
<fieldset class="bubble">
<legend>Allgemeines</legend>
<table>
<tr><th>Knoten-IP-Adresse:</th><td><a href="https://$_ddmesh_ip/">$_ddmesh_ip</a></td></td></tr>
<tr><th>Internet-Gateway:</th><td><a href="https://$INET_GW_IP/">$INET_GW</a></td></td></tr>
<tr><th>Nameserver:</th><td>$(grep nameserver /var/resolv.conf.final | sed 's#nameserver##g')</td></tr>
<tr><th>Ger&auml;telaufzeit:</th><td>$(uptime)</td></tr>
<tr><th>System:</th><td>$(uname -m) $(cat /proc/cpuinfo | sed -n '/system type/s#system[ 	]*type[ 	]*:##p')</td></tr>
<tr><th>Ger&auml;teinfo:</th><td><b>Model:</b> $model ($model2) - <b>CPU:</b> $(cat /proc/cpuinfo | sed -n '/system type/s#[^:]\+:[ 	]*##p') - <b>Board:</b> $(cat /tmp/sysinfo/board_name)</td></tr>
<tr><th>Firmware-Version:</th><td>Freifunk Dresden Edition $(cat /etc/version) / $DISTRIB_DESCRIPTION</td></tr>
<tr><th>Freier Speicher:</th><td>$(cat /proc/meminfo | grep MemFree | cut -d':' -f2) von $(cat /proc/meminfo | grep MemTotal | cut -d':' -f2)</td></tr>
<tr><th>WIFI AirTime:</th><td> 2Ghz: $(getairtime $wifi_status_radio2g_airtime)</td></tr>
$( [ ! -z "$wifi_status_radio5g_airtime" ] && echo "<tr><th><td> 5Ghz:"; getairtime $wifi_status_radio5g_airtime; echo "</td></tr>")
</table>
</fieldset>
EOF

. /usr/lib/www/page-post.sh
