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
<div id="nodeMap"></div>
<style>
@import"https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.3.1/leaflet.css";
#nodeMap{height:300px;width:600px;}
</style>
<script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.3.1/leaflet.js"></script>
<script>
var map = L.map('nodeMap').setView([$lat, $lon], 18);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://openstreetmap.org/copyright">OpenStreetMap</a> contributors'
}).addTo(map);
L.marker([$lat, $lon]).addTo(map).bindPopup('$COMMUNITY [$_ddmesh_node]').openPopup();
</script>
</fieldset>
EOF

. /usr/lib/www/page-post.sh
