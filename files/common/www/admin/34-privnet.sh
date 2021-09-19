#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

if [ "$(uci -q get ddmesh.network.mesh_on_lan)" != "1" ]; then

cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="privnet.cgi">Privates-Netzwerk</a></div></td></tr>
EOM

else

cat<<EOM
<tr><td><div class="plugin-disabled">Privates-Netzwerk</div></td></tr>
EOM

fi
