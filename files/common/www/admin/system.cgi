#!/bin/sh

. /lib/functions.sh

export TITLE="Verwaltung > Expert > System"

. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<H2>$TITLE</H2>
<br>
EOM

if [ -z "$QUERY_STRING" ]; then

cat<<EOM
<FORM ACTION="system.cgi" ID="systemform" METHOD="POST">
<fieldset class="bubble">
<legend>Systemeinstellungen</legend>
<table class="nowrap">

<TR>
<TH>Community:</TH>
<TD colspan="2">
        <select name="form_community" size="1">
EOM

print_communities() {
#$1 - community entry 
#$2 - current community
	if [ "$1" = "$2" ]; then
		echo " <option selected value=\"$1\">$1</option>"
	else
		echo " <option value=\"$1\">$1</option>"
	fi
}
config_load ddmesh
config_list_foreach system communities print_communities "$(uci get ddmesh.system.community)"
cat<<EOM
        </select>
</TR>

<TR><TD COLSPAN="3">&nbsp;</TD></TR>

<TR TITLE="Setzt die Umgebungsvariable TZ zur Korrektur von Zeitangaben.">
<TH>Zeitzone:</TH>
<TD colspan="2"><INPUT NAME="form_tz" SIZE="48" TYPE="TEXT" VALUE="$(uci get system.@system[0].timezone)"><br>
 (Berlin:CET-1CEST,M3.5.0,M10.5.0/3) <a href="http://wiki.openwrt.org/doc/uci/system#time.zones">Zeitzonen</a></TD>
</TR>

<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR><TH COLSPAN="3" class="heading">Verbindungen zu diesen Router via WAN-Interface</TH></TR>

<TR>
<TH class="nowrap">- SSH erlauben:</TH>
<TD><INPUT NAME="form_wanssh" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.wanssh)" = "1" ];then echo ' checked="checked"';fi)></TD>
<td></td>
</TR>

<TR>
<TH>- HTTP erlauben:</TH>
<TD><INPUT NAME="form_wanhttp" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.wanhttp)" = "1" ];then echo ' checked="checked"';fi)></TD>
<td></td>
</TR>

<TR>
<TH>- HTTPS erlauben:</TH>
<TD><INPUT NAME="form_wanhttps" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.wanhttps)" = "1" ];then echo ' checked="checked"';fi)></TD>
<td></td>
</TR>

<TR>
<TH>- Ping erlauben:</TH>
<TD><INPUT NAME="form_wanicmp" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.wanicmp)" = "1" ];then echo ' checked="checked"';fi)></TD>
<td></td>
</TR>

<TR>
<TH>- Zugang zur Verwaltung erlauben:</TH>
<TD><INPUT NAME="form_wansetup" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.wansetup)" = "1" ];then echo ' checked="checked"';fi)></td>
<td><font color="#ff0000">&Auml;nderung nach &Uuml;bernahme sofort aktiv. Router-Reset via Verwaltung vom WAN ist nicht erreichbar.</font></TD>
</TR>

<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR><TH COLSPAN="3" class="heading">Verbindungen zu diesen Router vom Freifunk-Netz aus</TH></TR>

<TR>
<TH>- SSH erlauben:</TH>
<TD><INPUT NAME="form_wifissh" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.wifissh)" = "1" ];then echo ' checked="checked"';fi)></TD>
<td></td>
</TR>

<TR>
<TH>- Zugang zur Verwaltung erlauben:</TH>
<TD><INPUT NAME="form_wifisetup" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.wifisetup)" = "1" ];then echo ' checked="checked"';fi)></td>
<td><font color="#ff0000">&Auml;nderung nach &Uuml;bernahme sofort aktiv. Router-Reset via Verwaltung aus dem Freifunk-Netz ist nicht erreichbar.</font></TD>
</TR>


<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR><TH COLSPAN="3" class="heading">Netzwerk</TH></TR>

<TR>
<TH>- Eignes Internet direkt freigeben:</TH>
<TD><INPUT NAME="form_announce_gateway" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.announce_gateway)" = "1" ];then echo ' checked="checked"';fi)></td>
<td>Bei Nutzung des Openvpn Paketes, muss dieser Schalter DEAKTIVIERT bleiben, sonst wird der eigene DSL/Kabel Anschluss freigegeben.</TD>
</TR>
<TR>
<TH>- LAN verwendet Lokales Internet:</TH>
<TD><INPUT NAME="form_lan_local_internet" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.network.lan_local_internet)" = "1" ];then echo ' checked="checked"';fi)></TD>
<td></td>
</TR>
<TR>
<TH>- Bevorzugtes Gateway (IP):</TH>
<TD><INPUT NAME="form_lan_preferred_gateway" TYPE="TEXT" VALUE="$(uci -q get ddmesh.bmxd.preferred_gateway)"></TD>
<td>Angegebenes Gateway (z.B.: 10.200.0.1) wird bei Gatewayauswahl bevorzugt. Ein leeres Feld l&ouml;scht das bevorzugte Gateway.</td>
</TR>
<TR>
<TH>- Freifunk DNS (IP):</TH>
<TD><INPUT NAME="form_internal_dns" TYPE="TEXT" VALUE="$(uci -q get ddmesh.network.internal_dns)"></TD>
<td></td>
</TR>

<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR><TH COLSPAN="3" class="heading">Cron</TH></TR>

<TR>
<TH>- Automatisches Firmware Update:</TH>
<TD><INPUT NAME="form_firmware_autoupdate" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.firmware_autoupdate)" = "1" ];then echo ' checked="checked"';fi)></td>
<td>T&auml;glich 03:00 Uhr wird auf eine neue Firmwareversion getestet. Gibt es eine, so aktualisiert sich der Router selbst&auml;ndig. Nachtr&auml;glich installierted Pakete werden m&uuml;ssen erneut installiert werden.<td> 
</TR>


<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR>
<TD COLSPAN="3"><INPUT NAME="form_submit" ONCLICK="return validate(systemform);" TITLE="Die Einstellungen &uuml;bernehmen. Diese werden erst nach einem Neustart wirksam." TYPE="SUBMIT" VALUE="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<INPUT NAME="form_abort" TITLE="Abbruch dieser Dialogseite" TYPE="SUBMIT" VALUE="Abbruch"></TD>
</TR>

</TABLE>
</fieldset>
</FORM>
<br>
<P>
EOM

else

# process form abort or save 
	if [ -n "$form_submit" ]; then
		uci set ddmesh.system.community="$(uhttpd -d $form_community)"
		uci set ddmesh.system.wanssh=${form_wanssh:-0}
		uci set ddmesh.system.wanhttp=${form_wanhttp:-0}
		uci set ddmesh.system.wanhttps=${form_wanhttps:-0}
		uci set ddmesh.system.wanicmp=${form_wanicmp:-0}
		uci set ddmesh.system.wansetup=${form_wansetup:-0}
		uci set ddmesh.system.wifissh=${form_wifissh:-0}
		uci set ddmesh.system.wifisetup=${form_wifisetup:-0}
		uci set ddmesh.system.announce_gateway=${form_announce_gateway:-0}
		uci set ddmesh.network.lan_local_internet=${form_lan_local_internet:-0}
		uci set ddmesh.bmxd.preferred_gateway=$form_lan_preferred_gateway
		uci set ddmesh.system.firmware_autoupdate=${form_firmware_autoupdate:-0}
		uci set ddmesh.network.internal_dns=$form_internal_dns
		uci set ddmesh.boot.boot_step=2
		uci commit
		notebox  'Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst beim n&auml;chsten <A HREF="/admin/firmware.cgi">Neustart</A> aktiv.'
	else
		notebox  'Einstellungen wurden nicht &uuml;bernommen.'
	fi
fi

. /usr/lib/www/page-post.sh ${0%/*}
