#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Tools: Speedtest (iPerf3)"
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
<fieldset class="bubble" id="fieldset" style="display:none;">
<legend>Speedtest &ndash; $node ($_ddmesh_ip)</legend>
<table class="speedtest">
<tr><th></th><th>Download Mbit/s</th><th>Upload Mbit/s</th></tr>
<tr><th>TCP</th><td id="rxtcp"></td><td id="txtcp"></td></tr>
<tr><th>UDP</th><td id="rxudp"></td><td id="txudp"></td></tr>
</table>
</fieldset>
<br />
<div id="formular">
<form action="speedtest-iperf3.cgi" method="POST" onsubmit="return checkInput();">
<fieldset class="bubble">
<legend>Speedtest</legend>
<table>
<tr>
<th>Knoten-Nr.:</th>
<td><input id="id_node" name="node" size="10" type="text" onkeypress="return isNumberKey(event);"></td>
<td><input name="post_speedtest" type="submit" value="Test"></td>
<td style="width: 100%;"></td>
</tr>
</table>
</fieldset>
</form>
</div>

EOF

if [ -n "$QUERY_STRING" ]; then

#set IFS to any value that is not used as values;else nvram will ignore all after spaces
	IFS='	'
	if [ -n "$post_speedtest" ]; then

		eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $node)

		cat<<EOM
<script type="text/javascript">
document.getElementById("formular").style.display="none"
document.getElementById("fieldset").style.display="block"
</script>
<br />

<div style="font-family: monospace;">
EOM
format()
{
 export elementId="$1"
	awk '{
		if(match($0, ".*receiver"))
		{
			speed=gensub(/.*MBytes[ ]+([0-9]+.[0-9]+)[ ]+Mbits\/sec.*/,"\\1",1,$0);
			printf("<script type=\"text/javascript\">document.getElementById(\"%s\").innerHTML=\"%s\"</script>\n",ENVIRON["elementId"], speed);
		}
		printf("%s</br>\n",$0);
	}'
}
	if [ -x /usr/bin/iperf3 ]; then
		echo '--- TCP rx ---<br />'
		/usr/lib/ddmesh/ddmesh-iperf3.sh $_ddmesh_ip rxtcp | format rxtcp
		echo '--- TCP tx ---<br />'
		/usr/lib/ddmesh/ddmesh-iperf3.sh $_ddmesh_ip txtcp | format txtcp
		echo '--- UDP rx ---<br />'
		/usr/lib/ddmesh/ddmesh-iperf3.sh $_ddmesh_ip rxudp | format rxudp
		echo '--- UDP tx ---<br />'
		/usr/lib/ddmesh/ddmesh-iperf3.sh $_ddmesh_ip txudp | format txudp
	fi

	cat<<EOM
</div>
<br />
<script type="text/javascript">
document.getElementById("formular").style.display="block"
document.getElementById("fieldset").style.backgroundColor="#acc1ac"
</script>
EOM

	fi # post_speedtest
fi # query

. /usr/lib/www/page-post.sh ${0%/*}
