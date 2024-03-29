#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Konfiguration: Privates Netzwerk"

. /usr/lib/www/page-pre.sh ${0%/*}
. /lib/functions.sh

#grep
DEFAULT_PORT="$(uci get ddmesh.privnet.default_fastd_port)"
NUMBER_OF_CLIENTS="$(uci get ddmesh.privnet.number_of_clients)"
STATUS_DIR="/var/privnet_status"
KEY_LEN=64
COUNT=$(uci show ddmesh | grep '=privnet_\(client\|accept\)' | wc -l)
TOGGEL=1


mkdir -p $STATUS_DIR

cat<<EOM
<script type="text/javascript">
function ask (n)
{
	var x = window.confirm("Verbindung zu "+n+" wirklich löschen?");
	return x;
}

function checkinput_server ()
{
	var v;
	v = document.privnet_form_server.form_privnet_server_port.value;
	if( checknumber(v) || v<1 || v>65535 ){ alert("Server-Port ist ungültig (1-65535).");return 0;}
	return 1;
}

function checkinput_outgoing ()
{
	var v;
	v = document.privnet_form_connection_out.form_privnet_peer_node.value;
	if( v.replace(/[0-9]/g,"") != "" ){ alert("Knoten ist ungültig.");return 0;}
	if( checknumber(v) || v<1 || v>$_ddmesh_max){ alert("Knoten ist ungültig.");return 0;}

	v = document.privnet_form_connection_out.form_privnet_peer_port.value;
	if( checknumber(v) || v<1 || v>65535 ){ alert("Server-Port ist ungültig (1-65535).");return 0;}

	v = document.privnet_form_connection_out.form_privnet_peer_key.value;
	if( v.length!=$KEY_LEN){ alert("Key ist ungültig ($KEY_LEN Zeichen).");return 0;}
	if( v.replace(/[0-9a-f]/g,"") != "" ){ alert("Key ist ungültig.");return 0;}
	return 1;
}

function checkinput_incomming ()
{
	var v;
	v = document.privnet_form_connection_in.form_privnet_peer_key.value;
	if( v.length!=$KEY_LEN){ alert("Key ist ungültig ($KEY_LEN Zeichen).");return 0;}
	if( v.replace(/[0-9a-f]/g,"") != "" ){ alert("Key ist ungültig.");return 0;}
	return 1;
}

function form_submit (form,action,entry)
{
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
html_msg()
{
	test ! "$1" = "0" && {
		case "$1" in
			1) msg="Die Einstellungen wurden &uuml;bernommen. Ein Neustart des Routers ist nicht n&ouml;tig." ;;
			2) msg="Die Einstellungen wurden &uuml;bernommen. Ein <b>Neustart</b> des Routers ist <b>n&ouml;tig</b>. Oder dr&uuml;cke den Button \"VPN-Neustart\"." ;;
			3) msg="Eintrag wurde hinzugef&uuml;gt. Ein <b>Neustart</b> des Routers ist <b>n&ouml;tig</b>. Oder dr&uuml;cke den Button \"VPN-Neustart\"." ;;
			4) msg="Eintrag wurde gel&ouml;scht. Ein <b>Neustart</b> des Routers ist <b>n&ouml;tig</b>. Oder dr&uuml;cke den Button \"VPN-Neustart\"." ;;
			5) msg="Eintrag wurde hinzugef&uuml;gt. Ein Neustart des Routers ist nicht n&ouml;tig." ;;
			6) msg="Eintrag wurde <b>nicht gespeichert</b>. Maximale Anzahl von <b>$NUMBER_OF_CLIENTS</b> wurde erreicht.";;
			7) msg="VPN wurde neu gestartet. Rufe nach etwa 30 s diese Seite erneut auf, um den aktuellen Status zu sehen.";;
			8) msg="VPN wird neu gestartet. Sollte die aktuelle Verbindung gerade &uuml;ber das VPN laufen,<br />wird diese Verbindung f&uuml;r einige Zeit gest&ouml;rt.";;
			9) msg="Es wurden keine Einstellungen ge&auml;ndert." ;;
			*) msg="unbekannt[$1]" ;;
		esac
		notebox "$msg"
	}
}

show_accept()
{
	local config="$1"
	local comment
	local key
	config_get key "$config" public_key
	config_get comment "$config" comment

	test -f "$STATUS_DIR/$key" && CONNECTED=/images/yes.png || CONNECTED=/images/no.png
	echo "<tr class=\"colortoggle$TOGGEL\"><td>$key</td><td>$comment</td>"
	echo "<td><img src=\"$CONNECTED\"></td>"
	echo "<td><button onclick=\"if(ask('$comment'))form_submit(document.forms.privnet_form_connection_in,'accept_del','$config')\" title=\"Verbindung l&ouml;schen\" type=\"button\">"
	echo "<img src=\"/images/loeschen.gif\" align=bottom width=16 height=16 hspace=4></button></td>"
	echo "</tr>"
	if [ $TOGGEL = "1" ]; then
		TOGGEL=2
	else
		TOGGEL=1
	fi
}
show_outgoing()
{
	local config="$1"
	local node
	local port
	local key
	config_get node "$config" node
	config_get port "$config" port
	config_get key "$config" public_key


	test -f "$STATUS_DIR/$key" && CONNECTED=/images/yes.png || CONNECTED=/images/no.png
	echo "<tr class=\"colortoggle$TOGGEL\"><td>$node</td><td>$port</td><td>$key</td>"
	echo "<td><img src=\"$CONNECTED\"></td>"
	echo "<td>"
	echo "<button onclick=\"if(ask('$node'))form_submit(document.forms.privnet_form_connection_out,'client_del','$config')\" title=\"Verbindung l&ouml;schen\" type=\"button\">"
	echo "<img src="/images/loeschen.gif" align=bottom width=16 height=16 hspace=4></button></td></tr>"
	if [ $TOGGEL = "1" ]; then
		TOGGEL=2
	else
		TOGGEL=1
	fi
}

content()
{
	privnet_server_port=$(uci get ddmesh.privnet.fastd_port)
	privnet_server_port=${privnet_server_port:-$DEFAULT_PORT}

	COUNT=$(uci show ddmesh | grep '=privnet_\(client\|accept\)' | wc -l)

	cat<<EOM
<fieldset class="bubble">
<legend>VPN-Einstellungen</legend>
<form name="privnet_form_server" action="privnet.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<table>
<tr><th title="TCP-Port des Servers">Server-TCP-Port:</th><td><input name="form_privnet_server_port" type="text" size="8" value="$privnet_server_port"</td>
 <td title="Einstellungen werden nach Neustart wirksam."><button onclick="if(checkinput_server())form_submit(document.forms.privnet_form_server,'local','none')" name="bb_btn_new" type="button">Speichern</button></td></tr>
</table>
</form>

<form name="privnet_form_keygen" action="privnet.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<table>
<tr><td colspan="3"><font color="red">Achtung: Wird ein neuer Schl&uuml;ssel generiert, muss dieser bei <b>allen</b> VPN-Servern aktualisiert werden, da sonst keine Verbindung mehr von diesem Router akzeptiert wird.</font></td></tr>
<tr><th>Public-Key:</th><td>$(/usr/lib/ddmesh/ddmesh-privnet.sh get_public_key)</td>
 <td title="Einstellungen werden nach Neustart wirksam."><button onclick="form_submit(document.forms.privnet_form_keygen,'keygen','none')" name="bb_btn_new" type="button">Key Generieren</button></td></tr>
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
<tr><th>Public-Key</th><th>Kommentar</th><th>Verbunden</th><th>&nbsp;</th></tr>
EOM

	TOGGEL=1
	config_load ddmesh
	config_foreach show_accept privnet_accept

	if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
		cat<<EOM
<tr class="colortoggle$TOGGEL">
 <td title="Public Key der Gegenstelle"><input name="form_privnet_peer_key" type="text" size="40" value=""></td>
 <td title="Kommentar"><input name="form_privnet_peer_comment" type="text" size="20" value=""></td>
 <td></td>
 <td><button onclick="if(checkinput_incomming())form_submit(document.forms.privnet_form_connection_in,'accept_add','none')" name="bb_btn_new" title="Verbindung Speichern" type="button">Neu</button></td>
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
<tr><th>Knoten</th><th>Server-Port</th><th>Public-Key</th><th>Verbunden</th><th>&nbsp;</th></tr>
EOM

	TOGGEL=1
	config_load ddmesh
	config_foreach show_outgoing privnet_client

	if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
	cat<<EOM
<tr class="colortoggle$TOGGEL">
 <td title="Knoten-Nr."><input name="form_privnet_peer_node" type="text" size="15" value=""></td>
 <td title="TCP-Port des Servers"><input name="form_privnet_peer_port" type="text" size="8" value="$DEFAULT_PORT"></td>
 <td title="Public-Key der Gegenstelle"><input name="form_privnet_peer_key" type="text" size="40" value=""></td>
 <td></td>
 <td><button onclick="if(checkinput_outgoing())form_submit(document.forms.privnet_form_connection_out,'client_add','none')" name="bb_btn_new" title="Verbindung Speichern" type="button">Neu</button></td>
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
Das private Netzwerk erlaubt es, die LAN-Ports eines Routers mit den LAN Ports eines entfernten Routers zu verbinden und somit sein privates
Netz mit einem entfernten privaten Netz zu koppeln. Die Verbindung
wird durch einen verschl&uuml;sselten Tunnel aufgebaut. Es lassen sich <b>$NUMBER_OF_CLIENTS Verbindungen</b> von oder zu einem Router
aufbauen.
<br><br>
EOM
	content
else
	MSG=0
	RESTART=0
	case $form_action in
		local)
			uci set ddmesh.privnet.fastd_port=$form_privnet_server_port
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
				uci set ddmesh.@privnet_client[-1].node="$form_privnet_peer_node"
				uci set ddmesh.@privnet_client[-1].port="$form_privnet_peer_port"
				uci set ddmesh.@privnet_client[-1].public_key="$form_privnet_peer_key"
				uci commit
				MSG=3;
			else
				MSG=6;
			fi
			;;
		accept_add)
			if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
				uci add ddmesh privnet_accept >/dev/null
				uci set ddmesh.@privnet_accept[-1].comment="$form_privnet_peer_comment"
				uci set ddmesh.@privnet_accept[-1].public_key="$form_privnet_peer_key"
				uci commit
				MSG=3;
			else
				MSG=6;
			fi
			;;

		keygen)
			/usr/lib/ddmesh/ddmesh-privnet.sh gen_secret_key
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
