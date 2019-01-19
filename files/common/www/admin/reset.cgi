#!/bin/sh

export TITLE="Verwaltung > Wartung: Neustart/Reset"

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
	<tr><th style="color:red;"><input name="form_reset_factory" type="checkbox" value="1"> Werkseinstellungen (setzt alle Einstellungen zur&uuml;ck und l&ouml;scht Passwort, Kontaktinfos, Portweiterleitungen, Backbone-Einstellungen und installierte Pakete).</th></tr>
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
			<tr><td>Router wird neu gestartet.</td></tr>
			<tr><td>
EOM
			if [ -n "$form_reset_factory" ]; then
				SECONDS=210
				BARS=3
				echo "Alle Einstellungen werden auf Standardwerte gesetzt (Passwort, IP-Adressen, SSH-Key, HTTPS-Zertifikate).<br />Ebenfalls wird eine neue Knoten-Nr. erzeugt."
			else
				if [ -n "$form_reset_reconfig" ]; then
					echo "Konfiguration wird an neue Hardware angepasst.<br/>"
					uci -q set ddmesh.boot.boot_step=2
					uci_commit.sh
				fi

				if [ "$(uci -q get ddmesh.boot.boot_step)" = "3" ]; then
					SECONDS=70
					BARS=1
				else
					SECONDS=120
					BARS=2
				fi

				echo "Alle Einstellungen bleiben erhalten."
			fi
			cat <<EOM
			</td></tr>
			<tr><td><div style="max-width: 300px" id="progress"></div></td></tr>
			</table>
			</fieldset>
			<SCRIPT LANGUAGE="JavaScript" TYPE="text/javascript">
				var t=$SECONDS * 1000;
				var bars=$BARS;
				var fields=20;
				var p = new GridField("progress", "myProgress", bars, fields, 10, 5, "#aaaaaa", "#0000ff");
				p.autoCounter(t / (bars*fields), bars*fields);
				window.setTimeout("window.location=\"/\"", t);
			</SCRIPT>
EOM
			if [ -n "$form_reset_factory" ]; then
				/sbin/firstboot -y
			fi
			sleep 2
			reboot&
			;;
		*)
		;;
	esac
fi

. /usr/lib/www/page-post.sh ${0%/*}

