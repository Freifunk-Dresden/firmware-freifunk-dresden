#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Allgemein: SSH-Key"
. /usr/lib/www/page-pre.sh ${0%/*}

AFILE="/etc/dropbear/authorized_keys"

cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

display()
{
 [ -f "$AFILE" ] && sshkey="$(cat $AFILE)"

cat<<EOF
<form action="ssh.cgi" method="POST">
<fieldset class="bubble">
<legend>Authorized Keys</legend>
<table>
<tr title="authorized_keys - file">
<th>authorized_keys:</th>
<td colspan="2"><textarea COLS="48" name="form_sshkey" ROWS="10" style="width: 100%;">$sshkey</textarea></td>
</tr>

<tr><td colspan="3">&nbsp;</td></tr>

<tr>
<td colspan="3"><input name="form_submit" title="File speichern" type="submit" value="Speichern">&nbsp;&nbsp;&nbsp;<input name="form_abort" title="Abbrechen und &Auml;nderungen verwerfen." type="submit" value="Abbrechen"></td>
</tr>

</table>
</fieldset>
</form>
EOF
}

if [ -n "$QUERY_STRING" ]; then
	if [ -n "$form_submit" ]
	then
		decoded="$(uhttpd -d "$form_sshkey")"
		echo "$decoded" > $AFILE
		notebox 'Keys wurden gespeichert.'
	else
		notebox 'Keine &Auml;nderungen vorgenommen.'
	fi
fi

display

. /usr/lib/www/page-post.sh
