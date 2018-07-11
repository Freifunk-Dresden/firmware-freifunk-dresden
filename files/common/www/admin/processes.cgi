#!/bin/sh

export TITLE="Infos: Prozesse"
. /usr/lib/www/page-pre.sh ${0%/*}

TMPFILE=/tmp/top.output

cat<<EOF
<h2>$TITLE</h2>

<br>
<fieldset class="bubble">
<legend>Prozesse (top)</legend>
<table>
<tr><th>PID</th><th>PPID</th><th>Stat</th><th>VSZ</th><th>%MEM</th><th>%CPU</th><th>Command</th></tr>
EOF

top -n 1 -b >$TMPFILE
#cat $TMPFILE |sed -n '4,$p' | sed 's#<#\&lt;#g;s#>#\&gt#g;s# *\([0-9]\+\) \+\([0-9]\+\) \+root \+\([^ ]\+\) \+\([0-9]*\) \+\([0-9.]*\) \+\([0-9.]*\) \+\(.*\)$#<tr><td>\1</td><td>\2</td><td>\3</td><td>\4</td><td>\5</td><td>\6</td><td>\7</td></tr>#
cat $TMPFILE |sed -n '4,$p' | sed 's#<##g;s#>##g;s#[ 	]*\([0-9]\+\)[ 	]\+\([0-9]\+\)[ 	]\+root[ 	]\+\([^ 	]\+\)[	 ]\+\([0-9]\+\)[ 	]\+\([0-9%]\+\)[ 	]\+\([0-9%]\+\)[ 	]\+\(.*\)$#<tr><td>\1</td><td>\2</td><td>\3</td><td>\4</td><td>\5</td><td>\6</td><td>\7</td></tr>#
' | sed -n '
2,${
s#<tr>#<tr class="colortoggle1">#
p
n
s#<tr>#<tr class="colortoggle2">#
p
}'

cat<<EOF
</table>
</fieldset>
EOF


. /usr/lib/www/page-post.sh
