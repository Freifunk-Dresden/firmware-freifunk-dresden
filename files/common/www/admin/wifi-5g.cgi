#!/bin/sh

export TITLE="Verwaltung &gt; Konfiguration: WIFI 5GHz"

. /usr/lib/www/page-pre.sh ${0%/*}
eval $(/usr/lib/ddmesh/ddmesh-utils-wifi-info.sh)

cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

if [ -z "$QUERY_STRING" ]; then

if [ "$(uci -q get ddmesh.network.wifi3_5g_network)" = "wan" ]; then
	checked_wan='checked="checked"'
else
	checked_lan='checked="checked"'
fi

# workaround to pass key with " and ' to input field
# javascript setWifi3_key reads content and assigns it to value of input field
wifi3_key="$(uci get credentials.wifi_5g.private_key)"
echo "<div style=\"visibility: hidden;\" id=\"wifi3_key\">$wifi3_key</div>"

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
</script>

<form onsubmit="return checkInput();" name="form_wifi" action="wifi-5g.cgi" class="form" method="POST">
<fieldset class="bubble">
<legend>WiFi-Einstellungen</legend>
<table>

<tr>
<th>Router steht Indoor</th>
<td><input name="form_wifi_indoor" id="id_wifi_indoor" type="checkbox" value="1" $(if [ "$(uci -q get ddmesh.network.wifi_indoor_5g)" = 1 ];then echo 'checked="checked"';fi) ></td>
</tr>

<tr><th>Indoor-Kanal:</th>
<td><input name="form_wifi_channel" size="32" type="text" value="$(uci get ddmesh.network.wifi_channel_5g)" disabled></td>
</tr>

<tr>
<th>Outdoor-Kanalbereich:</th>
<td><input name="form_wifi_channels" size="32" type="text" value="$(uci get ddmesh.network.wifi_channels_5g_outdoor)"></td>
</tr>

<tr><th>TX-Power:</th>
<td><select name="form_wifi_txpower" size="1">
$(iwinfo $wifi_status_radio5g_phy txpowerlist | awk '{if(match($1,"*")){sel="selected";v=$2;txt=$0}else{sel="";v=$1;txt=$0}; print "<option "sel" value=\""v"\">"txt"</option>"}')
</select> (konfiguriert: $(uci get ddmesh.network.wifi_txpower_5g) dBm) <b>Aktuell:</b> $(iwinfo $wifi_status_radio5g_phy info | awk '/Tx-Power:/{print $2,$3}')</td>
</tr>
<tr><td></td><td><font color="red">Falsche oder zu hohe Werte k&ouml;nnen den Router zerst&ouml;ren!</font></td></tr>

<tr><th></th><td></td></tr>
<tr><th>Access-Point-SSID:</th>
<TD class="nowrap">$(uci get wireless.@wifi-iface[2].ssid)</TD>
</tr>

<tr><td colspan="2"><hr size=1></td></tr>

<tr><th>Aktiviere privates WiFi:</th>
<td><INPUT onchange="enable_private_wifi();" id="id_wifi3_enabled" NAME="form_wifi3_enabled" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.network.wifi3_5g_enabled)" = "1" ];then echo ' checked="checked"';fi)>Erlaubt es, ein zusätzliches privates WiFi zu aktivieren.</td></tr>
<tr><th>SSID:</th>
<td><input id="id_wifi3_ssid" name="form_wifi3_ssid" size="32" type="text" value="$(uci get credentials.wifi_5g.private_ssid)"></td>
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
<tr><th>Frequenz</th><th>Kanal</th><th>Maximale Sendeleistung</th></tr>
$(iw $wifi_status_radio5g_phy info | sed -n '/[      ]*\*[   ]*[0-9]* MHz/{s#[       *]\+\([0-9]\+\) MHz \[\([0-9]\+\)\] (\(\([0-9.]\+\) \(dBm\)\))(*\(.*\))*#<tr><td>\1 MHz</td><td>\2</td><td>\4 \5\6</td></tr>#;p}')
</table>
</fieldset>

<script type="text/javascript">
enable_private_wifi();
setWifi3_key();
</script>

EOM

else #query string

	if [ -n "$form_wifi_submit" ]; then
		if [ -n "$form_wifi_txpower" ]; then
			uci set ddmesh.network.wifi_txpower_5g="$form_wifi_txpower"
			uci set ddmesh.network.wifi_indoor_5g="$form_wifi_indoor"
			uci set ddmesh.network.wifi_channels_5g_outdoor="$form_wifi_channels"
			
			uci set ddmesh.network.wifi3_5g_enabled="$form_wifi3_enabled"
			# avoid clearing values when disabled
			if [ "$form_wifi3_enabled" = 1 ]; then
				uci set ddmesh.network.wifi3_5g_network="$form_wifi3_network"
				uci set ddmesh.network.wifi3_5g_security="$form_wifi3_security"
				uci set credentials.wifi_5g.private_ssid="$(uhttpd -d "$form_wifi3_ssid")"
				uci set credentials.wifi_5g.private_key="$(uhttpd -d "$form_wifi3_key")"
			fi

			uci set ddmesh.boot.boot_step=2
			uci_commit.sh
			notebox "Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst beim n&auml;chsten <A HREF="reset.cgi">Neustart</A> aktiv."
		else #empty
			notebox "TX-Power falsch."
		fi #empty
	else #submit
		notebox "Es wurden keine Einstellungen ge&auml;ndert."

	fi #submit
fi #query string

. /usr/lib/www/page-post.sh ${0%/*}
