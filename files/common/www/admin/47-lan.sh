#!/bin/ash

if [ "$(uci -q get ddmesh.network.mesh_on_lan)" != "1" ]; then

cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="lan.cgi">LAN</a></div></td></tr>
EOM

else

cat<<EOM
<tr><td><div class="plugin-disabled">LAN</div></td></tr>
EOM

fi
