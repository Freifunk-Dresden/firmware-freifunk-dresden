#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Infos: Netzwerk"
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<h2>$TITLE</h2>
<br>

<fieldset class="bubble">
<legend>Bridge</legend>
<table>
<tr class="colortoggle1"><th>Name</th><th>ID</th><th>STP</th><th>Interface</th></tr>
EOM


brctl show | sed '
1d
s#[ 	]\+# #g
/^[^ ]/s#^\([^ ]*\) \([^ ]*\) \([^ ]*\)\( \([^ ]*\)\)*#<tr class="colortoggle2"><td>\1</td><td>\2</td><td>\3</td><td>\4</td></tr>#
/^[ ]/s#^\(.*\)#<tr class="colortoggle2"><td></td><td></td><td></td><td>\1</td></tr>#
'

cat<<EOM
</table>
</fieldset>

<br>

<fieldset class="bubble">
<legend>Switch</legend>
<table>
EOM

IFS='
'
for dev in $(swconfig list | awk '{print $2}')
do
	echo "<tr class="colortoggle1"><th colspan=2>$dev</th></tr>"
	for entry in $(swconfig dev $dev show | sed -n 's#link: port:\([0-9]\+\) link:\(.*\+\)#\1=\2#p')
	do
		port=${entry%%=*}
		state=${entry#*=}
		echo "<tr class="colortoggle2"><th>Port $port</th><td>$state</td></tr>"
	done
done

cat<<EOM
</table>
</fieldset>

<br>

<fieldset class="bubble">
<legend>Netzwerk-Schnittstellen</legend>
<table>
EOM

ifconfig -a | sed '
/^[^ ]/s#^\([^ ]*\)\(.*\)#<tr class="colortoggle1"><th>\1</th><td>\2</td></tr>#
/^[ ]/s#.*#<tr class="colortoggle2"><th></th><td>&</td></tr>#
s#\(UP\|inet addr:\|P-t-P:\|Bcast:\|Mask:\)#<b>\1</b>#g
s#\(MTU:\)\([0-9]\+\)#<b>\1</b><font style="color: magenta;">\2</font>#g
s#\([0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\)#<font style="color: blue;">\1</font>#g
'

cat<<EOM
</table>
</fieldset>

<br>

<fieldset class="bubble">
<legend>Aktive Verbindungen</legend>
<table>
<tr><th colspan="2">Lokal</th><th colspan="2">Entfernt</th></tr>
EOM

netstat -tn 2>/dev/null | grep ESTABLISHED | awk '
{
	split($4,a,":");
	split($5,b,":");
	printf("<tr class=\"colortoggle%d\"><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",(NR%2)+1,a[1],a[2],b[1],b[2]);
}'

cat<<EOM
</table>
</fieldset>
EOM

. /usr/lib/www/page-post.sh
