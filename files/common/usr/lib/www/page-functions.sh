#!/bin/sh

#set vars for all included sites
eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
eval $(cat /etc/openwrt_release)
export FFDD="www.freifunk-dresden.de"

#parse language
#http://de.selfhtml.org/diverses/sprachenlaenderkuerzel.htm#uebersicht_iso_639_1
langbrowser="$(echo $HTTP_ACCEPT_LANGUAGE |sed 'y/[ABCDEFGHIJKLMNOPQRSTUVWXYZ]/[abcdefghijklmnopqrstuvwxyz/')"
DEFAULT_LANG="de"
case "$langbrowser" in
        de*) LANG="de" ;;
        en*) LANG="en" ;;
        *) LANG="$DEFAULT_LANG" ;;
esac
export LANG

lang ()
{
 f=/usr/lib/www/lang/$LANG/$1
 if [ -f $f ]; then
	cat $f
 else
 	f=/usr/lib/www/lang/$DEFAULT_LANG/$1
	if [ -f $f ]; then
		cat $f
	else
		echo "[ERROR: missing translation]"
	fi
 fi
}

env()
{
echo "<pre>"
set
echo "</pre>"
}

#http server - query read/protection
process_query()
{
  if [ "$REQUEST_METHOD" = "GET" -a -n "$QUERY_STRING" -a "$HTTP_ALLOW_GET_REQUEST" != "1" ]; then
	logger -t "HTTP-Request:" "Deny HTTP Get Request [$REMOTE_HOST:$REQUEST_URI]"
	QUERY_STRING=""
	exit 0
  fi

  if [ "$REQUEST_METHOD" = "POST" ]; then
        QUERY_STRING="$(dd bs=1 count=$CONTENT_LENGTH 2>/dev/null)"
  fi

  #setup query variables
  if [ -n "$QUERY_STRING" ]; then
        IFS=\&
        for i in $QUERY_STRING
        do
                left=${i%%=*}; right=${i#*=}
                left=$(echo $left|sed 's#[^[:alnum:]]#_#g')
                if [ "$left" != "" ]; then eval export $left=\"$right\";fi
        done
        unset IFS;
  fi
  unset i
  unset left
  unset right
}

flush ()
{
	awk '{printf("%s<br>",$0); fflush();}'
}

notebox ()
{
  echo "<TABLE  BORDER="0" CLASS="note"><TR><TD>$1</TD></TR></TABLE><br/>"
}

check_passwd()
{
 if [ -n "$(cat /etc/shadow | grep '^root::0:')" ]; then
  return 0
 else
  return 1
 fi
}

URI_PATH=${1:-$DOCUMENT_ROOT}

export BMXD_DB_PATH=/var/lib/ddmesh/bmxd

#get gateway
export INET_GW_IP=$(cat $BMXD_DB_PATH/gateways | grep '^[ 	]*[0-9]*[ 	]*=>' | sed 's#^[ 	]*[0-9]*[ 	]*[^0-9]\+\([0-9.]\+\).*#\1#')
export INET_GW="local/none"
if [ -n "$INET_GW_IP" ]; then
	INET_GW="$INET_GW_IP&nbsp;($(/usr/lib/ddmesh/ddmesh-ipcalc.sh $INET_GW_IP))"
fi

process_query

