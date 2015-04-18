#!/bin/sh

export TITLE="Verwaltung > Expert > Privates Netzwerk"

. /usr/lib/www/page-pre.sh ${0%/*}
. /lib/functions.sh

#grep
DEFAULT_PORT="$(uci get ddmesh.privnet.default_server_port)"
DEFAULT_PASSWD="$(echo "$(ip link;date)" | md5sum | sed 's# .*$##' | cut -c3-10)"
NUMBER_OF_CLIENTS="$(uci get ddmesh.privnet.number_of_clients)"
STATUS_DIR="/var/vtund/privnet"
PASSWD_LEN=6
COUNT=$(uci show ddmesh | grep '=privnet_\(client\|accept\)' | wc -l)
TOGGEL=1

cat<<EOM
<script type="text/javascript">
function ask (n) {
	var x = window.confirm("Verbindung zu "+n+" wirklich l&ouml;schen?");
	return x;
}
function checkinput_server () {
	var v;
	v = document.privnet_form_server.form_privnet_server_port.value;
	if( checknumber(v) || v<1 || v>65535 ){ alert("Server Port ist ung&uuml;ltig (1-65535)");return 0;}
	return 1;
}
function checkinput_outgoing () {
	var v;
	var reg = new RegExp("r([0-9]+)");

	v = document.privnet_form_connection_out.form_privnet_peer_node.value;
	if( reg.test(v) == false) {alert("Node ist ung&uuml;ltig");return 0;}

	v = v.substr(1);
	if( checknumber(v) || v<1 || v>$_ddmesh_max){ alert("Node ist ung&uuml;ltig");return 0;}

	v = document.privnet_form_connection_out.form_privnet_peer_port.value;
	if( checknumber(v) || v<1 || v>65535 ){ alert("Server Port ist ung&uuml;ltig (1-65535)");return 0;}

	v = document.privnet_form_connection_out.form_privnet_peer_passwd.value;
	if( v.length<$PASSWD_LEN){ alert("Passwort ist ung&uuml;ltig (mind. $PASSWD_LEN Zeichen)");return 0;}
	if( v.indexOf(":")>0 ){ alert("Passwort ist ung&uuml;ltig (Passwort darf kein \":\" enthalten)");return 0;}

	return 1;
}
function checkinput_incomming () {
	var v;
	var reg = new RegExp("r([0-9]+)");

	v = document.privnet_form_connection_in.form_privnet_peer_node.value;
	if( reg.test(v) == false) {alert("Node ist ung&uuml;ltig");return 0;}
	v = v.substr(1);
	if( checknumber(v) || v<1 || v>$_ddmesh_max){ alert("Node ist ung&uuml;ltig");return 0;}

	v = document.privnet_form_connection_in.form_privnet_peer_passwd.value;
	if( v.length<$PASSWD_LEN){ alert("Passwort ist ung&uuml;ltig (mind. $PASSWD_LEN Zeichen)");return 0;}
	if( v.indexOf(":")>0 ){ alert("Passwort ist ung&uuml;ltig (Passwort darf kein \":\" enthalten)");return 0;}

	return 1;
}
function form_submit (form,action,entry) {
	form.form_action.value=action;
	form.form_entry.value=entry
	form.submit();
}
</script>

<h2>$TITLE</h2>
EOM

## some html helper functions
# ARGS: name value (0 or 1)
html_checkbox() {
	cat<<EOM
<input type="checkbox" name="$1" value="1"$(test "$2" = "1" && echo ' checked="checked"')>&nbsp;
EOM
}
html_msg() {
	test ! "$1" = "0" && {
		case "$1" in
			1) msg="Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Ein Neustart des Routers ist nicht n&ouml;tig." ;;
			2) msg="Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Ein Neustart des Routers <b>ist</b> n&ouml;tig. Oder Dr&uuml;cken Sie den Button \"VPN Neustart\"." ;;
			3) msg="Eintrag wurde hinzugef&uuml;gt. Ein Neustart des Routers <b>ist</b> n&ouml;tig. Oder Dr&uuml;cken Sie den Button \"VPN Neustart\"." ;;
			4) msg="Eintrag wurde gel&ouml;scht. Ein Neustart des Routers <b>ist</b> n&ouml;tig. Oder Dr&uuml;cken Sie den Button \"VPN Neustart\"." ;;
			5) msg="Eintrag wurde hinzugef&uuml;gt. Ein Neustart des Routers ist nicht n&ouml;tig." ;;
			6) msg="Eintrag wurde <b>nicht</b> gespeichert. Maximale Anzahl von <b>$NUMBER_OF_CLIENTS</b> wurden erreicht.";;
			7) msg="VPN Netzwerk wurde neu gestartet. Nach etwa 30s diese Seite erneut aufrufen um den aktuellen Status zu sehen";;
			8) msg="VPN Netzwerk wird neu gestartet. Sollte die aktuelle Verbindung gerade &uuml;ber das VPN laufen,<br />wird diese Verbindung f&uuml;r eine Zeit gest&ouml;rt";;
			9) msg="Es wurden keine Einstellungen ge&auml;ndert." ;;
			*) msg="unbekannt[$1]" ;;
		esac
		notebox "$msg"
	}
}

show_accept() {
	local config="$1"
	local user_arg="$2"
	local node
	local passwd
	config_get node "$config" name
	config_get passwd "$config" password

	test -f "$STATUS_DIR/incomming_$node" && CONNECTED=/images/yes.png || CONNECTED=/images/no.png
	echo "<tr class=\"colortoggle$TOGGEL\"><td>$node</td><td>$passwd</td>"
	echo "<td><img src=\"$CONNECTED\"></td>"
	echo "<td><button onclick=\"if(ask('$node'))form_submit(document.forms.privnet_form_connection_in,'accept_del','$config')\" title=\"Verbindung l&ouml;schen\" type=\"button\">"
	echo "<img src=\"/images/loeschen.gif\" align=bottom width=16 height=16 hspace=4></button></td>"
	echo "</tr>"
	if [ $TOGGEL = "1" ]; then
		TOGGEL=2
	else
		TOGGEL=1
	fi
}
show_outgoing() {
	local config="$1"
	local user_arg="$2"
	local name
	local port
	local passwd
	config_get node "$config" name
	config_get port "$config" port
	config_get passwd "$config" password

	test -f "$STATUS_DIR/outgoing_$node"_$port && CONNECTED=/images/yes.png || CONNECTED=/images/no.png
	echo "<tr class=\"colortoggle$TOGGEL\"><td>$node</td><td>$port</td><td>$passwd</td>"
	echo "<td><img src=\"$CONNECTED\"></td>"
	echo "<td>"
	echo "<button onclick=\"if(ask('$host'))form_submit(document.forms.privnet_form_connection_out,'client_del','$config')\" title=\"Verbindung l&ouml;schen\" type=\"button\">"
	echo "<img src="/images/loeschen.gif" align=bottom width=16 height=16 hspace=4></button></td></tr>"
	if [ $TOGGEL = "1" ]; then
		TOGGEL=2
	else
		TOGGEL=1
	fi
}

content() {
	privnet_server_enabled="$(uci get ddmesh.privnet.server_enabled)"
	privnet_server_enabled="${privnet_server_enabled:-0}"
	privnet_clients_enabled="$(uci get ddmesh.privnet.clients_enabled)"
	privnet_clients_enabled="${privnet_clients_enabled:-0}"
	privnet_server_port=$(uci get ddmesh.privnet.server_port)
	privnet_server_port=${privnet_server_port:-$DEFAULT_PORT}

	COUNT=$(uci show ddmesh | grep '=privnet_\(client\|accept\)' | wc -l)

	cat<<EOM
<fieldset class="bubble">
<legend>VPN-Einstellungen</legend>
<form name="privnet_form_server" action="privnet.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<table>
<tr><th>Client (baut Verbindungen auf):</th><td>$(html_checkbox form_privnet_clients_enabled $privnet_clients_enabled)</td></tr>
<tr><th>Server (akzeptiert eingehende Verbindungen):</th><td>$(html_checkbox form_privnet_server_enabled $privnet_server_enabled)</td></tr>
<tr><td colspan="3">&nbsp;</td></tr>
<tr><th title="TCP Port des Servers">Server TCP Port:</th><td><input name="form_privnet_server_port" type="text" size="8" value="$privnet_server_port"</td>
 <td title="Einstellungen werden nach Neustart wirksam."><button onclick="if(checkinput_server())form_submit(document.forms.privnet_form_server,'local','none')" name="bb_btn_new" type="button">Speichern</button></td></tr>
</table>
</form>
</fieldset>
<br>
<fieldset class="bubble">
<legend>Akzeptierte Verbindungen (Server)</legend>
<form name="privnet_form_connection_in" action="privnet.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<table>
<tr><th>Node</th><th>Passwort</th><th>Verbunden</th><th>&nbsp;</th></tr>
EOM

	TOGGEL=1
	config_load ddmesh
	config_foreach show_accept privnet_accept

	if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
		cat<<EOM
<tr class="colortoggle$TOGGEL">
	<td title="Zielrouter (z.B.: r200)"><input name="form_privnet_peer_node" type="text" size="5" value=""></td>
	<td title="Passwort f&uuml;r diese Verbindung"><input name="form_privnet_peer_passwd" type="text" size="8" value="$DEFAULT_PASSWD"></td>
	<td></td>
	<td><button onclick="if(checkinput_incomming())form_submit(document.forms.privnet_form_connection_in,'accept_add','none')" name="bb_btn_new" title="Verbindung speichern" type="button">Neu</button></td>
</tr>
EOM
	else
		cat<<EOM
<tr><td colspan="5"><font color="red">Es sind keine weiteren Clients m&ouml;glich.</font></td></tr>
EOM
	fi

	cat<<EOM
</table>
</form>
</fieldset>
<br>
<fieldset class="bubble">
<legend>Ausgehende Verbindungen (Client)</legend>
<form name="privnet_form_connection_out" action="privnet.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<table>
<tr><th>Node</th><th>Server Port</th><th>Passwort</th><th>Verbunden</th><th>&nbsp;</th></tr>
EOM

	TOGGEL=1
	config_load ddmesh
	config_foreach show_outgoing privnet_client

	if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
		cat<<EOM
<tr class="colortoggle$TOGGEL">
	<td title="Zielrouter (z.B.: r200)"><input name="form_privnet_peer_node" type="text" size="5" value=""></td>
	<td title="TCP Port des Servers"><input name="form_privnet_peer_port" type="text" size="8" value="$DEFAULT_PORT"></td>
	<td title="Passwort f&uuml;r diese Verbindung"><input name="form_privnet_peer_passwd" type="text" size="8" value="$DEFAULT_PASSWD"></td>
	<td></td>
	<td><button onclick="if(checkinput_outgoing())form_submit(document.forms.privnet_form_connection_out,'client_add','none')" name="bb_btn_new" title="Verbindung speichern" type="button">Neu</button></td>
</tr>
EOM
	else
		cat<<EOM
<tr><td colspan="5"><font color="red">Es sind keine weiteren Clients m&ouml;glich.</font></td></tr>
EOM
	fi

	cat<<EOM
</table>
</form>
</fieldset>

<br />
<form name="privnet_form_apply" action="privnet.cgi" method="POST">
	<input name="form_action" value="none" type="hidden">
	<input name="form_entry" value="none" type="hidden">
	<button onclick="form_submit(document.forms.privnet_form_apply,'refresh','none')" name="bb_btn_apply" title="Seite Aktualisieren" type="button">Seite Aktualisieren</button>
	<button onclick="form_submit(document.forms.privnet_form_apply,'restart','none')" name="bb_btn_apply" title="Werte werden sofort &uuml;bernommen und VPN neu gestartet" type="button">VPN Neustart</button>
</form>
EOM
}


if [ -z "$QUERY_STRING" ]; then

	cat<<EOM
Das Private Netzwerk erlaubt es die LAN Ports eines Routers mit den LAN Ports eines entfernten Routers zuverbinden und somit sein privates
Netz mit einem entfernten privaten Netz zu koppeln. Die Verbindung
wird durch einen verschl&uuml;sselten Tunnel aufgebaut. Es lassen sich <b>$NUMBER_OF_CLIENTS</b> Verbindungen von oder zu einem Router
aufbauen.
<br><br>
Bitte beachtet, dass das VPN mit dem LAN Ports gebr&uuml;ckt sind. Das kann bei ungew&ouml;hnlichen Netzwerkkonfigurationen dazu f&uuml;hren,
dass Pakete &uuml;ber mehrere Wege zum Ziel gelangen und somit Pakete verdoppelt werden.<br>
Dieses passiert zum Beispiel wenn zwei Router &uuml;ber LAN mit einander verbunden und beide haben eine VPN verbindung zu einem dritten Router irgendwo im Netzwerk. Das Bridge-Protokoll "STP" sollte eigentlich dieses Verhindern, aber tut es nicht stabil.
EOM
	content
else
	MSG=0
	RESTART=0
	case $form_action in
		local) uci set ddmesh.privnet.server_enabled=${form_privnet_server_enabled:-0}
			uci set ddmesh.privnet.clients_enabled=${form_privnet_clients_enabled:-0}
			uci set ddmesh.privnet.server_port=$form_privnet_server_port
			uci commit
			MSG=2
		;;
		client_del) uci delete ddmesh.$form_entry;
		uci commit
		MSG=4
		;;
		accept_del) uci delete ddmesh.$form_entry;
		uci commit
		MSG=4;
		;;
		client_add)
			if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
				uci add ddmesh privnet_client >/dev/null
				uci set ddmesh.@privnet_client[-1].name="$form_privnet_peer_node"
				uci set ddmesh.@privnet_client[-1].port="$form_privnet_peer_port"
				uci set ddmesh.@privnet_client[-1].password="$form_privnet_peer_passwd"
				uci commit
				MSG=3;
			else
				MSG=6;
			fi
			;;
		accept_add)
			if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
				uci add ddmesh privnet_accept >/dev/null
				uci set ddmesh.@privnet_accept[-1].name="$form_privnet_peer_node"
				uci set ddmesh.@privnet_accept[-1].password="$form_privnet_peer_passwd"
				uci commit
				MSG=3;
			else
				MSG=6;
			fi
			;;
		restart)
			html_msg 8
			RESTART=1
			MSG=7;
			;;
		refresh)
			;;

	esac
	test $RESTART -eq 1 && /usr/lib/ddmesh/ddmesh-privnet.sh restart >/dev/null 2>&1
	html_msg $MSG
	echo "<br>"
	content

fi

. /usr/lib/www/page-post.sh ${0%/*}
