#!/bin/ash
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

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

FASTD_PATH="$(which fastd)"
KEY_LEN_FASTD=64

WG_PATH="$(which wg)"
KEY_LEN_WG=44
WG_HAND_SHAKE_TIME_S=120
UTC=$(date +"%s")
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh tbbwg wg)

mkdir -p $STATUS_DIR

cat<<EOM
<script type="text/javascript">
function ask (n)
{
	var x = window.confirm("Verbindung zu "+n+" wirklich löschen?");
	return x;
}

function checkinput_server_ports ()
{
	var v;
	v = document.backbone_form_local.form_backbone_local_fastd_port.value;
	if( checknumber(v) || v<1 || v>65535 ){ alert("Fastd Server Port ist ungültig (1-65535)");return 0;}
	v = document.backbone_form_local.form_backbone_local_wg_port.value;
	if( checknumber(v) || v<1 || v>65535 ){ alert("Wireguard Server Port ist ungültig (1-65535)");return 0;}
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

function form_submit (form, action, entry)
{
	form.form_action.value = action;
	form.form_entry.value = entry;
	form.submit();
}

function form_submit_checked (form, action, entry, checked)
{
	form.form_action.value = action;
	form.form_entry.value = entry;
	form.form_checked.value = checked ? 1 : 0;
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
		document.getElementsByName('bb_btn_wgcheck')[0].disabled = false;
	}
	else
	{
		document.getElementsByName('form_backbone_outgoing_peer_node')[0].disabled = true;
		document.getElementsByName('bb_btn_wgcheck')[0].disabled = true;
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
	local vcomment
	local vkey
	local vtype
	local vnode
	local disabled

	config_get vnode "$config" node
	config_get vkey  "$config" public_key
	config_get vcomment "$config" comment
	config_get vtype "$config" type
	if [ "$vtype" = "" ]; then
		vtype="fastd"
	fi
	config_get disabled "$config" disabled

	if [ "$vtype" = "fastd" ]; then
		test -f "$STATUS_DIR/$vkey" && CONNECTED=/images/yes.png || CONNECTED=/images/no.png
		connect_title=""
	else
		if [ -n "$vkey" ]; then
			IFS='	'
			hs=$(wg show $wg_ifname latest-handshakes | grep "$vkey" | sed 's#.*\t##g')
			if [ -n "$hs" ]; then
				diff=$(( $UTC - $hs ))
				[ $diff -lt $WG_HAND_SHAKE_TIME_S ] && CONNECTED=/images/yes.png || CONNECTED=/images/no.png
			else
				CONNECTED=/images/no.png
			fi
			unset IFS
			connect_title="Handshake vor $diff s"
		fi
	fi

	cat<<EOM
	<tr class="colortoggle$TOGGEL">
	<td><input onclick="form_submit_checked(document.forms.backbone_form_connection_in,'update_enabled','$config', this.checked)" type="checkbox" $(if [ "$disabled" != "1" ];then echo ' checked="checked"';fi)></td>
	<td>$vtype</td> <td>$vnode</td> <td>$vkey</td>	<td>$vcomment</td>
	<td><img title="$connect_title" src="$CONNECTED"></td>
	<td><button onclick="if(ask('$vnode'))form_submit(document.forms.backbone_form_connection_in,'accept_del','$config')" title="Verbindung l&ouml;schen" type="button">
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
	local vhost
	local vport
	local vkey
	local vtype
	local vnode
	local disabled

	config_get vnode "$config" node
	config_get vhost "$config" host
	config_get vport "$config" port
	config_get vkey  "$config" public_key
	config_get vtype "$config" type
	if [ "$vtype" = "" ]; then
		vtype="fastd"
	fi
	config_get disabled "$config" disabled

	if [ "$vtype" = "fastd" ]; then
		test -f "$STATUS_DIR/$vkey" && CONNECTED=/images/yes.png || CONNECTED=/images/no.png
		connect_title=""
	else
		IFS='	'
		hs=$(wg show $wg_ifname latest-handshakes | grep "$vkey" | sed 's#.*\t##g')
		if [ -n "$hs" ]; then
			diff=$(( $UTC - $hs ))
			[ $diff -lt $WG_HAND_SHAKE_TIME_S ] && CONNECTED=/images/yes.png || CONNECTED=/images/no.png
		else
			CONNECTED=/images/no.png
		fi
		unset IFS
		connect_title="Handshake vor $diff s"
	fi

	cat<<EOM
	<tr class="colortoggle$TOGGEL">
	<td><input onclick="form_submit_checked(document.forms.backbone_form_connection_out,'update_enabled','$config', this.checked)" type="checkbox" $(if [ "$disabled" != "1" ];then echo ' checked="checked"';fi)></td>
	<td>$vtype</td><td>$vhost</td><td>$vport</td><td></td><td>$vnode</td><td>$vkey</td>
	<td><img title="$connect_title" src="$CONNECTED"></td>
	<td>
	<button onclick="if(ask('$vhost'))form_submit(document.forms.backbone_form_connection_out,'client_del','$config')" title="Verbindung l&ouml;schen" type="button">
	<img src="/images/loeschen.gif" align=bottom width=16 height=16 hspace=4></button></td></tr>
EOM

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

	backbone_local_wg_port=$(uci get ddmesh.backbone.wg_port)
	backbone_local_wg_port=${backbone_local_wg_port:-$DEFAULT_WG_PORT}

	cat<<EOM
<fieldset class="bubble">
<legend>Backbone-Einstellungen</legend>
<form name="backbone_form_local" action="backbone.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<table>
<tr>
<th title="Port des fastd Servers">Fastd-Server-Port:</th>
EOM
if [ -f "$WG_PATH" ];then
cat<<EOM
<th title="Port des wireguard Servers">Wireguard Server-Port:</th>
EOM
fi
cat<<EOM
<th></th>
</tr>

<tr>
<td><input name="form_backbone_local_fastd_port" type="text" size="8" value="$backbone_local_fastd_port"</td>
EOM
if [ -f "$WG_PATH" ];then
cat<<EOM
<td><input name="form_backbone_local_wg_port" type="text" size="8" value="$backbone_local_wg_port"</td>
EOM
fi
cat<<EOM
<td title="Einstellungen werden nach Neustart wirksam."><button onclick="if(checkinput_server_ports())form_submit(document.forms.backbone_form_local,'local','none')" name="bb_btn_new" type="button">Speichern</button></td>
</tr>
</table>
</form>

<form name="backbone_form_keygen" action="backbone.cgi" method="POST">
<input name="form_action" value="none" type="hidden">
<input name="form_entry" value="none" type="hidden">
<table>
<tr><td colspan="3"><font color="red">Achtung: Wird ein neuer Schl&uuml;ssel generiert, muss dieser bei <b>allen</b> Backbone-Servern aktualisiert werden, da sonst keine Verbindung mehr von diesem Router akzeptiert wird.</font></td></tr>
<tr><th>Fastd Public-Key:</th><td>$(/usr/lib/ddmesh/ddmesh-backbone.sh get_public_key)</td>
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
<input name="form_checked" value="none" type="hidden">
<table>
<tr><th>Aktiviert</th><th>Typ</th><th>Knotennummer</th><th>Public-Key</th><th>Kommentar</th><th>Verbunden</th><th>&nbsp;</th></tr>
EOM

	TOGGEL=1

	config_load ddmesh
	config_foreach show_accept backbone_accept

	if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
		cat<<EOM
	<tr class="colortoggle$TOGGEL">
	<td><input name="form_backbone_incomming_enabled" type="CHECKBOX" VALUE="1"></td>
	<td title="Typ"><select onchange="enable_formfields_incomming();" name="form_backbone_incomming_peer_type" size="1">
EOM
	if [ -f "$WG_PATH" ]; then
		echo "<option selected value=\"wireguard\">wireguard</option>"
	fi
	if [ -f "$FASTD_PATH" ]; then
		echo "<option value=\"fastd\">fastd</option>"
	fi
	cat<<EOM
	</select></td>
	<td title="Knoten der Gegenstelle"> <input name="form_backbone_incomming_peer_node" type="text" size="5" value=""></td>
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
<input name="form_checked" value="none" type="hidden">
<table>
<tr><th>Aktiv</th><th>Typ</th><th>Server-Hostname (Freifunk-Router)</th><th>Server-Port</th><th></th><th>Knotennummer</th><th>Public-Key</th><th>Verbunden</th><th>&nbsp;</th></tr>
EOM

	TOGGEL=1
	config_load ddmesh
	config_foreach show_outgoing backbone_client

	if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
	cat<<EOM
 <tr class="colortoggle$TOGGEL">
 <td><input name="form_backbone_outgoing_enabled" type="CHECKBOX" VALUE="1" checked></td>
 <td title="Typ"><select onchange="enable_formfields_outgoing();" name="form_backbone_outgoing_peer_type" size="1">
EOM
if [ -f "$WG_PATH" ]; then
	echo "<option selected value=\"wireguard\">wireguard</option>"
fi
if [ -f "$FASTD_PATH" ]; then
	echo "<option value=\"fastd\">fastd</option>"
fi
cat<<EOM
 </select></td>
 <td title="Hostname oder IP Adresse &uuml;ber den ein anderer Freifunk Router erreichbar ist (z.b. xxx.dyndns.org). Kann eine IP im LAN oder IP/Hostname im Internet sein."><input name="form_backbone_outgoing_peer_hostname" type="text" size="15" value=""></td>
 <td title="Port des Servers"><input name="form_backbone_outgoing_peer_port" type="text" size="8" value="$DEFAULT_WG_PORT"></td>
 <td><button onclick="ajax_regwg(document.backbone_form_connection_out.form_backbone_outgoing_peer_hostname.value)" name="bb_btn_wgcheck" title="Pr&uuml;fe Zugriff" type="button"><img src="/images/key16.png"></button></td>
 <td title="Zielknottennummer (nur f&uuml;r Wireguard)"><input id="wgcheck_node" name="form_backbone_outgoing_peer_node" type="text" size="5" value=""></td>
 <td class="nowrap" title="Public Key der Gegenstelle"><input id="wgcheck_key" name="form_backbone_outgoing_peer_key" type="text" size="40" value=""></td>
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
			uci set ddmesh.backbone.fastd_port=$form_backbone_local_fastd_port
			uci set ddmesh.backbone.wg_port=$form_backbone_local_wg_port
			uci_commit.sh
			MSG=2
		;;

		client_del)
			uci delete ddmesh.$form_entry;
			uci_commit.sh
			MSG=4
		;;

		accept_del)
			uci delete ddmesh.$form_entry;
			uci_commit.sh
			MSG=4;
		;;

		client_add_outgoing)
			if [ $COUNT -lt $NUMBER_OF_CLIENTS ];then
				uci add ddmesh backbone_client >/dev/null
				uci set ddmesh.@backbone_client[-1].host="$form_backbone_outgoing_peer_hostname"
				uci set ddmesh.@backbone_client[-1].port="$form_backbone_outgoing_peer_port"
				uci set ddmesh.@backbone_client[-1].public_key="$(uhttpd -d $form_backbone_outgoing_peer_key)"
				uci set ddmesh.@backbone_client[-1].type="$form_backbone_outgoing_peer_type"
				uci set ddmesh.@backbone_client[-1].node="$form_backbone_outgoing_peer_node"
				if [ "$form_backbone_outgoing_enabled" = "1" ]; then
					uci set ddmesh.@backbone_client[-1].disabled='0'
				else
					uci set ddmesh.@backbone_client[-1].disabled='1'
				fi
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
				uci set ddmesh.@backbone_accept[-1].public_key="$(uhttpd -d $form_backbone_incomming_peer_key)"
				uci set ddmesh.@backbone_accept[-1].node="$form_backbone_incomming_peer_node"
				uci set ddmesh.@backbone_accept[-1].type="$form_backbone_incomming_peer_type"
				if [ "$form_backbone_incomming_enabled" = "1" ]; then
					uci set ddmesh.@backbone_accept[-1].disabled='0'
				else
					uci set ddmesh.@backbone_accept[-1].disabled='1'
				fi
				uci_commit.sh
				MSG=3;
			else
				MSG=6;
			fi
			;;

		update_enabled)
			if [ "$form_checked" = "1" ]; then
				uci set ddmesh.${form_entry}.disabled='0'
			else
				uci set ddmesh.${form_entry}.disabled='1'
			fi
			uci_commit.sh
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
