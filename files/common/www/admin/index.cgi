#!/bin/sh

export TITLE="Verwaltung > Allgemein"
. /usr/lib/www/page-pre.sh ${0%/*}

if [ "$form_action" = "overlay" ]; then
	/usr/lib/ddmesh/ddmesh-overlay-md5sum.sh write >/dev/null
fi

eval $(cat /etc/built_info | sed 's#:\(.*\)$#="\1"#')

cat<<EOM
<h1>$TITLE</h1>
<br>
<fieldset class="bubble">
Willkommen zu den Verwaltungs-Seiten dieses
Access-Points. Sende Kommentare oder Korrekturvorschl&auml;ge zu dieser
Web-Oberfl&auml;che unter Angabe der Firmware-Version ($(cat /etc/version)) in das Dresdner Freifunk Forum.
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
<tr class="colortoggle1"><td>$(test -n "$(uci -q get ddmesh.gps.latitude)" && test -n "$(uci -q get ddmesh.gps.longitude)" && test -n "$(uci -q get ddmesh.gps.altitude)" && echo '<img alt="OK" src="../images/yes.png">' || echo '<img alt="Not OK" src="../images/no.png">')</td><td><a href="contact.cgi">Kontaktinfos</a>: GPS Koordinaten </td></tr>

</table>
</fieldset>

<br>
<fieldset class="bubble">
<legend>System Version</legend>
<table>
<tr class="colortoggle1"><th>Freifunk Version (Dresden)</th><td>$(cat /etc/version)</td></tr>
<tr class="colortoggle2"><th>Git Firmware Referenz</th><td>$git_ddmesh_ref</td></tr>
<tr class="colortoggle1"><th>Git Firmware Branch</th><td>$git_ddmesh_branch</td></tr>
<tr class="colortoggle2"><th>Git Lede Referenz</th><td>$git_lede_ref</td></tr>
<tr class="colortoggle1"><th>Git Lede Branch</th><td>$git_lede_branch</td></tr>
<tr class="colortoggle2"><th>Built Datum</th><td>$(cat /etc/built_info | sed -n '/builtdate/s#[^:]*:##p')</td></tr>
$(cat /etc/openwrt_release | sed 's#\(.*\)="*\([^"]*\)"*#<tr class="colortoggle1"><th>\1</th><td>\2</td></tr>#')
</table>
</fieldset>

<br>
<fieldset class="bubble">
<legend>System Info</legend>
<table>
<tr class="colortoggle2"><th>Knoten-IP:</th><td colspan="6">$_ddmesh_ip</td></tr>
<tr class="colortoggle2"><th>Nameserver:</th><td colspan="6">$(grep nameserver /tmp/resolv.conf.auto | sed 's#nameserver##g')</td></tr>
<tr class="colortoggle2"><th>Ger&auml;telaufzeit:</th><td colspan="6">$(uptime)</td></tr>
<tr class="colortoggle2"><th>System:</th><td colspan="6">$(uname -m) $(cat /proc/cpuinfo | sed -n '/system type/s#system[ 	]*type[ 	]*:##p')</td></tr>
<tr class="colortoggle2"><th>Ger&auml;teinfo:</th><td colspan="6">$device_model - $(cat /proc/cpuinfo | sed -n '/system type/s#.*:[ 	]*##p') [$(cat /tmp/sysinfo/board_name)]</td></tr>
<tr class="colortoggle2"><th>Filesystem:</th><td colspan="6">$(cat /proc/cmdline | sed 's#.*rootfstype=\([a-z0-9]\+\).*$#\1#')</td></tr>
<tr class="colortoggle2"><th>SSH Fingerprint (md5)</th><td colspan="6">$(dropbearkey -y -f /etc/dropbear/dropbear_rsa_host_key | sed -n '/Fingerprint/s#Fingerprint: md5 ##p')</td></tr>
<tr class="colortoggle1"><th></th><th>Total</th> <th>Used</th> <th>Free</th> <th>Shared</th> <th>Buffers</th> <th>Cached</th></tr>
$(free | sed -n '2,${s#[ 	]*\(.*\):[ 	]*\([0-9]\+\)[ 	]*\([0-9]\+\)[ 	]*\([0-9]*\)[ 	]*\([0-9]*\)[ 	]*\([0-9]*\)[ 	]*\([0-9]*\)#<tr class="colortoggle2"><th>\1</th><td>\2</td><td>\3</td><td>\4</td><td>\5</td><td>\6</td><td>\7</td></tr>#g;p}' )
</table>
</fieldset>
EOM

	cat<<EOM
<br>
<fieldset class="bubble">
<legend>DHCP Leases (aktuelle)</legend>
<table>
EOM

	IFS='
'
	T=1
	for i in $(cat /tmp/dhcp.leases | sed 's#\([^ ]\+\) \([^ ]\+\) \([^ ]\+\) \([^ ]\+\) \([^ ]\+\)#D="$(date --date=\"@\1\")";MAC1=\2;IP=\3;NAME=\4;MAC2=\5#')
	do
		eval $i
		echo "<tr class="colortoggle$T" ><th>Zeit:</th><td>$D</td><th>MAC:</th><td>$MAC1</td><th>IP:</th><td>$IP</td><th>Name:</th><td>$NAME</td></tr>"
		if [ $T = 1 ]; then T=2 ;else T=1; fi
	done

	cat<<EOM
</table>
</fieldset>
<br>
<fieldset class="bubble">
<legend>Internals</legend>
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
EOM

. /usr/lib/www/page-post.sh


