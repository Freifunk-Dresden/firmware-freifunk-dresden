#!/bin/sh

. /lib/functions.sh

export TITLE="Verwaltung > Expert > Splash"
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<h2>$TITLE</h2>
<br>
EOM

display_splash() {
cat<<EOM

<script type="text/javascript">
function ask (m) {
	var x = window.confirm("MAC: ["+m+"] wirklich loeschen?");
	return x;
}
function checkinput () {
	var msg="MAC Adresse ist ungueltig";
	var mac=document.form_splash_new.form_splash_mac.value;
	var i,c;
	for(i=0;i<mac.length;i++)
	{
		c=mac.charAt(i);
		if(i==2 || i==5 || i==8 || i==11 || i==14)
		{
			if(c!=':'){
				alert(msg);return false;
			}
		} else {
			if((c<'0' || c>'9') && (c<'a' || c>'f') && (c<'A' || c>'F')) {
				alert(msg);return false;
			}
		}
	}
	if(i!=17){
		alert(msg);return false;
	}
	return true;
}
</script>

<fieldset class="bubble">
<legend>Splash</legend>
<form name="form_disable" action="splash.cgi" method="post">
<input name="form_splash_action" value="disable" type="hidden">
<table>
<tr><td colspan="2">
Der Splash kann komplett abgeschaltet werden. Damit k&ouml;nnen Nutzer sich ohne Splash mit dem Freifunk verbinden.<br/>
Diese Einstellung ist nicht empfohlen, da der Splash die Nutzungsbedinungen bereitstellt und als Freifunk-Werbung dient.
</td></tr>
<tr><td>Splash Abschalten:<input name="form_disable_check" type="checkbox" value="1" $([ "$(uci get ddmesh.system.disable_splash)" = "1" ] && echo "checked")>
<input name="form_disable_submit" type="submit" value="Anwenden"></td>
</tr>
</table>
</form>
</fieldset>
<br />

<fieldset class="bubble">
<legend>Automatische Trennung</legend>
<form name="form_splash_disconnect" action="splash.cgi" method="post">
<input name="form_splash_action" value="disconnect" type="hidden">
<table>
<tr><td colspan="4">Hier wird die Zeit eingestellt, nach der der Nutzer zwangsgetrennt wird. Dies kann an Orten verwendet werden,
an denen viele Nutzer sich einloggen, um die Verf&uuml;gbarkeit des Knotens f&uuml;r andere zu erh&ouml;en.<br/>
Ist eine MAC gespeichert, so wird die Verbindung nicht getrennt.<br/>
Ebenso kann es das Filesharing erschweren</td></tr>
<tr>
<td class="nowrap" width="150">
Trennung nach:
	<select name="form_disconnect_timeout" size="1">
	<option selected value="0">niemals</option>
	<option value="15">15min</option>
	<option value="30">30min</option>
	<option value="60"> 1h (60min)</option>
	<option value="90"> 1.5h (90min)</option>
	<option value="120"> 2h (120min)</option>
	<option value="180"> 3h (180min)</option>
	<option value="240"> 4h (240min)</option>
	<option value="300"> 5h (300min)</option>
	<option value="480"> 8h (480min)</option>
	<option value="600">10h (600min)</option>
	<option value="900">15h (900min)</option>
	<option value="1440">24h (1440min)</option>
	<option value="2880">48h (2880min)</option>
	<option value="5760">96h (5760min)</option>
	</select>
	&nbsp;(<b>aktuell:</b> $(uci get ddmesh.network.client_disconnect_timeout) min)
</td>
<td><input name="form_disconnect_submit" type="submit" value="Anwenden"></td>
</tr>
</table>
</form>
</fieldset>
<br/>
<fieldset class="bubble">
<legend>Wifi Dhcp Lease Zeit</legend>
<form name="form_splash_lease" action="splash.cgi" method="post">
<input name="form_splash_action" value="lease" type="hidden">
<table>
<tr><td colspan="4">Hier wird die Zeit eingestellt, nach der ein Endger&auml;t die Wifi IP Adressen aktualisieren muss.
Erfolgt keine Aktualisierung, wird der Nutzer wieder gespeert (falls Splash aktiv ist).<br/>
F&uuml;r &ouml;ffentliche Orte, sollte der Wert klein gehalten werden,
um die Verf&uuml;gbarkeit des Knotens f&uuml;r andere zu erh&ouml;en.<br/>
</td></tr>
<tr>
<td class="nowrap" width="150">
DHCP Lease:
	<select name="form_lease_time" size="1">
	<option selected value="5m"> 5min (öffentliche Plätze)</option>
	<option value="10m">10min</option>
	<option value="15m">15min</option>
	<option value="20m">20min (Imbiss)</option>
	<option value="30m">30min</option>
	<option value="45m">45min (Kneipe)</option>
	<option value="1h"> 1h</option>
	<option value="2h"> 2h (Veranstaltungen)</option>
	<option value="3h"> 3h</option>
	<option value="5h"> 5h</option>
	<option value="10h">10h</option>
	<option value="48h">48h (Camps)</option>
	<option value="96h">96h</option>
	</select>
	&nbsp;(<b>aktuell:</b> $(uci get ddmesh.network.wifi2_dhcplease))
</td>
<td><input name="form_lease_submit" type="submit" value="Anwenden"></td>
</tr>
</table>
</form>
</fieldset>
<br/>
<fieldset class="bubble">
<legend>Aktuelle WLAN Client MAC Adressen</legend>
<table>
<tr><td colspan="4">Hier k&ouml;nnen MAC Adressen dauerhaft eingetragen werden, so dass diese nach einem Neustart aktiv sind.</td></tr>
EOM

echo "<tr><th>MAC</th><th>IP</th><th>Hostname</th><th>Dauer</th></tr>"
IFS='
'
T=1
C=0
for i in $(cat /tmp/dhcp.leases | sed 's#\([^ ]\+\) \([^ ]\+\) \([^ ]\+\) \([^ ]\+\) \([^ ]\+\)#D="$(date --date=\"@\1\")";MAC1=\2;IP=\3;NAME=\4;MAC2=\5#')
do
	eval $i
	stored=$(/usr/lib/ddmesh/ddmesh-splash.sh listmac | grep "$MAC1")
	echo "<tr class="colortoggle$T" ><td>$MAC1</td><td>$IP</td><td>$NAME</td><td>$D</td>"

	if [ -n "$stored" ]; then
	 echo "<td valign=bottom><FORM name=\"form_splash_rm_"$C"\" ACTION=\"splash.cgi\" METHOD=\"POST\">"
	 echo "<input name=\"form_splash_action\" value=\"rm\" type=\"hidden\">"
	 echo "<input name=\"form_splash_mac\" value=\"$MAC1\" type=\"hidden\">"
	 echo "<button onclick=\"if(ask('$MAC1'))document.forms.form_splash_rm_"$C".submit()\" name=\"form_splash_btn_rm\" title=\"Entfernt aktuelle akzeptiere MAC wenn diese nicht gepeichert wurde\" type=\"button\"><img src="/images/loeschen.gif" align=bottom width=16 height=16 hspace=4></button>"
	 echo "</form></td>"
	else
	 echo "<td>nicht registriert oder gespeichert</td>"
	fi

	echo "<td valign=bottom><FORM name=\"form_splash_add_"$C"\" ACTION=\"splash.cgi\" METHOD=\"POST\">"
	echo "<input name=\"form_splash_action\" value=\"add\" type=\"hidden\">"
	echo "<input name=\"form_splash_mac\" value=\"$MAC1\" type=\"hidden\">"
	echo "<input type=\"submit\" value=\"Speichern\">"
	echo "</form></td>"

	echo "</tr>"
	if [ $T = 1 ]; then T=2 ;else T=1; fi
	C=$(($C+1))
done
unset IFS

cat<<EOM
</table>
</fieldset>
<br>
<fieldset class="bubble">
<legend>Gespeicherte MAC Adressen</legend>
<table>

<tr><th width="100">MAC-Adresse</th><th></th></tr>
EOM

T=1
C=0
print_splash_mac() {
	if [ -n "$1" ]; then
		echo "<tr class=\"colortoggle$T\" ><td width=\"100\">$1</td>"
		echo "<td valign=bottom><FORM name=\"form_splash_del_"$C"\" ACTION=\"splash.cgi\" METHOD=\"POST\">"
		echo "<input name=\"form_splash_action\" value=\"del\" type=\"hidden\">"
		echo "<input name=\"form_splash_mac\" value=\"$1\" type=\"hidden\">"
		echo "<button onclick=\"if(ask('$1'))document.forms.form_splash_del_"$C".submit()\" name=\"form_splash_btn_del\" title=\"MAC l&ouml;schen\" type=\"button\"><img src="/images/loeschen.gif" align=bottom width=16 height=16 hspace=4></button></FORM></td></tr>"
		if [ $T = 1 ]; then T=2 ;else T=1; fi
		C=$(($C+1))
	fi
}
config_load ddmesh
config_list_foreach network splash_mac print_splash_mac

cat<<EOM
<tr><td colspan="3"><form name="form_splash_del_all" action="splash.cgi" method="post">
<input name="form_splash_action" value="delall" type="hidden">
<button onclick="if(ask('alle'))document.forms.form_splash_del_all.submit()" name="form_splash_btn_delall" title="L&ouml;sche alle MAC Adressen" type="button">Alle MACs l&ouml;schen</button>
</form></td></tr>

</table>
</fieldset>
<br>
<fieldset class="bubble">
<legend>MAC Adresse hinzuf&uuml;gen</legend>
<form name="form_splash_new" action="splash.cgi" method="post" onsubmit="return checkinput();">
<table>
<tr><td width="150" title="MAC Adresse im Format 11:22:33:44:55:66">
 <input name="form_splash_action" value="add" type="hidden">
 <input name="form_splash_mac" type="text" value="" size="17" maxlength="17">
 </td>
 <td>
 <input title="MAC hinzuf&uuml;gen" type="submit" value="Neu">
</td></tr>
</table>
</form>
</fieldset>
EOM
#end display_splash
}

if [ -n "$QUERY_STRING" ]; then
	if [ -n "$form_splash_action" ]; then
		case $form_splash_action in
		  add)
			mac=$(uhttpd -d $form_splash_mac)
			uci add_list ddmesh.network.splash_mac="$mac"
			uci commit
			/usr/lib/ddmesh/ddmesh-splash.sh addmac $mac >/dev/null
			notebox "MAC Adresse <b>$mac</b> hinzugef&uuml;gt."
			;;
		  del)
			mac=$(uhttpd -d $form_splash_mac)
			uci del_list ddmesh.network.splash_mac="$mac"
			uci commit
			/usr/lib/ddmesh/ddmesh-splash.sh delmac $mac >/dev/null
			notebox "MAC Adresse <b>$mac</b> gel&ouml;scht."
			;;
		  rm)
			mac=$(uhttpd -d $form_splash_mac)
			/usr/lib/ddmesh/ddmesh-splash.sh delmac $mac >/dev/null
			notebox "MAC Adresse <b>$mac</b> vom Firewall gel&ouml;scht."
			;;
		  delall)
			uci delete ddmesh.network.splash_mac
			uci commit
			notebox "Alle MAC Adressen wurden gel&ouml;scht."
			;;
		  disable)
		  	if [ "$form_disable_check" = "1" ]; then
		  		uci set ddmesh.system.disable_splash="1"
		  	else
		  		uci set ddmesh.system.disable_splash="0"
		  	fi
			notebox "Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst beim n&auml;chsten <A HREF="reset.cgi">Neustart</A> aktiv."
			uci commit
		  	;;
		  lease)
			uci set ddmesh.network.wifi2_dhcplease="$form_lease_time"
			uci commit
			notebox "Lease Zeit aktualisiert."
			;;
		  disconnect)
			uci set ddmesh.network.client_disconnect_timeout="$form_disconnect_timeout"
			uci commit
			notebox "WLAN Clientverbindungen werden absofort nach $form_disconnect_timeout Minuten unterbrochen"
			;;
		esac
	fi
fi

display_splash

. /usr/lib/www/page-post.sh ${0%/*}
