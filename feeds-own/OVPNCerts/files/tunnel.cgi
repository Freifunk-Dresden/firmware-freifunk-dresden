#!/bin/sh

. /lib/functions.sh

export TITLE="Verwaltung > Software"

OVPN_FILE="/tmp/ovpn.tgz"

if [ "$REQUEST_METHOD" = "GET" -a -n "$QUERY_STRING" ]; then
	. $DOCUMENT_ROOT/page-pre.sh ${0%/*}
	notebox 'GET not allowed'
	. $DOCUMENT_ROOT/page-post.sh ${0%/*}
	exit 0
fi
#get form data and optionally file 
eval $(/usr/bin/freifunk-upload -e 2>/dev/null)

. $DOCUMENT_ROOT/page-pre.sh ${0%/*}
echo "<H1>$TITLE</H1>"

avail_size="$(df -k /overlay | sed -n '2,1{s# \+# #g; s#[^ ]\+ [^ ]\+ [^ ]\+ \([^ ]\+\) .*#\1#;p}')"

[ "$form_action" != "install" ] && rm -f $OVPN_FILE

show_page() {
 	cat<<EOM
	<form name="form_upload" ACTION="tunnel.cgi" ENCTYPE="multipart/form-data" METHOD="POST">
	<input name="form_action" value="upload" type="hidden">
	 <fieldset class="bubble">
	 <legend>Openvpn Zertifikat-Installation</legend>
	 <table>
	 <tr><th width="100">Certifikate&nbsp;(*.tgz&nbsp;oder&nbsp;*.tar.gz):</th>
	     <td><input name="form_filename" size="40" type="file" value="Durchsuche..."></td></tr>	
	 <tr><td colspan="2">&nbsp;</td></tr>
	 <tr><td colspan="2"><input name="form_submit" type="submit" value="Zertifikate laden">
	     <input name="form_abort" type="reset" value="Abbruch"></td></tr>
	 </table>
	 </fieldset>
	</form>
	<br />
	<fieldset class="bubble">
	<legend>Hinweise</legend>
	<ul>
	<li> Das tgz-file sollte alle Openvpn-Zertifikate und das Config-File enthalten.</li>
	<li> Das Config-File muss auf <b>.conf</b> oder <b>.ovpn</b> enden.</li>
	<li> Es sollte auf Unterverzeichnisse verzichtet werden. Wenn Pfade verwendet werden, sollten diese im Config-File als 
	relative Pfade aufgef&uuml;hrte werden.</li>
	<li> Werden Login Daten gebraucht, so muss das File welches Nutzerkennung (1.Zeile) und Passwort (2.Zeile) <b>openvpn.login</b> hei&szlig;en;</li>
	</ul>
	<pre>

	Die <b>fett</b> geschriebenen Bestandteile der Filenamen sind zwingend so zu benennen!
		
	Beispiel bei dem alle Zertifikate im config file hinterlegt sind und Nutzerkennung/Passwort verwendet werden:
	./abc.<b>conf</b> (oder abc.<b>ovpn</b>)
	./<b>openvpn.login</b>
	
	Beispiel bei dem Zertifikate und Keys extra liegen und keine Nutzerkennung/Passwort verwendet werden, sondern Zertifikate:
	./ca.crt
	./ca.key
	./client.crt
	./client.key
	./client.<b>conf</b> (oder client.<b>ovpn</b>)
	</pre>
	</fieldset>
EOM
}

if [ -z "$form_action" ]; then
	
	show_page
	
else #form_action

	case "$form_action" in
		upload)
			mv $ffout $OVPN_FILE
	
			cat<<EOM
				<fieldset class="bubble">
				<legend>Zertifikate Installieren</legend>
				<form name="form_update" action="tunnel.cgi" method="POST">
	 			<input name="form_action" value="install" type="hidden">
				 <table>
				 <tr><th>Datei:</th><td>$ffout</td></tr>
				 <tr><td colspan="2">
				 <input name="form_submit" type="submit" value="Zertifikate installieren">
				 <input name="form_abort" type="submit" value="Abbruch">
				 </td></tr>
				 </table>
				</form>
				</fieldset>
EOM
			;;
		install)
			#extract to tmp
			rm -rf /tmp/openvpn
			mkdir -p /tmp/openvpn
			cd /tmp/openvpn
			tar xzf $OVPN_FILE
			conf="$(ls *.ovpn *.conf)"
			login="$(ls *.login)"

			#prepare conf dir	
			mkdir -p /etc/openvpn
			cd /etc/openvpn/
			rm *.conf *.ovpn *.login
			cp -a /tmp/openvpn/* /etc/openvpn/
			test -f "$login" && mv "/tmp/openvpn/$login" /etc/openvpn/openvpn.login
			/etc/openvpn/gen-config.sh "/tmp/openvpn/$conf"
			
			notebox "Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst beim n&auml;chsten <A HREF="firmware.cgi">Neustart</A> aktiv."
			;;
		*)
		;;
	esac
fi	 

. $DOCUMENT_ROOT/page-post.sh ${0%/*}

