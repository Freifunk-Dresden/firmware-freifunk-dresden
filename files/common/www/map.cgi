#!/bin/sh

export TITLE="Infos: Karte"
. /usr/lib/www/page-pre.sh

text -x /usr/bin/qrencode && QR_IMG="<img style=\"float:right\" src=\"/images/qr-geo.png\">"

cat <<EOF
<h2>$TITLE</h2>
<br>
<fieldset class="bubble">
<legend>Google Maps</legend>
<img border="0" alt="standort" src="//maps.googleapis.com/maps/api/staticmap?zoom=15&size=600x300&maptype=roadmap&markers=color:blue%7Clabel:R%7C$(uci get ddmesh.gps.latitude),$(uci get ddmesh.gps.longitude)&sensor=false">
$QR_IMG
</fieldset>
EOF


. /usr/lib/www/page-post.sh
