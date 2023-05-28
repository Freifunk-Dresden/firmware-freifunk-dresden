#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Wartung: Firmware"

# check before calling freifunk-upload
if [ "$REQUEST_METHOD" = "GET" -a -n "$QUERY_STRING" ]; then
	. /usr/lib/www/page-pre.sh ${0%/*}
	notebox 'GET not allowed'
	. /usr/lib/www/page-post.sh ${0%/*}
	exit 0
fi
#get form data and optionally file
eval $(/usr/bin/freifunk-upload -e 2>/dev/null)

. /lib/functions.sh
. /usr/lib/www/compare_versions.sh
. /usr/lib/www/page-pre.sh ${0%/*}

FIRMWARE_FILE="/tmp/firmware.bin"


echo "<H1>$TITLE</H1>"

test "$form_action" != "flash" && rm -f $FIRMWARE_FILE


if [ -z "$form_action" ]; then

cat<<EOM
	<fieldset class="bubble">
	<legend>Firmware-Update</legend>
	<form name="form_firmware_upload" action="firmware.cgi" enctype="multipart/form-data" method="POST">
	<input name="form_action" value="upload" type="hidden">
	<table>
	<tr><th>Ger&auml;teinfo:</th><td><b>Model:</b> $model ($model2) - <b>CPU:</b> $(cat /proc/cpuinfo | sed -n '/system type/s#[^:]\+:[ 	]*##p')</td></tr>
	<tr><th>Filesystem:</th><td>$(cat /proc/cmdline | sed -n 's#.*rootfstype=\([a-z0-9]\+\).*$#\1#p')</td></tr>
	<tr><th colspan="2">&nbsp;</th></tr>
	<tr><td colspan="2">&nbsp;</td></tr>
EOM

	if [ "$(uci get ddmesh.system.firmware_autoupdate)" = "1" ]; then
		echo '<tr><td colspan="2">'
		notebox "<b>Hinweis:</b> Firmware-Auto-Update ist aktiv!<br />Firmware wird automatisch &uuml;berschrieben, wenn eine neuere existiert. (<a href='/admin/system.cgi'>Systemeinstellungen</a>)"
		echo '</td></tr>'
	fi

cat<<EOM
	<tr><td colspan="2"><input name="filename" size="40" type="file" value="Durchsuchen..."></td></tr>
	<tr><td colspan="2"><input name="form_firmware_submit" type="submit" value="Firmware laden"></td></tr>
	</table>
	</form>
	<br/>
EOM



cat<<EOM
	<hr size="1">
	<table class="firmware">
	<tr><td><button onclick="ajax_swupdate()" type="button" >Update-Info</button><div id="progress"></div></td></tr>
	<tr><td class="nowrap">&nbsp;</td>

	<tr><th colspan="2">Weitere Infos sind nur verf&uuml;gbar, wenn der Download-Server erreichbar ist:</th></tr>
	<tr><th width="100" style="white-space: nowrap;">- Erwartete Firmware-Datei:</th><td id="firmware_expected_filename"></td></tr>
	<tr><th width="100" style="white-space: nowrap;">- Kommentar:</th><td id="firmware_comment"></td></tr>
	<tr><td class="nowrap">&nbsp;</td>

	<tr><td class="nowrap">
	<form name="form_firmware_dl_release" action="firmware.cgi" method="POST" style="text-align: left;">
	<input name="form_action" value="download" type="hidden">
	<input id="firmware_release_url" name="form_fileinfo_url" type="hidden">
	<input id="firmware_release_version" name="form_fileinfo_version" type="hidden">
	<input id="firmware_release_md5sum" name="form_fileinfo_md5sum" type="hidden">
	<input title="$(uci get credentials.url.firmware_download_release)" disabled id="ajax_swupdate_latest" name="form_firmware_submit" type="submit" value="Download: 'latest'-Version (unbekannt)">
	</form>
	</td> </td><td id="firmware_release_url_info"></td>
	</tr>

	<tr><td class="nowrap">
	<form name="form_firmware_dl_testing" action="firmware.cgi" method="POST" style="text-align: left;">
	<input name="form_action" value="download" type="hidden">
	<input id="firmware_testing_url" name="form_fileinfo_url" value="$firmware_testing_url" type="hidden">
	<input id="firmware_testing_version" name="form_fileinfo_version" value="$firmware_testing_version" type="hidden">
	<input id="firmware_testing_md5sum" name="form_fileinfo_md5sum" type="hidden">
	<input title="$(uci -q get credentials.url.firmware_download_testing)" disabled id="ajax_swupdate_testing" name="form_firmware_submit" type="submit" value="Download: 'testing'-Version (unbekannt)">
	</form>
	</td><td id="firmware_testing_url_info"></td>
	</tr>
	</table>
	</fieldset>

<SCRIPT LANGUAGE="JavaScript" type="text/javascript"><!--
ajax_swupdate();
//--></SCRIPT>

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
		# final step
		flash)
			if [ -n "$form_update_abort" ]; then
				rm -f $FIRMWARE_FILE
				notebox 'Laden der Firmware abgebrochen.'
			else
				SECONDS=300
				BARS=3

				cat<<EOM
				<fieldset class="bubble">
				<legend>Firmware-Update</legend>
				<table>
				<tr><td>Werkseinstellung:$(if [ "$form_firmware_factory" = "1" ];then echo "Ja";else echo "Nein";fi)</td></tr>
				<tr><td>Schreibe Firmware...</td></tr>
				<tr><td><div style="max-width: 300px" id="progress"></div></td></tr>
				</table>
				</fieldset>
				<SCRIPT LANGUAGE="JavaScript" TYPE="text/javascript">
					var t=$SECONDS * 1000;
					var bars=$BARS;
					var fields=10;
					var p = new GridField("progress", "myProgress", bars, fields, 10, 5, "#aaaaaa", "#0000ff");
					p.autoCounter(t / (bars*fields), bars*fields);
					window.setTimeout("window.location=\"/\"", t);
				</SCRIPT>
EOM

				sleep 5	# let browser load all content before killing httpd

				if [ "$form_firmware_factory" = "1" ]; then
				  /usr/lib/ddmesh/ddmesh-display.sh msg "   SysUprade    (Factory Reset)"
					rm /tmp/freifunk-running # disable cron and hotplug
					(sleep 10 ; /usr/lib/ddmesh/ddmesh-display.sh factory; sysupgrade -n $FIRMWARE_FILE 2>&1 >/dev/null) &
				else
					#update configs after firmware update
					/usr/lib/ddmesh/ddmesh-display.sh msg "   SysUprade    (keep Config)"
					uci set ddmesh.boot.boot_step=2
					uci set ddmesh.boot.upgrade_running=1
					uci commit
					sync
					rm /tmp/freifunk-running # disable cron and hotplug
					(sleep 10 ; /usr/lib/ddmesh/ddmesh-display.sh reboot; sysupgrade $FIRMWARE_FILE 2>&1 >/dev/null) &
				fi
			fi
			;;

		# first step
		upload|download)

			VERSION_WARNING=""
			MD5_WARNING=""
			do_update=0

			if [ "$form_action" = "download" ]; then

				URL=$(uhttpd -d "$form_fileinfo_url")
				VER=$(uhttpd -d "$form_fileinfo_version")
				server_md5sum="$form_fileinfo_md5sum"

				echo "<pre>"
				echo "Try downloading '$URL'"
				wget -O $FIRMWARE_FILE "$URL" 2>&1 | flush
				echo "</pre>"

				file_md5sum=$(md5sum $FIRMWARE_FILE | cut -d' ' -f1)
				if [ -z "$server_md5sum" -o "$server_md5sum" != "$file_md5sum" ]; then
					notebox "Fehler: Download-<b>MD5-Summe</b> fehlerhaft!"
					rm -f $FIRMWARE_FILE
					do_update=0
				else
					cur_version="$(cat /etc/version)"
					compare_versions "$VER"  "$cur_version" || VERSION_WARNING="<div style=\"color: red;\">Hinweis: Die Firmware-Version ist kleiner oder gleich der aktuellen Firmware (<b>$VER <= $cur_version</b>)!<br/>
					 Die Funktion oder Stabilit&auml;t kann nicht sichergestellt werden! </div>"
					MD5_WARNING=""
					MD5_OK='<div style="color: green;">korrekt</div>'
					do_update=1
				fi
			else
				mv $ffout $FIRMWARE_FILE
				file_md5sum=$(md5sum $FIRMWARE_FILE | cut -d' ' -f1)
				MD5_WARNING="Bitte &uuml;berpr&uuml;fe die <b>MD5-Summe</b>, welche sicherstellt, dass die Firmware korrekt &uuml;bertragen wurde."
				do_update=1
			fi

			if [ "$do_update" = "1" ]; then

				#check firmware
				if m="$(sysupgrade --test $FIRMWARE_FILE 2>&1 )" ;then
					cat<<EOM
					<fieldset class="bubble">
					<legend>Firmware-Update</legend>
					<form name="form_firmware_update" action="firmware.cgi" method="POST">
		 			<input name="form_action" value="flash" type="hidden">
					 <table>
					 <tr><th>Firmware-File</th><td>$ffout</td></tr>
					 <tr><th>Firmware-Version</th><td>$VER</td></tr>
					 <tr><th>Firmware-MD5-Summe</th><td>$file_md5sum $MD5_OK</td></tr>
					 <tr><th>Werkseinstellungen:</th><td><input name="form_firmware_factory" type="checkbox" value="1"></td></tr>
					 <tr><td colspan="2">
						$MD5_WARNING</br>
							Das Speichern der Firmware dauert einige Zeit. Bitte schalte das Ger&auml;t nicht aus. Es ist m&ouml;glich, dass sich der Router
								mehrfach neustartet, um alle Aktualisierungen vorzunehmen.<br />
				 				Wird das Zur&uuml;cksetzen auf Werkseinstellungen aktiviert, erh&auml;lt der Router bei der n&auml;chsten Registrierung eine neue Node-Nummer und damit auch
							 				eine neue IP-Adresse im Freifunknetz.</td></tr>
					 <tr><td colspan="2"> $VERSION_WARNING </td></tr>
					 <tr><td colspan="2">
					 <input name="form_update_submit" type="submit" value="Firmware speichern">
					 <input name="form_update_abort" type="submit" value="Abbrechen">
					 </td></tr>
					 </table>
					</form>
					</fieldset>
EOM
				else # firmware check
					rm -f $FIRMWARE_FILE
					notebox "Falsche Firmware: <br/><br/><i>$m</i>"
				fi
			fi
			;;
		*)
		;;
	esac
fi

. /usr/lib/www/page-post.sh ${0%/*}
