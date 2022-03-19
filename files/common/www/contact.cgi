#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Infos &gt; Kontakt"
. /usr/lib/www/page-pre.sh

SYSINFO_MOBILE_GEOLOC=/var/geoloc-mobile.json

if [ "$(uci -q get ddmesh.system.node_type)" = "mobile" ]; then
        eval $(cat $SYSINFO_MOBILE_GEOLOC | jsonfilter \
                -e gps_lat='@.location.lat' \
                -e gps_lng='@.location.lng' )
        gps_alt=0
else
        gps_lat=$(uci -q get ddmesh.gps.latitude)
        gps_lng=$(uci -q get ddmesh.gps.longitude)
        gps_alt=$(uci -q get ddmesh.gps.altitude)
fi
gps_lat=$(printf '%f' ${gps_lat:=0} 2>/dev/null)
gps_lng=$(printf '%f' ${gps_lng:=0} 2>/dev/null)
gps_alt=$(printf '%d' ${gps_alt:=0} 2>/dev/null)

cat<<EOF
<h2>$TITLE</h2>
<br>
<fieldset class="bubble" style="width: 600px">
<legend>Kontaktdaten</legend>
<table border="0">
<tr><th class="bubble">Name:</th><td>$(uhttpd -d "$(uci get ddmesh.contact.name)")</td></tr>
<tr><th class="bubble">E-Mail:&nbsp;</th><td>$(uhttpd -d "$(uci get ddmesh.contact.email)")</td></tr>
<tr><th class="bubble">Standort:&nbsp;</th><td>$(uhttpd -d "$(uci get ddmesh.contact.location)")</td></tr>
<tr><th class="bubble">GPS-Koordinaten:&nbsp;</th><td>
 <i>Breitengrad:</i> $gps_lat, <i>L&auml;ngengrad:</i> $gps_lng, <i>H&ouml;he:</i> $gps_alt <br/>
  <a target="_blank" href="https://meshviewer.freifunk-dresden.de/$_ddmesh_node" target="_blank">Meshviewer</a>
, <a target="_blank" href="http://maps.google.de/maps?f=q&hl=de&q=$gps_lat,$gps_lng&ie=UTF8&z=14&iwloc=addr&om=1"><b>Google Maps</b></a>
</td></tr>
<tr><th class="bubble">Notiz:&nbsp;</th><td>$(uhttpd -d "$(uci get ddmesh.contact.note)")</td></tr>
</table>
</fieldset>
<br>

<fieldset class="bubble" style="width: 600px">
<legend>OpenStreetMap</legend>
<div id="nodeMap"></div>
<style>
@import"https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.3.1/leaflet.css";
#nodeMap{height:300px;width:600px;}
</style>
<script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.3.1/leaflet.js"></script>
<script>
var map = L.map('nodeMap').setView([$gps_lat, $gps_lng], 18);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://openstreetmap.org/copyright">OpenStreetMap</a> contributors'
}).addTo(map);
L.marker([$gps_lat, $gps_lng]).addTo(map).bindPopup('$COMMUNITY [$_ddmesh_node]').openPopup();
</script>
</fieldset>

EOF



EOF

. /usr/lib/www/page-post.sh
