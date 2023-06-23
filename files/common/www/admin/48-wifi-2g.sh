#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

if [ "$wifi_status_radio2g_up" = "1" ]; then
cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="wifi-2g.cgi">WiFi 2.4 GHz</a></div></td></tr>
EOM

fi
