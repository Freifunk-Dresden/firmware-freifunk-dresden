#!/bin/sh

export TITLE="Verwaltung > Tools > Speedtest"
. /usr/lib/www/page-pre.sh ${0%/*}


cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

if [ -z "$QUERY_STRING" ]; then

	cat<<EOF
<form action="speedtest.cgi" method="POST">
<fieldset class="bubble">
<legend>Speedtest</legend>
<table>

<tr>
<th>Knoten/IP (z.B.:10.200.0.1:</th>
<td><input name="host" size="48" style="width: 100%;" type="text"></td>
<td><input name="post_speedtest" type="submit" value="Test"></td>
</tr>
</table>
</fieldset>
</form>
EOF

else
#set IFS to any value that is not used as values;else nvram will ignore all after spaces
	IFS='	'
	if [ -n "$post_speedtest" ]; then

		cat<<EOM
<fieldset class="bubble">
<legend>Speedtest - $host</legend>
starte...<br>
EOM
	ddmesh-nuttcp.sh $host | flush
	cat<<EOM
<br />
finished.
</fieldset>
EOM

	fi

#query
fi

. /usr/lib/www/page-post.sh ${0%/*}
