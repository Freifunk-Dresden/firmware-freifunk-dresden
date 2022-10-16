#!/bin/sh

export TITLE="Verwaltung > Tools > Feinstaubsensor"
. /usr/lib/www/page-pre.sh ${0%/*}
. /lib/functions.sh

config='fine-particle'
hight=200
width=320
columns=2


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
function form_submit (form,action,entry)
{
        form.form_action.value=action;
        form.form_entry.value=entry;
	form.submit();
}
</script>

<h2>$TITLE</h2>
<br>
EOF

if [ -n "$QUERY_STRING" ]; then

	case "$form_action" in
		add)
			entry="$form_data_sensor $form_data_period"
			uci add_list fine-particle.sensors.entries="$entry"
			uci commit
			;;
		del)
			entry="$(uhttpd -d $form_entry)"
			uci del_list fine-particle.sensors.entries="$entry"
			uci commit
			;;
	esac

	if [ -n "$post_sensor" ]; then
		uci -q set fine-particle.sensors.id="$id_sensor"
		uci commit
		notbox "Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind sofort aktiv."
	fi

fi #query

cat<<EOM
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
EOM

cat<<EOM
</tr>
</table>
</fieldset>
</form>
EOM

# ----------------
config_load $config


# lookups
lookupHelper()
{
	local entry="$1"
	local toSearch="$2"
	local key=${entry%% *}
	local text=${entry#* }
	if [ "$key" = "$toSearch" ]; then
		echo "$text"
	fi
}
lookupSensor()
{
 toSearch="$1"
 config_list_foreach gui sensors lookupHelper $toSearch
}
lookupPeriod()
{
 toSearch="$1"
 config_list_foreach gui periods lookupHelper $toSearch
}

show_one_form()
{
	local entry="$1"
	local sensor="${entry%% *}"
	local period="${entry#* }"

	echo "<tr class=\"colortoggle$T\" >"
	echo "<td>$(lookupSensor $sensor)</td>"
	echo "<td>$(lookupPeriod $period)</td>"
	echo "<td><button onclick=\"form_submit(document.forms.form_sensor,'del','$entry')\" name=\"form_btn_del\" title=\"Sensor l&ouml;schen\" type=\"button\"><img src="/images/loeschen.gif" align=bottom width=16 height=16 hspace=4></button>"
	echo "</td></tr>"

	if [ $T = 1 ]; then T=2 ;else T=1; fi
	C=$(($C+1))
}

# gui select
guiSelectHelper()
{
 local entry="$1"
 local key=${entry%% *}
 local text=${entry#* }
 echo "<option value=\"$key\">$text</option>"
}
show_forms()
{
 T=1
 C=0
 config_list_foreach sensors entries show_one_form

 # new
 echo "<tr class=\"colortoggle$T\" >"
 echo "<td><select name=\"form_data_sensor\" size=\"1\"\">"
 config_list_foreach gui sensors guiSelectHelper
 echo "</select></td>"
 echo "<td><select name=\"form_data_period\" size=\"1\"\">"
 config_list_foreach gui periods guiSelectHelper
 echo "</select></td>"
 echo "<td><button onclick=\"form_submit(document.forms.form_sensor,'add','none')\" name=\"form_btn_add\" title=\"Sensor anlegen\" type=\"button\">Sensor anlegen</button>"
 echo "</td></tr>"
}


cat<<EOM
<fieldset class="bubble">
<legend>Feinstaubsensoren</legend>
<form name="form_sensor" action="fineparticle.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<table>
<tr><th>Sensortyp</th><th>Periode</th><th></th></tr>
EOM

show_forms

cat<<EOM
</table>
</form>
</fieldset>
EOM

# ----------------

cat<<EOM
<fieldset class="bubble">
<legend>Feinstaubsensor $n</legend>
EOM

count=0
show_img() {
	local entry="$1"
	local id="$2" # user_arg
	local url="$3" # user_arg
	local sensor="${entry%% *}"
	local period="${entry#* }"

	count=$((count + 1))

	echo "<img hight=\"$hight\" width=\"$width\" src=\"$url-$id-$sensor-$period.png\" alt="$id-$sensor-$period">"
	test $((count % columns)) -eq 0 && echo "<br>"

}
config_get vid sensors id
config_get vurl sensors url
config_list_foreach sensors entries show_img $vid $vurl

cat<<EOM
</fieldset>
EOM

. /usr/lib/www/page-post.sh ${0%/*}
