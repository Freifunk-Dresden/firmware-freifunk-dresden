#!/bin/sh

. /lib/functions.sh
. /lib/upgrade/common.sh
. /lib/upgrade/platform.sh

#return 0 if new > cur
compare_versions() {
	new=$1
	cur=$2
	local IFS='.';
	set $new; a1=$1; a2=$2; a3=$3
	set $cur; b1=$1; b2=$2; b3=$3
	[ "$a1" -lt "$b1" ] && return 1
		[ "$a1" -eq "$b1" ] && {
		[ "$a2" -lt "$b2" ] && return 1
			[ "$a2" -eq "$b2" ] &&  [ "$a3" -le "$b3" ] && return 1
		}
	return 0
}

export TITLE="Verwaltung > Update > Firmware"

if [ "$REQUEST_METHOD" = "GET" -a -n "$QUERY_STRING" ]; then
	. /usr/lib/www/page-pre.sh ${0%/*}
	notebox 'GET not allowed'
	. /usr/lib/www/page-post.sh ${0%/*}
	exit 0
fi
#get form data and optionally file
eval $(/usr/bin/freifunk-upload -e 2>/dev/null)

. /usr/lib/www/page-pre.sh ${0%/*}

FIRMWARE="$(/usr/lib/ddmesh/ddmesh-get-firmware-name.sh)"
DL_SERVER="$(uci get credentials.url.firmware_download_server)"
URL_RELEASE="$(uci get credentials.url.firmware_download_release)"
URL_TESTING="$(uci get credentials.url.firmware_download_testing)"
URL_ARCH="${DISTRIB_TARGET%/*}"
FIRMWARE_FILE="/tmp/firmware.bin"

#check connection, reduce timeout
ping -c 1 -W 3 $DL_SERVER >/dev/null 2>/dev/null  && {
	firmware_release_version=$(wget -O - "$URL_RELEASE/version")
	firmware_testing_version=$(wget -O - "$URL_TESTING/version")
}

echo "<H1>$TITLE</H1>"

test "$form_action" != "flash" && rm -f $FIRMWARE_FILE


if [ -z "$form_action" ]; then

	if [ "$(uci get ddmesh.system.firmware_autoupdate)" = "1" ]; then
		notebox "<b>Hinweis:</b> Firmware Auto-Update ist aktiv!"
	fi

cat<<EOM
	<fieldset class="bubble">
	<legend>Firmware-Update</legend>
	<table>
	<form name="form_firmware_upload" action="firmware.cgi" enctype="multipart/form-data" method="POST">
	<input name="form_action" value="upload" type="hidden">
	<tr><th>Ger&auml;teinfo:</th><td>$(cat /var/sysinfo/model);$(cat /proc/cpuinfo | sed -n '/system type/s#.*:[ 	]*##p')</td></tr>
	<tr><th width="100" style="white-space: nowrap;">Erwartete Firmware-Datei:</th><td>$FIRMWARE</td></tr>
	<tr><td colspan="2">&nbsp;</td></tr>
EOM

	if [ "$(uci get ddmesh.system.firmware_autoupdate)" = "1" ]; then
		echo '<tr><td colspan="2">'
		notebox "<b>Hinweis:</b> Firmware Auto-Update ist aktiv!<br />Firmware wird automatisch &uuml;berschrieben wenn diese neuer ist. (<a href='/admin/system.cgi'>Systemeinstellungen</a>)"
		echo '</td></tr>'
	fi

cat<<EOM
	<tr><td colspan="2"><input name="filename" size="40" type="file" value="Durchsuche..."></td></tr>
	<tr><td colspan="2"><input name="form_firmware_submit" type="submit" value="Firmware laden"></td></tr>
	</table>
	</form>
	<br/>
EOM

	if [ -n "$FIRMWARE" ]; then
cat<<EOM
	<table>
	<tr><td colspan="2">
	<form name="form_firmware_dl_release" action="firmware.cgi" method="POST" style="text-align: left;">
	<input name="form_action" value="download_release" type="hidden">
	<input $(test -z "$firmware_release_version" && echo disabled) name="form_firmware_submit" type="submit" value="Download latest ($firmware_release_version) Version from Server"></td></tr>
	</form>
	</td></tr>
	<tr><td colspan="2">
	<form name="form_firmware_dl_testing" action="firmware.cgi" method="POST" style="text-align: left;">
	<input name="form_action" value="download_testing" type="hidden">
	<input $(test -z "$firmware_testing_version" && echo disabled) name="form_firmware_submit" type="submit" value="Download testing ($firmware_testing_version) Version from Server"></td></tr>
	</form>
	</td></tr>
	<tr><td colspan="2">(Wenn der direkte Download nicht verf&uuml;gbar ist, konnte der Download-Server nicht erreicht werden. Bitte Seite neu laden.)</td></tr>
	</table>
EOM
	fi
cat<<EOM
	</fieldset>

	<br/><br/>

	<fieldset class="bubble">
	<legend>Reset</legend>
	<form name="form_reset" action="firmware.cgi" method="POST">
	<input name="form_action" value="reset" type="hidden">
	<table>
	<tr><th>Werkseinstellung:<input name="form_firmware_factory" type="checkbox" value="1"></th></tr>
	<tr><th><input name="form_reset_submit" type="submit" value="Neustart"></tr>
	</table>
	</form>
	</fieldset>

	<br/><br/>

	<fieldset class="bubble">
	<legend>Upgrade-Historie</legend>
	<table>
EOM
print_upgrade_hist() {
	echo "<tr><td>$1</td></tr>"
}
config_load ddmesh
config_list_foreach boot upgraded print_upgrade_hist
	
cat<<EOM
	 </table>
	 </fieldset>
EOM

else #form_action

	case "$form_action" in
		flash)
			if [ -n "$form_update_abort" ]; then
				rm -f $FIRMWARE_FILE
				notebox 'Firmware Laden abgebrochen'
			else	
				cat<<EOM
				<fieldset class="bubble">
				<legend>Firmware-Update</legend>
				<table>
				<tr><td>Werkseinstellung:$(if [ "$form_firmware_factory" = "1" ];then echo "Ja";else echo "Nein";fi)</td></tr>
				<tr><td>Schreibe Firmware...</td></tr>
				<tr><td><img src="/images/progress170.gif?s=$(date +'%s')" vspace="10" width="255"></td></tr>
				</table>
				</fieldset>
				<SCRIPT LANGUAGE="JavaScript" TYPE="text/javascript">
				window.setTimeout("window.location=\"/\"", 190*1000);
				</SCRIPT>
EOM
				if [ "$form_firmware_factory" = "1" ]; then
					sysupgrade -n $FIRMWARE_FILE 2>&1 >/dev/null &
				else
					#update configs after firmware update
					uci set ddmesh.boot.boot_step=2
					uci commit
					sync
					sysupgrade $FIRMWARE_FILE 2>&1 >/dev/null &
				fi
			fi
			;;
		reset)
			cat<<EOM
			<fieldset class="bubble">
			<legend>Neustart</legend>
			<table>
			<tr><td>Router wird neu gestartet</td></tr>
			<tr><td>
EOM
			if [ -n "$form_firmware_factory" ]; then
				echo "Alle Einstellungen werden auf Standardwerte gesetzt (Passwort,IP Adressen,ssh-key,https Zertifikate).<br />Ebenso wird eine neue Node-Nummber erzeugt."
			else
				echo "Alle Einstellungen bleiben erhalten."
			fi
			cat <<EOM
			</td></tr>
			<tr><td><img src="/images/progress170.gif?s=$(date +'%s')" vspace="10" width="255"></td></tr>
			</table>
			</fieldset>
			<SCRIPT LANGUAGE="JavaScript" TYPE="text/javascript">
			window.setTimeout("window.location=\"/\"", 100*1000);
			</SCRIPT>
EOM
			test -n "$form_firmware_factory" && mtd -r erase rootfs_data
			sleep 2
			reboot&
			;;
		upload|download_release|download_testing)
			if [ "$form_action" = "download_release" -o "$form_action" = "download_testing" ]; then
				if [ "$form_action" = "download_release" ]; then
					URL="$URL_RELEASE/$URL_ARCH"
					VER="$firmware_release_version"
				else
					URL="$URL_TESTING/$URL_ARCH"
					VER="$firmware_testing_version"
				fi

				echo "<pre>"
				echo "Try downloading $URL/$FIRMWARE"
				wget -O $FIRMWARE_FILE "$URL/$FIRMWARE" 2>&1 | flush
				echo "</pre>"

				server_md5sum=$(wget -O - "$URL/md5sums" | grep "$FIRMWARE" | cut -d ' ' -f1)
				file_md5sum=$(md5sum $FIRMWARE_FILE | cut -d' ' -f1)
				if [ "$server_md5sum" != "$file_md5sum" ]; then
					notebox "ERROR: Download fehlerhaft !"
					rm -f $FIRMWARE_FILE
					break
				fi
				cur_version="$(cat /etc/version)"
				compare_versions "$VER"  "$cur_version" || notebox "Hinweis: Firmware version ist kleiner oder gleich der aktuellen Firmware ($VER <= $cur_version) !"
			else
				mv $ffout $FIRMWARE_FILE
			fi

			file_md5sum=$(md5sum $FIRMWARE_FILE | cut -d' ' -f1)	
			#check firmware (see /lib/upgrade)
			if m=$(platform_check_image $FIRMWARE_FILE) ;then
				cat<<EOM
				<fieldset class="bubble">
				<legend>Firmware-Update</legend>
				<form name="form_firmware_update" action="firmware.cgi" method="POST">
	 			<input name="form_action" value="flash" type="hidden">
				 <table>
				 <tr><th>Firmware File</th><td>$ffout</td></tr>
				 <tr><th>Firmware Version</th><td>$VER</td></tr>
				 <tr><th>Firmware md5sum</th><td>$file_md5sum</td></tr>
				 <tr><th>Werkseinstellung:</th><td><input name="form_firmware_factory" type="checkbox" value="1"></td></tr>
				 <tr><td colspan="2">Bitte &Uuml;berpr&uuml;fen Sie die md5sum, welche sicherstellt, dass die Firmware korrekt &uuml;bertragen wurde.<br />
	  			  Das Speichern der Firmware dauert einige Zeit. Bitte schalten Sie das Ger&auml;t nicht aus. Es ist m&ouml;glich, dass sich der Router
	    			  mehrfach neustarted, um alle aktualisierungen vorzunehmen.<br />
	     			  Wird die Werkseinstellung aktiviert, erh&auml;lt der Router bei der n&auml;chsten Registrierung eine neue Node-Nummer und damit auch
             			  eine neue IP-Adresse im Freifunknetz.</td></tr>
				 <tr><td colspan="2">
				 <input name="form_update_submit" type="submit" value="Firmware speichern">
				 <input name="form_update_abort" type="submit" value="Abbruch">
				 </td></tr>
				 </table>
				</form>
				</fieldset>
EOM
			else # firmware check
				rm -f $FIRMWARE_FILE
				notebox "Falsche Firmware: <i>$m</i>"
			fi
			;;
		*)
		;;
	esac
fi	

. /usr/lib/www/page-post.sh ${0%/*}
