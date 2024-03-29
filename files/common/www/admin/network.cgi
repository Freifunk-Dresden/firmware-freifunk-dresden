#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
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
EOM


SWITCH_INFO="$(/usr/lib/ddmesh/ddmesh-utils-switch-info.sh csv | sort)"

if [ -n "${SWITCH_INFO}" ]; then
cat<<EOM
<fieldset class="bubble">
<legend>Switch $(/usr/lib/ddmesh/ddmesh-utils-switch-info.sh isdsa >/dev/null && echo "(DSA)")</legend>
<table>
<tr class="colortoggle1"> <th>Port</th> <td>Carrier</td> <td>Speed</td> </tr>
EOM

unset IFS;
IFS='
'
for entry in ${SWITCH_INFO}; do
	IFS=','
	set $entry
	echo "<tr class="colortoggle2"> <th>$1</th> <td>$2</td> <td>$3</td> </tr>"
	unset IFS
done
unset IFS

cat<<EOM
</table>
</fieldset>
<br>
EOM
fi

cat<<EOM
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
