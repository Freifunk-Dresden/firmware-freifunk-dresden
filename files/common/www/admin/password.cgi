#!/bin/sh

export TITLE="Verwaltung > Allgemein > Kennwort"
. $DOCUMENT_ROOT/page-pre.sh ${0%/*}

export uhttpd_restart=0

cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

if [ -z "$QUERY_STRING" ]; then

	cat<<EOM
<form action="password.cgi" method="POST">
<fieldset class="bubble">
<legend>Kennwort</legend>
<table>

<tr title="Eingabe eines neuen Kennwortes mit bis zu 8 Buchstaben, Ziffern oder Sonderzeichen.">
<th>Neues Kennwort:</th><td><input name="form_pw" size="32" type="PASSWORD"></td>
</tr>

<tr title="Wiederholte Eingabe des neuen Kennwortes.">
<th>Kennwort wiederholen:</th><td><input name="form_confirm_pw" size="32" type="PASSWORD"></td>
</tr>

<tr><td colspan="2">&nbsp;</td></tr>

<tr>
<td colspan="2"><input name="form_submit" title="Die Einstellungen &uuml;bernehmen. Diese werden erst nach einem Neustart wirksam." type="submit" value="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<input name="form_abort" title="Abbruch dieser Dialogseite" type="submit" value="Abbruch"></td>
</tr>

</table>
</fieldset>
</form>
<br>
<p><b>Hinweis</b>: Das
Funknetz ist normalerweise unverschl&uuml;sselt. Beim Abruf von
Verwaltungsseiten wird das Kennwort bei jedem Seitenabruf <b>unverschl&uuml;sselt</b>
&uuml;bertragen. Zur Sicherheit sollten daher die Verwaltungsseiten nur &uuml;ber
https oder LAN bedient werden.</p>
EOM

else
	if [ -n "$form_submit" ]; then
		if [ -n "$form_pw" ]; then
			if [ "$form_pw" = "$form_confirm_pw" ]; then
				p=$(uhttpd -d "$form_pw")
				echo "root:$p" | chpasswd --md5 >/dev/null
				uhttpd_restart=1
				notebox 'Das Kennwort wurde ge&auml;ndert.'
			else
				notebox 'Kennw&ouml;rter stimmen nicht &uuml;berein! Das Kennwort wurde nicht ge&auml;ndert.'
			fi
		else
			notebox 'Leeres Kennwort ist nicht erlaubt!'
		fi
	else
		notebox 'Das Kennwort wurde nicht ge&auml;ndert.'
	fi
fi

. $DOCUMENT_ROOT/page-post.sh
