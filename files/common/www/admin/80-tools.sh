#!/bin/sh

test -x /usr/bin/iperf3 || test -x /usr/bin/nuttcp || exit 0

cat <<EOM
<tr><td height="8"></td></tr>
<tr><td><img class="icon" src="/images/expert.png"><big class="plugin">Tools</big></td></tr>
EOM


if [ -x /usr/bin/iperf3 ]; then
cat <<EOM
<tr><td><div class="plugin"><a class="plugin" href="speedtest-iperf3.cgi">Speedtest-iperf3</a></div></td></tr>
EOM
fi

if [ -x /usr/bin/nuttcp ]; then
cat <<EOM
<tr><td><div class="plugin"><a class="plugin" href="speedtest-nuttcp.cgi">Speedtest-nuttcp</a></div></td></tr>
EOM
fi
