#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wan)

echo 'Content-type: text/plain txt'
echo ''

cat<<EOM
<table>
<tr><th>Interface:</th><td>$net_ifname</td></tr>
<tr><th>IP-Adresse:</th><td>$net_ipaddr</td></tr>
<tr><th>Netzmaske:</th><td>$net_netmask</td></tr>
<tr><th>Broadcast:</th><td>$net_broadcast</td></tr>
<tr><th>Nameserver:</th><td>$net_dns</td></tr>
<tr><th>Gateway:</th><td>$net_gateway</td></tr>
<tr><th>Verbindungszeit:</th><td>$net_connect_time</td></tr>
</table>
EOM
