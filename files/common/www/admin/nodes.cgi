#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Infos: Knoten"
. /usr/lib/www/page-pre.sh ${0%/*}


cat<<EOM
<h2>$TITLE</h2>
<br>
<fieldset class="bubble">
<legend>Direkte Nachbarn</legend>
<table>
<tr><th colspan="2">&nbsp;</th><th colspan="2">Interface-</th><th colspan="3">Linkqualit&auml;t</th></tr>
<tr><th>Knoten-Nr.</th><th>IP-Adresse</th><th>Device</th><th>IP-Adresse</th><th>RTQ</th><th>vom Nachbarn (RQ)</th><th>zum Nachbarn (TQ)</th></tr>
EOM

/usr/bin/bmxd -c --links | awk -f /usr/lib/www/page-functions.awk -e '
 BEGIN {prevNode=0;c=1;count=0;rtq=0;rq=0;tq=0}
 {
	if(match($0,"^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]"))
	{
		node=getnode($1)
		if(prevNode!=node) {if(c==1)c=2;else c=1;}
 		printf("<tr class=\"colortoggle%d\"><td>%s</td><td><a href=\"http://%s/\">%s</a></td><td>%s</td><td>%s</td><td class=\"quality_%s\">%s</td><td>%s</td><td>%s</td></tr>\n",c,node,$3,$3,color_interface($2),$1,$4,$4,$5,$6);
		count=count+1;
		rtq=rtq+$4;
		rq=rq+$5;
		tq=tq+$6;
		prevNode=node;
	}
 }
 END {if(count){rtq=int(rtq/count);rq=int(rq/count);tq=int(tq/count); printf("<tr><td colspan=\"4\"><b>Anzahl:</b>&nbsp;%d</td><td class=\"quality_%s\"><b>%s</b></td><td class=\"quality_%s\"><b>%s</b></td><td class=\"quality_%s\"><b>%s</b></td></tr>", count, rtq, rtq, rq, rq, tq, tq);}}
'

cat<<EOM
</table><br />
<TABLE BORDER="0" cellspacing="0" CELLPADDING="1" WIDTH="100%">
<TR>
<TD class="quality"><div class="quality1"></div>perfekt</TD>
<TD class="quality"><div class="quality2"></div>ausreichend</TD>
<TD class="quality"><div class="quality3"></div>schlecht</TD>
<TD class="quality"><div class="quality4"></div>unbenutzbar</TD></TR>
</TABLE>
</fieldset>
<br/>
<fieldset class="bubble">
<legend>Gateways</legend>
<table>
<tr><th>Pr&auml;f.</th><th>Aktiv</th><th>Community</th><th>Statistik</th><th>Knoten-Nr.</th><th>IP-Adresse</th><th>Best Next Hop</th><th>BRC</th><th></th></tr>
EOM

export preferred="$(uci -q get ddmesh.bmxd.preferred_gateway | sed -n '/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$/p' )"
/usr/bin/bmxd -c --gateways | awk -f /usr/lib/www/page-functions.awk -e '
 BEGIN {c=1;count=0;brc=0}
 {
	if(match($0,"^[=> 	]*[0-9]+[.][0-9]+[.][0-9]+[.][0-9]"))
 	{
		img=match($0,"=>") ? "<img src=\"/images/yes12.png\">" : ""
		gsub("^=>","")
		rest=substr($0,index($0,$5))
		sub(",","",$3)
		sub(",","",$4)
		cimg=match($4,"1") ? "<img src=\"/images/yes12.png\">" : ""
		statfile="/var/statistic/gateway_usage"
		stat=0
		while((getline line < statfile) > 0)
		{
			split(line,a,":");
			if(a[1]==$1) { stat=a[2]; break; }
		}
		close(statfile)
		p="^" ENVIRON["preferred"] "$"
		pref = p && match($1,p) ? "<img src=\"/images/yes12.png\">" : ""
 		printf("<tr class=\"colortoggle%d\"><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td><a href=\"http://%s/\">%s</a></td><td>%s</td><td class=\"quality_%s\">%s</td><td>%s</td></tr>\n",c,pref,img,cimg,stat,getnode($1),$1,$1,$2,$3,$3,rest);
		if(c==1)c=2;else c=1;
		count=count+1;
		brc=brc+$3
	}
 }
 END {if(count){brc=int(brc/count); printf("<tr><td colspan=\"7\"><b>Anzahl:</b>&nbsp;%d</td><td class=\"quality_%s\"><b>%s</b></td><td></td></tr>", count, brc, brc);}}
'

cat<<EOM
</table>
</fieldset>
<br/>
<fieldset class="bubble">
<legend>Freifunk-Knoten</legend>
<table>
<tr><th>Knoten-Nr.</th><th>IP-Adresse</th><th>BRC</th><th>via Routing-Interface</th><th>via Router</th></tr>
EOM

/usr/bin/bmxd -c --originators | awk -f /usr/lib/www/page-functions.awk -e '
 BEGIN {c=1;count=0;brc=0}
 {

	if(match($0,"^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]"))
	{
 		printf("<tr class=\"colortoggle%d\"><td>%s</td><td><a href=\"http://%s/\">%s</a></td><td class=\"quality_%s\">%s</td><td>%s</td><td>%s</td></tr>\n",c,getnode($1),$1,$1,$4,$4,color_interface($2),$3);
		if(c==1)c=2;else c=1;
		count=count+1;
		brc=brc+$4
	}
 }
 END {if(count){brc=int(brc/count); printf("<tr><td colspan=\"2\"><b>Anzahl:</b>&nbsp;%d</td><td class=\"quality_%s\"><b>%s</b></td><td></td><td></td></tr>", count, brc, brc);}}
'

cat<<EOM
</table><br />
<table border="0" cellspacing="0" cellpadding="1" width="100%">
<tr>
<td class="quality"><div class="quality1"></div>perfekt</td>
<td class="quality"><div class="quality2"></div>ausreichend</td>
<td class="quality"><div class="quality3"></div>schlecht</td>
<td class="quality"><div class="quality4"></div>unbenutzbar</td></tr>
</table>
</fieldset>
EOM

. /usr/lib/www/page-post.sh
