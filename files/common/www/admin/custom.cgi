#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh
. /lib/upgrade/common.sh
. /lib/upgrade/platform.sh

export TITLE="Verwaltung &gt; Wartung: Custom-Splash"

CUSTOM_PATH="/www/custom"

# check before freifunk-upload
if [ "$REQUEST_METHOD" = "GET" -a -n "$QUERY_STRING" ]; then
	. /usr/lib/www/page-pre.sh ${0%/*}
	notebox 'GET not allowed'
	. /usr/lib/www/page-post.sh ${0%/*}
	exit 0
fi

eval $(/usr/bin/freifunk-upload -e 2>/dev/null)

. /usr/lib/www/page-pre.sh ${0%/*}
echo "<H1>$TITLE</H1>"

case "$form_action" in
	clear)
		rm -f $CUSTOM_PATH/*
		notebox "Custom-Anpassungen wurden gel&ouml;scht."
		;;
	upload)
		mv $ffout $CUSTOM_PATH/
		notebox "$ffout wurde hochgeladen."
		;;
	*)
	;;
esac

cat<<EOM
<fieldset class="bubble">
<legend>Benutzerdefinierter Splash-Screen</legend>
<form name="form_custom_upload" ACTION="custom.cgi" ENCTYPE="multipart/form-data" METHOD="POST">
<input name="form_action" value="upload" type="hidden">
<table>
<tr><td colspan="2">Jedes Hochladen und L&ouml;schen verringert den verf&uuml;gbaren Flash-Speicher!<br/>
	Wenn der Flash-Speicher voll ist, kann auch keine Konfiguration mehr sauber gespeichert werden.<br/>
	In diesem Fall hilft nur ein <a href="reset.cgi">Neustart mit Werkseinstellungen</a>, bei dem alle Daten und Einstellungen verloren gehen.<br /><br />
	Aus folgenden Spezial-Dateien setzt sich der Splash-Screen zusammen:<br/>
	<ul>
	<li><i>custom.html</i> &ndash; Wird auf der Splash-Seite im Hauptteil angezeigt.</li>
	<li><i>custom.url</i> &ndash; Wenn diese Datei existiert, wird <i>custom.html</i> ignoriert und der HTML-Code von der URL in dieser Datei geladen.</li>
	<li><i>custom-head.html</i> &ndash; Wird auf der Splash-Seite rechts vom Kopfteil angezeigt.</li>
	<li><i>custom-head.url</i> &ndash; Wenn diese Datei existiert, wird <i>custom-head.html</i> ignoriert und der HTML-Code von der URL in dieser Datei geladen.</li>
	<li><i>logo.*</i> &ndash; Beliebige Bilddatei, welche mit "logo." beginnt (z. B.: logo.png oder logo.gif). Ersetzt das vorhandene Logo.</li>
	</ul>
	<b>Hinweise:</b> Beim Verlinken von Bildern sollte in den HTML-Files der URL-Pfad "/custom" vorangestellt werden.<br/>Beispiel: &lt;img src="/custom/image.png"&gt;<br/>
	Die Inhalte der <i>custom.html/url</i> und <i>custom-head.html/url</i> werden in einen &lt;div&gt;-Block gesetzt und sollten niemals die HTML-Tags &lt;html&gt;, &lt;head&gt; und &lt;body&gt; enthalten.
	<br/><br/></td></tr>
	<tr><th width="20">Datei:</th>
	<td><input name="filename" size="40" type="file" value="Durchsuchen..."></td></tr>
	<tr><td colspan="2">&nbsp;</td></tr>
	<tr><td colspan="2"><input name="form_custom_submit" type="submit" value="Datei hochladen"></td></tr>
	</table>
	</form>
	</fieldset>

	<br/><br/><br/>
	<fieldset class="bubble">
	<legend>L&ouml;schen</legend>
	<form name="form_custom_clear_" ACTION="custom.cgi" METHOD="POST">
	<input name="form_action" value="clear" type="hidden">
	<table>
	<tr><th><input name="form_clear_submit" type="submit" value="Custom-Splash entfernen"></tr>
	</table>
	</form>
	</fieldset>
	<br/><br/><br/>
	<fieldset class="bubble">
	<legend>Verzeichnis-Inhalt</legend>
	<pre>$(ls -l $CUSTOM_PATH/*)</pre>
	<br /><br />
	<pre>$(df $CUSTOM_PATH)</pre>
	</fieldset>
EOM


. /usr/lib/www/page-post.sh ${0%/*}
