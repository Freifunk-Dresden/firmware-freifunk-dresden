#!/bin/sh

export TITLE="Infos: Logs"
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<h2>$TITLE</h2>
<br>

<fieldset class="bubble">
<legend>Kernel Log: <a href="#" onclick="return fold('fs_dmesg')">Ein-/Ausblenden</a></legend>
<table class="hidden" id="fs_dmesg">
EOM
dmesg 2>&1 | sed -n '
s#^.*$#<tr class="colortoggle1"><td>&</td></tr>#
p
n
s#^.*$#<tr class="colortoggle2"><td>&</td></tr>#
p
'
cat<<EOM
</table>
</fieldset>
<br>
<fieldset class="bubble">
<legend>System Log: <a href="#" onclick="return fold('fs_logread')">Ein-/Ausblenden</a></legend>
<table class="hidden" id="fs_logread">
EOM

logread 2>&1 | sed -n '
s#^.*$#<tr class="colortoggle1"><td>&</td></tr>#
p
n
s#^.*$#<tr class="colortoggle2"><td>&</td></tr>#
p
'

cat<<EOM
</table>
</fieldset>
<br>
<fieldset class="bubble">
<legend>Netzwerk: <a href="#" onclick="return fold('fs_ifconfig')">Ein-/Ausblenden</a></legend>
<table class="hidden" id="fs_ifconfig">
EOM

ifconfig | sed '
/^[^ ]/s#^\([^ ]*\)\(.*\)#<tr class="colortoggle1"><th>\1</th><td>\2</td></tr>#
/^[ ]/s#.*#<tr class="colortoggle2"><th></th><td>&</td></tr>#'

cat<<EOM
</table>
</fieldset>
<br>
<fieldset class="bubble">
<legend>Aktive Verbindungen: <a href="#" onclick="return fold('fs_conntrk')">Ein-/Ausblenden</a></legend>
<table class="hidden" id="fs_conntrk">
<tr><th colspan="2">Lokal</th><th colspan="2">Entfernt</th></tr>
EOM

netstat -tn 2>/dev/null | grep ESTABLISHED | awk '
{
	split($4,a,":");
	split($5,b,":");
	if(match(a[1],"169.254")) a[1]="Gateway Tunnel"
	printf("<tr class=\"colortoggle%d\"><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",(NR%2)+1,a[1],a[2],b[1],b[2]);
}'

cat<<EOM
</table>
</fieldset>
<br>
<fieldset class="bubble">
<legend>DHCP Log: <a href="#" onclick="return fold('fs_dhcp')">Ein-/Ausblenden</a></legend>
<table class="hidden" id="fs_dhcp">
<tr><th>Date</th><th>CMD</th><th>MAC</th><th>IP</th><!--<th>Hostname</th>--></tr>
EOM

touch /var/log/dnsmasq.log
cat /var/log/dnsmasq.log | sed -n '
s#^[ 	]*\[\(.*\)\][ 	]\+cmd=\([^ 	]\+\)[	 ]\+mac=\([^	 ]\+\)[ 	]\+ip=\([^	 ]\+\)[ 	]\+hostname=\([^	 ]*\).*$#<tr class="colortoggle1"><td>\1</td><td>\2</td><td>\3</td><td>\4</td><!-- <td>\5</td> --></tr>#
p
n
s#^[ 	]*\[\(.*\)\][ 	]\+cmd=\([^ 	]\+\)[	 ]\+mac=\([^	 ]\+\)[ 	]\+ip=\([^	 ]\+\)[ 	]\+hostname=\([^	 ]*\).*$#<tr class="colortoggle2"><td>\1</td><td>\2</td><td>\3</td><td>\4</td><!-- <td>\5</td> --></tr>#
p
'

cat<<EOM
</table>
</fieldset>
EOM

. /usr/lib/www/page-post.sh
