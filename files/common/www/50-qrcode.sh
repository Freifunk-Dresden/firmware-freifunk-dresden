#!/bin/sh

test -x /usr/bin/qrencode || exit 0

cat<<EOM
<tr><td height="10"></td></tr>
<tr><td><div class="plugin"><a class="plugin" href="qrcode.cgi"><img alt="" src="/images/2d.png"></a></div></td></tr>
EOM
