#!/bin/sh

#redirect to splash               
if [ "$SERVER_PORT" = "81" ];then          
        export DOCUMENT_ROOT="/www/splash" 
        $DOCUMENT_ROOT/index.cgi                      
        exit 0                                        
fi                                     

node=$(uci get ddmesh.system.node)                                                          
tmpmin=$(uci get ddmesh.system.tmp_min_node)                                                
tmpmax=$(uci get ddmesh.system.tmp_max_node)                                                
if [ $node -ge $tmpmin -a $node -le $tmpmax ]; then
 	#export NOMENU=1
	export TITLE="Auto-Setup"

	. $DOCUMENT_ROOT/page-pre.sh

#echo "<pre>";set;echo "/<pre>"

cat<<EOM
<h1>Auto-Setup</h1>
Diese Seite wird automatisch aufgerufen, wenn das erste Mal eine Freifunk Firmware auf den Router gespielt wurde.<br />
Der Router wurde mit am h&auml;ufigsten verwendeten Einstellungen konfiguriert. Die Einstellungen k&ouml;nnen sp&auml;ter ge&auml;ndert werden.<br />
Bei Start des Auto-Setup, wird nach einem Nutzernamen und Passwort gefragt. Wurden diese bisher nicht ge&auml;ndert, so lauten der
Nutzername "root" und das Passwort "admin".<br />
Das Passwort sollte nach dem Durchlaufen des Auto-Setup ge&auml;ndert werden.<br><br>
Dem Router wurde eine tempor&auml;re Node-Nummer vergeben wenn er nicht zuvor schon eine Node-Nummer von $FFDD zugewiesen wurde.
Nach einem Update mit  Werkseinstellung oder nach dem erstmaligem Aufspielen der Freifunk Firmware erh&auml;lt der Router unter Umst&auml;nden eine andere Node-Nummer und ist im Freifunknetz &uuml;ber eine andere IP erreichbar.<br />
<a href="/admin/autosetup.cgi">Starte Auto-Setup</a>
EOM

. $DOCUMENT_ROOT/page-post.sh

else #autosetup

export TITLE="Hauptseite"
. $DOCUMENT_ROOT/page-pre.sh

cat<<EOM
<fieldset class="bubble">
<p>Dies ist ein Freifunk WLAN-Access-Point, auf dem der Freifunk-Firmware Version $(cat /etc/version)
l&auml;uft.
Informationen &uuml;ber das Freifunk-Projekt finden sie im Internet unter <a href="http://$FFDD/">http://$FFDD/</a><br />
Es besteht kein Anspruch oder Garantie auf eine Internetverbindung. Die Verbindung zum Internet ist an
die Bereitstellung privater Internetzug&auml;nge gebunden und h&auml;ngt von der aktuellen Netzstruktur ab.<br />
F&uuml;r die Nutzung des Netzes gelten diese <a href="license.cgi?license=1">Nutzungsbedingungen</a> und das <a href="license.cgi?license=2">Pico Agreement</a>, welche zu beachten sind.</p>
</fieldset>
<br>

<fieldset class="bubble">
<legend>Links</legend>
<ul>
<li><a href="http://$FFDD/">Dresdner Freifunk</a></li>
</ul>
</fieldset>
EOM

. $DOCUMENT_ROOT/page-post.sh

fi #autosetup
