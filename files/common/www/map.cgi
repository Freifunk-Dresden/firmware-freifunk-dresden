#!/bin/sh

export TITLE="Infos: Karte"
. $DOCUMENT_ROOT/page-pre.sh

text -x /usr/bin/qrencode && QR_IMG="<img style=\"float:right\" src=\"/images/qr-geo.png\">"

cat <<EOF
<h2>$TITLE</h2>
<br>
<fieldset class="bubble">
<legend>Google Maps</legend>
<iframe onload="iFrameHeight()" src="http://maps.google.de/maps?f=q&amp;hl=de&amp;geocode=&amp;q=http:%2F%2Finfo.freifunk-dresden.de%2Finfo%2Fnetwork.kmz%3Frandom%3D$(date +"%s")-$RANDOM&amp;ie=UTF8&amp&amp;ll=$(nvram get gps_latitude),$(nvram get gps_longitude)&amp;spn=0.01,0.01&amp;output=embed&amp;s=AARTsJqa9QXWhdEZZRirvObWlK4yEMZzHg" name="iframe" id="blockrandom" class="wrapper" align="top" frameborder="0" height="400" width="100%"></iframe>
$QR_IMG
</fieldset>
EOF


. $DOCUMENT_ROOT/page-post.sh
