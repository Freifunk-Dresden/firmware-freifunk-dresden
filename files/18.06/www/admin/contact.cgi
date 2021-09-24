#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Allgemein: Kontaktinfos"
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

display()
{
tmp_name=$(uhttpd -d "$(uci get ddmesh.contact.name)")
tmp_email=$(uhttpd -d "$(uci get ddmesh.contact.email)")
tmp_location=$(uhttpd -d "$(uci get ddmesh.contact.location)")
tmp_note=$(uhttpd -d "$(uci get ddmesh.contact.note)")
lat=$(uci -q get ddmesh.gps.latitude)
lon=$(uci -q get ddmesh.gps.longitude)
alt=$(uci -q get ddmesh.gps.altitude)
alt=${alt:=0}

# default koord. else leaflet will not show map
def_lat="51.05405"
def_lon="13.74364"

leaflet_lat=$lat
leaflet_lon=$lon
[ -z "$leaflet_lat" -o "$leaflet_lat" = "0" ] && leaflet_lat="$def_lat"
[ -z "$leaflet_lon" -o "$leaflet_lon" = "0" ] && leaflet_lon="$def_lon"

cat<<EOF
<form action="contact.cgi" method="POST">
<fieldset class="bubble">
<legend>Kontakt-Informationen</legend>
<div style="color: #000088;">
<font size="+1"><b>Hinweis zur Datenschutz-Grundverordnung (EU-DSGVO):</b></font><br/>
$(lang text-dsgvo)
<br /><br />
</div>
<table>

<tr title="Freiwillige Angabe eines Namens">
<th>Name:</th>
<td colspan="2"><input name="form_contact_name" size="48" style="width: 100%;" type="text" value="$tmp_name"></td>
</tr>

<tr title="Freiwillige Angabe einer E-Mail-Adresse">
<th>E-Mail:</th>
<td colspan="2"><input name="form_contact_email" size="48" style="width: 100%;" type="text" value="$tmp_email"></td>
</tr>

<tr title="Standort-Angabe des Ger&auml;tes">
<th>Standort:</th>
<td colspan="2"><input name="form_contact_location" size="48" style="width: 100%;" type="text" value="$tmp_location"></td>
</tr>

<tr title="GPS-Altitude, H&ouml;he &uuml;ber Boden in Meter">
<th>H&ouml;he:</th>
<td><input id="geoloc_alt" name="form_gps_altitude" size="20" type="text" value="$alt"> H&ouml;he &uuml;ber Boden in Meter (Beispiel: 9)</td>
<td></td>
</tr>

<tr title="GPS-Latitude">
<th>Breitengrad:</th>
<td><input id="geoloc_lat" name="form_gps_latitude" size="20" type="text" value="$lat">(Beispiel: 51.05812)</td>
<td><button onclick="ajax_geoloc()" type="button" title="$(lang text-geoloc01)">$(lang text-geoloc00)</button></td>
</tr>

<tr title="GPS-Longitude">
<th>L&auml;ngengrad:</th>
<td><input id="geoloc_lng" name="form_gps_longitude" size="20" type="text" value="$lon">(Beispiel: 13.72053)</td>
<td></td>
</tr>

<tr title="Notizen und kurze Hinweise zu diesem Access-Point. Die Notiz sollte nicht l&auml;nger als 500 Zeichen sein.">
<th>Notiz:</th>
<td colspan="2"><textarea COLS="48" name="form_contact_note" ROWS="3" style="width: 100%;">$tmp_note</textarea></td>
</tr>

<tr><td colspan="3">&nbsp;</td></tr>

<tr>
<td colspan="3"><input name="form_submit" title="Die Einstellungen &uuml;bernehmen. Diese werden sofort auf der Seite 'Status' angezeigt." type="submit" value="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<input name="form_abort" title="Abbrechen und &Auml;nderungen verwerfen." type="submit" value="Abbrechen"></td>
</tr>

</table>
</fieldset>
</form>
<br>
<p><b>Hinweis:</b><br />
Diese Angaben sind auf der Seite <a href="/contact.cgi">Kontakt</a>
f&uuml;r andere sichtbar.<br />
Der Standort kann per Drag and Drop mit dem Mauszeiger verschoben werden.<br/>
</p>
<fieldset class="bubble" style="width: 600px" >
<legend>OpenStreetMap</legend>
<div id="nodeMap"></div>
<style>
@import"https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.3.1/leaflet.css";
#nodeMap{height:300px;width:600px;}
</style>
<script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.3.1/leaflet.js"></script>
<script>
var map = L.map('nodeMap').setView([$leaflet_lat, $leaflet_lon], 18);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://openstreetmap.org/copyright">OpenStreetMap</a> contributors'
}).addTo(map);
map.on('click', onMapClick);

var marker = L.marker([$leaflet_lat, $leaflet_lon]);
//marker.bindPopup('$COMMUNITY [$_ddmesh_node]').openPopup();
marker.on('moveend', onMarkerMove);
marker.addTo(map);
marker.dragging.enable(); // after adding to map !

</script>
</fieldset>
EOF
}

if [ -n "$QUERY_STRING" ]; then
	if [ -n "$form_submit" ]
	then
		uci set ddmesh.contact.name="$form_contact_name"
		uci set ddmesh.contact.email="$form_contact_email"
		uci set ddmesh.contact.location="$form_contact_location"
		uci set ddmesh.contact.note="$form_contact_note"
		uci set ddmesh.gps.latitude="$form_gps_latitude"
		uci set ddmesh.gps.longitude="$form_gps_longitude"
		uci set ddmesh.gps.altitude="$form_gps_altitude"
		uci_commit.sh
		notebox 'Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind sofort aktiv.'
	else
		notebox 'Es wurden keine Einstellungen ge&auml;ndert.'
	fi
fi

display

. /usr/lib/www/page-post.sh
