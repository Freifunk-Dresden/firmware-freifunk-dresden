#!/bin/sh

export TITLE="Verwaltung &gt; Konfiguration: Backbone"

. /usr/lib/www/page-pre.sh ${0%/*}
. /lib/functions.sh

#grep
DEFAULT_FASTD_PORT="$(uci get ddmesh.backbone.default_fastd_port)"
DEFAULT_WG_PORT="$(uci get ddmesh.backbone.default_wg_port)"
NUMBER_OF_CLIENTS="$(uci get ddmesh.backbone.number_of_clients)"
STATUS_DIR="/var/backbone_status"
COUNT=$(uci show ddmesh | grep '=backbone_\(client\|accept\)' | wc -l)
TOGGEL=1

DEFAULT_FASTD_KEY="$(uci get credentials.backbone.fastd_default_server_key)"
FASTD_PATH="$(which fastd)"
KEY_LEN_FASTD=64

WG_PATH="$(which wg)"
KEY_LEN_WG=44
WG_HAND_SHAKE_TIME_S=120
UTC=$(date +"%s")
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh tbb_wg wg)

mkdir -p $STATUS_DIR

cat<<EOM
<script type="text/javascript">
function ask (n)
{
	var x = window.confirm("Verbindung zu "+n+" wirklich löschen?");
	return x;
}

function checkinput_fastd_server_port ()
{
	var v;
	v = document.backbone_form_local_fastd.form_backbone_local_fastd_port.value;
	if( checknumber(v) || v<1 || v>65535 ){ alert("fastd-Server-Port ist ungültig (1-65535)");return 0;}
	return 1;
}

function checkinput_outgoing ()
{
	var h = document.backbone_form_connection_out.form_backbone_outgoing_peer_hostname.value;
	if( h == ""){ alert("Hostname ist ungültig");return 0;}

	var p = document.backbone_form_connection_out.form_backbone_outgoing_peer_port.value;
	if( checknumber(p) || p<1 || p>65535 ){ alert("Server-Port ist ungültig (1-65535)");return 0;}

	var k = document.backbone_form_connection_out.form_backbone_outgoing_peer_key.value;
	var t = document.backbone_form_connection_out.form_backbone_outgoing_peer_type.value;
	if( t == "fastd" || t == ""){
		if( k.length != $KEY_LEN_FASTD){ alert("Key ist ungültig (Fastd Key ist $KEY_LEN_FASTD Zeichen)");return 0;}
		if( k.replace(/[0-9a-f]/g,"") != "" ){ alert("Key ist ungültig");return 0;}
	}

	if( t == "wireguard"){
		var n = document.backbone_form_connection_out.form_backbone_outgoing_peer_node.value;
		if( n == ""){ alert("Knotennummer ist ungültig");return 0;}

		if( k.length != $KEY_LEN_WG){ alert("Key ist ungültig (Wireguard Key ist $KEY_LEN_WG Zeichen)");return 0;}
	}
	return 1;
}

function checkinput_incomming ()
{
	var t = document.backbone_form_connection_in.form_backbone_incomming_peer_type.value;
	var k = document.backbone_form_connection_in.form_backbone_incomming_peer_key.value;

	if( t == "fastd" || t == ""){
		if( k.length != $KEY_LEN_FASTD){ alert("Key ist ungültig (Fastd Key ist $KEY_LEN_FASTD Zeichen)");return 0;}
		if( k.replace(/[0-9a-f]/g,"") != "" ){ alert("Key ist ungültig");return 0;}
	}

	if( t == "wireguard"){
		var n = document.backbone_form_connection_in.form_backbone_incomming_peer_node.value;
		if( n == ""){ alert("Knotennummer ist ungültig");return 0;}

		if( k.length != $KEY_LEN_WG){ alert("Key ist ungültig (Wireguard Key ist $KEY_LEN_WG Zeichen)");return 0;}
	}

	return 1;
}

function form_submit (form,action,entry)
{
	form.form_action.value=action;
	form.form_entry.value=entry
	form.submit();
}

function enable_formfields_incomming()
{
	var type = document.getElementsByName('form_backbone_incomming_peer_type')[0].value;

	if(type == "wireguard")
	{
		document.getElementsByName('form_backbone_incomming_peer_node')[0].disabled = false;
	}
	else
	{
		document.getElementsByName('form_backbone_incomming_peer_node')[0].disabled = true;
	}
}

function enable_formfields_outgoing()
{
	var type = document.getElementsByName('form_backbone_outgoing_peer_type')[0].value;

	if(type == "wireguard")
	{
		document.getElementsByName('form_backbone_outgoing_peer_node')[0].disabled = false;
		document.getElementsByName('form_backbone_outgoing_peer_port')[0].value = "$DEFAULT_WG_PORT";
	}
	else
	{
		document.getElementsByName('form_backbone_outgoing_peer_node')[0].disabled = true;
		document.getElementsByName('form_backbone_outgoing_peer_port')[0].value = "$DEFAULT_FASTD_PORT";
	}
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
			2) msg="Die Einstellungen wurden &uuml;bernommen. Ein <b>Neustart</b> des Routers ist <b>n&ouml;tig</b>. Oder dr&uuml;cke den Button \"Backbone-Neustart\"." ;;
			3) msg="Eintrag wurde hinzugef&uuml;gt. Ein <b>Neustart</b> des Routers ist <b>n&ouml;tig</b>. Oder dr&uuml;cke den Button \"Backbone-Neustart\"." ;;
			4) msg="Eintrag wurde gel&ouml;scht. Ein <b>Neustart</b> des Routers ist <b>n&ouml;tig</b>. Oder dr&uuml;cke den Button \"Backbone-Neustart\"." ;;
			5) msg="Eintrag wurde hinzugef&uuml;gt. Ein Neustart des Routers ist nicht n&ouml;tig." ;;
			6) msg="Eintrag wurde <b>nicht gespeichert</b>. Maximale Anzahl von <b>$NUMBER_OF_CLIENTS</b> wurde erreicht.";;
			7) msg="Backbone wurde neu gestartet. Rufe nach etwa 30 s diese Seite erneut auf, um den aktuellen Status zu sehen.";;
			8) msg="Backbone wird neu gestartet. Sollte die aktuelle Verbindung gerade &uuml;ber das Backbone laufen,<br />wird diese Verbindung f&uuml;r einige Zeit gest&ouml;rt.";;
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
	local type
	local node

	config_get node "$config" node
	config_get key "$config" public_key
	config_get comment "$config" comment
	config_get type "$config" type
	if [ "$type" = "" ]; then
		type="fastd"
	fi

	test -f "$STATUS_DIR/$key" && CONNECTED=/images/yes.png || CONNECTED=/images/no.png
	cat <<EOM
	<tr class="colortoggle$TOGGEL">
	<td>$type</td> <td>$node</td> <td>$key</td>	<td>$comment</td>
	<td><img src="$CONNECTED"></td>
	<td><button onclick="if(ask('$comment'))form_submit(document.forms.backbone_form_connection_in,'accept_del','$config')" title="Verbindung l&ouml;schen" type="button">
	<img src="/images/loeschen.gif" align=bottom width=16 height=16 hspace=4></button></td>
	</tr>
EOM
	if [ $TOGGEL = "1" ]; then
		TOGGEL=2
	else
		TOGGEL=1
	fi
}
show_outgoing()
{
	local config="$1"
	local host
	local port
	local key
	local type
	local node

	config_get node "$config" node
	config_get host "$config" host
	config_get port "$config" port
	config_get key "$config" public_key

	config_get type "$config" type
	if [ "$type" = "" ]; then
		type="fastd"
	fi

	if [ "$type" = "fastd" ]; then
		test -f "$STATUS_DIR/$key" && CONNECTED=/images/yes.png || CONNECTED=/images/no.png
		connect_title=""
	else
		IFS='	'
		hs=$(wg show $wg_ifname latest-handshakes | grep "$key")
		if [ -n "$hs" ]; then
			set $(wg show $wg_ifname latest-handshakes | grep "$key")
			diff=$(( $UTC - $2 ))
			[ $diff -lt $WG_HAND_SHAKE_TIME_S ] && CONNECTED=/images/yes.png || CONNECTED=/images/no.png
		else
			CONNECTED=/images/no.png
		fi
		connect_title="Handshake vor $diff s"
	fi

	echo "<tr class=\"colortoggle$TOGGEL\"><td>$type</td><td>$node</td><td>$host</td><td>$port</td><td>$key</td>"
	echo "<td><img title=\"$connect_title\" src=\"$CONNECTED\"></td>"
	echo "<td>"
	echo "<button onclick=\"if(ask('$host'))form_submit(document.forms.backbone_form_connection_out,'client_del','$config')\" title=\"Verbindung l&ouml;schen\" type=\"button\">"
	echo "<img src="/images/loeschen.gif" align=bottom width=16 height=16 hspace=4></button></td></tr>"
	if [ $TOGGEL = "1" ]; then
		TOGGEL=2
	else
		TOGGEL=1
	fi
}

content()
{
	backbone_local_fastd_port=$(uci get ddmesh.backbone.fastd_port)
	backbone_local_fastd_port=${backbone_local_fastd_port:-$DEFAULT_FASTD_PORT}

	COUNT=$(uci show ddmesh | grep '=backbone_\(client\|accept\)' | wc -l)

	cat<<EOM
<fieldset class="bubble">
<legend>Backbone-Einstellungen</legend>
<form name="backbone_form_local_fastd" action="backbone.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<table>
<tr><th title="Port des Servers">Server-Port:</th><td><input name="form_backbone_local_fastd_port" type="text" size="8" value="$backbone_local_fastd_port"</td>
 <td title="Einstellungen werden nach Neustart wirksam."><button onclick="if(checkinput_fastd_server_port())form_submit(document.forms.backbone_form_local_fastd,'local','none')" name="bb_btn_new" type="button">Speichern</button></td></tr>
</table>
</form>

<form name="backbone_form_keygen" action="backbone.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<table>
<tr><td colspan="3"><font color="red">Achtung: Wird ein neuer Schl&uuml;ssel generiert, muss dieser bei <b>allen</b> Backbone-Servern aktualisiert werden, da sonst keine Verbindung mehr von diesem Router akzeptiert wird.</font></td></tr>
<tr><th>FastD Public-Key:</th><td>$(/usr/lib/ddmesh/ddmesh-backbone.sh get_public_key)</td>
 <td title="Einstellungen werden nach Neustart wirksam."><button onclick="form_submit(document.forms.backbone_form_keygen,'keygen_fastd','none')" name="bb_btn_new" type="button">FastD Key Generieren</button></td></tr>
EOM
if [ -f "$WG_PATH" ];then
cat<<EOM
<tr><th>Wireguard Public-Key:</th><td>$(uci get credentials.backbone_secret.wireguard_key | wg pubkey)</td>
 <td title="Einstellungen werden nach Neustart wirksam."><button onclick="form_submit(document.forms.backbone_form_keygen,'keygen_wg','none')" name="bb_btn_new" type="button">Wireguard Key Generieren</button></td></tr>
EOM
fi
cat<<EOM
</table>
</form>
</fieldset>
<br>
<fieldset class="bubble">
<legend>Akzeptierte Verbindungen (Server)</legend>
<form name="backbone_form_connection_in" action="backbone.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<table>
<tr><th>Typ</th><th>Knotennummer</th><th>Public-Key</th><th>Kommentar</th><th>Verbunden</th><th>&nbsp;</th></tr>
EOM

	TOGGEL=1
	config_load ddmesh
	config_foreach show_accept backbone_accept

	if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
		cat<<EOM
	<tr class="colortoggle$TOGGEL">
	<td title="Typ"><select onchange="enable_formfields_incomming();" name="form_backbone_incomming_peer_type" size="1">
EOM
	if [ -f "$FASTD_PATH" ]; then
		echo "<option selected value=\"fastd\">fastd</option>"
	fi
	if [ -f "$WG_PATH" ]; then
		echo "<option value=\"wireguard\">wireguard</option>"
	fi
	cat<<EOM
	</select></td>
	<td title="Knoten der Gegenstelle"> <input disabled name="form_backbone_incomming_peer_node" type="text" size="5" value=""></td>
	<td title="Public Key der Gegenstelle"> <input name="form_backbone_incomming_peer_key" type="text" size="40" value=""></td>
	<td title="Kommentar"> <input name="form_backbone_incomming_peer_comment" type="text" size="20" value=""></td>
	<td></td>
	<td><button onclick="if(checkinput_incomming())form_submit(document.forms.backbone_form_connection_in,'client_add_incomming','none')" name="bb_btn_new" title="Verbindung speichern" type="button">Neu</button></td>
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
<form name="backbone_form_connection_out" action="backbone.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<table>
<tr><th>Typ</th><th>Knotennumer</th><th>Server-Hostname (Freifunk-Router)</th><th>Server-Port</th><th>Public-Key</th><th>Verbunden</th><th>&nbsp;</th></tr>
EOM

	TOGGEL=1
	config_load ddmesh
	config_foreach show_outgoing backbone_client

	if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
	cat<<EOM
 <tr class="colortoggle$TOGGEL">
 <td title="Typ"><select onchange="enable_formfields_outgoing();" name="form_backbone_outgoing_peer_type" size="1">
EOM
if [ -f "$FASTD_PATH" ]; then
echo "<option selected value=\"fastd\">fastd</option>"
fi
if [ -f "$WG_PATH" ]; then
echo "<option value=\"wireguard\">wireguard</option>"
fi
cat<<EOM
 </select></td>
 <td title="Zielknottennummer (nur f&uuml;r Wireguard)"><input disabled name="form_backbone_outgoing_peer_node" type="text" size="5" value=""></td>
 <td title="Hostname oder IP Adresse &uuml;ber den ein anderer Freifunk Router erreichbar ist (z.b. xxx.dyndns.org). Kann eine IP im LAN oder IP/Hostname im Internet sein."><input name="form_backbone_outgoing_peer_hostname" type="text" size="15" value=""></td>
 <td title="Port des Servers"><input name="form_backbone_outgoing_peer_port" type="text" size="8" value="$DEFAULT_FASTD_PORT"></td>
 <td title="Public Key der Gegenstelle"><input name="form_backbone_outgoing_peer_key" type="text" size="40" value="$DEFAULT_FASTD_KEY"></td>
 <td></td>
 <td><button onclick="if(checkinput_outgoing())form_submit(document.forms.backbone_form_connection_out,'client_add_outgoing','none')" name="bb_btn_new" title="Verbindung speichern" type="button">Neu</button></td>
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
<form name="backbone_form_apply" action="backbone.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<button onclick="form_submit(document.forms.backbone_form_apply,'refresh','none')" name="bb_btn_apply" title="Seite Aktualisieren" type="button">Seite Aktualisieren</button>
<button onclick="form_submit(document.forms.backbone_form_apply,'restart','none')" name="bb_btn_apply" title="Werte werden sofort &uuml;bernommen und Backbone neu gestartet" type="button">Backbone-Neustart</button>
</form>
EOM
}


if [ -z "$QUERY_STRING" ]; then

cat<<EOM
Das Backbone kann verwendet werden, um Verbindungen zu anderen Netzwerk-Wolken des Freifunknetzes aufzubauen.<br />Notwendig wird dies,
wenn man keine WLAN-Verbindung herstellen kann, aber Stadtbereiche miteinander verbinden m&ouml;chte.<br>
Dabei l&auml;uft der Router als Server und Client. Die Verbindung wird &uuml;ber das Internet oder LAN aufgebaut.<br>
Der Router beschr&auml;nkt dabei die Anzahl der ausgehenden und eingehenden Verbindungen auf maximal <b>$NUMBER_OF_CLIENTS</b>, um den Router nicht zu &uuml;berlasten.
<br><br>
EOM
	content
else
	MSG=0
	RESTART=0
	case $form_action in
		local)
			uci set ddmesh.backbone.fastd_port=$backbone_local_fastd_port
			uci_commit.sh
			MSG=2
		;;
		client_del) uci delete ddmesh.$form_entry;
		uci_commit.sh
		MSG=4
		;;
		accept_del) uci delete ddmesh.$form_entry;
		uci_commit.sh
		MSG=4;
		;;
		client_add_outgoing)
			if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
				uci add ddmesh backbone_client >/dev/null
				uci set ddmesh.@backbone_client[-1].host="$form_backbone_outgoing_peer_hostname"
				uci set ddmesh.@backbone_client[-1].port="$form_backbone_outgoing_peer_port"
				uci set ddmesh.@backbone_client[-1].public_key="$form_backbone_outgoing_peer_key"
				uci set ddmesh.@backbone_client[-1].type="$form_backbone_outgoing_peer_type"
				uci set ddmesh.@backbone_client[-1].node="$form_backbone_outgoing_peer_node"
				uci_commit.sh
				MSG=3;
			else
				MSG=6;
			fi
			;;
		client_add_incomming)
			if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
				uci add ddmesh backbone_accept >/dev/null
				uci set ddmesh.@backbone_accept[-1].comment="$form_backbone_incomming_peer_comment"
				uci set ddmesh.@backbone_accept[-1].public_key="$form_backbone_incomming_peer_key"
				uci set ddmesh.@backbone_accept[-1].node="$form_backbone_incomming_peer_node"
				uci set ddmesh.@backbone_accept[-1].type="$form_backbone_incomming_peer_type"
				uci_commit.sh
				MSG=3;
			else
				MSG=6;
			fi
			;;

		keygen_fastd)
			/usr/lib/ddmesh/ddmesh-backbone.sh gen_secret_key
			;;
		keygen_wg)
			/usr/lib/ddmesh/ddmesh-backbone.sh gen_wgsecret_key
			;;
		restart)
			html_msg 8
			RESTART=1
			MSG=7;
			;;
		refresh)
			;;

	esac
	test $RESTART -eq 1 && /usr/lib/ddmesh/ddmesh-backbone.sh restart >/dev/null 2>&1
	html_msg $MSG
	echo "<br>"
	content

fi

. /usr/lib/www/page-post.sh ${0%/*}
