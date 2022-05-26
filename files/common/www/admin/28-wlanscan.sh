#!/bin/ash
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

if [ "$wifi_status_radio2g_up" = "1" ]; then
cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="wlanscan.cgi">WLAN-Scan</a></div></td></tr>
EOM
fi
