#!/bin/sh

export TITLE="Verwaltung > Expert > WIFI"
. $DOCUMENT_ROOT/page-pre.sh ${0%/*}

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi)

eval "$(cat /etc/openwrt_release)"
if [ ! "$DISTRIB_TARGET" = "brcm-2.4" ]; then
	MAX_TX_POWER=$(iw phy | sed -n '/\* 2412 MHz \[1\]/{s#.*(\([0-9]\+\).*#\1#; p}')
else
	MAX_TX_POWER=$(iwlist $net_device txpower | sed -n '2,${/Current/d;/^[	 ]*$/d;p}' | sed -n '$s#^[	 ]*\([0-9]\+\).*#\1#p')
fi

cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

if [ -z "$QUERY_STRING" ]; then

cat<<EOM
<script type="text/javascript">
function disable_fields(s) {
	var c=document.getElementsByName('form_wifi_diversity')[0].checked;
	document.getElementsByName('form_wifi_rxantenna')[0].disabled=c;
	document.getElementsByName('form_wifi_txantenna')[0].disabled=c;
}
</script>

<form name="form_wifi" action="wifi.cgi" class="form" method="POST">
<fieldset class="bubble">
<legend>Wifi-Einstellungen</legend>
<table>

<tr><th>Freifunk-IP:</th>
<td><input name="form_wifi_ip" size="32" type="text" value="$(uci get network.wifi.ipaddr)" disabled></td>
</tr>

<tr><th>Freifunk-Netmask:</th>
<td><input name="form_wifi_netmask" size="32" type="text" value="$(uci get network.wifi.netmask)" disabled></td>
</tr>

<tr><th>Kanal:</th>
<td><input name="form_wifi_channel" size="32" type="text" value="$(uci get ddmesh.network.wifi_channel)" disabled></td>
</tr>

<tr><th>TX Power:</th>
<td><input name="form_wifi_txpower" size="32" type="text" value="$(uci get ddmesh.network.wifi_txpower)"> dBm</td>
</tr>
<tr><td></td><td><font color="red">Falsche oder zu hohe Werte k&ouml;nnen den Router zerst&ouml;ren!</font></td></tr>

<!--
<tr><th>Antenne:</th>
<td><input onchange="disable_fields();" name="form_wifi_diversity" type="CHECKBOX" value="1" $(if [ "$(uci get ddmesh.network.wifi_diversity)" != "0" ];then echo ' checked="checked"';fi)>Automatisch</td>
</tr>
<tr><th></th><td>RX Antenne (Maske): <input name="form_wifi_rxantenna" size="2" MAXLENGTH="1" type="text" value="$(uci get ddmesh.network.wifi_rxantenna )" onkeypress="return isNumberKey(event)"></td></tr>
<tr><th></th><td>TX Antenne (Maske): <input name="form_wifi_txantenna" size="2" MAXLENGTH="1" type="text" value="$(uci get ddmesh.network.wifi_txantenna )" onkeypress="return isNumberKey(event)"></td></tr>
<tr><th></th><td>Bit-Maske: jedes bit steht f&uuml;r eine Antenne. z.B.: 1:Antenne 1; 2:Antenne 2; 4:Antenne 3;<br /> Oder 3:Antennen 1+2; 5-Antennen 1+3; 6:Antennen 2+3; 7:Antennen 1+2+3 </td></tr>
-->
<!-- distance, beacon_int, basic_rate -->


<tr><th>Adhoc-SSID:</th>
<td><input name="form_wifi_adhoc_ssid" size="32" type="text" value="$(uci get wireless.@wifi-iface[0].ssid)" disabled></td>
</tr>

<tr><th>BSSID:</th>
<td><input name="form_wifi_bssid" size="32" type="text" value="$(uci get ddmesh.network.bssid_adhoc)" disabled></td>
</tr>

<tr><th></th><td></td></tr>
<tr><th>Access Point-SSID:</th>
<TD class="nowrap"><INPUT NAME="form_wifi_ap_ssid_prefix" SIZE="16" TYPE="TEXT" VALUE="$(uci get ddmesh.system.community)" disabled><INPUT NAME="form_wifi_ap_ssid" SIZE="23" maxlength="15" TYPE="TEXT" VALUE="$(uci get ddmesh.network.essid_ap)"> aktuell: $(uci get wireless.@wifi-iface[1].ssid)</TD>
</tr>

<tr><th></th><td>Leeres Feld erzeugt ein vorgebenen Wert.</td></tr>

<tr><td colspan="2">&nbsp;</td></tr>
<tr>
<td colspan="2"><input name="form_wifi_submit" title="Die Einstellungen &uuml;bernehmen. Diese werden erst nach einem Neustart wirksam." type="submit" value="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<input name="form_wifi_abort" title="Abbruch dieser Dialogseite" type="submit" value="Abbruch"></td>
</tr>
</table>
</fieldset>
</form>
<br>

<fieldset class="bubble">
<legend>Info</legend>
<table>
<tr><th>Frequenz</th><th>Kanal</th><th>Maximale Sendeleistung</th></tr>
$(iw phy0 info | sed -n '/[      ]*\*[   ]*[0-9]* MHz/{s#[       *]\+\([0-9]\+\) MHz \[\([0-9]\+\)\] (\(.*\))#<tr><td>\1</td><td>\2</td><td>\3</td></tr>#;p}')
</table>
</fieldset>
EOM

else #query string

	if [ -n "$form_wifi_submit" ]; then
#		if [ -n "$form_wifi_channel" -a "$form_wifi_txpower" -le "$MAX_TX_POWER" ]; then
		if [ -n "$form_wifi_txpower" ]; then
			uci set ddmesh.network.wifi_txpower="$form_wifi_txpower"
			uci set ddmesh.network.wifi_diversity="$form_wifi_diversity"
			uci set ddmesh.network.wifi_rxantenna="$form_wifi_rxantenna"
			uci set ddmesh.network.wifi_txantenna="$form_wifi_txantenna"
			uci set ddmesh.network.essid_ap=$(uhttpd -d "$form_wifi_ap_ssid")
			uci set ddmesh.boot.boot_step=2
			uci commit
			notebox "Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst beim n&auml;chsten <A HREF="firmware.cgi">Neustart</A> aktiv."
		else #empty
			notebox "TXPower falsch"
		fi #empty
	else #submit
		notebox "Es wurden keine Einstellungen ge&auml;ndert."

	fi #submit
fi #query string

. $DOCUMENT_ROOT/page-post.sh ${0%/*}
