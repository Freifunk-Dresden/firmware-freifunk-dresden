#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Konfiguration: WAN"
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<script type="text/javascript">
  function disable_fields(s) {
     var s=document.getElementsByName('form_wan_proto')[0].value;
     var d;

     d = (s=="dhcp") ? true : false;
     document.getElementsByName('form_wan_ip')[0].disabled=d;
     document.getElementsByName('form_wan_netmask')[0].disabled=d;
     document.getElementsByName('form_wan_gateway')[0].disabled=d;
     document.getElementsByName('form_wan_dns')[0].disabled=d;
}
</script>
<H2>$TITLE</H2>
<br>
EOM

# get network settings from config or dhcp
wan_proto="$(uci get ddmesh.network.wan_proto)"
if [ "$wan_proto" = "static" ];then

	wan_ipaddr="$(uci get ddmesh.network.wan_ipaddr)"
	wan_netmask="$(uci get ddmesh.network.wan_netmask)"
	wan_gateway="$(uci get ddmesh.network.wan_gateway)"
	wan_dns="$(uci get ddmesh.network.wan_dns)"
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
		uci set ddmesh.network.wan_proto=$form_wan_proto
		uci set ddmesh.network.wan_ipaddr=$form_wan_ip
		uci set ddmesh.network.wan_netmask=$form_wan_netmask
		uci set ddmesh.network.wan_gateway=$form_wan_gateway
		uci set ddmesh.network.wan_dns=$form_wan_dns
		uci set ddmesh.boot.boot_step=2
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
 die Gateway IP und eine DNS IP eingetragen werden. Die DNS IP kann jeder &ouml;ffentliche DNS<br/>
Konfigurationen &uuml;ber die Konsole (ssh-login) sollten <b>NICHT</b> gemacht werden, da sonst das Rounting und die Firewall gest&ouml;rt
werden und das private Netz zug&auml;nglich wird.
EOM
fi

. /usr/lib/www/page-post.sh ${0%/*}
