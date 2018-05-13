#!/bin/sh

export TITLE="Feinstaubsensor"
. /usr/lib/www/page-pre.sh

hight=240
width=380

cat<<EOM
<fieldset class="bubble">
<legend>Feinstaubsensor Projekt</legend>
Das Feinstaubsensor Projekt ist ein deutschlandweites Projekt um den Feinstaubgehalt in der Luft
zu messen. Dieser Sensor kann recht einfach nach einer Anleitung
gebaut werden.</br> Die Messwerte werden f&uuml;r weitere Forschungen verwendet.</br>
<ul>
<li> <a href="http://luftdaten.info/feinstaubsensor-bauen/">Anleitung</a>
<li> <a href="http://deutschland.maps.luftdaten.info">Karte</a>.
</ul>
</fieldset>
<br>

EOM

for n in $(uci -q get fine-particle.sensors.id)
do

cat<<EOM
<fieldset class="bubble">
<legend>Feinstaubsensor $n</legend>
<img hight="$hight" width="$width" src="https://www.madavi.de/sensor/images/sensor-esp8266-$n-sds011-1-floating.png">
<img hight="$hight" width="$width" src="https://www.madavi.de/sensor/images/sensor-esp8266-$n-sds011-25-floating.png"></br>
<img hight="$hight" width="$width" src="https://www.madavi.de/sensor/images/sensor-esp8266-$n-dht-1-floating.png">
<img hight="$hight" width="$width" src="https://www.madavi.de/sensor/images/sensor-esp8266-$n-dht-25-floating.png"></br>

</fieldset>
EOM
done

. /usr/lib/www/page-post.sh

