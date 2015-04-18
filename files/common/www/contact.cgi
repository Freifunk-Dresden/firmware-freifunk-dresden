#!/bin/sh

export TITLE="Allgemein: Kontakt"
. /usr/lib/www/page-pre.sh

lat=$(uci get ddmesh.gps.latitude)
long=$(uci get ddmesh.gps.longitude)
alt=$(uci get ddmesh.gps.altitude)

cat<<EOF
<h2>$TITLE</h2>
<br>
<fieldset class="bubble">
<legend>Kontaktdaten</legend>
<table border="0">
<tr><th class="bubble">Name:</th><td>$(uhttpd -d "$(uci get ddmesh.contact.name)")</td></tr>
<tr><th class="bubble">E-Mail:&nbsp;</th><td>$(uhttpd -d "$(uci get ddmesh.contact.email)")</td></tr>
<tr><th class="bubble">Standort:&nbsp;</th><td>$(uhttpd -d "$(uci get ddmesh.contact.location)")</td></tr>
<tr><th class="bubble">GPS:&nbsp;</th><td>
 <i>Latitude:</i> $lat, <i>Longitude:</i> $long, <i>Altitude:</i> $alt, <a href="http://www.openstreetmap.org/export/embed.html?bbox=$long,$lat,$long,$lat&layer=mapnik&marker=$lat,$long"><b>OpenStreetMap</b></a>, <a href="http://maps.google.de/maps?f=q&hl=de&q=$lat,$long&ie=UTF8&z=14&iwloc=addr&om=1"><b>Google Maps</b></a>
</td></tr>
<tr><th class="bubble">Notiz:&nbsp;</th><td>$(uhttpd -d "$(uci get ddmesh.contact.note)")</td></tr>
</table>
</fieldset>
EOF

. /usr/lib/www/page-post.sh
