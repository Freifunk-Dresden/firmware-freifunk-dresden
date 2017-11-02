#!/bin/ash
if [ "$wan_iface_present" = "1" ]; then
if [ "$(uci -q get ddmesh.network.mesh_on_wan)" != "1" ]; then

cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="wan.cgi">WAN</a></div></td></tr>
EOM

else

cat<<EOM
<tr><td><div class="plugin-disabled">WAN</div></td></tr>
EOM

fi
fi
