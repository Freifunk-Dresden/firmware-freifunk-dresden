#!/bin/ash

eval $(/usr/lib/ddmesh/ddmesh-utils-wifi-info.sh)

if [ "$wifi_status_radio2g_up" = "1" ]; then
cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="wlanscan.cgi">WLAN-Scan</a></div></td></tr>
EOM
fi
