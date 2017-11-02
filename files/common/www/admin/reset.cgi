#!/bin/sh

. /lib/functions.sh
. /lib/upgrade/common.sh
. /lib/upgrade/platform.sh


export TITLE="Verwaltung > Update > Reset"

. /usr/lib/www/page-pre.sh ${0%/*}

echo "<H1>$TITLE</H1>"


if [ -z "$form_action" ]; then
cat<<EOM
	<fieldset class="bubble">
	<legend>Reset</legend>
	<form name="form_reset" action="reset.cgi" method="POST">
	<input name="form_action" value="reset" type="hidden">
	<br/>
	<table>
	<tr><th style="color:red;"><input name="form_reset_factory" type="checkbox" value="1"> Werkseinstellung (setzt alle Einstellungen zur&uuml;ck und l&ouml;scht Passwort, Kontaktinfos, Portforwarding, Backbone, installierte Pakete)</th></tr>
	<tr><th><input name="form_reset_reconfig" type="checkbox" value="1"> Konfiguration neuer Hardware</th></tr>
	<tr><td>&nbsp;</td></tr>
	<tr><td><input name="form_reset_submit" type="submit" value="Neustart"></td</tr>
	</table>
	</form>
	</fieldset>
EOM

else #form_action

	case "$form_action" in
		reset)
			cat<<EOM
			<fieldset class="bubble">
			<legend>Neustart</legend>
			<table>
			<tr><td>Router wird neu gestartet</td></tr>
			<tr><td>
EOM
			if [ -n "$form_reset_factory" ]; then
				echo "Alle Einstellungen werden auf Standardwerte gesetzt (Passwort,IP Adressen,ssh-key,https Zertifikate).<br />Ebenso wird eine neue Node-Nummber erzeugt."
			else
				if [ -n "$form_reset_reconfig" ]; then
					echo "System passt Konfiguration an neue Hardware an.<br/>"
					uci -q set ddmesh.boot.boot_step=2
					uci commit
				fi
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
			test -n "$form_reset_factory" && mtd -r erase rootfs_data
			sleep 2
			reboot&
			;;
		*)
		;;
	esac
fi

. /usr/lib/www/page-post.sh ${0%/*}

