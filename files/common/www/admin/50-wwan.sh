#!/bin/ash

if [ "$wwan_iface_present" = "1" ]; then

cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="wwan.cgi">WWAN (Modem)</a></div></td></tr>
EOM

fi

