#!/bin/sh

if [ "$(uci -q get ddmesh.network.mesh_on_lan)" != "1" ]; then

cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="privnet.cgi">Privates-Netzwerk</a></div></td></tr>
EOM

else

cat<<EOM
<tr><td><div class="plugin-disabled">Privates-Netzwerk</div></td></tr>
EOM

fi
