#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

#redirect to splash
if [ "$SERVER_PORT" = "81" -a "$ALLOW_PAGE" != "1" ];then
        export DOCUMENT_ROOT="/www/splash"
        "$DOCUMENT_ROOT"/index.cgi
        exit 0
fi

. /usr/lib/www/page-functions.sh
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)
eval $(/usr/lib/ddmesh/ddmesh-utils-wifi-info.sh)

# get model
eval $(cat /etc/board.json | jsonfilter -e model='@.model.id' -e model2='@.model.name')
export model="$(echo $model | sed 's#[ 	]*\(\1\)[ 	]*#\1#')"
export model2="$(echo $model2 | sed 's#[ 	]*\(\1\)[ 	]*#\1#')"


#check if access comes from disabled network and we have access to "Verwalten" enabled
in_ifname="$(ip ro get $REMOTE_ADDR | sed -n '1,2s#.*dev[ ]\+\([^ ]\+\).*#\1#p')"
enable_setup=1
test ! "$(uci get ddmesh.system.wansetup)" = "1" && test "$in_ifname" = "$(uci get network.wan.ifname)" && enable_setup=0
if [ "$(uci get ddmesh.system.meshsetup)" != "1" ]; then
	test "$in_ifname" = "$wifi_adhoc_ifname" && enable_setup=0
	test "$in_ifname" = "$wifi_mesh_ifname" && enable_setup=0
	test "$in_ifname" = "$wifi2_ifname" && enable_setup=0
	test "${in_ifname%%[_0-9]*}" = "tbb" && enable_setup=0
	test "$in_ifname" = "$tbb_ifname" && enable_setup=0
fi

echo "Status: 200 OK"
echo "Content-Type: text/html; charset=utf-8"
echo ""

#check if user wants to access any page in admin
#check if we are in "Verwalten"
test "$URI_PATH" = "/www/admin" && test "$enable_setup" = "0" && {
cat<<EOM
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
<meta content="text/html; charset=UTF-8" http-equiv="Content-Type">
</head>
<body>Zugriff &uuml;ber aktuelles Netzwerk-Interface wurde in den Einstellungen verboten</pre></body></html>
EOM
exit
}

cat<<EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
	$SPLASH_BASE
	<title>$_ddmesh_node [$in_ifname] - $TITLE</title>
	<meta content="text/html; charset=UTF-8" http-equiv="Content-Type">
	<meta content="no-cache" http-equiv="cache-control">
	<meta http-equiv="expires" content="0">
	<meta name="viewport" content="width=device-width" />
	<meta name="author" content="Stephan Enderlein">
	<meta name="robots" content="noindex">
	<link href="/css/ff.css?random=${RANDOM}" rel="StyleSheet" TYPE="text/css">
	<link rel="shortcut icon" href="/images/favicon.ico">
	<script type="text/javascript" src="/js/jquery.js"></script>
	<script type="text/javascript" src="/js/help.js"></script>
	<script type="text/javascript" src="/js/grid.js"></script>
EOF

test "$URI_PATH" = "/www/admin" && {
	echo '<script type="text/javascript" src="/admin/js/admin.js?random=${RANDOM}"></script>'
}

cat<<EOF
</head>

<body>
<table border="0" cellpadding="0" cellspacing="0" class="body">
<tr><td class="topmenu" colspan="5" height="18">
EOF

if [ -z "$NOMENU" ]; then
cat<<EOM
<img src="/images/home.png">
<a class="topmenu" href="/">Home</a>
<img alt="" height="10" hspace="2" src="/images/vertbar.gif" width="1">
EOM

	if [ "$enable_setup" = "1" ]; then
cat <<EOM
<img src="/images/process.png">
<a class="topmenu" href="https://$HTTP_HOST/admin/index.cgi">Verwalten</a>
<img alt="" height="10" hspace="2" src="/images/vertbar.gif" width="1">
EOM
	fi

cat<<EOM
<a class="topmenu" href="http://$FFDD/">Freifunk-Dresden</a>
<img alt="" height="10" hspace="2" src="/images/vertbar.gif" width="1">
<a class="topmenu" href="http://www.freifunk.net/">Freifunk.net</a>
EOM

else

cat<<EOM
<a class="topmenu" href="http://$FFDD/">Freifunk-Dresden</a>
EOM

fi

if [ "$SERVER_PORT" = "443" ]; then
	lockimg="/images/green-lock-icon.png"
else
	lockimg="/images/red-unlock-icon.png"
fi

COMMUNITY="Freifunk $(uci get ddmesh.system.community | sed 's#[ ]#\&nbsp;#g' )"
NETID="$(uci -q get ddmesh.system.mesh_network_id)"
cat<<EOM
</TD></TR>
<TR><TD COLSPAN="5">
 <TABLE WIDTH="100%" BORDER="0" CELLPADDING="0" CELLSPACING="0">
  <TR>
  <TD width="40" HEIGHT="33" ><img src="$lockimg"></TD>
  <TD HEIGHT="33" style="vertical-align: middle;"><font size="5"><b>$COMMUNITY</b>&nbsp;$_ddmesh_node</font><font size="4">&nbsp;&nbsp;(Network ID: $NETID)</font>
EOM
test "$URI_PATH" = "/www/admin" && check_passwd && {
	echo "<font size="+1" color="red"><span class="blink">!!! BITTE Password setzen !!!</span</font>"
}
cat<<EOM
  </td>
  <TD HEIGHT="33" WIDTH="150" valign="bottom"><IMG ALT="" BORDER="0" HEIGHT="33" SRC="/images/ff-logo-1r.gif" WIDTH="150"></TD></tr>
 </TABLE></TD></TR>
 <tr><td COLSPAN="5">
  <table class="navibar" width="100%" CELLPADDING="0" CELLSPACING="0">
  <tr>
  <TD COLSPAN="4" HEIGHT="19" class="infobar" >Model: <span class="infobarvalue">$model2</span>, Version:<span class="infobarvalue">$(cat /etc/version)</span></TD>
  <TD HEIGHT="19" WIDTH="150"><IMG ALT="" BORDER="0" HEIGHT="19" SRC="/images/ff-logo-2.gif" WIDTH="150"></TD></TR>
  </table></td></tr>
 <TR><TD class="ie_color" HEIGHT="100%" VALIGN="top">
     <table  BORDER="0" CELLPADDING="0" CELLSPACING="0" HEIGHT="100%" style="table-layout: inherit">
       <tr><TD class="ie_white" HEIGHT="5"  VALIGN="top" ></td></tr>
       <tr><TD class="navi"  VALIGN="top" >
           <table VALIGN="top" border="0">
EOM

if [ -z "$NOMENU" ]; then
	for inc in $URI_PATH/[0-9][0-9]-* ; do
#call?
		if [ "${inc#*.}" = "sh" ]; then
			/bin/sh $inc
		else
			cat $inc;
		fi
	done
fi

cat<<EOF
			</table>
		</td></tr>
	</table>
</td>
<td width="5">&nbsp;</td>
<td valign="top" style="min-width:300px; width:100%;">
	<table height="100%" border="0" cellpadding="0" cellspacing="0" width="100%">
		<tr><td height="5" valign="top" width="100%"></td></tr>
		<tr><td valign="top" height="100%" width="100%">
<!-- page-pre -->
EOF
