#!/bin/sh
. /usr/lib/www/page-functions.sh

#Redirect (change url) to router if not already there
#HTTP_HOST will set to $SERVER_ADDR:$SERVER_PORT
#Android needs dnsmasq to return public ip, to popup browser

TARGET="hotspot"
HTTP_HOST=$(echo $HTTP_HOST | tr '[A-Z]' '[a-z]')

#add support for windows phone 8 (www.msftncsi.com/ncsi.txt)
#redirect is ignored by windows phone 8
if [ "$REDIRECT" = "1" -a "$HTTP_HOST" != "$TARGET" -a "$REQUEST_URI" != "/ncsi.txt" -a "$HTTP_HOST" != "www.msftncsi.com" ];then
	echo "Status: 302 Found"
	echo "Location: http://$TARGET/?host=$HTTP_HOST&uri=$REQUEST_URI"
	echo "Content-Type: text/html; charset=utf-8"
	echo ""
	exit
else
	echo "Status: 200 OK"
	echo "Content-Type: text/html; charset=utf-8"
	echo ""
fi

LOGO_IMG="$(ls -1 /www/custom/logo.* | sed -n '1,1p')"
LOGO_IMG=${LOGO_IMG:-/www/images/logo-dresden.png}
LOGO_IMG=${LOGO_IMG/*www/}

cat<<EOM
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<HTML>
<HEAD>
$SPLASH_BASE
<TITLE>$in_ifname: $_ddmesh_hostname.$_ddmesh_domain - $TITLE</TITLE>
<meta CONTENT="text/html; charset=UTF-8" HTTP-EQUIV="Content-Type">
<meta CONTENT="no-cache" HTTP-EQUIV="cache-control">
<meta http-equiv="expires" content="0">
<meta name="viewport" content="width=device-width" />
<meta name="author" content="Stephan Enderlein">
<meta name="robots" content="noindex">
<link HREF="/css/ff.css" REL="StyleSheet" TYPE="text/css">
<link rel="shortcut icon" href="/images/favicon.ico">
<script type="text/javascript" src="/js/jquery.js"></script>
<script type="text/javascript" src="/js/ff.js"></script>
</HEAD>
<BODY>
<table border=0>
<tr><td class="navihead" height="10" colspan="5"></td></tr>
<tr><td><table border=0>
	<tr><td><img style="float:left;" src="$LOGO_IMG"></td>
	<td><table border=0>
	<tr><td class="top" height="50"><font size="5"><b>Knoten</b>&nbsp;$_ddmesh_node</font></td></tr>
	<tr><td>
	<div>
EOM
if [ -f /www/custom/custom-head.url ]; then
        url="$(cat /www/custom/custom-head.url | sed '1,1{s#[`$()]##}')"
        wget -O - "$url"
else
	cat /www/custom/custom-head.html
fi

cat<<EOM
	</div></td></tr>
	</table></td></tr>
	
	</table>
</td></tr>
<tr><td><table>
 	<tr><td height="100%">
	<div>
EOM
#show_set
