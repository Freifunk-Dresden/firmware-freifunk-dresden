#!/bin/sh

test -x /usr/bin/qrencode || exit 0

/usr/bin/qrencode -s 3 -o /tmp/2d.png "Freifunk Dresden, $_ddmesh_hostname, http://$_ddmesh_ip.freifunk-dresden.de"

T=/tmp/2d-big.txt
>$T
echo "Freifunk Dresden - Freie WLAN Community" >> $T
echo "Knoten: $_ddmesh_hostname" >> $T
echo "http://$_ddmesh_ip.freifunk-dresden.de" >>$T
echo "geo: $(uci get ddmesh.gps.latitude),$(uci get ddmesh.gps.longitude)" >> $T
uhttpd -d "$(uci get ddmesh.contact.note)" >> $T
cat $T | sed 's#$#\r#g' | qrencode -s 5 -o /tmp/2d-big.png

#geo
/usr/bin/qrencode -s 3 -o /tmp/qr-geo.png "GEO:$(uci get ddmesh.gps.latitude),$(uci get ddmesh.gps.longitude)"
