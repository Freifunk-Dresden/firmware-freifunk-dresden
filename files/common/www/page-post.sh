#!/bin/sh

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
	<tr><td class="navibar" colspan="5" height="18" width="100%"><a href="/license.cgi?license=0">License/Copyright</a>
Version:<font color="white">&nbsp;$(cat /etc/version)</font>, Internet&nbsp;IPv4&nbsp;via:&nbsp;<font color="white">$INET_GW</font>, Verbunden&nbsp;via:&nbsp;<font color="white">$in_ifname</font></td></tr>
</table>
</body>
</html>
EOM

test "$uhttpd_restart" = "1" && (killall -9 uhttpd && /etc/init.d/uhttpd start)&
