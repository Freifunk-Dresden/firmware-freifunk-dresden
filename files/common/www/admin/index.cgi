#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Allgemein"
. /usr/lib/www/page-pre.sh ${0%/*}

RESOLV_PATH="/tmp/resolv.conf.d"

if [ "$form_action" = "overlay" ]; then
	/usr/lib/ddmesh/ddmesh-overlay-md5sum.sh write >/dev/null
fi

eval $(sed 's#:\(.*\)$#="\1"#' /etc/built_info)

case  "$git_ddmesh_branch" in
	master)
		html_git_ddmesh_branch="<font color=\"red\">$git_ddmesh_branch</font>"
		;;
	T_*)
		html_git_ddmesh_branch="<font color=\"green\">$git_ddmesh_branch</font>"
		;;
	*)
		html_git_ddmesh_branch="<font color=\"blue\">$git_ddmesh_branch</font>"
		;;
esac

cat<<EOM
<h1>$TITLE</h1>
<br>
<fieldset class="bubble">
Willkommen auf den Verwaltungs-Seiten dieses
Access-Points. Weiterf&uuml;hrende Informationen dazu findest du im <a href="https://wiki.freifunk-dresden.de">Freifunk-Wiki</a>. Kommentare oder Korrekturvorschl&auml;ge zu dieser
Web-Oberfl&auml;che kannst du uns gern unter Angabe der Firmware-Version ($(cat /etc/version)) im <a href="https://forum.freifunk.net/c/community/dresden">Dresdner Freifunk-Forum</a> mitteilen.
</fieldset>

<NOSCRIPT><table BORDER="0" class="note">
<tr><td>F&uuml;r das automatische Laden der Startseiten beim <a href="reset.cgi">Neustart</a>
wird JavaScript ben&ouml;tigt.</td></tr>
</table></NOSCRIPT>

<p><b>Tipp</b>: Dr&uuml;cke
<KBD style="text-decoration: blink;">[F1]</KBD> oder zeige mit der Maus
auf eines der Steuerungselemente, um kurze Hilfetexte einzublenden.</p>

<br>
<fieldset class="bubble">
<legend>Notwendige Einstellungen</legend>
<table>
<tr><th width="20">Status</th><th>Einstellung</th></tr>
<tr class="colortoggle1"><td>$(test -n "$(uci -q get ddmesh.contact.email)" && echo '<img alt="OK" src="../images/yes.png">' || echo '<img alt="Not OK" src="../images/no.png">')</td><td><a href="contact.cgi">Kontaktinfos</a>: E-Mail</td></tr>
<tr class="colortoggle2"><td>$(test -n "$(uci -q get ddmesh.contact.location)" && echo '<img alt="OK" src="../images/yes.png">' || echo '<img alt="Not OK" src="../images/no.png">')</td><td><a href="contact.cgi">Kontaktinfos</a>: Standort </td></tr>
<tr class="colortoggle1"><td>$(test -n "$(uci -q get ddmesh.gps.latitude)" && test -n "$(uci -q get ddmesh.gps.longitude)" && test -n "$(uci -q get ddmesh.gps.altitude)" && echo '<img alt="OK" src="../images/yes.png">' || echo '<img alt="Not OK" src="../images/no.png">')</td><td><a href="contact.cgi">Kontaktinfos</a>: Koordinaten </td></tr>

</table>
</fieldset>

<br>
<fieldset class="bubble">
<legend>Flash</legend>
<form name="form_overlay" action="index.cgi" method="POST">
<input name="form_action" value="overlay" type="hidden">
<p>Zeigt Flash&auml;nderungen, welche nur nach &Auml;nderung der Einstellungen vorhanden sein sollten.</p>
<table>
<tr><th></th><th>Vorhergehend</th><th>Aktuell</th></tr>
EOM

eval $(/usr/lib/ddmesh/ddmesh-overlay-md5sum.sh read | sed 's#\(.*\):\(.*\)$#ovl_\1=\2#')
if [ "$ovl_old" = "$ovl_cur" ]; then
 co="green"
else
 co="red"
fi

cat<<EOM
<tr class="colortoggle1" style="font-weight:bold;color: $co;"><th>Flash Overlay MD5</th><td>$ovl_old</td><td>$ovl_cur</td>
<td><input name="form_firmware_submit" type="submit" value="Reset"></td></tr>
</table>
</form>
</fieldset>

<br>
<fieldset class="bubble">
<legend>System-Version</legend>
<table>
<tr class="colortoggle1"><th>Freifunk-Version (Dresden)</th><td>$(cat /etc/version)</td></tr>
<tr class="colortoggle2"><th>Git-Firmware-Revision</th><td>$git_ddmesh_rev</td></tr>
<tr class="colortoggle1"><th>Git-Firmware-Branch/Tag</th><td>$html_git_ddmesh_branch</td></tr>
<tr class="colortoggle2"><th>Git-Openwrt-Revision</th><td>$git_openwrt_rev</td></tr>
<tr class="colortoggle1"><th>Git-Openwrt-Branch/Tag</th><td>$git_openwrt_branch</td></tr>

<tr class="colortoggle2"><th>Build-Datum</th><td>$(sed -n '/builtdate/s#[^:]*:##p' /etc/built_info)</td></tr>
$(cat /etc/openwrt_release | sed 's#\(.*\)="*\([^"]*\)"*#<tr class="colortoggle1"><th>\1</th><td>\2</td></tr>#')
</table>
</fieldset>

<br>
<fieldset class="bubble">
<legend>System Info</legend>
<table>
<tr class="colortoggle2"><th>Knoten-IP:</th><td colspan="6">$_ddmesh_ip</td></tr>
<tr class="colortoggle2"><th>Nameserver:</th><td colspan="6">$(grep nameserver ${RESOLV_PATH}/resolv.conf.auto | sed 's#nameserver##g')</td></tr>
<tr class="colortoggle2"><th>Ger&auml;telaufzeit:</th><td colspan="6">$(uptime)</td></tr>
<tr class="colortoggle2"><th>System:</th><td colspan="6">$(uname -m) $(sed -n '/system type/s#system[ 	]*type[ 	]*:##p' /proc/cpuinfo)</td></tr>
<tr class="colortoggle2"><th>Ger&auml;teinfo:</th><td colspan="6"><b>Model:</b> $model ($model2) - <b>CPU:</b> $(sed -n '/system type/s#[^:]\+:[ 	]*##p' /proc/cpuinfo) - <b>Board:</b> $(cat /tmp/sysinfo/board_name)</td></tr>
<tr class="colortoggle2"><th>Filesystem:</th><td colspan="6">$(sed 's#.*rootfstype=\([a-z0-9]\+\).*$#\1#' /proc/cmdline)</td></tr>
<tr class="colortoggle2"><th>SSH-Fingerprint (MD5)</th><td colspan="6">$(dropbearkey -y -f /etc/dropbear/dropbear_rsa_host_key | sed -n '/Fingerprint/s#Fingerprint: md5 ##p')</td></tr>
<tr class="colortoggle1"><th></th><th>Total</th> <th>Used</th> <th>Free</th> <th>Shared</th> <th>Buffered</th> <th>Cached</th></tr>
$(free | sed -n '2,${s#[ 	]*\(.*\):[ 	]*\([0-9]\+\)[ 	]*\([0-9]\+\)[ 	]*\([0-9]*\)[ 	]*\([0-9]*\)[ 	]*\([0-9]*\)[ 	]*\([0-9]*\)#<tr class="colortoggle2"><th>\1</th><td>\2</td><td>\3</td><td>\4</td><td>\5</td><td>\6</td><td>\7</td></tr>#g;p}' )
</table>
</fieldset>

<br>
<fieldset class="bubble">
<legend>DHCP-Leases (aktuelle)</legend>
<table>
EOM

	IFS='
'
	T=1
	for i in $(sed 's#\([^ ]\+\) \([^ ]\+\) \([^ ]\+\) \([^ ]\+\) \([^ ]\+\)#D="$(date --date=\"@\1\")";MAC1=\2;IP=\3;NAME=\4;MAC2=\5#' /tmp/dhcp.leases)
	do
		eval $i
		echo "<tr class="colortoggle$T" ><th>Zeit:</th><td>$D</td><th>MAC:</th><td>$MAC1</td><th>IP:</th><td>$IP</td><th>Name:</th><td>$NAME</td></tr>"
		if [ $T = 1 ]; then T=2 ;else T=1; fi
	done

cat<<EOM
</table>
</fieldset>
EOM

. /usr/lib/www/page-post.sh
