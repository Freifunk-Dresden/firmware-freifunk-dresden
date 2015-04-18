#!/bin/sh

if [ "$(uci get ddmesh.system.node)" -le "$(uci get ddmesh.system.tmp_max_node)" ]; then
#	export NOMENU=1
	export TITLE="Auto-Setup"
else
	export TITLE="Verwaltung &gt; Allgemein &gt; Automatic-Setup"
fi
 
. /usr/lib/www/page-pre.sh ${0%/*}
 
WIDTH=100

cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

cat<<EOM
<fieldset class="bubble">
<legend>Registrierung</legend>
	<table>

	<tr>
	<td>
	Die Registrierung erfolgt automatisch wenn der Router eine Verbindung zum Registrator ($FFDD)
	erh&auml;lt. Dabei kann die Verbindung &uuml;ber das Freifunk-Netz oder &uuml;ber eine Internetverbindung erfolgen.<br />
	Nach dem Autosetup, welches alle notwendigen Freifunk-Einstellungen macht, muss der WAN Anschlu&szlig; konfiguriert werden.<br />
	Wird irgendwann der Router zur&uuml;ckgesetzt wird eine neue Registrierung durchgef&uuml;hrt. Da durch das Zur&uuml;cksetzen
	der Registrierungs-Schl&uuml;ssel neu erzeugt werden muss und es beim Registrator bereits eine Registrierung mit der gleichen Node
	gibt, wird dann eine neue Node-Nummer automatisch vergeben. Der Router erh&auml;lt dadurch eine neue Freifunk-IP Adresse.<br />
	<br />
	Hat der Router keine Verbindung zum Registrator, wird eine tempor&auml;re Node-Nummer vergeben, die dann automatisch aktualisiert wird. <br />

	</td>
	</tr>		

	<tr><td><b>Aktuelle Node:</b> $(uci get ddmesh.system.node)</td></tr>	
	<tr><td><pre><div id="ajax_register">Lade...</div></pre></td></tr>	
	</table>
</fieldset>
<SCRIPT LANGUAGE="JavaScript" type="text/javascript"><!--
ajax_register();
//--></SCRIPT>
<br />
<fieldset class="bubble">
<legend>Access Points (automatische Aktualisierung)</legend>
<div id="ajax_wlan">Lade...</div>
</fieldset>
<SCRIPT LANGUAGE="JavaScript" type="text/javascript"><!--
ajax_wlan();
//--></SCRIPT>
<br />
EOM

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wan)          
if [ -n "$net_device" ]; then

cat<<EOM
<fieldset class="bubble">
<legend >WAN Anschlu&szlig; Status (automatische Aktualisierung)</legend>
<div id="ajax_dhcp">Lade...</div>
</fieldset>
<SCRIPT LANGUAGE="JavaScript" type="text/javascript"><!--
ajax_dhcp();
//--></SCRIPT>
EOM

fi

. /usr/lib/www/page-post.sh

