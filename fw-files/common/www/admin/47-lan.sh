#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

if [ "$(uci -q get ddmesh.network.mesh_on_lan)" != "1" ]; then

cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="lan.cgi">LAN</a></div></td></tr>
EOM

else

cat<<EOM
<tr><td><div class="plugin-disabled">LAN</div></td></tr>
EOM

fi
