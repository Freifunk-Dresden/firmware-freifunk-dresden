#!/bin/sh

export TITLE="Verwaltung > Expert > WAN"
. /usr/lib/www/page-pre.sh ${0%/*}

if [ -x /usr/sbin/pppd ]; then
 PPP=true
else
 PPP=false
fi

cat<<EOM
<script type="text/javascript">
  function disable_fields(s) {
     var s=document.getElementsByName('form_wan_proto')[0].value;
     var d;

     d = (s=="dhcp" || s=="pppoe") ? true : false;
     document.getElementsByName('form_wan_ip')[0].disabled=d;
     document.getElementsByName('form_wan_netmask')[0].disabled=d;
     document.getElementsByName('form_wan_gateway')[0].disabled=d;
     document.getElementsByName('form_wan_dns')[0].disabled=d;
EOM
$PPP && {
cat<<EOM
     d = (s=="pppoe") ? false : true;
     document.getElementsByName('form_pppoe_username')[0].disabled=d;
     document.getElementsByName('form_pppoe_password')[0].disabled=d;
     document.getElementsByName('form_pppoe_ac')[0].disabled=d;
     document.getElementsByName('form_pppoe_service')[0].disabled=d;
     document.getElementsByName('form_pppoe_mtu')[0].disabled=d;
EOM
}
cat<<EOM
}
</script>
<H2>$TITLE</H2>
<br>
EOM

# get network settings from config or dhcp
wan_proto="$(uci get network.wan.proto)"
if [ "$wan_proto" = "static" ];then

	wan_ipaddr="$(uci get network.wan.ipaddr)"
	wan_netmask="$(uci get network.wan.netmask)"
	wan_gateway="$(uci get network.wan.gateway)"
	wan_dns="$(uci get network.wan.dns)"
fi

# wan interface present?
if [ "$wan_iface_present" = "1" ]; then

if [ -z "$QUERY_STRING" ]; then

cat<<EOM
<FORM ACTION="wan.cgi" METHOD="POST">
<fieldset class="bubble">
<legend>WAN-Einstellungen</legend>
<table>

<TR>
<TH>WAN-Protokoll:</TH>
<TD><SELECT name="form_wan_proto" onchange="disable_fields();">
<OPTION VALUE='dhcp' $(test "$wan_proto" = "dhcp" && echo "selected=selected")>DHCP-Server abfragen</OPTION>
<OPTION VALUE='static' $(test "$wan_proto" = "static" && echo "selected=selected")>Statisch</OPTION>
EOM
$PPP && {
cat<<EOM
<OPTION VALUE='pppoe' $(test "$wan_proto" = "pppoe" && echo "selected=selected")>PPPoE</OPTION>
EOM
}
cat<<EOM
</SELECT> </TD>
</TR>

<TR TITLE="Dies ist die IP-Adresse des Internet-Anschlusses (RJ45).">
<TH>WAN-IP:</TH>
<TD><INPUT NAME="form_wan_ip" SIZE="32" TYPE="TEXT" VALUE="$wan_ipaddr"$(if [ "$wan_proto" != "static" ];then echo ' disabled="disabled"';fi)></TD>
</TR>

<TR TITLE="Die Netzmaske bestimmt, welche drahtgebundenen IP-Adressen am Internet-Anschluss direkt erreicht werden k&ouml;nnen.">
<TH>WAN-Netzmaske:</TH>
<TD><INPUT NAME="form_wan_netmask" SIZE="32" TYPE="TEXT" VALUE="$wan_netmask"$(if [ "$wan_proto" != "static" ];then echo ' disabled="disabled"';fi)></TD>
</TR>

<TR TITLE="Default-Route f&uuml;r den Internet-Anschluss.">
<TH>WAN-Gateway:</TH>
<TD><INPUT NAME="form_wan_gateway" SIZE="32" TYPE="TEXT" VALUE="$wan_gateway"$(if [ "$wan_proto" != "static" ];then echo ' disabled="disabled"';fi)></TD>
</TR>

<TR TITLE="DNS-Server f&uuml;r den Internet-Anschluss.">
<TH>WAN-DNS-IP:</TH>
<TD><INPUT NAME="form_wan_dns" SIZE="32" TYPE="TEXT" VALUE="$wan_dns"$(if [ "$wan_proto" != "static" ];then echo ' disabled="disabled"';fi)></TD>
</TR>
EOM

$PPP && {

cat<<EOM
<TR><TD COLSPAN="2">&nbsp;<hr size=1></TD></TR>

<TR TITLE="Benutzernamen des Internet-Zugangs eingeben.z.B.:1und1/1234-567@online.de">
<TH>Benutzername:</TH>
<TD><INPUT NAME="form_pppoe_username" SIZE="48" TYPE="TEXT" VALUE="$(uci -P /var/state get network.wan.username)"></TD>
</TR>

<TR TITLE="Kennwort des Internet-Zugangs eingeben.">
<TH>Kennwort:</TH>
<TD><INPUT NAME="form_pppoe_password" SIZE="48" TYPE="PASSWORD" VALUE="$(uci -P /var/state get network.wan.password)"></TD>
</TR>


<TR TITLE="Option: ID der Gegenstation, im Regelfall das Eingabefeld leer lassen.">
<TH>Access-Concentrator:</TH>
<TD><INPUT NAME="form_pppoe_ac" SIZE="48" TYPE="TEXT" VALUE="$(uci -P /var/state get network.wan.ac)"></TD>
</TR>

<TR TITLE="Option: ID des DSL-Modems wenn mehrere DSL-Modems vorhanden sind. Im Regelfall das Eingabefeld leer lassen.">
<TH>Service-Name:</TH>
<TD><INPUT NAME="form_pppoe_service" SIZE="48" TYPE="TEXT" VALUE="$(uci -P /var/state get network.wan.service)"></TD>
</TR>

<TR TITLE="Option: Maximale &Uuml;bertragungs-Paketgr&ouml;&szlig;e, im Regelfall den Vorgabewert von 1500 verwenden. Bei Verbindungsproblemen zu einigen Websites kann dieser Wert verringert werden, z.B. auf 1492.">
<TH>MTU:</TH>
<TD><INPUT MAXLENGTH="4" NAME="form_pppoe_mtu" SIZE="48" TYPE="TEXT" VALUE="$(uci -P /var/state get network.wan.mtu)"></TD>
</TR>
EOM
}
cat<<EOM
<TR><TD COLSPAN="2">&nbsp;</TD></TR>
<TR> <TD COLSPAN="2"><INPUT NAME="form_submit" TITLE="Die Einstellungen &uuml;bernehmen. Diese werden erst nach einem Neustart wirksam." TYPE="SUBMIT" VALUE="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<INPUT NAME="form_abort" TITLE="Abbruch dieser Dialogseite" TYPE="SUBMIT" VALUE="Abbruch"></TD> </TR>

</TABLE>
</fieldset>
</form>

<script type="text/javascript">
disable_fields();
</script>
EOM


else # query_sring

	if [ -n "$form_submit" ]; then
		uci set network.wan.proto=$form_wan_proto
		uci set network.wan.ipaddr=$form_wan_ip
		uci set network.wan.netmask=$form_wan_netmask
		uci set network.wan.gateway=$form_wan_gateway
		uci set network.wan.dns=$form_wan_dns
		$PPP && {
		 uci set network.wan.username=$form_pppoe_username
		 uci set network.wan.password=$form_pppoe_password
		 uci set network.wan.ac=$form_pppoe_ac
		 uci set network.wan.service=$form_pppoe_service
		 uci set network.wan.mtu=$form_pppoe_mtu
		}
		uci_commit.sh

		notebox "Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst beim n&auml;chsten <A HREF="reset.cgi">Neustart</A> aktiv."
	else

		notebox "Es wurden keine Einstellungen ge&auml;ndert."
	fi
fi

else #wan interface
	notebox "Es ist kein WAN Anschlu&szlig; verf&uuml;gbar"
	cat<<EOM
<br/>
Um den Router mit dem Internet zu verbinden, m&uuml;ssen in den LAN Einstellungen eine freie IP Adresse aus dem lokalen Netz,
 die Gateway IP und eine DNS IP eingetragen werden. Die DNS IP kann auch der &ouml;ffentliche DNS von Google sein (8.8.8.8)<br/>
Konfigurationen &uuml;ber die Konsole (ssh-login) sollten <b>NICHT</b> gemacht werden, da sonst das Rounting und die Firewall gest&ouml;rt
werden und das private Netz zug&auml;nglich wird.
EOM
fi
. /usr/lib/www/page-post.sh ${0%/*}

