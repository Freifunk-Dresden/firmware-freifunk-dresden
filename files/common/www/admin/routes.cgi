#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Infos: Routen"
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOF
<h2>$TITLE</h2>
<br>
EOF

for t in main local_gateway fallback_gateway public_gateway bat_route ; do

	cat<<EOF
<fieldset class="bubble">
<legend>Routing-Tabelle: $t</legend>
<table>
<tr><th>Ziel</th><th>via</th><th>Netzwerkger&auml;t</th><th>Protokoll</th><th>Scope</th><th>Metric</th><th>Quell-IP-Adresse</th></tr>
EOF

	ip route list table $t | sed '
s@^\([^ ]*\)[ ]\?[ ]*\(via [^ ]*\)\?[ ]\?[ ]*\(dev [^ ]*\)\?[ ]\?[ ]*\(proto [^ ]*\)\?[ ]\?[ ]*\(scope [^ ]*\)\?[ ]\?[ ]*\(metric [^ ]*\)\?[ ]\?[ ]*\(src [^ ]*\)\?[ ]\?[ ]*@\1 \2 \3 \4 \5 \6 \7@
' | sed '
s@via @@
s@dev @@
s@scope @@
s@metric @@
s@src @@
s@linkdown @@
s@proto @@
' | sed -n -e '
s@^\(default[^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\)@<tr class="colortoggle3"><td>\1</td><td>\2</td><td>\3</td><td>\4</td><td>\5</td><td>\6</td><td>\7</td></tr>@
s@^\([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\)@<tr class="colortoggle1"><td>\1</td><td>\2</td><td>\3</td><td>\4</td><td>\5</td><td>\6</td><td>\7</td></tr>@
s@\([0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\)\([^/]\)@\1\2@g
p
n
s@^\(default[^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\)@<tr class="colortoggle3"><td>\1</td><td>\2</td><td>\3</td><td>\4</td><td>\5</td><td>\6</td><td>\7</td></tr>@
s@^\([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\) \([^ ]*\)@<tr class="colortoggle2"><td>\1</td><td>\2</td><td>\3</td><td>\4</td><td>\5</td><td>\6</td><td>\7</td></tr>@
s@\([0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\)\([^/]\)@\1\2@g
p
'
	cat<<EOF
</table>
</fieldset>
<br>
EOF

done

. /usr/lib/www/page-post.sh ${0%/*}
