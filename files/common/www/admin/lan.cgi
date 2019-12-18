#!/bin/sh

export TITLE="Verwaltung &gt; Konfiguration: LAN"
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<h2>$TITLE</h2>
<br>
EOM

if [ -z "$QUERY_STRING" ]; then
	eval $(ipcalc.sh $(uci get network.lan.ipaddr) $(uci get network.lan.netmask))
	cat<<EOM
<form name="form_lan" action="lan.cgi" class="form" method="POST">
<fieldset class="bubble">
<legend>LAN-Einstellungen</legend>
<table>
<tr><th colspan="2">Achtung, falsche Werte k&ouml;nnen den Zugang &uuml;ber den LAN-Anschluss verhindern.<br>
LAN- und WAN-IP-Adressen/-Bereiche sollten sich nicht &uuml;berschneiden!</th></tr>
<tr><td colspan="2">&nbsp;</td></tr>
<tr>
<th>LAN-IP-Adresse:</th>
<td><input name="form_lan_ip" size="32" type="text" value="$(uci get network.lan.ipaddr)"></td>
</tr>
<tr>
<th>LAN-Netzmaske:</th>
<td><input name="form_lan_netmask" size="32" type="text" value="$(uci get network.lan.netmask)"></td>
</tr>
<tr>
<th>LAN-Gateway:</th>
<td><input name="form_lan_gateway" size="32" type="text" value="$(uci get network.lan.gateway)"></td>
</tr>
<tr>
<th>LAN-DNS-IP-Adresse:</th>
<td><input name="form_lan_dns" size="32" type="text" value="$(uci get network.lan.dns)"></td>
</tr>


<TR><TD COLSPAN="2"></TD></TR>

<TR TITLE="Startwert f&uuml;r die per DHCP zugewiesenen IP-Adressen.">
<TH>DHCP-Start-IP-Adresse:</TH>
<TD>$(echo $NETWORK|cut -d'=' -f2|cut -d'.' -f1-3).<INPUT NAME="form_dhcp_offset" SIZE="6" TYPE="TEXT" VALUE="$(uci get ddmesh.network.dhcp_lan_offset)"></TD>
</TR>

<TR TITLE="Anzahl der vom DHCP-Server verwalteten IP-Adressen. Die Summe aus Startwert und Anzahl sollte kleiner als 255 sein.">
<TH>DHCP-Benutzeranzahl:</TH>
<TD><INPUT NAME="form_dhcp_limit" SIZE="6" TYPE="TEXT" VALUE="$(uci get ddmesh.network.dhcp_lan_limit)">(DHCP-Server abschalten mit &quot;0&quot;)</TD>
</TR>

<TR TITLE="Zeit (in Stunden), nach der eine zuvor belegte IP-Adresse neu vergeben werden kann. F&uuml;r die Vorgabe von 12 Stunden (43200) das Eingabefeld leer oder auf 0 lassen.">
<TH>DHCP-Lease-Dauer:</TH>
<TD><INPUT NAME="form_dhcp_lease" SIZE="6" TYPE="TEXT" VALUE="$(uci get ddmesh.network.dhcp_lan_lease)">(h-Stunden, s-Sekunden)</TD>
</TR>

<TR><TD COLSPAN="2">&nbsp;</TD></TR>

<TR>
<TD COLSPAN="2"><INPUT NAME="form_lan_submit" TITLE="Die Einstellungen &uuml;bernehmen. Diese werden erst nach einem Neustart wirksam." TYPE="SUBMIT" VALUE="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<INPUT NAME="form_lan_abort" TITLE="Abbrechen und &Auml;nderungen verwerfen." TYPE="SUBMIT" VALUE="Abbrechen"></TD>
</TR>
</table>
</fieldset>
</form>
EOM

else #query string

	if [ -n "$form_lan_submit" ]; then
		if [ -n "$form_lan_ip" -a -n "$form_lan_netmask" ]; then
			uci set network.lan.ipaddr="$form_lan_ip"
			uci set network.lan.netmask="$form_lan_netmask"
			uci set network.lan.gateway="$form_lan_gateway"
			uci set network.lan.dns="$form_lan_dns"
			uci set ddmesh.network.dhcp_lan_offset="$form_dhcp_offset"
			uci set ddmesh.network.dhcp_lan_limit="$form_dhcp_limit"
			uci set ddmesh.network.dhcp_lan_lease="$form_dhcp_lease"
			uci set ddmesh.boot.boot_step=2	#let update fw
			uci_commit.sh
			notebox "Die Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst nach dem n&auml;chsten <a href="reset.cgi">Neustart</a> aktiv."
		else #empty
			notebox "IP-Adresse oder Netzmaske sind falsch."
		fi #empty
	else #submit
		notebox "Es wurden keine Einstellungen ge&auml;ndert."

	fi #submit
fi #query string

. /usr/lib/www/page-post.sh ${0%/*}
