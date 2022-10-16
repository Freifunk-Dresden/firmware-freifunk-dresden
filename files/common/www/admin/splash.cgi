#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

export TITLE="Verwaltung &gt; Konfiguration: Splash"
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<h2>$TITLE</h2>
<br>
EOM

display_splash() {
cat<<EOM

<script type="text/javascript">
function ask (m) {
	var x = window.confirm("MAC-Adresse: ["+m+"] wirklich loeschen?");
	return x;
}
function checkinput () {
	var msg="MAC-Adresse ist ungueltig";
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
<legend>Splash-Screen</legend>
<form name="form_disable" action="splash.cgi" method="post">
<input name="form_splash_action" value="disable" type="hidden">
<table>
<tr><td colspan="2">
Der Splash-Screen kann komplett abgeschaltet werden. Damit k&ouml;nnen sich Nutzer ohne Einblendung einer Vorschaltseite, welche Informationen zu Freifunk bereitstellt und auf seine Nutzungsbedingungen hinweist, mit dem Freifunk-WLAN verbinden.
</td></tr>
<tr><td>Splash-Screen abschalten:<input name="form_disable_check" type="checkbox" value="1" $([ "$(uci get ddmesh.system.disable_splash)" = "1" ] && echo "checked")>
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
<tr><td colspan="4">Hier wird die Zeit eingestellt, nach der der Nutzer zwangsgetrennt wird. Diese Option kann an Orten verwendet werden,
an denen sich viele Nutzer einloggen, um die Verf&uuml;gbarkeit des Knotens f&uuml;r andere zu erh&ouml;en.<br/>
Ist eine MAC gespeichert, so wird die Verbindung nicht getrennt.<br/>
Ebenso kann die automatische Trennung das Filesharing erschweren.</td></tr>
<tr>
<td class="nowrap" width="150">
Trennung nach:
	<select name="form_disconnect_timeout" size="1">
	<option selected value="0">niemals</option>
	<option value="15">15 min</option>
	<option value="30">30 min</option>
	<option value="60"> 1 h (60 min)</option>
	<option value="90"> 1.5 h (90 min)</option>
	<option value="120"> 2 h (120 min)</option>
	<option value="180"> 3 h (180 min)</option>
	<option value="240"> 4 h (240 min)</option>
	<option value="300"> 5 h (300 min)</option>
	<option value="480"> 8 h (480 min)</option>
	<option value="600">10 h (600 min)</option>
	<option value="900">15 h (900 min)</option>
	<option value="1440">24 h (1440 min)</option>
	<option value="2880">48 h (2880 min)</option>
	<option value="5760">96 h (5760 min)</option>
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
<legend>Aktuelle WLAN-Client-MAC-Adressen</legend>
<table>
<tr><td colspan="4">Hier k&ouml;nnen MAC-Adressen dauerhaft eingetragen werden, sodass f&uuml;r einzelne Ger&auml;te kein Splash-Screen eingeblendet wird.</td></tr>
EOM

echo "<tr><th>MAC</th><th>IP</th><th>Hostname</th><th>Dauer</th></tr>"
IFS='
'
T=1
C=0
for i in $(sed 's#\([^ ]\+\) \([^ ]\+\) \([^ ]\+\) \([^ ]\+\) \([^ ]\+\)#D="$(date --date=\"@\1\")";MAC1=\2;IP=\3;NAME=\4;MAC2=\5#' /tmp/dhcp.leases)
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
<legend>Gespeicherte MAC-Adressen</legend>
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
<button onclick="if(ask('alle'))document.forms.form_splash_del_all.submit()" name="form_splash_btn_delall" title="L&ouml;sche alle MAC-Adressen" type="button">Alle MAC-Adressen l&ouml;schen</button>
</form></td></tr>

</table>
</fieldset>
<br>
<fieldset class="bubble">
<legend>MAC-Adresse hinzuf&uuml;gen</legend>
<form name="form_splash_new" action="splash.cgi" method="post" onsubmit="return checkinput();">
<table>
<tr><td width="150" title="MAC-Adresse im Format 11:22:33:44:55:66">
 <input name="form_splash_action" value="add" type="hidden">
 <input name="form_splash_mac" type="text" value="" size="17" maxlength="17">
 </td>
 <td>
 <input title="MAC-Adresse hinzuf&uuml;gen" type="submit" value="Neu">
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
			notebox "MAC-Adresse <b>$mac</b> hinzugef&uuml;gt."
			;;
		  del)
			mac=$(uhttpd -d $form_splash_mac)
			uci del_list ddmesh.network.splash_mac="$mac"
			uci commit
			/usr/lib/ddmesh/ddmesh-splash.sh delmac $mac >/dev/null
			notebox "MAC-Adresse <b>$mac</b> gel&ouml;scht."
			;;
		  rm)
			mac=$(uhttpd -d $form_splash_mac)
			/usr/lib/ddmesh/ddmesh-splash.sh delmac $mac >/dev/null
			notebox "MAC-Adresse <b>$mac</b> von Firewall gel&ouml;scht."
			;;
		  delall)
			uci delete ddmesh.network.splash_mac
			uci commit
			notebox "Alle MAC-Adressen gel&ouml;scht."
			;;
		  disable)
		  	if [ "$form_disable_check" = "1" ]; then
		  		uci set ddmesh.system.disable_splash="1"
		  	else
		  		uci set ddmesh.system.disable_splash="0"
		  	fi
			notebox "Die Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst nach dem n&auml;chsten <A HREF="reset.cgi">Neustart</A> aktiv."
			uci commit
		  	;;
		  disconnect)
			uci set ddmesh.network.client_disconnect_timeout="$form_disconnect_timeout"
			uci commit
			notebox "WLAN-Clientverbindungen werden ab sofort nach $form_disconnect_timeout Minuten unterbrochen."
			;;
		esac
	fi
fi

display_splash

. /usr/lib/www/page-post.sh ${0%/*}
