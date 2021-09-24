#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh
. /lib/upgrade/common.sh
. /lib/upgrade/platform.sh

export TITLE="Verwaltung &gt; Wartung: Konfiguration"

eval $(cat /etc/board.json | jsonfilter -e model='@.model.id' -e model2='@.model.name')
export model="$(echo $model | sed 's#[ 	]*\(\1\)[ 	]*#\1#')"
export model2="$(echo $model2 | sed 's#[ 	]*\(\1\)[ 	]*#\1#')"

ver=$(uci get ddmesh.boot.upgrade_version)
CONF_FILE="config-${model2}-router-$(uci get ddmesh.system.node)-fw$ver-$(date +"%Y%b%d-%H%M%S").tgz"
PACKAGES="/etc/installed.packages"
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

. /usr/lib/www/page-functions.sh ${0%/*}

if [ "$form_action" = "download" ]; then
	# save installed packages
	/usr/lib/ddmesh/ddmesh-installed-ipkg.sh > $PACKAGES

	echo "Content-Type: application/x-compressed"
	echo "Content-Disposition: attachment;filename=$CONF_FILE"
	echo ""
	sysupgrade -b -

	exit 0
fi

. /usr/lib/www/page-pre.sh ${0%/*}

echo "<H1>$TITLE</H1>"

if [ -z "$form_action" ]; then

cat<<EOM
	<br/>
	<fieldset class="bubble">
	<legend>Konfiguration sichern</legend>
	<form name="form_conf_download" action="config.cgi" method="POST">
	<input name="form_action" value="download" type="hidden">
	<table>
	<tr><td><input name="form_download_submit" type="submit" value="Konfiguration sichern"></td></tr>
	</table>
	</form>
	</fieldset>

	<br/><br/>

	<fieldset class="bubble">
	<legend>Konfiguration zur&uuml;ckspielen</legend>
	<form name="form_conf_upload" action="config.cgi" enctype="multipart/form-data" method="POST">
	<input name="form_action" value="upload" type="hidden">
	<table>
	<tr><td><input name="filename" size="40" type="file" value="Durchsuche..."></td></tr>
	<tr><td>&nbsp;</td></tr>
	<tr><td>Installiere vorherige Pakete:<input name="form_conf_ipkg_install" type="checkbox" value="1"></td></tr>
	<tr><td><input name="form_conf_submit" type="submit" value="Konfiguration laden"></td></tr>
	<tr><td>&nbsp;</td></tr>
	</table>
	</form>
	</fieldset>
EOM

else #form_action
	if [ "$form_action" = "upload" ]; then
		if [ -z "$ffout" ]; then
			notebox "Kein File"
		else
			echo "<pre>"
			if [ -f "$PACKAGES" -a "$form_conf_ipkg_install" = "1" ]; then
				opkg update && {
					IFS='
'
					for ipkg in $(cat $PACKAGES)
					do
						IFS=':'
						set $ipkg
						echo "*** re-installing $1"
						opkg -V2 --force-overwrite install $1 2>$OPKG_ERROR | flush
						name=$(opkg --noaction install $1 2>/dev/null | cut -d' ' -f2)
						echo "*** set flag ok [$name]"
						opkg flag ok $name 2>>$OPKG_ERROR | flush
						cat $OPKG_ERROR
					done
				} || {
					echo "Fehler: Keine Pakete zum Downloaden verf&uuml;gbar."
				}
			fi
			echo "Installiere Konfigurations-Files."
			sysupgrade -r $ffout
			echo "</pre>"
			notebox "<b>Hinweis:</b> Konfiguration wurde eingespielt. Die Einstellungen sind erst nach dem n&auml;chsten <A HREF="reset.cgi">Neustart</A> aktiv."
		fi
	fi
fi

. /usr/lib/www/page-post.sh ${0%/*}
