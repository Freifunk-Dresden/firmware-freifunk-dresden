#!/bin/ash
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

if [ "$wwan_iface_present" = "1" ]; then

cat<<EOM
<tr><td><div class="plugin"><a class="plugin" href="wwan.cgi">WWAN (Modem)</a></div></td></tr>
EOM

fi
