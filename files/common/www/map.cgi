#!/bin/sh

export TITLE="Infos: Karte"
. /usr/lib/www/page-pre.sh
export lat=$(uci get ddmesh.gps.latitude)
export lon=$(uci get ddmesh.gps.longitude)

cat <<EOF
<h2>$TITLE</h2>
<br>
<fieldset class="bubble">
<legend>Openstreetmap</legend>
<img border="0" alt="standort" src="https://freifunk.it-service-merkelt.de/staticmap.php?center=$lat,$lon&zoom=15&markers=$lat,$lon,ol-marker-blue">
</fieldset>
EOF

. /usr/lib/www/page-post.sh
