#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

if [ "$(uci get ddmesh.system.node)" -le "$(uci get ddmesh.system.tmp_max_node)" ]; then
#	export NOMENU=1
	export TITLE="Auto-Setup"
else
	export TITLE="Verwaltung &gt; Allgemein: Auto-Setup"
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
	Die Registrierung erfolgt automatisch, wenn der Router eine Verbindung zum Registrator ($FFDD)
	erh&auml;lt. Dabei kann die Verbindung &uuml;ber das Freifunk-Netz oder &uuml;ber eine Internetverbindung erfolgen.<br />
	Nach dem Autosetup, welches alle notwendigen Freifunk-Einstellungen vornimmt, muss eventuell der WAN-Anschluss konfiguriert werden.<br />
	Wird irgendwann der Router zur&uuml;ckgesetzt, wird eine neue Registrierung durchgef&uuml;hrt. Da durch das Zur&uuml;cksetzen
	der Registrierungs-Schl&uuml;ssel neu erzeugt werden muss und es beim Registrator bereits eine Registrierung mit der gleichen Knoten-Nr.
	gibt, wird dabei eine neue Knoten-Nr. automatisch vergeben. Der Router erh&auml;lt dadurch ebenfalls eine neue Freifunk-IP-Adresse.<br />
	<br />
	<br />
	<div class="note"><b>Hinweis</b>: <div> Nach einem Neustart des Routers, dauert es bis zu <b>5 Minuten</b>, bis der Router alle
	Informationen f&uuml;r den Zugang zum Freifunk-Netz gesammelt hat.</div>
	</div>
	<br />
	Hat der Router keine Verbindung zum Registrator, wird eine tempor&auml;re Knoten-Nr. vergeben, die später bei erfolgreicher Verbindung automatisch aktualisiert wird.<br />
	</td>
	</tr>

	<tr><td><b>Aktuelle Node:</b> $(uci get ddmesh.system.node)</td></tr>
	<tr><td><pre><div id="ajax_register">Lade...</div></pre></td></tr>
	</table>
</fieldset>
<SCRIPT LANGUAGE="JavaScript" type="text/javascript"><!--
ajax_register();
//--></SCRIPT>
EOM
if [ "$wifi_status_radio2g_up" = "1" ]; then
cat<<EOM
<br />
<fieldset class="bubble">
<legend>Access-Points (automatische Aktualisierung)</legend>
<div id="ajax_wlan">Lade...</div>
</fieldset>
<SCRIPT LANGUAGE="JavaScript" type="text/javascript"><!--
ajax_wlan();
//--></SCRIPT>
<br />
EOM
fi

if [ "$wan_iface_present" = "1" ]; then

cat<<EOM
<fieldset class="bubble">
<legend >WAN-Anschluss-Status (automatische Aktualisierung)</legend>
<div id="ajax_dhcp">Lade...</div>
</fieldset>
<SCRIPT LANGUAGE="JavaScript" type="text/javascript"><!--
ajax_dhcp();
//--></SCRIPT>
EOM

fi

. /usr/lib/www/page-post.sh
