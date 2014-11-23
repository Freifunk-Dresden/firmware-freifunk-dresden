#!/bin/sh

export TITLE="Verwaltung > Allgemein > Kontaktinfos"
. $DOCUMENT_ROOT/page-pre.sh ${0%/*}

cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

if [ -z "$QUERY_STRING" ]; then
tmp_name=$(uhttpd -d "$(uci get ddmesh.contact.name)")
tmp_email=$(uhttpd -d "$(uci get ddmesh.contact.email)")
tmp_location=$(uhttpd -d "$(uci get ddmesh.contact.location)")
tmp_note=$(uhttpd -d "$(uci get ddmesh.contact.note)")

cat<<EOF
<form action="contact.cgi" method="POST">
<fieldset class="bubble">
<legend>Kontakt-Informationen</legend>
<table>

<tr title="Freiwillige Angabe eines Namens">
<th>Name:</th>
<td><input name="form_contact_name" size="48" style="width: 100%;" type="text" value="$tmp_name"></td>
</tr>

<tr title="Freiwillige Angabe einer E-Mail-Adresse">
<th>E-Mail:</th>
<td><input name="form_contact_email" size="48" style="width: 100%;" type="text" value="$tmp_email"></td>
</tr>

<tr title="Standort-Angabe des Ger&auml;tes">
<th>Standort:</th>
<td><input name="form_contact_location" size="48" style="width: 100%;" type="text" value="$tmp_location"></td>
</tr>

<tr title="GPS-Position,H&ouml;he &uuml;ber Boden in Meter (z.B.: 9)">
<th>GPS Altitude:</th>
<td><input name="form_gps_altitude" size="20" type="text" value="$(uci get ddmesh.gps.altitude)"> GPS-Position,H&ouml;he &uuml;ber Boden in Meter (z.B.: 9)</td>
</tr>

<tr title="GPS-Position,Breitengrad (z.B.: 51.05812205978327)">
<th>GPS Latitude:</th>
<td><input name="form_gps_latitude" size="20" type="text" value="$(uci get ddmesh.gps.latitude)">(z.B.: 51.05812205978327)</td>
</tr>

<tr title="GPS-Position,L&auml;ngengrad (z.B.:13.72053812812492">
<th>GPS Longitude:</th>
<td><input name="form_gps_longitude" size="20" type="text" value="$(uci get ddmesh.gps.longitude)">(z.B.:13.720</td>
</tr>

<tr title="Notizen und kurze Hinweise zu diesem Access-Point. Die Notiz sollte nicht l&auml;nger als 500 Zeichen sein.">
<th>Notiz:</th>
<td><textarea COLS="48" name="form_contact_note" ROWS="3" style="width: 100%;">$tmp_note</textarea></td>
</tr>

<tr><td colspan="2">&nbsp;</td></tr>

<tr>
<td colspan="2"><input name="form_submit" title="Die Einstellungen &uuml;bernehmen. Diese werden sofort auf der Seite 'Status' angezeigt." type="submit" value="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<input name="form_abort" title="Abbruch dieser Dialogseite" type="submit" value="Abbruch"></td>
</tr>

</table>
</fieldset>
</form>
<br>
<p><b>Tipp</b>:
Diese Angaben sind auf der Seite <a href="/contact.cgi">Kontakt</a>
f&uuml;r andere sichtbar.</p>
EOF

else
	if [ -n "$form_submit" ]
	then
		uci set ddmesh.contact.name="$form_contact_name"
		uci set ddmesh.contact.email="$form_contact_email"
		uci set ddmesh.contact.location="$form_contact_location"
		uci set ddmesh.contact.note="$form_contact_note"
		uci set ddmesh.gps.latitude="$form_gps_latitude"
		uci set ddmesh.gps.longitude="$form_gps_longitude"
		uci set ddmesh.gps.altitude="$form_gps_altitude"
		uci commit
		notebox 'Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind sofort aktiv.'
	else
		notebox 'Es wurden keine Einstellungen ge&auml;ndert.'
	fi
fi

. $DOCUMENT_ROOT/page-post.sh
