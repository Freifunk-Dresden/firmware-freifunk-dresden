#!/bin/ash
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

eval $(/usr/lib/ddmesh/ddmesh-utils-wifi-info.sh)

if [ "$wifi_status_radio2g_up" = "1" ]; then
cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="wifi-2g.cgi">WiFi 2.4 GHz</a></div></td></tr>
EOM

# slash will be removed; keep it sill active if used
if [ "$(uci -q get ddmesh.system.disable_splash)" != "1" ]; then
cat<<EOM
<tr><td><div class="plugin">&nbsp;&nbsp;<a class="plugin" href="splash.cgi">Splash</a></div></td></tr>
EOM
fi

fi
