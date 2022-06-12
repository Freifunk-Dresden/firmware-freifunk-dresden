#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

if [ "$wifi_status_radio5g_up" = "1" ]; then
cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="wifi-5g.cgi">WiFi 5 GHz</a></div></td></tr>
EOM
fi
