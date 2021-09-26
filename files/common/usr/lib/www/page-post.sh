#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

#use envirment variables set by html or cgi pages
#uhttpd_restart - uhttpd must be restarted at end

cat<<EOM
<!-- page-post -->
				</td>
				<td bgcolor="white" height="5"  valign="top" width="100%"></td></tr>
			</table>
		</td>
		<td width="5">&nbsp;</td>
		<td class="navi" valign="top" height="100%" width="150"><img alt="" border="0" height="62" src="/images/ff-logo-3.gif" width="150"></td>
	</tr>
	<tr><td colspan="5" height="5"></td></tr>
	<tr><td class="navibar" colspan="5" height="18" width="100%"><span class="infobar"><a href="/license.cgi?license=0">License/Copyright</a>, Internet&nbsp;IPv4&nbsp;via:&nbsp;<span class="infobarvalue">$INET_GW</span>, Verbunden&nbsp;via:&nbsp;<span class="infobarvalue">$in_ifname</span></span></td></tr>
</table>
</body>
</html>
EOM

test "$uhttpd_restart" = "1" && (killall -9 uhttpd && /etc/init.d/uhttpd start)&
