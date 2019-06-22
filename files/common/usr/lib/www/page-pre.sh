#!/bin/sh

#redirect to splash
if [ "$SERVER_PORT" = "81" -a "$ALLOW_PAGE" != "1" ];then
        export DOCUMENT_ROOT="/www/splash"
        $DOCUMENT_ROOT/index.cgi
        exit 0
fi

. /usr/lib/www/page-functions.sh
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh all)

device_model="$(cat /var/sysinfo/model 2>/dev/null | sed 's#[ ]\+$##')"
test -z "$device_model" && device_model="$(cat /proc/cpuinfo | grep 'model name' | cut -d':' -f2)"
export device_model

#check if access comes from disabled network and we have access to "Verwalten" enabled
in_ifname="$(ip ro get $REMOTE_ADDR | sed -n '1,2s#.*dev[ ]\+\([^ ]\+\).*#\1#p')"
enable_setup=1
test ! "$(uci get ddmesh.system.wansetup)" = "1" && test "$in_ifname" = "$(uci get network.wan.ifname)" && enable_setup=0
if [ "$(uci get ddmesh.system.meshsetup)" != "1" ]; then
	test "$in_ifname" = "$wifi_ifname" && enable_setup=0
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
	<title>$in_ifname: $_ddmesh_hostname.$_ddmesh_domain - $TITLE</title>
	<meta content="text/html; charset=UTF-8" http-equiv="Content-Type">
	<meta content="no-cache" http-equiv="cache-control">
	<meta http-equiv="expires" content="0">
	<meta name="viewport" content="width=device-width" />
	<meta name="author" content="Stephan Enderlein">
	<meta name="robots" content="noindex">
	<link href="/css/ff.css" rel="StyleSheet" TYPE="text/css">
	<link rel="shortcut icon" href="/images/favicon.ico">
	<script type="text/javascript" src="/js/jquery.js"></script>
	<script type="text/javascript" src="/js/help.js"></script>
	<script type="text/javascript" src="/js/grid.js"></script>
EOF

test "$URI_PATH" = "/www/admin" && {
	echo '<script type="text/javascript" src="/admin/js/admin.js"></script>'
}

cat<<EOF
</head>

<body>
<table border="0" cellpadding="0" cellspacing="0" class="body">
<tr><td class="navihead" colspan="5" height="18">
EOF

if [ -z "$NOMENU" ]; then
	cat<<EOM
<span class="color"><a class="color" href="/"><img class="icon" src="/images/home.png">Home</a></span>
<img alt="" height="10" hspace="2" src="/images/vertbar.gif" width="1">
EOM

	if [ "$enable_setup" = "1" ]; then
		cat <<EOM
<span class="color"><a class="color" href="https://$HTTP_HOST/admin/index.cgi"><img class="icon" src="/images/process.png">Verwalten</a></span>
<img alt="" height="10" hspace="2" src="/images/vertbar.gif" width="1">
EOM
	fi

	cat<<EOM
<span class="color"><a class="color" href="http://$FFDD/">Freifunk-Dresden</a></span>
<img alt="" height="10" hspace="2" src="/images/vertbar.gif" width="1">
<span class="color"><a class="color" href="http://www.freifunk.net/">Freifunk.net</a></span>
EOM

else

	cat<<EOM
<span class="color"><a class="color" href="http://$FFDD/">Freifunk-Dresden</a></span>
EOM

fi

if [ "$SERVER_PORT" = "443" ]; then
	lockimg="/images/green-lock-icon.png"
else
	lockimg="/images/red-unlock-icon.png"
fi

COMMUNITY="$(uci get ddmesh.system.community | sed 's#[ ]#\&nbsp;#g' )"
cat<<EOM
</TD></TR>
<TR><TD COLSPAN="5">
 <TABLE WIDTH="100%" BORDER="0" CELLPADDING="0" CELLSPACING="0">
  <TR>
  <TD width="40" HEIGHT="33" ><img src="$lockimg"></TD>
  <TD HEIGHT="33" style="vertical-align: middle;"><font size="5"><b>$COMMUNITY</b>&nbsp;$_ddmesh_node</font>
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
  <TD COLSPAN="4" HEIGHT="19" class="infobar" >Model: <span class="infobarvalue">$device_model</span>, Version:<span class="infobarvalue">$(cat /etc/version)</span></TD>
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

