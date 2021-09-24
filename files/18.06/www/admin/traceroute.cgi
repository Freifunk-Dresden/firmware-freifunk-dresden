#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Tools: Traceroute"
. /usr/lib/www/page-pre.sh ${0%/*}


cat<<EOF
<script type="text/javascript">
function checkInput()
{
	var node = document.getElementById('id_node').value;
	if( node === undefined || checknumber(node) || node < 0)
	{
		alert("Falsche Knoten-Nr.");
		return false;
	}
	return true;
}
</script>

<h2>$TITLE</h2>
<br>
EOF

if [ -n "$QUERY_STRING" ]; then

#set IFS to any value that is not used as values;else nvram will ignore all after spaces
	IFS='	'
	if [ -n "$post_traceroute" ]; then

		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)

		cat<<EOM
<fieldset class="bubble">
<legend>Traceroute &ndash; $node ($_ddmesh_ip)</legend>
Starte...<br>
<pre>
EOM

	if [ -x /usr/bin/iperf3 ]; then
		traceroute -ln $_ddmesh_ip | flush
	fi

	cat<<EOM
</pre>
<br />

</fieldset>
EOM

	fi

#query
fi

cat<<EOF
<form action="traceroute.cgi" method="POST" onsubmit="return checkInput();">
<fieldset class="bubble">
<legend>Traceroute</legend>
<table>
<tr>
<th>Knoten-Nr.:</th>
<td><input id="id_node" name="node" size="10" type="text" onkeypress="return isNumberKey(event);"></td>
<td><input name="post_traceroute" type="submit" value="Test"></td>
<td style="width: 100%;"></td>
</tr>
</table>
</fieldset>
</form>
EOF

. /usr/lib/www/page-post.sh ${0%/*}
