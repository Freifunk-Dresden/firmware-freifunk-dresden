#!/bin/sh

. /lib/functions.sh

export TITLE="Verwaltung &gt; Konfiguration: Knoten ignorieren"
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<h2>$TITLE</h2>
<br>

Hier k&ouml;nnen benachbarte Knoten gespeichert werden, die ignoriert werden sollen.<br>
Die Einstellungen sind erst nach Aktivierung oder Neustart des Routers aktiv.<br><br>
EOM

display_ignored_nodes() {
cat<<EOM

<fieldset class="bubble">
<legend>Gespeicherte Knoten</legend>
<table>

<tr><th width="100">Knoten</th><th>LAN/WAN</th><th>Backbone</th><th>Wifi-Adhoc</th><th>Wifi-802.11s 5GHz</th><th>Wifi-802.11s 5GHz</th><th></th></tr>
EOM

T=1
C=0
print_node() {
	entry=$1
	IFS=':'
	set $entry
	unset IFS
	local node=$1
	local opt_lan=$2
	local opt_tbb=$3
	local opt_wifi_adhoc=$4
	local opt_wifi2_mesh=$5
	local opt_wifi5_mesh=$6

	# old format
	[ -z "$opt_lan" -a -z "$opt_tbb" -a -z "$opt_wifi_adhoc" -a -z "$opt_wifi2_mesh" -a -z "$opt_wifi5_mesh" ] && opt_wifi_adhoc='1'

	if [ -n "$1" ]; then
		echo "<tr class=\"colortoggle$T\" ><td width=\"100\">$node</td>"
		echo "<td><input disabled name="form_opt_lan" type="checkbox" value="1" $(if [ "$opt_lan" = "1" ];then echo 'checked="checked"';fi)></td>"
		echo "<td><input disabled name="form_opt_tbb" type="checkbox" value="1" $(if [ "$opt_tbb" = "1" ];then echo 'checked="checked"';fi)></td>"
		echo "<td><input disabled name="form_opt_wifi_adhoc" type="checkbox" value="1" $(if [ "$opt_wifi_adhoc" = "1" ];then echo 'checked="checked"';fi)></td>"
		echo "<td><input disabled name="form_opt_wifi2_mesh" type="checkbox" value="1" $(if [ "$opt_wifi2_mesh" = "1" ];then echo 'checked="checked"';fi)></td>"
		echo "<td><input disabled name="form_opt_wifi5_mesh" type="checkbox" value="1" $(if [ "$opt_wifi5_mesh" = "1" ];then echo 'checked="checked"';fi)></td>"
		echo "<td valign=bottom><FORM name=\"form_node_del_"$C"\" ACTION=\"ignore.cgi\" METHOD=\"POST\">"
		echo "<input name=\"form_action\" value=\"del\" type=\"hidden\">"
		echo "<input name=\"form_node\" value=\"$entry\" type=\"hidden\">"
		echo "<button onclick=\"document.forms.form_node_del_"$C".submit()\" name=\"form_btn_del\" title=\"Knoten l&ouml;schen\" type=\"button\"><img src="/images/loeschen.gif" align=bottom width=16 height=16 hspace=4></button></FORM></td></tr>"
		if [ $T = 1 ]; then T=2 ;else T=1; fi
		C=$(($C+1))
	fi
}
config_load ddmesh
config_list_foreach ignore_nodes node print_node

cat<<EOM
<tr><td colspan="3"><form name="form_node_del_all" action="ignore.cgi" method="post">
<input name="form_action" value="delall" type="hidden">
<button onclick="document.forms.form_node_del_all.submit()" name="form_btn_delall" title="L&ouml;sche alle Knoten" type="button">Alle Knoten l&ouml;schen</button>
</form></td></tr>

</table>
</fieldset>
<br>
<fieldset class="bubble">
<legend>Knoten hinzuf&uuml;gen</legend>
<form name="form_node_new" action="ignore.cgi" method="post">
<input name="form_action" value="add" type="hidden">
<table>
 <tr><th width="100">Knoten</th><th>LAN/WAN</th><th>Backbone</th><th>Wifi-Adhoc</th><th>Wifi-802.11s 2.4GHz</th><th>Wifi-802.11s 5GHz</th><th></th></tr>
 <tr>	<td><input name="form_node" type="text" value="" size="17" maxlength="17"></td>
	<td><input name="form_opt_lan" type="checkbox" value="1" ></td>
	<td><input name="form_opt_tbb" type="checkbox" value="1" ></td>
	<td><input name="form_opt_wifi_adhoc" type="checkbox" value="1" ></td>
	<td><input name="form_opt_wifi2_mesh" type="checkbox" value="1" ></td>
	<td><input name="form_opt_wifi5_mesh" type="checkbox" value="1" ></td>
	<td><input title="Knoten hinzuf&uuml;gen" type="submit" value="Neu"></td>
 </tr>
</table>
</form>
</fieldset>
<br>
<form name="form_firewall_update" action="ignore.cgi" method="post">
<input name="form_action" value="firewall_update" type="hidden">
<input type="submit" value="Aktualisiere Konfiguration">
</form>

EOM
EOM
#end display_ignored_nodes
}

if [ -n "$QUERY_STRING" ]; then
	if [ -n "$form_action" ]; then
		case $form_action in
		  add)
			if [ -z "$(uci get ddmesh.ignore_nodes)" ]; then
				uci add ddmesh ignore_nodes
				uci rename ddmesh.@ignore_nodes[-1]='ignore_nodes'
			fi

			node=$(uhttpd -d $form_node)
			entry="$node:$form_opt_lan:$form_opt_tbb:$form_opt_wifi_adhoc:$form_opt_wifi2_mesh:$form_opt_wifi5_mesh"
			uci add_list ddmesh.ignore_nodes.node="$entry"
			uci_commit.sh
			notebox "Knoten <b>$node</b> wurde zur Konfiguration hinzugef&uuml;gt. Bitte Konfiguration aktualisieren!"
			;;
		  del)
			node=$(uhttpd -d $form_node)
			uci del_list ddmesh.ignore_nodes.node="$node"
			uci_commit.sh
			notebox "Knoten <b>$node</b> wurde gel&ouml;scht. Bitte Konfiguration aktualisieren!"
			;;
		  delall)
			uci delete ddmesh.ignore_nodes.node
			uci_commit.sh
			notebox "Alle Knoten wurden gel&ouml;scht. Bitte Konfiguration aktualisieren!"
			;;
		  firewall_update)
			/usr/lib/ddmesh/ddmesh-firewall-addons.sh update_ignore
			notebox "Firewall wurde aktualisiert"
			;;
		esac
	fi
fi

display_ignored_nodes

. /usr/lib/www/page-post.sh ${0%/*}
