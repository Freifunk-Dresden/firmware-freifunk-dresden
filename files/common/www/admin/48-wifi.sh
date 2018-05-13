#!/bin/ash

if [ "$wifi_iface_present" = "1" ]; then
cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="wifi.cgi">WIFI</a></div></td></tr>
<tr><td><div class="plugin">&nbsp;&nbsp;<a class="plugin" href="splash.cgi">Splash</a></div></td></tr>
<tr><td><div class="plugin">&nbsp;&nbsp;<a class="plugin" href="ignore.cgi">Knoten&nbsp;ignorieren</a></div></td></tr>
EOM
fi

