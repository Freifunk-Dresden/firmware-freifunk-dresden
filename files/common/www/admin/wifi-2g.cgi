#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Konfiguration: WIFI 2.4GHz"

. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

if [ -z "$QUERY_STRING" ]; then

if [ "$(uci -q get ddmesh.network.wifi3_2g_network)" = "wan" ]; then
	checked_wan='checked="checked"'
else
	checked_lan='checked="checked"'
fi

# workaround to pass key with " and ' to input field
# javascript setWifi3_key reads content and assigns it to value of input field
wifi3_key="$(uci -q get credentials.wifi_2g.private_key)"
echo "<div style=\"visibility: hidden;\" id=\"wifi3_key\">$wifi3_key</div>"

cat<<EOM
<div id="status"></div>
<script type="text/javascript">
function enable_custom_essid(s) {
	var c=document.getElementsByName('form_wifi_custom_essid')[0].checked;
	document.getElementsByName('form_wifi_ap_ssid')[0].disabled= !c;
}
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

<form onsubmit="return checkInput();" name="form_wifi" action="wifi-2g.cgi" class="form" method="POST">
<fieldset class="bubble">
<legend>WiFi-Einstellungen</legend>
<table>

<tr><th>Freifunk-IP-Adresse:</th>
<td><input name="form_wifi_ip" size="32" type="text" value="$_ddmesh_ip" disabled></td>
</tr>

<tr><th>Freifunk-Netzmaske:</th>
<td><input name="form_wifi_netmask" size="32" type="text" value="$_ddmesh_netmask" disabled></td>
</tr>

<tr><th>Freifunk-DHCP Roaming:</th>
<td><input name="form_wifi2_roaming" TYPE="CHECKBOX"
$(if [ "$_ddmesh_wifi2roaming" != "1" ];then echo ' disabled';fi)
VALUE="1"$(if [ "$(uci -q get ddmesh.network.wifi2_roaming_enabled)" = "1" ];then echo ' checked="checked"';fi)> Aktiviert Roaming wenn m&ouml;glich (Knotennummer < 32767).</td></tr>

<tr><th>Freifunk-DHCP Bereich:</th>
<td><input name="form_wifi_dncp" size="32" type="text" value="$_ddmesh_wifi2dhcpstart - $_ddmesh_wifi2dhcpend" disabled> <br/>
Der Bereich von <b>$_ddmesh_wifi2FixIpStart</b> bis <b>$_ddmesh_wifi2FixIpEnd</b> kann an Ger&auml;te fest vergeben werden.
</tr>

<tr><th>Kanal:</th>
<td><input name="form_wifi_channel" size="32" type="text" value="$(uci get ddmesh.network.wifi_channel)" disabled></td>
</tr>

<tr><th>TX-Power:</th>
<td><select name="form_wifi_txpower" size="1">
$(iwinfo $wifi_status_radio2g_phy txpowerlist | awk '{if(match($1,"*")){sel="selected";v=$2;txt=$0}else{sel="";v=$1;txt=$0}; print "<option "sel" value=\""v"\">"txt"</option>"}')
</select> (konfiguriert: $(uci -q get ddmesh.network.wifi_txpower) dBm) <b>Aktuell:</b> $(iwinfo $wifi_status_radio2g_phy info | awk '/Tx-Power:/{print $2,$3}')</td>
</tr>
<tr><td></td><td><font color="red">Falsche oder zu hohe Werte k&ouml;nnen den Router zerst&ouml;ren!</font></td></tr>

EOM
if [ "$(uci -q get ddmesh.network.mesh_mode)" != "mesh" ]; then
cat<<EOM
<tr><th>Ad-hoc-SSID:</th>
<td><input name="form_wifi_adhoc_ssid" size="32" type="text" value="$(uci -q get wireless.wifi_adhoc.ssid)" disabled></td>
</tr>

<tr><th>BSSID:</th>
<td><input name="form_wifi_bssid" size="32" type="text" value="$(uci -q get credentials.wifi_2g.bssid)" disabled></td>
</tr>
EOM
fi
cat<<EOM

<tr><th></th><td></td></tr>
<tr><th>Access-Point-SSID:</th>
<TD class="nowrap"><INPUT NAME="form_wifi_ap_ssid_prefix" SIZE="16" TYPE="TEXT" VALUE="Freifunk $(uci -q get ddmesh.system.community)" disabled>
<INPUT onchange="enable_custom_essid();" NAME="form_wifi_custom_essid" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.network.custom_essid)" = "1" ];then echo ' checked="checked"';fi)>
<INPUT NAME="form_wifi_ap_ssid" SIZE="23" maxlength="15" TYPE="TEXT" VALUE="$(uci -q get ddmesh.network.essid_ap)"> aktuell: $(uci -q get wireless.wifi2_2g.ssid)</TD>
</tr>
<tr><th>Reduziere WLAN-Datenrate:</th><td><INPUT NAME="form_wifi_slow_rates" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.network.wifi_slow_rates)" = "1" ];then echo ' checked="checked"';fi)> (Nicht empfohlen. Wenn aktiviert, kann Reichweite auf Kosten der &Uuml;bertragungsrate erh&ouml;ht werden. Dies gilt auch f&uuml;r Verbindungen zu anderen Knoten.)</td></tr>

EOM
if [ "$wifi_status_radio2g_mode_ap" -gt 1 ]; then
cat <<EOM
<tr><td colspan="2"><hr size=1></td></tr>
<tr><th>Aktiviere privates WiFi:</th>
<td><INPUT onchange="enable_private_wifi();" id="id_wifi3_enabled" NAME="form_wifi3_enabled" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.network.wifi3_2g_enabled)" = "1" ];then echo ' checked="checked"';fi)>Erlaubt es, ein zusätzliches privates WiFi zu aktivieren.</td></tr>
<tr><th>SSID:</th>
<td><input id="id_wifi3_ssid" name="form_wifi3_ssid" size="32" type="text" value="$(uci -q get credentials.wifi_2g.private_ssid)"></td>
</tr>
<tr><th>Verschl&uuml;sselung:</th>
<td><INPUT onchange="enable_wifi_security();" id="id_wifi3_security" NAME="form_wifi3_security" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.network.wifi3_2g_security)" = "1" ];then echo ' checked="checked"';fi)>WPA2-PSK</td></tr>
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
<tr><th width="100" >Frequenz</th><th width="50">Sendeleistung</th><th>Modes</th></tr>
EOM

iw $wifi_status_radio2g_phy channels | awk '
				BEGIN{ RS="*";FS="\n" }
				(NR==1){next}
				{
								power=""
								radar=""
								width=""
								dfs_state=""
								dfs_cac=""
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
								printf("<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n",ch,power,width);
				}
'

cat << EOM
</table>
</fieldset>

<script type="text/javascript">
enable_custom_essid();
enable_private_wifi();
setWifi3_key();
</script>

EOM

else #query string

	if [ -n "$form_wifi_submit" ]; then
		if [ -n "$form_wifi_txpower" ]; then
			uci set ddmesh.network.wifi_txpower="$form_wifi_txpower"
			uci set ddmesh.network.wifi_diversity="$form_wifi_diversity"
			uci set ddmesh.network.wifi_rxantenna="$form_wifi_rxantenna"
			uci set ddmesh.network.wifi_txantenna="$form_wifi_txantenna"
			uci set ddmesh.network.essid_ap="$(uhttpd -d "$form_wifi_ap_ssid")"
			uci set ddmesh.network.custom_essid="$form_wifi_custom_essid"
			uci set ddmesh.network.wifi_slow_rates="$form_wifi_slow_rates"
			uci set ddmesh.network.wifi2_roaming_enabled="$form_wifi2_roaming"
			[ "$form_wifi2_roaming" = "1" ] && uci -q get ddmesh.system.disable_splash='1'

			uci set ddmesh.network.wifi3_2g_enabled="$form_wifi3_enabled"
			# avoid clearing values when disabled
			if [ "$form_wifi3_enabled" = 1 ]; then
				uci set ddmesh.network.wifi3_2g_network="$form_wifi3_network"
				uci set ddmesh.network.wifi3_2g_security="$form_wifi3_security"
				uci set credentials.wifi_2g.private_ssid="$(uhttpd -d "$form_wifi3_ssid")"
				uci set credentials.wifi_2g.private_key="$(uhttpd -d "$form_wifi3_key")"
			fi

			uci set ddmesh.boot.boot_step=2
			uci commit
			notebox "Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst beim n&auml;chsten <A HREF="reset.cgi">Neustart</A> aktiv."
		else #empty
			notebox "TX-Power falsch."
		fi #empty
	else #submit
		notebox "Es wurden keine Einstellungen ge&auml;ndert."

	fi #submit
fi #query string

. /usr/lib/www/page-post.sh ${0%/*}
