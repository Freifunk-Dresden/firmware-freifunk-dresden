#!/bin/sh

export TITLE="Feinstaubsensor"
. /usr/lib/www/page-pre.sh
. /lib/functions.sh

config='fine-particle'

hight=240
width=380
columns=2

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

url=$(uci -q get fine-particle.sensors.url)

if [ -n "$url" ]; then

cat<<EOM
<fieldset class="bubble">
<legend>Feinstaubsensor $n</legend>
EOM

count=0
show() {
	local entry="$1"
	local id="$2" # user_arg
	local url="$3" # user_arg
	local sensor="${entry%% *}"
	local period="${entry#* }"

	count=$((count + 1))

	echo "<img hight=\"$hight\" width=\"$width\" src=\"$url-$id-$sensor-$period.png\" alt="$id-$sensor-$period">"
	test $((count % columns)) -eq 0 && echo "<br>"
	
}
config_load $config
config_get vid sensors id
config_get vurl sensors url 
config_list_foreach sensors entries show $vid $vurl

cat<<EOM
</fieldset>
EOM
else
	echo "Kein Sensor konfiguriert."
fi

. /usr/lib/www/page-post.sh

