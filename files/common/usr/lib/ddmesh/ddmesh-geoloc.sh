#!/bin/sh

# ddmesh-geoloc.sh [scan]
# scan - only scan for access points

OUTPUT=/tmp/geoloc.json.tmp
FINAL_OUTPUT=/tmp/geoloc.json

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi)


cat<<EOM >$OUTPUT
{
  "considerIp": "false",
  "wifiAccessPoints": [
$(iwinfo $net_ifname scan | awk '
/^Cell/{
        f[nf=1]=$0;
        while(getline && $0 != "") {f[++nf]=$0}

        sig=0
        mac=""
        for(i=1;i<nf;i++)
        {
#if(i==1)print f[1]
                split(f[i],a)
                if(match(f[i],/Signal/)){ sig=a[2]}
                if(match(f[i],/Address/)){ mac=a[5]}
        }

	if(sig > -100)
	{
        	print "{\"macAddress\":\""mac"\", \"signalStrength\":"sig",\"signalToNoiseRatio\":0},"
	}
}
 ' | sed '$s#,[  ]*$##')
  ]
}
EOM

mv $OUTPUT $FINAL_OUTPUT


#request location
if [ "$1" != "scan" ]; then

	host=$(uci -q get credentials.geoloc.host)
	host=${host:=geoloc.ffdd}
	port=$(uci -q get credentials.geoloc.port)
	port=${port:=80}
	uri=$(uci -q get credentials.geoloc.uri)
	uri=${uri:=/geoloc}

	SIZE=$(ls -l $FINAL_OUTPUT | awk '{print $5}')
	DATA="$(cat $FINAL_OUTPUT)"

cat<<EOM > $FINAL_OUTPUT.req
POST /geoloc HTTP/1.1
User-Agent: Wget/1.17.1 (linux-gnu)
Accept: */*
Accept-Encoding: identity
Host: api.main.freifunk-dresden.de
Connection: Keep-Alive
Content-Type: application/json
Content-Length: $SIZE

$DATA

EOM

	cat $FINAL_OUTPUT.req | nc $host $port | sed 's#\r##' | awk 'BEGIN{s=0} /^$/{ if(s==0){s=1; getline;getline}else{s=0}} {if(s)print $0}'

fi
