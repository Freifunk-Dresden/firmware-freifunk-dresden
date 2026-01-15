#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

export TITLE="Verwaltung &gt; Wartung: Software"

IPK_FILE="/tmp/paket.ipk"
OPKG_ERROR="/tmp/opkg.error"

# check before freifunk-upload
if [ "$REQUEST_METHOD" = "GET" -a -n "$QUERY_STRING" ]; then
	. /usr/lib/www/page-pre.sh ${0%/*}
	notebox 'GET not allowed'
	. /usr/lib/www/page-post.sh ${0%/*}
	exit 0
fi
#get form data and optionally file
eval $(/usr/bin/freifunk-upload -e 2>/dev/null)

. /usr/lib/www/page-pre.sh ${0%/*}
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
	 <tr><th>Ger&auml;teinfo:</th><td>$(cat /var/sysinfo/model 2>/dev/null);$(cat /proc/cpuinfo | sed -n '/system type/s#.*:[ 	]*##p')</td></tr>
	 <tr><th width="100">Zusatzpaket-Datei&nbsp;(*.ipk):</th>
	     <td><input name="form_ipk_filename" size="40" type="file" value="Durchsuche..."></td></tr>
	 <tr><td colspan="2">&nbsp;</td></tr>
	 <tr><td colspan="2"><input name="form_ipk_submit" type="submit" value="Paket laden">
	     <input name="form_ipk_abort" type="reset" value="Abbrechen"></td></tr>
	 </table>
	 </fieldset>
	</form>

	<br />
	<font size="2"><b>Verf&uuml;gbarer Speicher:</b> $avail_size KB</font> <br />
	<b>Hinweis:</b> Die Pakete k&ouml;nnen mehr Speicher im Flash belegen als hier angegeben. Es k&ouml;nnen Abh&auml;ngigkeiten zu anderen Paketen bestehen, die ebenfalls installiert werden. Sollte der restliche freie Speicher zu klein werden, lassen sich auch keine Konfigurationen mehr speichern. Bei Ger&auml;ten mit <b>weniger als 8 MByte Flash</b> sollten <b>keine Pakete</b> installiert werden.<br/>
	Nur durch einen Neustart mit Werkseinstellungen k&ouml;nnen alle &Auml;nderungen wieder r&uuml;ckgängig gemacht werden. Dabei gehen aber alle Einstellungen verloren und eine neue Knoten-Nr. (sowie IP-Adresse) wird vergeben.
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
#generates: p=paket v=version [installed=true] clear
#"clear" is just a separator and used to do the action. all other are used to set variables via eval
for i in $( opkg info | sed -n '
/^Package:.*/{s#^Package: \(.*\)#p="\1"#;h}
/^Version:.*/{s#^Version: \(.*\)#v="\1"#;H}
/^Status:.*/{s#^Status: \(.*\)#t="\1"#;H}
/^Size:.*/{s#^Size: \(.*\)#s="\1"#;H}
/^$/{x;a \
clear
p
}')
do
	if [ "$i" = "clear" ]; then
		test -z "$p" && continue
		test -z "$v" && continue
		test -z "$s" && continue
		test "${t/not-installed/}" = "$t" && continue

		size=$(( ($s+1023) / 1024))

		cat<<EOM
		<TR class="colortoggle$T"><TD>$p</TD><td>$v</td><td>$size Kbyte</td><TD ALIGN="center">
		<form name="form_ipk_avail" action="opkg.cgi" method="post">
		<input name="form_action" value="install" type="hidden">
		<input name="form_paket" value="$p" type="hidden">
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
for i in $(/usr/lib/ddmesh/ddmesh-installed-ipkg.sh)
do
	IFS=':'
	set $i
	echo "<TR class=\"colortoggle$T\"><TD>$1</TD><td>$2</td></tr>"
	if [ "$T" = "1" ];then T=2; else T=1; fi
done

cat<<EOM
</TABLE>
</fieldset>
EOM
}

create_opkg_conf()
{
cat <<EOM >/tmp/opkg.conf
src/gz ddmesh $1
dest root /
dest ram /tmp
lists_dir ext /var/opkg-lists
#option overlay_root /overlay
EOM
}

update_opkg()
{
 RELEASE_FILE_INFO_JSON="$(/usr/lib/ddmesh/ddmesh-get-firmware-name.sh)"
 error=$(echo $RELEASE_FILE_INFO_JSON | jsonfilter -e '@.error')
 test -n "$error" && RELEASE_FILE_INFO_JSON=""

 opkg_release_url="$(echo $RELEASE_FILE_INFO_JSON | jsonfilter -e '@.opkg_url')"

 create_opkg_conf $opkg_release_url
 echo "<pre>"
 opkg update | flush
 echo "</pre>"
}

if [ -z "$form_action" ]; then

	show_page

else #form_action

	case "$form_action" in
		update)
			update_opkg
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
				</td></tr>
				</table>
				</form>
				</fieldset>
EOM
			;;
		upload_install)
			if [ -z "$IPK_FILE" ]; then
				notebox "Kein Paket geladen"
			else
				create_opkg_conf

				echo "<pre>"
				echo "*** install [$IPK_FILE]"
				opkg -V2 --force-overwrite install $IPK_FILE 2>$OPKG_ERROR | flush
				name=$(opkg --noaction install $IPK_FILE 2>/dev/null | cut -d' ' -f2)
				echo "*** set flag ok [$name]"
				opkg flag ok $name 2>>$OPKG_ERROR | flush
				cat $OPKG_ERROR
				echo "</pre><br/> Aktion beendet. Bitte Fehlermeldung beachten."
			fi
			;;
		install)
			if [ -z "$form_paket" ]; then
				notebox "Kein Paket geladen"
			else
				echo "<pre>"
				echo "*** install [$IPK_FILE]"
				opkg -V2 --force-overwrite install $form_paket 2>$OPKG_ERROR | flush
				name=$(opkg --noaction install $form_paket 2>/dev/null | cut -d' ' -f2)
				echo "*** set flag ok [$name]"
				opkg flag ok $name 2>>$OPKG_ERROR | flush
				cat $OPKG_ERROR
				echo "</pre><br/> Aktion beendet. Bitte Fehlermeldung beachten."
			fi
			;;
		*)
		;;
	esac
fi

. /usr/lib/www/page-post.sh ${0%/*}
