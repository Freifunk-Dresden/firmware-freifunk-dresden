#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

export TITLE="Verwaltung &gt; Konfiguration: System"

#led
if [ -z "$(uci -q get ddmesh.led)" ]; then
	uci -q add ddmesh led >/dev/null
	uci -q rename ddmesh.@led[-1]='led' >/dev/null
fi

. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<script type="text/javascript">
	function disable_mesh_fields(s) {
		// disabled for now
		return
		var v=document.getElementsByName('form_vlan_meshing')[0].checked;
		var d = (v=="1") ? true : false;
		document.getElementsByName('form_lan_meshing')[0].disabled=d;
		document.getElementsByName('form_wan_meshing')[0].disabled=d;
		document.getElementsByName('form_lan_meshing_sleep')[0].disabled=d;
		document.getElementsByName('form_vlan_id')[0].disabled=!d;
}
</script>
<H2>$TITLE</H2>
<br>
EOM

if [ -z "$QUERY_STRING" ]; then

mesh_on_vlan="$(uci -q get ddmesh.network.mesh_on_vlan)"

cat<<EOM
<FORM ACTION="system.cgi" ID="systemform" METHOD="POST">
<fieldset class="bubble">
<legend>Systemeinstellungen</legend>
<table class="nowrap">
EOM

cat<<EOM
<TR>
<TH>Ger&auml;te-Typ:</TH>
<TD>
        <select name="form_node_type" size="1">
EOM
print_nodetypes() {
#$1 - node types entry
#$2 - current node type
	if [ "$1" = "$2" ]; then
		echo " <option selected value=\"$1\">$1</option>"
	else
		echo " <option value=\"$1\">$1</option>"
	fi
}
config_load ddmesh
config_list_foreach system node_types print_nodetypes "$(uci get ddmesh.system.node_type)"
cat<<EOM
        </select>
</td>
<td><b>node</b>: vollst&auml;ndiger Freifunk-Knoten - WiFi, fester Standort, auf Karten angezeigt<br>
    <b>mobile</b>: vollst&auml;ndiger Freifunk-Knoten - WiFi, st&auml;ndige Standortbestimmung, auf Karten als <i>mobil</i> angezeigt, nur f&uuml;r LTE Router sinnvoll<br>
    <b>server</b>: Offloader,VM,Qemu,.... - kein Wifi, nicht auf Karte angezeigt
</td>
</TR>
EOM

cat<<EOM
<TR>
<TH>Community:</TH>
<TD>
        <select name="form_community" size="1">
EOM
print_communities() {
#$1 - community config entry
#$2 - current community
	entry="$1"
	community="$2"
	entry_id="${entry%%\%*}"
	entry_name="${entry#*\%}"

	if [ "$entry_name" = "$community" ]; then
		echo " <option selected value=\"$entry_name\">$entry_name ($entry_id)</option>"
	else
		echo " <option value=\"$entry_name\">$entry_name ($entry_id)</option>"
	fi
}
config_load ddmesh
config_list_foreach communities community print_communities "$(uci get ddmesh.system.community)"
cat<<EOM
        </select></td>
<td>Community Name und Network ID werden in Zukunft zusammen gelegt</td>
</TR>
EOM

cat<<EOM
<TR>
<TH>- Netzwerk-ID <font class="marked-input-fg">*</font>:</TH>
<TD><INPUT class="marked-input-bg" NAME="form_mesh_network_id" TYPE="TEXT" VALUE="$(uci -q get ddmesh.system.mesh_network_id)"></TD>
<td>Knoten-Netzwerkzuordnung. <font color="#ff0000"><b>Achtung:</b>&Auml;nderung nach &Uuml;bernahme sofort aktiv.</font></td>
</TR>
<TR>
<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TH>Router-Gruppe<font class="marked-input-fg">*</font>:</TH>
<TD><INPUT class="marked-input-bg" NAME="form_group_id" TYPE="TEXT" VALUE="$(uci -q get ddmesh.system.group_id)"></TD>
<td>optional: Gruppiert Router zu einer Gruppe. Verwendet von Statistik/Kartendarstellungen</td>
</TR>

<TR><TD COLSPAN="3">&nbsp;</TD></TR>

<TR TITLE="Setzt die Umgebungsvariable TZ zur Korrektur von Zeitangaben.">
<TH>Zeitzone:</TH>
<TD colspan="2"><INPUT NAME="form_tz" SIZE="48" TYPE="TEXT" VALUE="$(uci get system.@system[0].timezone)"><br>
 (Berlin: "CET-1CEST,M3.5.0,M10.5.0/3"; <a href="https://www.gnu.org/software/libc/manual/html_node/TZ-Variable.html">Format</a>,<a href="https://en.m.wikipedia.org/wiki/List_of_tz_database_time_zones">Zeitzonen</a>)</TD>
</TR>

<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR><TH COLSPAN="3" class="heading">Verbindungen zu diesem Router via WAN-Interface</TH></TR>

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
<td><font color="#ff0000"><b>Achtung:</b><br/>&Auml;nderung nach &Uuml;bernahme sofort aktiv. Router-Reset via Verwaltung &uuml;ber WAN anschlie&szlig;end nicht mehr erreichbar.</font></TD>
</TR>

<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR><TH COLSPAN="3" class="heading">Verbindungen zu diesem Router vom Freifunk-Netz aus</TH></TR>

<TR>
<TH>- SSH erlauben:</TH>
<TD><INPUT NAME="form_meshssh" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.meshssh)" = "1" ];then echo ' checked="checked"';fi)></TD>
<td></td>
</TR>

<TR>
<TH>- Zugang zur Verwaltung erlauben:</TH>
<TD><INPUT NAME="form_meshsetup" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.meshsetup)" = "1" ];then echo ' checked="checked"';fi)></td>
<td><font color="#ff0000"><b>Achtung:</b><br/>&Auml;nderung nach &Uuml;bernahme sofort aktiv. Router-Reset via Verwaltung aus dem Freifunk-Netz anschlie&szlig;end nicht mehr erreichbar.</font></TD>
</TR>


<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR><TH COLSPAN="3" class="heading">Netzwerk</TH></TR>

<TR>
<TH>- Eigenes Internet direkt freigeben:</TH>
<TD><INPUT NAME="form_announce_gateway" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.announce_gateway)" = "1" ];then echo ' checked="checked"';fi)></td>
<td><font color="#ff0000"><b>Achtung:</b><br/>Auch bei Nutzung des OpenVPN-Paketes muss dieser Schalter <b>deaktiviert</b> bleiben, sonst wird der eigene DSL/Kabel-Anschluss freigegeben.</font></TD>
</TR>
<TR>
<TH>- LAN verwendet Lokales Internet:</TH>
<TD><INPUT NAME="form_lan_local_internet" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.network.lan_local_internet)" = "1" ];then echo ' checked="checked"';fi)></TD>
<td></td>
</TR>

<tr><td colspan="3">
<fieldset>

<table>
<TR>
<TH>- VLAN-Meshing:</TH>
<TD><INPUT NAME="form_vlan_meshing" TYPE="CHECKBOX" VALUE="1"$(if [ "${mesh_on_vlan}" = "1" ];then echo ' checked="checked"';fi) onchange="disable_mesh_fields();"></TD>
<td>Wenn aktiv, wird ein VLAN $(uci -q get ddmesh.network.mesh_vlan_id) &uuml;ber alle Ethernet-Ports zum direkten Meshing genutzt.</td>
</TR>
<TR>
<TH>- VLAN-ID:</TH>
<TD><INPUT NAME="form_vlan_id" TYPE="TEXT" VALUE="$(uci -q get ddmesh.network.mesh_vlan_id)"></TD>
<td>Hinweis: Bei manchen Ger&auml;ten k&ouml;nnen nur kleine Zahlen verwendet werden.</td>
</TR>
<tr><td colspan="3"><hr size="1"></td></tr>
EOM
if [ "$wan_iface_present" = "1" ]; then
cat<<EOM

<TR>
<TH>- WAN-Meshing:</TH>
<TD><INPUT NAME="form_wan_meshing" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.network.mesh_on_wan)" = "1" ];then echo ' checked="checked"';fi)></TD>
<td>Wenn aktiv, wird der WAN-Port zum direkten Meshing genutzt. Der Router ist dann <b>nur noch &uuml;ber die Knoten-IP-Adresse via WAN</b> erreichbar.<br/>WAN-Konfiguration wird deaktiviert.</td>
</TR>

EOM
fi
cat<<EOM
<TR>
<TH>- LAN-Meshing:</TH>
<TD><INPUT NAME="form_lan_meshing" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.network.mesh_on_lan)" = "1" ];then echo ' checked="checked"';fi)></TD>
<td>Wenn aktiv, werden alle LAN-Ports zum direkten Meshing genutzt. Der Router ist dann <b>nur noch &uuml;ber Knoten-IP-Adresse via LAN</b> erreichbar.<br/>LAN-Konfiguration und privates Netzwerk werden deaktiviert. LAN-Meshing wird erst 5 minuten nach Routerstart aktiviert wenn dies im Punkt "LAN-Meshing Wartezeit" nicht explizit deaktiviert wurde.</td>
</TR>

<TH>- LAN-Meshing Wartezeit:</TH>
<TD><INPUT NAME="form_lan_meshing_sleep" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.system.mesh_sleep)" = "1" ];then echo ' checked="checked"';fi)></TD>
<td>Wenn aktiv, dann wird LAN-Meshing erst 5 minuten nach Routerstart aktiviert.</td>
</TR>

</table></fieldset></td></tr>
<tr><td COLSPAN="3">&nbsp;</td></tr>

<TR>
<TH>- Bevorzugtes Gateway (IP) <font class="marked-input-fg">*</font>:</TH>
<TD><INPUT class="marked-input-bg" NAME="form_bmxd_preferred_gateway" TYPE="TEXT" VALUE="$(uci -q get ddmesh.bmxd.preferred_gateway)"></TD>
<td>Angegebenes Gateway (z. B.: 10.200.0.1) wird bei Gateway-Auswahl bevorzugt. Ein leeres Feld l&ouml;scht das bevorzugte Gateway.</td>
</TR>
<TR>
<TH>- W&auml;hle nur Community Gateways <font class="marked-input-fg">*</font></TH>
<TD><INPUT NAME="form_bmxd_only_community" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.bmxd.only_community_gateways)" = "1" ];then echo ' checked="checked"';fi)>
</td>
<td><td>
</TR>


<TR>
<TH>- Freifunk-DNS 1 (IP):</TH>
<TD><INPUT NAME="form_internal_dns1" TYPE="TEXT" VALUE="$(uci -q get ddmesh.network.internal_dns1)"></TD>
<td></td>
</TR>
<TR>
<TH>- Freifunk-DNS 2 (IP):</TH>
<TD><INPUT NAME="form_internal_dns2" TYPE="TEXT" VALUE="$(uci -q get ddmesh.network.internal_dns2)"></TD>
<td></td>
</TR>
<TR>
<TH>- Fallback-DNS (IP):</TH>
<TD><INPUT NAME="form_fallback_dns" TYPE="TEXT" VALUE="$(uci -q get ddmesh.network.fallback_dns)"></TD>
<td>DNS-IP-Adresse wird zus&auml;tzlich an Wifi-Ger&auml;te per DHCP als alternativen Nameserver mitgeteilt, falls DNS im Freifunk gest&ouml;rt ist.</td>
</TR>

EOM
if [ -n "$(which ethtool)" ]; then
cat <<EOM
<TR>
<TH>- Ethernet Link-Speed 100Mbit</TH>
<TD><INPUT NAME="form_ethernet_speed" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.network.force_ether_100mbit)" = "1" ];then echo ' checked="checked"';fi)>
</td>
<td>LAN/WAN Ports werden auf 100Mbit/s beschr&auml;nkt.<td>
</TR>
EOM
fi

if [ -n "$(which usbmuxd)" ]; then
cat <<EOM
<TR>
<TH>- Aktiviere IOS USB-Tethering</TH>
<TD><INPUT NAME="enable_ios_tethering" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.network.enable_ios_tethering)" = "1" ];then echo ' checked="checked"';fi)>
</td>
<td>Hinweis: Kann auf einigen Ger&auml;ten zu hoher Systemlast f&uuml;hren<td>
</TR>
EOM
fi

cat <<EOM

<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR><TH COLSPAN="3" class="heading">Cron</TH></TR>

<tr><td colspan="3">
<fieldset>
<table>
<tr><th>- Zeitpunkt:</th>
<td><select name="form_maintenance_time" size=1>
EOM

maintenance="$(uci -q get ddmesh.system.maintenance_time)"
maintenance="${maintenance:=4}"


for h in $(seq 0 23)
do
	if [ "$h" = "$maintenance" ]; then
		echo " <option selected value=\"$h\">$h Uhr</option>"
	else
		echo " <option value=\"$h\">$h Uhr</option>"
	fi
done
cat<<EOM
</select></td>
<td>Zeitpunkt f&uuml;r t&auml;glichen Neustart und Firmware-update check<td>
</tr>

<TR>
<TH>- Automatischer n&auml;chtlicher Neustart:</TH>
<TD><INPUT NAME="form_nightly_reboot" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.system.nightly_reboot)" = "1" ];then echo ' checked="checked"';fi)></td>
<td>Router wird t&auml;glich neu gestartet. Dies l&ouml;st manchmal seltsame Probleme, wenn der Router aus unbekannten Gr&uuml;nden nicht mehr richtig funktioniert.<td>
</TR>

<TR>
<TH>- Automatisches Firmware-Update:</TH>
<TD><INPUT NAME="form_firmware_autoupdate" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci get ddmesh.system.firmware_autoupdate)" = "1" ];then echo ' checked="checked"';fi)></td>
<td>Firmware wird automatisch aktualisiert. Nachtr&auml;glich installierte Pakete m&uuml;ssen erneut installiert werden.<td>
</TR>

</table>
</fieldset></td></tr>
<tr><td COLSPAN="3">&nbsp;</td></tr>

<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR><TH COLSPAN="3" class="heading">LEDs</TH></TR>
EOM

# simulate array
led_comment_wifi="Gateway Status:<ul><li>blinkt kurz: kein Gatway gefunden/selektiert</li><li>konstant an: Gateway selektiert</li><li>blink schnell: <font color="red">Router selbst ist ein Gateway !</font></li></ul>"
led_comment_status="Boot-Status"
led_comment_wwan="LTE Status"

for led in wifi status $([ "$wwan_iface_present" = "1" ] && echo 'wwan')
do
cat<<EOM
<tr style="vertical-align:top;">
<th>- ${led}-LED:</th>
<td>
EOM
ddmesh_led="$(uci -q get ddmesh.led.${led})"
case "$ddmesh_led" in
	on) 	check_led_on='checked="checked"'
		check_led_off=''
		check_led_status=''
		;;
	off) 	check_led_on=''
		check_led_off='checked="checked"'
		check_led_status=''
		;;
	*) 	check_led_on=''
		check_led_off=''
		check_led_status='checked="checked"'
		;;
esac

eval comment=$(echo \$led_comment_${led})

cat <<EOM
<input name="form_led_${led}" type="radio" value="status" $check_led_status>Status
<input name="form_led_${led}" type="radio" value="on" $check_led_on>On
<input name="form_led_${led}" type="radio" value="off" $check_led_off>Off
</td>
<td>${comment}</td>
</th>
EOM
done

cat<<EOM
<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR><TH COLSPAN="3" class="heading">Sonstiges</TH></TR>
<TR>
<TH>- Ignoriere Werkseinstellungs-Button:</TH>
<TD><INPUT NAME="form_ignore_factory_reset_button" TYPE="CHECKBOX" VALUE="1"$(if [ "$(uci -q get ddmesh.system.ignore_factory_reset_button)" = "1" ];then echo ' checked="checked"';fi)></td>
<td>Verhindert das Zur&uuml;cksetzen des Routers via Reset-Button<td>
</TR>

<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR><TD COLSPAN="3"><font class="marked-input-fg">*</font> Einstellungen werden sofort aktiv</TD></TR>
<TR><TD COLSPAN="3">&nbsp;</TD></TR>
<TR>
<TD COLSPAN="3"><INPUT NAME="form_submit" ONCLICK="return validate(systemform);" TITLE="Einstellungen &uuml;bernehmen. Diese werden erst nach einem Neustart wirksam." TYPE="SUBMIT" VALUE="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<INPUT NAME="form_abort" TITLE="Abbrechen und &Auml;nderungen verwerfen." TYPE="SUBMIT" VALUE="Abbrechen"></TD>
</TR>

</TABLE>
</fieldset>
</FORM>
<br>
<p>

<script type="text/javascript">
disable_mesh_fields();
</script>

EOM


else

# process form abort or save
	if [ -n "$form_submit" ]; then
		uci set ddmesh.system.node_type="$(uhttpd -d ${form_node_type})"
		# community und network id muessen noch zusammen gefuehrt werden
		uci set ddmesh.system.community="$(uhttpd -d ${form_community})"
		uci set ddmesh.system.mesh_network_id=${form_mesh_network_id:-0}
		uci set ddmesh.system.group_id="$(uhttpd -d ${form_group_id:-0})"

		[ -n "${form_tz}" ] && uci set system.@system[0].timezone="$(uhttpd -d ${form_tz})"

		uci set ddmesh.system.wanssh=${form_wanssh:-0}
		uci set ddmesh.system.wanhttp=${form_wanhttp:-0}
		uci set ddmesh.system.wanhttps=${form_wanhttps:-0}
		uci set ddmesh.system.wanicmp=${form_wanicmp:-0}
		uci set ddmesh.system.wansetup=${form_wansetup:-0}
		uci set ddmesh.system.meshssh=${form_meshssh:-0}
		uci set ddmesh.system.meshsetup=${form_meshsetup:-0}
		uci set ddmesh.system.announce_gateway=${form_announce_gateway:-0}
		uci set ddmesh.network.lan_local_internet=${form_lan_local_internet:-0}
		uci set ddmesh.system.mesh_sleep=${form_lan_meshing_sleep:-0}
		uci set ddmesh.system.maintenance_time=${form_maintenance_time:-4}

		# vlan and mesh-lan/wan can only be used alternatively. some switch devices
		# can not setup vlan 1 and van 9 with same ports
		# vlan has precedence over lan/wan meshing
		uci set ddmesh.network.mesh_on_vlan=${form_vlan_meshing:-0}
		uci set ddmesh.network.mesh_vlan_id=${form_vlan_id:-9}
#		if [ "${form_vlan_meshing:-0}" = 1]; then
#			uci set ddmesh.network.mesh_on_lan='0'
#			uci set ddmesh.network.mesh_on_wan='0'
#		else
			uci set ddmesh.network.mesh_on_lan=${form_lan_meshing:-0}
			uci set ddmesh.network.mesh_on_wan=${form_wan_meshing:-0}
#		fi
		uci set ddmesh.network.force_ether_100mbit=${form_ethernet_speed:-0}
		uci set ddmesh.network.enable_ios_tethering=${enable_ios_tethering:-0}

		test -n "$form_bmxd_preferred_gateway" && prefgw="$(uhttpd -d ${form_bmxd_preferred_gateway})"
		uci set ddmesh.bmxd.preferred_gateway="$prefgw"
		uci set ddmesh.bmxd.only_community_gateways=${form_bmxd_only_community:-0}
		uci set ddmesh.system.firmware_autoupdate=${form_firmware_autoupdate:-0}
		uci set ddmesh.system.nightly_reboot=${form_nightly_reboot:-0}
		uci set ddmesh.system.ignore_factory_reset_button=${form_ignore_factory_reset_button:-0}
		test -n "$form_internal_dns1" && uci set ddmesh.network.internal_dns1="$(uhttpd -d ${form_internal_dns1})"
		test -n "$form_internal_dns2" && uci set ddmesh.network.internal_dns2="$(uhttpd -d ${form_internal_dns2})"
		test -n "$form_fallback_dns" && uci set ddmesh.network.fallback_dns="$(uhttpd -d ${form_fallback_dns})"
		uci set ddmesh.led.wifi="${form_led_wifi:-status}"
		uci set ddmesh.led.status="${form_led_status:-status}"
		uci set ddmesh.led.wwan="${form_led_wwan:-status}"

		uci set ddmesh.boot.boot_step=2
		uci commit
		notebox  'Die Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst beim n&auml;chsten <A HREF="reset.cgi">Neustart</A> aktiv.'
		/usr/lib/ddmesh/ddmesh-bmxd.sh prefered_gateway "$prefgw" 2>&1 >/dev/null
		/usr/lib/ddmesh/ddmesh-bmxd.sh netid "${form_mesh_network_id:-0}" 2>&1 >/dev/null
		/usr/lib/ddmesh/ddmesh-bmxd.sh only_community_gateway "${form_bmxd_only_community:-0}" 2>&1 >/dev/null

	else
		notebox  'Einstellungen wurden nicht &uuml;bernommen.'
	fi
fi

. /usr/lib/www/page-post.sh ${0%/*}
