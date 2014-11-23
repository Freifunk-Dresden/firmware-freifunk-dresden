#!/bin/sh

. /lib/functions.sh
. /lib/upgrade/common.sh
. /lib/upgrade/platform.sh

export TITLE="Verwaltung > Update > Firmware"

FIRMWARE_FILE="/tmp/firmware.bin"

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

test "$form_action" != "flash" && rm -f $FIRMWARE_FILE

if [ -z "$form_action" ]; then

	cat<<EOM
	<form name="form_firmware_upload" action="firmware.cgi" enctype="multipart/form-data" method="POST">
	<input name="form_action" value="upload" type="hidden">
	<fieldset class="bubble">
	<legend>Firmware-Update</legend>
	 <table>
	 <tr><th>Ger&auml;teinfo:</th><td>$(cat /var/sysinfo/model);$(cat /proc/cpuinfo | sed -n '/system type/s#.*:[ 	]*##p')</td></tr>
	 <tr><th width="100">Firmware-Datei&nbsp;(*.bin):</th>
	     <td><input name="filename" size="40" type="file" value="Durchsuche..."></td></tr>
	 <tr><th width="100">Werkseinstellung:</th>
		<td><input name="form_firmware_factory" type="checkbox" value="1"></td></tr>
	 <tr><td colspan="2">&nbsp;</td></tr>
	 <tr><td colspan="2"><input name="form_firmware_submit" type="submit" value="Firmware laden">
	     <input name="form_firmware_upload_abort" type="reset" value="Abbruch"></td></tr>
	 </table>
	 </fieldset>
	</form>
	<br/><br/>
	<form name="form_reset" action="firmware.cgi" method="POST">
	 <input name="form_action" value="reset" type="hidden">
	 <fieldset class="bubble">
	 <legend>Reset</legend>
	 <table>
	 <tr><th>Werkseinstellung:<input name="form_firmware_factory" type="checkbox" value="1"></th></tr>
	 <tr><th><input name="form_reset_submit" type="submit" value="Neustart"></tr>
	 </table>
	 </fieldset>
	</form>
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
					sleep 1
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
		upload)
			mv $ffout $FIRMWARE_FILE
	
			#check firmware (see /lib/upgrade)
			if m=$(platform_check_image $FIRMWARE_FILE) ;then 
				cat<<EOM
				<fieldset class="bubble">
				<legend>Firmware-Update</legend>
				<form name="form_firmware_update" action="firmware.cgi" method="POST">
	 			<input name="form_action" value="flash" type="hidden">
				 <table>
				 <tr><th>Firmware File</th><td>$ffout</td></tr>
				 <tr><th>Firmware md5sum</th><td>$(md5sum $FIRMWARE_FILE | cut -d' ' -f1)</td></tr>
				 <tr><th>Werkseinstellung:</th><td>$( test "$form_firmware_factory" = "1" && echo "Ja" || echo "Nein")</td></tr>
				 <input name="form_firmware_factory" type="hidden" value="$form_firmware_factory"></td></tr>
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

. $DOCUMENT_ROOT/page-post.sh ${0%/*}
