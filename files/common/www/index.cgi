#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

node=$(uci -q get ddmesh.system.node)
tmpmin=$(uci -q get ddmesh.system.tmp_min_node)
tmpmax=$(uci -q get ddmesh.system.tmp_max_node)
if [ $node -ge $tmpmin -a $node -le $tmpmax ]; then
 	#export NOMENU=1
	export TITLE="Auto-Setup"

	. /usr/lib/www/page-pre.sh

#echo "<pre>";set;echo "/<pre>"

cat<<EOM
<h1>Auto-Setup</h1>
Diese Seite wird automatisch aufgerufen, wenn das erste Mal eine Freifunk Firmware auf den Router gespielt wurde.<br />
Der Router wurde mit den am h&auml;ufigsten verwendeten Einstellungen konfiguriert. Die Einstellungen k&ouml;nnen sp&auml;ter
ge&auml;ndert werden.<br />
<br />
Das Passwort sollte nach dem Durchlaufen des Auto-Setups ge&auml;ndert werden.<br><br>
Dem Router wurde eine tempor&auml;re Knoten-Nummer vergeben.
Nach einem Update mit Werkseinstellungen oder nach dem erstmaligem Aufspielen der Freifunk-Firmware erh&auml;lt der Router
eine neue Knoten-Nummer und ist dann im Freifunk-Netz unter einer anderen IP-Adresse erreichbar.<br />
<a href="/admin/autosetup.cgi">Starte Auto-Setup</a>
EOM

. /usr/lib/www/page-post.sh

else #autosetup

export TITLE="Hauptseite"
. /usr/lib/www/page-pre.sh

cat<<EOM
<fieldset class="bubble">
<p>Dies ist ein Freifunk-WLAN-Access-Point, auf dem die Freifunk-Firmware-Version $(cat /etc/version)
l&auml;uft.
Informationen &uuml;ber das Freifunk-Projekt findest du im Internet unter <a href="http://$FFDD/">http://$FFDD/</a>.<br />
Es besteht kein Anspruch oder Garantie auf eine Internetverbindung. Die Verbindung zum Internet ist an
die Bereitstellung privater Internetzug&auml;nge gebunden und h&auml;ngt von der aktuellen Netzstruktur ab.<br />
F&uuml;r die Nutzung des Netzes gelten diese <a href="license.cgi?license=1">Nutzungsbedingungen</a> und das <a href="license.cgi?license=2">Pico Peering Agreement</a>, welche zu beachten sind.</p>
</fieldset>
<br>

<fieldset class="bubble">
<legend>Links</legend>
<ul>
<li><a href="http://$FFDD/">Freifunk Dresden</a></li>
</ul>
</fieldset>
<br>

<fieldset class="bubble">
<legend>Standort-Infos</legend>
<img alt="" src="$(/usr/lib/ddmesh/ddmesh-wttr.sh -url)">
</ul>
</fieldset>
EOM

. /usr/lib/www/page-post.sh

fi #autosetup
