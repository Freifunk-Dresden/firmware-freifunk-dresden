#!/bin/sh

export TITLE="Infos &gt; Karte"
. /usr/lib/www/page-pre.sh

SYSINFO_MOBILE_GEOLOC=/var/geoloc-mobile.json

if [ "$(uci -q get ddmesh.system.node_type)" = "mobile" ]; then
	eval $(cat $SYSINFO_MOBILE_GEOLOC | jsonfilter \
                -e gps_lat='@.location.lat' \
                -e gps_lng='@.location.lng' )
else
        gps_lat=$(uci -q get ddmesh.gps.latitude)
        gps_lng=$(uci -q get ddmesh.gps.longitude)
fi
gps_lat=$(printf '%f' ${gps_lat:=0} 2>/dev/null)
gps_lng=$(printf '%f' ${gps_lng:=0} 2>/dev/null)


cat <<EOF
<h2>$TITLE</h2>
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
<br/>
<a href="https://meshviewer.freifunk-dresden.de/$_ddmesh_node" target="_blank">Anzeige in interaktiver Karte</a> (Online:Meshviewer)
EOF

. /usr/lib/www/page-post.sh
