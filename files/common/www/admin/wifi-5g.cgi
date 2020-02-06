#!/bin/sh

export TITLE="Verwaltung &gt; Konfiguration: WIFI 5GHz"

. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

if [ -z "$QUERY_STRING" ]; then

cat<<EOM

<form onsubmit="return checkInput();" name="form_wifi" action="wifi.cgi" class="form" method="POST">
<fieldset class="bubble">
<legend>WiFi-Einstellungen</legend>
<table>

<tr><th>Kanal:</th>
<td><input name="form_wifi_channel" size="32" type="text" value="$(uci get ddmesh.network.wifi_channel_5g)"></td>
</tr>

<tr><th>TX-Power:</th>
<td><select name="form_wifi_txpower" size="1">
$(iwinfo $wifi_status_radio5g_phy txpowerlist | awk '{if(match($1,"*")){sel="selected";v=$2;txt=$0}else{sel="";v=$1;txt=$0}; print "<option "sel" value=\""v"\">"txt"</option>"}')
</select> (konfiguriert: $(uci get ddmesh.network.wifi_txpower_5g) dBm) <b>Aktuell:</b> $(iwinfo $wifi_status_radio5g_phy info | awk '/Tx-Power:/{print $2,$3}')</td>
</tr>
<tr><td></td><td><font color="red">Falsche oder zu hohe Werte k&ouml;nnen den Router zerst&ouml;ren!</font></td></tr>

<tr><th></th><td></td></tr>
<tr><th>Access-Point-SSID:</th>
<TD class="nowrap">$(uci get wireless.@wifi-iface[1].ssid)</TD>
</tr>

<tr><td colspan="2"><hr size=1></td></tr>

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
$(iw $wifi_status_radio5g_phy info | sed -n '/[      ]*\*[   ]*[0-9]* MHz/{s#[       *]\+\([0-9]\+\) MHz \[\([0-9]\+\)\] (\(.*\))#<tr><td>\1</td><td>\2</td><td>\3</td></tr>#;p}')
</table>
</fieldset>

EOM

else #query string

	if [ -n "$form_wifi_submit" ]; then
		if [ -n "$form_wifi_txpower" ]; then
			uci set ddmesh.network.wifi_channel_5g="$form_wifi_channel"
			uci set ddmesh.network.wifi_txpower_5g="$form_wifi_txpower"
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
