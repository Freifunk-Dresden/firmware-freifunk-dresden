#!/bin/sh

text -x /usr/bin/qrencode || exit 0

export TITLE="Barcode"
. $DOCUMENT_ROOT/page-pre.sh

cat<<EOF
<h2>$TITLE</h2>
<br>
<fieldset class="bubble">
<legend>2D Barcode</legend>
<table>
<tr><th>Barcode</th><th>Inhalt</th></tr>
<tr><td><img src="/images/2d-big.png"></td>
<td><pre>$(cat /tmp/2d-big.txt)</pre></td>
</tr>
</table>
</fieldset>
EOF

. $DOCUMENT_ROOT/page-post.sh
