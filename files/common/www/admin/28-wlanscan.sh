#!/bin/ash

if [ "$wifi_status_radio2g_up" = "true" ]; then
cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="wlanscan.cgi">WLAN-Scan</a></div></td></tr>
EOM
fi
