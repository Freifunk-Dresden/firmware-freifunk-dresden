#!/bin/sh

. /lib/functions.sh

export TITLE="Verwaltung > Software"

IPK_FILE="/tmp/packet.ipk"
OPKG_ERROR="/tmp/opkg.error"

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

[ "$form_action" != "upload_install" ] && [ "$form_action" != "install" ] && rm -f $IPK_FILE

show_page() {
 	cat<<EOM
	<form name="form_ipk_upload" ACTION="opkg.cgi" ENCTYPE="multipart/form-data" METHOD="POST">
	<input name="form_action" value="upload" type="hidden">
	 <fieldset class="bubble">
	 <legend>Zusatz-Software-Installation</legend>
	 <table>
	 <tr><th>Ger&auml;teinfo:</th><td>$(cat /var/sysinfo/model);$(cat /proc/cpuinfo | sed -n '/system type/s#.*:[ 	]*##p')</td></tr>
	 <tr><th width="100">Zusatzpaket-Datei&nbsp;(*.ipk):</th>
	     <td><input name="form_ipk_filename" size="40" type="file" value="Durchsuche..."></td></tr>	
	 <tr><td colspan="2">&nbsp;</td></tr>
	 <tr><td colspan="2"><input name="form_ipk_submit" type="submit" value="Paket laden">
	     <input name="form_ipk_abort" type="reset" value="Abbruch"></td></tr>
	 </table>
	 </fieldset>
	</form>

	<br />
	<font size="2"><b>Verf&uuml;gbarer Speicher:</b> $avail_size Kbyte</font> <br />
	<b>Hinweis:</b> Die Pakete k&ouml;nnen mehr Speicher im Flash belegen, als hier angegeben. Es k&ouml;nnen Abh&auml;ngigkeiten zu anderen Paketen bestehen, die ebenfalls installiert werden. Sollte der restliche freie Speicher zu klein werden, lassen sich auch keine Konfigurationen mehr speichern. Bei Ger&auml;ten mit weniger als <b>8Mbyte Flash</b>, sollten KEINE Pakete installiert werden.<br/>
	Nur durch ein Neustart mit Werkseinstellung, werden alle &Auml;nderungen verworfen. Dabei gehen aber alle Einstellungen verloren und eine neue Knotennummer (IP Adresse) wird vergeben.	
	<br /><br />
	<fieldset class="bubble">
	<legend>Verf&uuml;gbare Pakete</legend>
	<form name="form_ipklist_update" ACTION="opkg.cgi" ENCTYPE="multipart/form-data" METHOD="POST">
	<input name="form_action" value="update" type="hidden">
	<input name="form_ipklist_submit" type="submit" value="Liste aktualisieren">
	</form>
	<br />
	<TABLE>
	<TR class="header">
	<TH WIDTH="60%">Paketname</TH>
	<TH WIDTH="20%">Version</TH>
	<TH WIDTH="20%">Gr&ouml;&szlig;e</TH>
	<TH WIDTH="20%"></TH>
	</TR>
EOM

T=1
IFS='
'
#generates: p=packet v=version [installed=true] clear
#"clear" is just a separator and used to do the action. all other are used to set variables via eval
for i in $(zcat /var/opkg-lists/ddmesh | sed -n '
/^Package:.*/{s#^Package: \(.*\)#p="\1"#;h}
/^Version:.*/{s#^Version: \(.*\)#v="\1"#;H}
/^Installed-Size:.*/{s#^Installed-Size: \(.*\)#s="\1"#;H}
/^$/{x;a \
clear
p
}')
do
	if [ "$i" = "clear" ]; then
		test -z "$p" && continue
		test -z "$v" && continue
		test -z "$s" && continue

		size=$(( ($s+1023) / 1024))

		cat<<EOM
		<TR class="colortoggle$T"><TD>$p</TD><td>$v</td><td>$size Kbyte</td><TD ALIGN="center">
		<form name="form_ipk_avail" action="opkg.cgi" method="post">
		<input name="form_action" value="install" type="hidden">
		<input name="form_packet" value="$p" type="hidden">
		<input name="form_submit" type="submit" value="Installieren"></TD></TR>
		</form>
EOM

		if [ "$T" = "1" ];then T=2; else T=1; fi 

		#del old values
		unset p
		unset v
		unset installed
	else
		eval $i
	fi
done

	cat<<EOM
	</TABLE>
	</fieldset>

	<br /><br />
	<fieldset class="bubble">
	<legend>Installierte  Pakete</legend>
	<TABLE>
	<TR class="header">
	<TH WIDTH="60%">Paketname</TH>
	<TH WIDTH="20%">Version</TH>
	</TR>
EOM
T=1
IFS='
'
#generates: p=packet v=version [installed=true] clear
#"clear" is just a separator and used to do the action. all other are used to set variables via eval
for i in $(cat /usr/lib/opkg/status | sed -n '
/^Package:.*/{s#^Package: \(.*\)#p="\1"#;h}
/^Version:.*/{s#^Version: \(.*\)#v="\1"#;H}
/^Status:.*/{s#^Status: \(.*\)#s="\1"#;H}
/^$/{x;a \
clear
p
}')
do
	if [ "$i" = "clear" ]; then
		test -z "$p" && continue
		test -z "$v" && continue
		test -z "$s" && continue

		#only user installed packages	
		test "${s/user/}" = "$s" && continue

		echo "<TR class=\"colortoggle$T\"><TD>$p</TD><td>$v</td></tr>"

		if [ "$T" = "1" ];then T=2; else T=1; fi 

		#del old values
		unset p
		unset v
		unset installed
	else
		eval $i
	fi
done

cat<<EOM
</TABLE>
</fieldset>
EOM
}

if [ -z "$form_action" ]; then
	
	show_page
	
else #form_action

	case "$form_action" in
		update)
			echo "<pre>"
			opkg update | flush
			echo "</pre>"
			show_page
			;;
		upload)
			mv $ffout $IPK_FILE
	
			cat<<EOM
				<fieldset class="bubble">
				<legend>Erweiterung Installieren</legend>
				<form name="form_ipk_update" action="opkg.cgi" method="POST">
	 			<input name="form_action" value="upload_install" type="hidden">
				 <table>
				 <tr><th>Paket:</th><td>$ffout</td></tr>
				 <tr><th>md5sum:</th><td>$(md5sum $IPK_FILE | cut -d' ' -f1)</td></tr>
				 <tr><td colspan="2">Bitte &Uuml;berpr&uuml;fen Sie die md5sum, welche sicherstellt, dass das Erweiterungspaket korrekt &uuml;bertragen wurde.<br />
	  			  Bitte schalten Sie das Ger&auml;t nicht aus. Es ist m&ouml;glich, dass sich der Router
	    			  mehrfach neustarted, um alle aktualisierungen vorzunehmen.<br />
             			  </td></tr>
				 <tr><td colspan="2">
				 <input name="form_ipk_submit" type="submit" value="Erweiterung installieren">
				 <input name="form_ipk_abort" type="submit" value="Abbruch">
				 </td></tr>
				 </table>
				</form>
				</fieldset>
EOM
			;;
		upload_install)
			echo "<pre>"
			opkg install $IPK_FILE 2>$OPKG_ERROR | flush
			cat $OPKG_ERROR
			echo "</pre><br/> Aktion beendet. Bitte Fehlermeldung beachten."
			;;
		install)
			echo "<pre>"
			opkg install $form_packet 2>$OPKG_ERROR | flush
			cat $OPKG_ERROR
			echo "</pre><br/> Aktion beendet. Bitte Fehlermeldung beachten."
			;;
		*)
		;;
	esac
fi	 

. $DOCUMENT_ROOT/page-post.sh ${0%/*}
