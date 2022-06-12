#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

#use envirment variables set by html or cgi pages
#uhttpd_restart - uhttpd must be restarted at end

cat<<EOF
</div>
</td></tr>
</table></td></tr>
<tr><td colspan="2" width="100%">
<div class="navibar" HEIGHT="18" width="100%">
<a href="/license.cgi?license=0">License/Copyright</a>
Version:<font color="white">&nbsp;$(cat /etc/version)</font>, Internet&nbsp;IPv4&nbsp;via:&nbsp;<font color="white">$INET_GW</font>, Verbunden&nbsp;via:&nbsp;<font color="white">$in_ifname</font>
</div></td></tr></table>
</BODY>
</HTML>
EOF
