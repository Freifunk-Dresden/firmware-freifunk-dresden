#!/bin/sh

test -x /usr/bin/nuttcp || exit 0

cat <<EOM
<tr><td height="8"></td></tr>
<tr><td><img class="icon" src="/images/expert.png"><big class="plugin">Tools</big></td></tr>
<tr><td><div class="plugin"><a class="plugin" href="speedtest.cgi">Speedtest</a></div></td></tr>
EOM
