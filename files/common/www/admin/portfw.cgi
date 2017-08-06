#!/bin/sh

export TITLE="Verwaltung > Expert > Portweiterleitung"
. /usr/lib/www/page-pre.sh ${0%/*}
. /lib/functions.sh

show_rules() {
cat<<EOM

<script type="text/javascript">
function ask (r,name) {
var x = window.confirm("Rule: ["+r+": "+name+"] wirklich loeschen?");
return x;
}
</script>

<H2>$TITLE</H2>
<br>

<fieldset class="bubble">
<legend>Portweiterleitungen</legend>
<table>
<tr><th>Rule</th><th>Name</th><th>Protokoll</th><th>Port(Bereich)</th><th>Ziel-IP</th><th>Ziel-Port</th></tr>
EOM

T=1
C=0
print_rules() {
	local config="$1"
	local user_arg="$2"

	local vname
	local vproto
	local vsrc_dport
	local vdest_ip
	local vdest_port

	config_get vname "$config" name
	config_get vproto "$config" proto
	config_get vsrc_dport "$config" src_dport
	config_get vdest_ip "$config" dest_ip
	config_get vdest_port "$config" dest_port

	echo "<tr class=\"colortoggle$T\" >"
	echo "<td >$C</td>"
	echo "<td >$vname</td>"
	echo "<td >$vproto</td>"
	echo "<td >$vsrc_dport</td>"
	echo "<td >$vdest_ip</td>"
	echo "<td >$vdest_port</td>"
	echo "<td valign=bottom><FORM name=\"form_portfw_del_"$C"\" ACTION=\"portfw.cgi\" METHOD=\"POST\">"
	echo "<input name=\"form_action\" value=\"del\" type=\"hidden\">"
	echo "<input name=\"form_rule_config\" value=\"$config\" type=\"hidden\">"
	echo "<input name=\"form_rule_name\" value=\"$vname\" type=\"hidden\">"
	echo "<input name=\"form_rule_number\" value=\"$C\" type=\"hidden\">"
	echo "<button onclick=\"if(ask('$C','$vname'))document.forms.form_portfw_del_"$C".submit()\" name=\"form_portfw_btn_del\" title=\"Regel [$C:$vname] l&ouml;schen\" type=\"button\"><img src="/images/loeschen.gif" align=bottom width=16 height=16 hspace=4></button></FORM></td></tr>"
	if [ $T = 1 ]; then T=2 ;else T=1; fi
	C=$(($C+1))
}

config_load ddmesh
config_foreach print_rules portforwarding

PORTS=$(/usr/lib/ddmesh/ddmesh-portfw.sh ports | sed 's# #, #')

cat<<EOM
</table>
</fieldset>
<br/><br/>

<b>Folgende Ports werden vom Router verwendet und k&ouml;nnen nicht verwendet werden:</b><br/>
$PORTS, $(uci get ddmesh.backbone.server_port), $(uci get ddmesh.privnet.server_port)<br/>
<br />
<form name="form_portfw_new" action="portfw.cgi" method="POST">
<input name="form_action" value="add" type="hidden">
<fieldset class="bubble">
<legend>Neue Regel</legend>
<table>
<tr><th>Name</th><th>Protokoll</th><th>Port(Bereich)</th><th>LAN Ziel-IP</th><th>Ziel-Port</th><th></th></tr>
<tr class="colortoggle0"><td title="Der Name dient zur Wiedererkennung"><input name="form_rule_name" type="text" size="8"></td>
<td> <select name="form_rule_proto" size="1">
 <option selected value="tcp">tcp</option>
 <option value="udp">udp</option>
 <option value="tcpudp">tcp+udp</option>
 </select></td>
<td title="Port oder Portbereich. Bereich wird durch '-' angegeben.(z.B.: 7000-8000)"><input name="form_rule_src_dport" type="text" size="8"></td>
<td title="Ziel IP aus dem LAN Bereich"><input name="form_rule_dest_ip" type="text" size="15"></td>
<td title="Zielport (definiert den Zielport-Start wenn ein Bereich weitergeleitet wird)"><input name="form_rule_dest_port" type="text" size="8"></td>
<td><input type="submit" value="Speichern"></td>
</tr>
</table>
</fieldset>
</form>
EOM
}

if [ -z "$QUERY_STRING" ]; then
	show_rules
else
	case $form_action in
		del)
			uci delete ddmesh.$form_rule_config
			uci commit
			notebox "Regel $form_rule_number ($form_rule_name) wurde gel&ouml;scht. &Auml;nderungen sind sofort aktiv."
			/usr/lib/ddmesh/ddmesh-portfw.sh load
		;;
		add)
			uci add ddmesh portforwarding >/dev/null
			uci set ddmesh.@portforwarding[-1].name="$form_rule_name"
			uci set ddmesh.@portforwarding[-1].proto="$form_rule_proto"
			uci set ddmesh.@portforwarding[-1].src_dport="$form_rule_src_dport"
			uci set ddmesh.@portforwarding[-1].dest_ip="$form_rule_dest_ip"
			uci set ddmesh.@portforwarding[-1].dest_port="$form_rule_dest_port"
			uci commit
			notebox "&Auml;nderungen sind sofort aktiv."
			/usr/lib/ddmesh/ddmesh-portfw.sh load
		;;
	esac
	show_rules
fi


. /usr/lib/www/page-post.sh ${0%/*}
