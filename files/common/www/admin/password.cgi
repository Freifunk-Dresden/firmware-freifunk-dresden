#!/bin/sh

export TITLE="Verwaltung > Allgemein: Kennwort"
. /usr/lib/www/page-pre.sh ${0%/*}

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

<tr title="Eingabe eines neuen Kennwortes mit bis zu 32 Buchstaben, Ziffern oder Sonderzeichen.">
<th>Neues Kennwort:</th><td><input name="form_pw" size="32" type="PASSWORD"></td>
</tr>

<tr title="Wiederholte Eingabe des neuen Kennwortes.">
<th>Kennwort wiederholen:</th><td><input name="form_confirm_pw" size="32" type="PASSWORD"></td>
</tr>

<tr><td colspan="2">&nbsp;</td></tr>

<tr>
<td colspan="2"><input name="form_submit" title="Die Einstellungen &uuml;bernehmen. Diese werden sofort wirksam." type="submit" value="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<input name="form_abort" title="Abbrechen und &Auml;nderungen verwerfen." type="submit" value="Abbrechen"></td>
</tr>

</table>
</fieldset>
</form>
<br>
<p><b>Hinweis:</b> Das
Funknetz ist normalerweise unverschl&uuml;sselt. Beim Abruf von
Verwaltungsseiten wird das Kennwort bei jedem Seitenabruf <b>unverschl&uuml;sselt</b>
&uuml;bertragen. <b>Zur Sicherheit sollten daher die Verwaltungsseiten nur &uuml;ber
HTTPS oder LAN bedient werden!</b></p>
EOM

else
	if [ -n "$form_submit" ]; then
		if [ -n "$form_pw" ]; then
			if [ "$form_pw" = "$form_confirm_pw" ]; then
				p=$(uhttpd -d "$form_pw")
				# delete blocking files
				rm -f '/etc/passwd+' '/etc/shadow+'
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

. /usr/lib/www/page-post.sh
