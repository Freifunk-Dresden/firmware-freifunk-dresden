#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Konfiguration: WIFI 5GHz"

. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

if [ -z "$QUERY_STRING" ]; then

if [ "$(uci -q get ddmesh.network.wifi3_5g_network)" = "wan" ]; then
	checked_wan='checked'
else
	checked_lan='checked'
fi

# workaround to pass key with " and ' to input field
# javascript setWifi3_key reads content and assigns it to value of input field
wifi3_key="$(uci -q get credentials.wifi_5g.private_key)"
echo "<div style=\"visibility: hidden;\" id=\"wifi3_key\">$wifi3_key</div>"
range=$(uci -q get ddmesh.network.wifi_channels_5g_outdoor)
wifi_5g_channels_min="${range%-*}"
wifi_5g_channels_max="${range#*-}"
cat<<EOM
<div id="status"></div>
<script type="text/javascript">
function enable_private_wifi(s) {
	var c=document.getElementsByName('form_wifi3_enabled')[0].checked;
	document.getElementsByName('form_wifi3_ssid')[0].disabled= !c;
	document.getElementsByName('form_wifi3_security')[0].disabled= !c;
	enable_wifi_security(s);
}
function enable_wifi_security(s) {
	var c1=document.getElementsByName('form_wifi3_enabled')[0].checked;
	var c2=document.getElementsByName('form_wifi3_security')[0].checked;
	document.getElementsByName('form_wifi3_key')[0].disabled= !c1 || !c2;
}
function setWifi3_key()
{
	var k = document.getElementById('wifi3_key');
	//use textContent because innerText is empty when div is invisible
	document.getElementById('id_wifi3_key').value = k.textContent;
}
function checkInput()
{
	var enabled = document.getElementById('id_wifi3_enabled').checked;
	var security = document.getElementById('id_wifi3_security').checked;

	if(enabled)
	{
		var key = document.getElementById('id_wifi3_key').value;
		var ssid = document.getElementById('id_wifi3_ssid').value;
		if(   ssid === undefined
			 || ( security &&
			( key === undefined || key.length < 8
				|| !checkWifiKey(document.getElementById('id_wifi3_key').value)))
			)
		{
			alert("Ungültige WiFi-Konfiguration!\nWiFi-Key/-SSID zu kurz oder enthält ungültige Zeichen.");
			return false;
		}
	}
	return true;
}
function fold_mode()
{
	if(document.getElementById('radio_wifi5g_mode_disabled').checked)
	{
		obj = document.getElementById('div_wifi5g_mode_normal').style.display = 'none';
		obj = document.getElementById('div_wifi5g_mode_client').style.display = 'none';
	}
	if(document.getElementById('radio_wifi5g_mode_normal').checked)
	{
		obj = document.getElementById('div_wifi5g_mode_normal').style.display = 'block';
		obj = document.getElementById('div_wifi5g_mode_client').style.display = 'none';
	}
	if(document.getElementById('radio_wifi5g_mode_client').checked)
	{
		obj = document.getElementById('div_wifi5g_mode_normal').style.display = 'none';
		obj = document.getElementById('div_wifi5g_mode_client').style.display = 'block';
	}
	return false;
}
</script>


<form onsubmit="return checkInput();" name="form_wifi" action="wifi-5g.cgi" class="form" method="POST">
<fieldset class="bubble">
<legend>WiFi-Einstellungen</legend>
<table>
<tr>
<td>
EOM
mode="$(uci -q get ddmesh.network.wifi5g_mode)"
for i in "disabled:Aus" "normal:Normal" "client:WAN"
do
	value=${i%:*}
	text=${i#*:}
	[ "$value" = "$mode" ] && checked="checked" || checked=""
	echo "<input onchange=\"fold_mode()\" name=\"form_wifi5g_mode\" type=\"radio\" value=\"${value}\" id=\"radio_wifi5g_mode_${value}\" $checked>${text}"
done
cat<<EOM
</td></tr>
</table>

<div id="div_wifi5g_mode_client">
<table>
<tr><td colspan="2"><hr size=1></td></tr>
<tr><th>SSID:</th>
<td><input name="form_wificlient_5g_ssid" size="32" type="text" value="$(uci -q get ddmesh.network.wificlient_5g_ssid)"></td>
</tr>
<tr><th>Verschl&uuml;sselung:</th>
<td><select name="form_wificlient_5g_encryption" size="1">
EOM

encr="$(uci -q get ddmesh.network.wificlient_5g_encryption)"
for i in "none:Offen" "psk2+ccmp:WPA2 Personal (PSK) CCMP" "psk2+tkip:WPA2 Personal (PSK) TKIP" "psk2+aes:WPA2 Personal (PSK) AES" "psk2+tkip+ccmp:WPA2 Personal (PSK) TKIP,CCMP" "psk2+tkip+aes:WPA2 Personal (PSK) TKIP,AES" "psk+ccmp:WPA Personal (PSK) CCMP" "psk+tkip:WPA Personal (PSK) TKIP" "psk+aes:WPA Personal (PSK) AES" "psk+tkip+ccmp:WPA Personal (PSK) TKIP,CCMP" "psk+tkip+aes:WPA Personal (PSK) TKIP,AES"
do
	enc="${i%:*}"
	text="${i#*:}"
	if [ "$encr" = "$enc" ]; then
		sel="selected"
		mark="*"
	else
		sel=""
		mark=" "
	fi
	echo "<option $sel value=\"$enc\">$mark $text</option>"
done
cat<<EOM
</select></td>
</tr>
<tr><th>Key</th>
<td><input name="form_wificlient_5g_key" type="text" value="$(uci -q get credentials.wificlient_5g.key)"> (optional)</td>
</tr>
<tr><th>Lokale MAC Addr</th>
<td><input name="form_wificlient_5g_macaddr" type="text" value="$(uci -q get credentials.wificlient_5g.macaddr)"> (optional)</td>
</tr>
</table>
</div>

<div id="div_wifi5g_mode_normal">
<table>
<tr><td colspan="2"><hr size=1></td></tr>
<tr>
<th>Router steht im Haus (Indoor):</th>
<td><input name="form_wifi_indoor" type="checkbox" value="1" $(if [ "$(uci -q get ddmesh.network.wifi_indoor_5g)" = 1 ];then echo 'checked="checked"';fi) ></td>
</tr>
<tr><th></th>
<td>
<font color="red">Einstellung darf nur gesetzt werden, wenn Router innerhalb eines Gebäudes steht!</font><br/>
Outdoor: automatische Kanalwahl aus Bereich f&uuml;r Outdoor; nur Access-Point<br/>
Indoor: fester Kanal; AccessPoint $([ "$wifi_status_radio5g_mode_mesh" -gt 0 ] && echo "und Mesh 802.11s")
</td>
</tr>
<tr><th></th><td></td></tr>
<tr><th>Meshing:</th>
<td>$(if [ "$wifi_status_radio5g_mode_mesh" -gt 0 ]; then echo "m&ouml;glich"; else echo "nicht unterst&uuml;tzt"; fi)</td>
</tr>

<tr><th>Indoor-Kanal:</th>
<td><input name="form_wifi_channel" size="32" type="text" value="$(uci -q get ddmesh.network.wifi_channel_5g)" disabled></td>
</tr>

<tr>
<th>Outdoor-Kanalbereich:</th>
<td>
<input name="form_wifi_channels_lower" size="15" type="number" min="$(uci -q get ddmesh.network.wifi_ch_5g_outdoor_min)" max="$(uci -q get ddmesh.network.wifi_ch_5g_outdoor_max)" step="4" value="$wifi_5g_channels_min">
-
<input name="form_wifi_channels_upper" size="15" type="number" min="$(uci -q get ddmesh.network.wifi_ch_5g_outdoor_min)" max="$(uci -q get ddmesh.network.wifi_ch_5g_outdoor_max)" step="4" value="$wifi_5g_channels_max">
</td>
</tr>

<tr><th>TX-Power:</th>
<td><select name="form_wifi_txpower" size="1">
$(echo "dummy" | awk -v cfg="$(uci -q get ddmesh.network.wifi_txpower_5g)" '{ for(v=1;v<=23;v++){ if(v==cfg){sel="selected";mark="* "}else{sel="";mark=""}; printf("<option %s value=\"%d\">%s%d dBm (%d mW)</option>\n",sel,v,mark,v,10^(v/10));}}')
</select> <b>Aktuell:</b> $(iwinfo $wifi_status_radio5g_phy info | awk '/Tx-Power:/{print $2,$3}')
</td>
</tr>
<tr><td></td><td><font color="red">Falsche oder zu hohe Werte k&ouml;nnen den Router zerst&ouml;ren!</font></td></tr>

<tr><th></th><td></td></tr>
<tr><th>Access-Point-SSID:</th>
<TD class="nowrap">$(uci -q get wireless.wifi2_5g.ssid)</TD>
</tr>

EOM
if [ "$wifi_status_radio5g_mode_ap" -gt 1 ]; then
cat <<EOM
<tr><td colspan="2"><hr size=1></td></tr>
<tr><th>Aktiviere privates WiFi:</th>
<td><INPUT onchange="enable_private_wifi();" id="id_wifi3_enabled" NAME="form_wifi3_enabled" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.network.wifi3_5g_enabled)" = "1" ];then echo ' checked="checked"';fi)>Erlaubt es, ein zusätzliches privates WiFi zu aktivieren.</td></tr>
<tr><th>SSID:</th>
<td><input id="id_wifi3_ssid" name="form_wifi3_ssid" size="32" type="text" value="$(uci -q get credentials.wifi_5g.private_ssid)"></td>
</tr>
<tr><th>Verschl&uuml;sselung:</th>
<td><INPUT onchange="enable_wifi_security();" id="id_wifi3_security" NAME="form_wifi3_security" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.network.wifi3_5g_security)" = "1" ];then echo ' checked="checked"';fi)>WPA2-PSK</td></tr>
<tr><th>Key (mind. 8 Zeichen):</th>
<td><input onkeypress="return isWifiKey(event);" id="id_wifi3_key" name="form_wifi3_key" width="30" type="text"></td>
</tr>
<tr><th>Verbinde WiFi mit:</th><td class="nowrap">
<input name="form_wifi3_network" type="radio" value="lan" $checked_lan>LAN
<input name="form_wifi3_network" type="radio" value="wan" $checked_wan>WAN
</td></tr>
EOM
fi
cat <<EOM
</table>
</div>

<table>
<tr><td colspan="2">&nbsp;</td></tr>
<tr>
<td colspan="2"><input name="form_wifi_submit" title="Die Einstellungen &uuml;bernehmen. Diese werden erst nach einem Neustart wirksam." type="submit" value="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<input name="form_wifi_abort" title="Abbrechen und &Auml;nderungen verwerfen." type="submit" value="Abbrechen"></td>
</tr>
</table>

</fieldset>
</form>
<br>

<fieldset class="bubble">
<legend>Kanal-Info</legend>
<table>
<tr><th width="100" >Frequenz</th><th width="50">Sendeleistung</th><th>Modes</th><th width="50">Radar</th><th width="100">Nutzbar seit</th><th width="50">DFS CAC</th></tr>
EOM

iw $wifi_status_radio5g_phy channels | awk '
	BEGIN{ RS="*";FS="\n" }
	(NR==1){next}
	{
		power=""
		radar=""
		width=""
		dfs_state=""
		dfs_cac=""
		usable=""
		wait=""
		for( f=1; f<NF;f++)
		{
			split($(f),a,":")
			if(f==1) ch=$(f)
			if($(f) ~ /TX power/) power=a[2]
			if($(f) ~ /Radar/) radar="Radar"
			if($(f) ~ /Channel widths/) width=a[2]
			if($(f) ~ /DFS state/) dfs_state=a[2]
			if($(f) ~ /DFS CAC/) dfs_cac=a[2]
		}
		if(length(dfs_state))
		{
			split(dfs_state,_t," ")
			t=_t[3];s=(t%60);m=(t/60)%60;h=(t/3600)%24;d=(t/3600/24)
			usable=sprintf("%02ud:%02uh:%02um:%02us",d,h,m,s)
		}
		if(length(dfs_cac))
		{
			split(dfs_cac,_t," ")
			t=_t[1]/1000;s=(t%60);m=(t/60)
			wait=sprintf("%02um:%02us",m,s)
		}

		printf("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n", ch, power, width, radar, usable, wait);
	}
'

cat << EOM
</table>
</fieldset>

<script type="text/javascript">
fold_mode();
enable_private_wifi();
setWifi3_key();
</script>

EOM

else #query string

	if [ -n "$form_wifi_submit" ]; then

		[ -z "$form_wifi_txpower" ] && form_wifi_txpower="$(uci -q get ddmesh.network.wifi_txpower_5g)"

		uci set ddmesh.network.wifi5g_mode="$form_wifi5g_mode"
		uci set ddmesh.network.wifi_txpower_5g="$form_wifi_txpower"
		uci set ddmesh.network.wifi_indoor_5g="$form_wifi_indoor"
		if [ "$form_wifi_channels_lower" -gt "$form_wifi_channels_upper" ]; then
			uci set ddmesh.network.wifi_channels_5g_outdoor="$form_wifi_channels_upper-$form_wifi_channels_lower"
		else
			uci set ddmesh.network.wifi_channels_5g_outdoor="$form_wifi_channels_lower-$form_wifi_channels_upper"
		fi

		uci set ddmesh.network.wifi3_5g_enabled="$form_wifi3_enabled"
		# avoid clearing values when disabled
		if [ "$form_wifi3_enabled" = 1 ]; then
			uci set ddmesh.network.wifi3_5g_network="$form_wifi3_network"
			uci set ddmesh.network.wifi3_5g_security="$form_wifi3_security"
			uci set credentials.wifi_5g.private_ssid="$(uhttpd -d "$form_wifi3_ssid")"
			uci set credentials.wifi_5g.private_key="$(uhttpd -d "$form_wifi3_key")"
		fi

		uci set ddmesh.network.wificlient_5g_ssid="$(uhttpd -d "$form_wificlient_5g_ssid")"
		uci set ddmesh.network.wificlient_5g_encryption="$(uhttpd -d "$form_wificlient_5g_encryption")"
		uci set credentials.wificlient_5g.key="$(uhttpd -d "$form_wificlient_5g_key")"
		uci set credentials.wificlient_5g.macaddr="$(uhttpd -d "$form_wificlient_5g_macaddr")"

		uci set ddmesh.boot.boot_step=2
		uci commit
		notebox "Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst beim n&auml;chsten <A HREF="reset.cgi">Neustart</A> aktiv."

	else #submit
		notebox "Es wurden keine Einstellungen ge&auml;ndert."
	fi #submit

fi #query string

. /usr/lib/www/page-post.sh ${0%/*}
