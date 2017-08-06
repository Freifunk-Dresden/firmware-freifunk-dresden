#!/bin/sh

. /lib/functions.sh
. /lib/upgrade/common.sh
. /lib/upgrade/platform.sh

export TITLE="Verwaltung > Update > Custom"

CUSTOM_PATH="/www/custom"

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
		notebox "Custom Anpassungen wurden gel&ouml;scht."
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
<legend>Custom</legend>
<form name="form_custom_upload" ACTION="custom.cgi" ENCTYPE="multipart/form-data" METHOD="POST">
<input name="form_action" value="upload" type="hidden">
<table>
<tr><td colspan="2">Jedes hochladen und l&ouml;schen veringert den Flash-Speicher!<br/>
	Wenn der Flash-Speicher voll ist, kann auch keine Konfigration mehr sauber gespeichert werden.<br/>
	In diesem Fall hilft nur ein Neustart mit Werkseinstellung, bei der alle Daten und Einstellungen verloren gehen.<br />
	Es gibt spezial Dateien.<br/>
	<ul>
	<li>custom.html - Wird auf der Splash-Seite im Hauptteil angezeigt</li>
	<li>custom.url - Wenn diese Datei existiert wird custom.html ignoriert und der HTML-Code von der URL in dieser Datei geladen.</li>
	<li>custom-head.html - Wird auf der Splash-Seite rechts vom Kopfteil angezeigt</li>
	<li>custom-head.url - Wenn diese Datei existiert wird custom-head.html ignoriert und der HTML-Code von der URL in dieser Datei geladen.</li>
	<li>logo.* - beliebige Bilddatei welche mit 'logo.' (z.B.: logo.png oder logo.gif) beginnt, ersetzt das vorhandene Logo</li>
	</ul>
	<b>Hinweise:</b> Beim Verlinken von Bildern sollte in den Html-files der URL Pfad "/custom" vorangestellt werden.<br/>Beispiel:&lt;img src="/custom/image.png"&gt;<br/>
	Der Inhalt der custom.html/url und custom-head.html/url werden in einen &lt;div&gt; Block gesetzt und sollten niemals HTML Tags &lt;html&gt;,&lt;head&gt;,&lt;body&gt; enthalten.
	<br/><br/></td></tr>
	<tr><th width="20">Datei:</th>
	<td><input name="filename" size="40" type="file" value="Durchsuche..."></td></tr>
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
	<tr><th><input name="form_clear_submit" type="submit" value="Custom entfernen"></tr>
	</table>
	</form>
	</fieldset>
	<br/><br/><br/>
	<fieldset class="bubble">
	<legend>Directory Inhalt</legend>
	<pre>$(ls -l $CUSTOM_PATH/*)</pre>
	<br /><br />
	<pre>$(df $CUSTOM_PATH)</pre>
	</fieldset>
EOM


. /usr/lib/www/page-post.sh ${0%/*}
