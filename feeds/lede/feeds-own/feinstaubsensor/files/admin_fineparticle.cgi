#!/bin/sh

export TITLE="Verwaltung > Tools > Feinstaubsensor"
. /usr/lib/www/page-pre.sh ${0%/*}

width="200"

cat<<EOF
<script type="text/javascript"> 
function checkInput()                                                     
{                                                                         
	var sensor = document.getElementById('id_sensor').value;  
	if( sensor === undefined || checknumber(sensor) || sensor < 0)
	{                                                                                    
		alert("Falsche Sensor Id");
		return false;                                                                                    
	}                                                                                                        
	return true;                                                                                                     
}                                                                                                                        
</script>

<h2>$TITLE</h2>
<br>
EOF

if [ -n "$QUERY_STRING" ]; then

	if [ -n "$post_sensor" ]; then
		uci -q set fine-particle.sensors.id="$id_sensor"
		uci_commit.sh
		notbox "Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind sofort aktiv."
	fi

fi #query

cat<<EOF
<form action="fineparticle.cgi" method="POST" onsubmit="return checkInput();">
<fieldset class="bubble">
<legend>Feinstaubsensor Projekt</legend>
Das Feinstaubsensor Projekt ist ein deutschlandweites Projekt um den Feinstaubge
halt in der Luft
zu messen. Dieser Sensor kann recht einfach nach einer Anleitung
gebaut werden.</br> Die Messwerte werden f&uuml;r weitere Forschungen verwendet.
</br>
<ul>
<li> <a href="http://luftdaten.info/feinstaubsensor-bauen/">Anleitung</a>
<li> <a href="http://deutschland.maps.luftdaten.info">Karte</a>.
</ul>

<table>
<tr>
<th>Sensor&nbsp;Id:</th>
<td><input id="id_sensor" name="id_sensor" size="20" type="text" value="$(uci -q get fine-particle.sensors.id)" onkeypress="return isNumberKey(event);"></td>
<td><input name="post_sensor" type="submit" value="Save"></td>
<td style="width: 100%;"></td>
</tr>
</table>
</fieldset>
</form>
EOF

for n in $(uci -q get fine-particle.sensors.id)
do
cat<<EOM
<fieldset class="bubble">
<legend>Feinstaubsensor $n</legend>
<img width="$width" src="https://www.madavi.de/sensor/images/sensor-esp8266-$n-sds011-1-floating.png">
<img width="$width" src="https://www.madavi.de/sensor/images/sensor-esp8266-$n-sds011-25-floating.png"></br>
<img width="$width" src="https://www.madavi.de/sensor/images/sensor-esp8266-$n-dht-1-floating.png">
<img width="$width" src="https://www.madavi.de/sensor/images/sensor-esp8266-$n-dht-25-floating.png"></br>
</fieldset>
EOM
done

. /usr/lib/www/page-post.sh ${0%/*}
