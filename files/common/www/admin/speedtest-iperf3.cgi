#!/bin/sh

export TITLE="Verwaltung > Tools > Speedtest-iperf3"
. /usr/lib/www/page-pre.sh ${0%/*}


cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

if [ -n "$QUERY_STRING" ]; then

#set IFS to any value that is not used as values;else nvram will ignore all after spaces
	IFS='	'
	if [ -n "$post_speedtest" ]; then

		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)

		cat<<EOM
<fieldset class="bubble">
<legend>Speedtest - $node ($_ddmesh_ip)</legend>
starte...<br>
<pre>
EOM

	if [ -x /usr/bin/iperf3 ]; then
		echo '--- TCP rx ---'
		/usr/lib/ddmesh/ddmesh-iperf3.sh $_ddmesh_ip rxtcp | flush
		echo '--- TCP tx ---'
		/usr/lib/ddmesh/ddmesh-iperf3.sh $_ddmesh_ip txtcp | flush
		echo '--- UDP rx ---'
		/usr/lib/ddmesh/ddmesh-iperf3.sh $_ddmesh_ip rxudp | flush
		echo '--- UDP tx ---'
		/usr/lib/ddmesh/ddmesh-iperf3.sh $_ddmesh_ip txudp | flush
	fi

	cat<<EOM
</pre>
<br />
finished.
</fieldset>
EOM

	fi

#query
fi

cat<<EOF
<form action="speedtest-iperf3.cgi" method="POST">
<fieldset class="bubble">
<legend>Speedtest</legend>
<table>
<tr>
<th>Knotennummer:</th>
<td><input name="node" size="10" type="text"></td>
<td><input name="post_speedtest" type="submit" value="Test"></td>
<td style="width: 100%;"></td>
</tr>
</table>
</fieldset>
</form>
EOF

. /usr/lib/www/page-post.sh ${0%/*}
