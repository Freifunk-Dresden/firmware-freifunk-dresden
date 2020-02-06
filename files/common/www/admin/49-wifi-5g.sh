#!/bin/ash

if [ "$wifi_status_radio5g_up" = "true" ]; then
cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="wifi.cgi">WiFi</a></div></td></tr>
EOM
fi

