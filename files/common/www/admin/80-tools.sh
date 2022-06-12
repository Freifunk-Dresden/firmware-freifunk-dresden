#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

test -x /usr/bin/iperf3 || exit 0

cat <<EOM
<tr><td height="8"></td></tr>
<tr><td><img src="/images/expert.png"><big class="plugin">Tools</big></td></tr>
EOM


if [ -x /usr/bin/iperf3 ]; then
cat <<EOM
<tr><td><div class="plugin"><a class="plugin" href="speedtest-iperf3.cgi">Speedtest (iPerf3)</a></div></td></tr>
<tr><td><div class="plugin"><a class="plugin" href="traceroute.cgi">Traceroute</a></div></td></tr>
EOM
fi
