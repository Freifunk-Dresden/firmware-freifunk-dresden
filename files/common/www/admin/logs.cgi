#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Infos: Logs"
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<h2>$TITLE</h2>
<br>

<fieldset class="bubble">
<legend>Kernel-Log: <a href="#" onclick="return fold('fs_dmesg')">Ein-/Ausblenden</a></legend>
<table class="hidden" id="fs_dmesg">
EOM
dmesg 2>&1 | sed -n '
s#^.*$#<tr class="colortoggle1"><td>&</td></tr>#
p
n
s#^.*$#<tr class="colortoggle2"><td>&</td></tr>#
p
'
cat<<EOM
</table>
</fieldset>
<br>
<fieldset class="bubble">
<legend>System-Log: <a href="#" onclick="return fold('fs_logread')">Ein-/Ausblenden</a></legend>
<table class="hidden" id="fs_logread">
EOM

logread 2>&1 | awk '
BEGIN {t=1;}
{
	line=$0
	d=substr(line,1,24)
	line=substr($0,26)
	len=index(line,":");
	tag=substr(line,1,len);
	tag1=gensub(/([^ :]+)[^:]*:.*/,"\\1", "", tag)
	tag2=gensub(/([^ :]+)([^:]*):.*/,"\\2", "", tag)
	line=substr(line,len+1);

	tag1=gensub(/(user\..*)/,"<font color=\"green\">\\1</font>","",tag1);
	tag2=gensub(/(ddmesh.*)/,"<font color=\"green\">\\1</font>","",tag2);
	tag1=gensub(/(kern\..*)/,"<font color=\"blue\">\\1</font>","",tag1);
	tag1=gensub(/(.*\.err)/,"<font color=\"red\">\\1</font>","",tag1);
	tag2=gensub(/(kernel)/,"<font color=\"blue\">\\1</font>","",tag2);
	tag2=gensub(/(netifd)/,"<font color=\"purple\">\\1</font>","",tag2);
	tag2=gensub(/(hostapd|wpa_.*|mac80211)/,"<font color=\"#8f8f0f\">\\1</font>","",tag2);

	line=gensub(/(br-mesh_lan|br-mesh_wan|(br|mesh)[-_](lan|wan|wifi)[0-9a-z]*|mesh[25]g-80211s)/,"<font color=\"#000088\">\\1</font>","",line);
	line=gensub(/(.*hotplug.*)/,"<font color=\"#006655\">\\1</font>","",line);
	line=gensub(/(.*([Ff][Aa][Ii][Ll][Ee][Dd]|[Ee][Rr][Rr][Oo][Rr]).*)/,"<font color=\"red\">\\1</font>","",line);
	line=gensub(/(.*Wait for WIFI up.*|.*WIFI is up.*)/,"<div style=\"background-color:#ffaaff;\">\\1</div>","",line);
	printf("<tr class=\"colortoggle%d\"><td class=\"nowrap\">%s</td><td class=\"nowrap\">%s</td><td class=\"nowrap\">%s</td><td>%s</td></tr>\n",t,d,tag1,tag2,line);
	

	if(t==1){ t=2;}
	else{ t=1;}
}
'

cat<<EOM
</table>
</fieldset>
<br>
<fieldset class="bubble">
<legend>DHCP-Log: <a href="#" onclick="return fold('fs_dhcp')">Ein-/Ausblenden</a></legend>
<table class="hidden" id="fs_dhcp">
<tr><th>Date</th><th>CMD</th><th>MAC</th><th>IP</th><!--<th>Hostname</th>--></tr>
EOM

touch /var/log/dnsmasq.log
cat /var/log/dnsmasq.log | sed -n '
s#^[ 	]*\[\(.*\)\][ 	]\+cmd=\([^ 	]\+\)[	 ]\+mac=\([^	 ]\+\)[ 	]\+ip=\([^	 ]\+\)[ 	]\+hostname=\([^	 ]*\).*$#<tr class="colortoggle1"><td>\1</td><td>\2</td><td>\3</td><td>\4</td><!-- <td>\5</td> --></tr>#
p
n
s#^[ 	]*\[\(.*\)\][ 	]\+cmd=\([^ 	]\+\)[	 ]\+mac=\([^	 ]\+\)[ 	]\+ip=\([^	 ]\+\)[ 	]\+hostname=\([^	 ]*\).*$#<tr class="colortoggle2"><td>\1</td><td>\2</td><td>\3</td><td>\4</td><!-- <td>\5</td> --></tr>#
p
'

cat<<EOM
</table>
</fieldset>
EOM

. /usr/lib/www/page-post.sh
