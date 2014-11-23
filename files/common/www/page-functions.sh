#!/bin/sh

#set vars for all included sites
eval $(/usr/bin/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
eval $(cat /etc/openwrt_release)
export FFDD="www.freifunk-dresden.de"

#parse language
#http://de.selfhtml.org/diverses/sprachenlaenderkuerzel.htm#uebersicht_iso_639_1
langbrowser="$(echo $HTTP_ACCEPT_LANGUAGE |sed 'y/[ABCDEFGHIJKLMNOPQRSTUVWXYZ]/[abcdefghijklmnopqrstuvwxyz/')"
case "$langbrowser" in
        de*) LANG="de" ;;
        en*) LANG="en" ;;
        *) LANG="en" ;;
esac
export LANG

show_set ()
{
echo "<pre>"
set
echo "</pre>"
}

#http server - query read/protection
process_query()
{
  if [ "$REQUEST_METHOD" = "GET" -a -n "$QUERY_STRING" -a "$HTTP_ALLOW_GET_REQUEST" != "1" ]; then
	logger -t "HTTP-Request:" "Deny HTTP Get Request"
	QUERY_STRING=""
	return
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
                if [ "$left" != "" ]; then eval $left=\"$right\";fi
        done
        unset IFS;
  fi
  unset i
  unset left
  unset right
}

#use lua to flush stdout after each line
flush ()
{
 lua -e 'for line in io.lines() do io.write(line,"<br />") io.flush() end'
}

notebox ()
{
  echo "<TABLE  BORDER="0" CLASS="note"><TR><TD>$1</TD></TR></TABLE><br/>"
}


URI_PATH=${1:-$DOCUMENT_ROOT}

export BMXD_DB_PATH=/var/lib/ddmesh/bmxd

#get gateway
export INET_GW=$(cat $BMXD_DB_PATH/gateways | grep '^[ 	]*[0-9]*[ 	]*=>' | sed 's#^[ 	]*[0-9]*[ 	]*[^0-9]\+\([0-9.]\+\).*#\1#')
test -z "$INET_GW" && INET_GW=$_ddmesh_ip
INET_GW="$INET_GW&nbsp;($(ddmesh-ipcalc.sh $INET_GW))"

process_query

