#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Wartung: Neustart/Reset"

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
				SECONDS=260
				BARS=3
				echo "Alle Einstellungen werden auf Standardwerte gesetzt (Passwort, IP-Adressen, SSH-Key, HTTPS-Zertifikate).<br />Ebenfalls wird eine neue Knoten-Nr. erzeugt."
			else
				if [ -n "$form_reset_reconfig" ]; then
					echo "Konfiguration wird an neue Hardware angepasst.<br/>"
					uci -q set ddmesh.boot.boot_step=2
					uci commit
				fi

				SECONDS=120
				BARS=1

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
				/usr/lib/ddmesh/ddmesh-display.sh factory
				/sbin/firstboot -y
			fi
				/usr/lib/ddmesh/ddmesh-display.sh reboot
				# update config and reboot
				/usr/lib/ddmesh/ddmesh-bootconfig.sh reboot &

			;;
		*)
		;;
	esac
fi

cat <<EOM
<br/><br/>
<div class="note"><b>Hinweis</b>: <div> Nach einem Neustart des Routers, dauert es bis zu <b>5 Minuten</b>, bis der Router alle
Informationen f&uuml;r den Zugang zum Freifunk-Netz gesammelt hat.</div>
</div>
EOM

. /usr/lib/www/page-post.sh ${0%/*}
