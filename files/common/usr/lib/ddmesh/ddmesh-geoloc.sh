#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

OUTPUT=/var/geoloc.json.tmp
FINAL_OUTPUT=/var/geoloc.json
SYSINFO_MOBILE_GEOLOC=/var/geoloc-mobile.json
SYSLOG_TAG="geoloc"

GEO_LAST=/var/geoloc-last
GEO_CURR=/var/geoloc-current
touch $GEO_CURR $GEO_LAST

# remove my own macs from scan
bssid="$(uci get credentials.wifi_2g.bssid)"
own_macs=$(iwinfo | awk '/Access Point/{printf("%s ", gensub(/.*Access Point: /,"",$0))} END{printf("'$bssid'")}')
# echo "one_macs:[$own_macs]"
# remove stored macs
user_macs=''
store_ignore_macs() {
 user_macs="$user_macs $1"
}
config_load ddmesh
config_list_foreach geoloc ignore_macs store_ignore_macs

export ignore_macs="$own_macs $user_macs"

scan()
{
  cat<<EOM >$OUTPUT
{
  "considerIp": "false",
  "wifiAccessPoints": [
$(iwinfo wifi2ap scan | awk '
BEGIN{
	split(ENVIRON["ignore_macs"],ignore_macs);
}
/^Cell/{
        f[nf=1]=$0;
        while(getline && $0 != "") {f[++nf]=$0}

        sig=0
        mac=""
        for(i=1;i<nf;i++)
        {
                split(f[i],a)
                if(match(f[i],/Signal/)){ sig=a[2]}
                if(match(f[i],/Address/)){ mac=a[5]}
                if(match(f[i],/ESSID/)){ essid=a[2]}
        }

	# ignore hotspots: Freifunk+LTE router with hidden ssid
	if(match(essid,/Freifunk/)) { continue; }
	if(essid == "unknown") { continue; }

	found=0
	for(m in ignore_macs)
	{
		a=tolower(ignore_macs[m])
		b=tolower(mac)
		if(a==b) {found=1; break}
	}

	if(found == 0 && sig > -100)
	{
        	print "{\"macAddress\":\""mac"\", \"signalStrength\":"sig",\"signalToNoiseRatio\":0},"
	}
}
 ' | sed '$s#,[  ]*$##' )
  ]
}
EOM

mv $OUTPUT $FINAL_OUTPUT
}

check_update_allowed()
{

 # compare against last scan
 > $GEO_CURR
 IFS='
'
 for r in $(cat $FINAL_OUTPUT | jsonfilter -e '@.wifiAccessPoints[*]')
 do
	eval $(echo "$r" | jsonfilter -e mac='@.macAddress' -e signal='@.signalStrength')
	echo "$mac $signal" >> $GEO_CURR
#	echo "$mac $signal"
 done

 # check if new list still contains mac from old list
 awk '
	FILENAME==ARGV[1]{ a[$1] = $2 }
	FILENAME==ARGV[2]{ b[$1] = $2 }
	{
		# create assosiated array and count macs
		# if count is 2 then the corresponding mac was seen
		mac[$1] = mac[$1] + 1
	}
	END {
		# google needs at least 2 AP
		if(length(b) <= 1) exit 1

		for(m in mac)
		{
			if ( mac[m] > 1 ) { exit 1;}
		}
		exit 0
	}
 ' $GEO_LAST $GEO_CURR
 # forward back $? to caller
}

send_request()
{
# $1 - 	store: writes to config
#	sysinfo: stores json in tempfile

	host=$(uci -q get credentials.geoloc.host)
	host=${host:=geoloc.ffdd}
	port=$(uci -q get credentials.geoloc.port)
	port=${port:=80}
	uri=$(uci -q get credentials.geoloc.uri)
	uri=${uri:=/geoloc}

	SIZE=$(ls -l $FINAL_OUTPUT | awk '{print $5}')
	DATA="$(cat $FINAL_OUTPUT)"

# append '\r' before newline. required by HTTP standard
cat<<EOM | sed 's#$#\r#' > $FINAL_OUTPUT.req
POST /geoloc HTTP/1.1
User-Agent: Wget/1.17.1 (linux-gnu)
Accept: */*
Accept-Encoding: identity
Host: api.freifunk-dresden.de
Connection: Keep-Alive
Content-Type: application/json
Content-Length: $SIZE

EOM
	# send data
	echo "$DATA" >> $FINAL_OUTPUT.req

	j_response=$(cat $FINAL_OUTPUT.req | nc $host $port | sed 's#\r##' | awk 'BEGIN{s=0} /^$/{ if(s==0){s=1; getline;getline}else{s=0}} {if(s)print $0}')

	# check for valid answer
	eval $(echo "$j_response" | jsonfilter \
			-e j_lat='@.location.lat' \
			-e j_lng='@.location.lng' )

	if [ -n "$j_response" -a -n "$j_lat" -a -n "$j_lng" ]; then

		logger -t $SYSLOG_TAG "request: $j_response"
		echo "$j_response"
		if [ "$1" = "sysinfo" ]; then
			# when we got a connection/response then save wifi scan
			mv $GEO_CURR $GEO_LAST
			echo "$j_response" > $SYSINFO_MOBILE_GEOLOC
		fi

		if [ "$1" = "store" ]; then
			# when we got a connection/response then save wifi scan
			mv $GEO_CURR $GEO_LAST
			echo "$j_response" > $SYSINFO_MOBILE_GEOLOC

			uci set ddmesh.gps.latitude="$j_lat"
			uci set ddmesh.gps.longitude="$j_lng"
			uci set ddmesh.gps.altitude="0"
			uci_commit.sh
			logger -s -t $SYSLOG_TAG "geoloc saved"
		fi
	else
		logger -s -t $SYSLOG_TAG "Error: no response"
	fi
}

case "$1" in
	scan)
		scan
		cat $FINAL_OUTPUT
		;;
	request-only)
		scan
		send_request
		;;
	update-config)
		scan
		send_request store
		;;
	update-sysinfo)
		scan
		# forward arg
		send_request sysinfo
		;;
	mobile)
		# only request and store temporarily
		while true; do
			scan
			check_update_allowed && send_request sysinfo
			sleep 60
		done
		;;
	*)
	echo "ddmesh-geoloc.sh [scan | request-only | update-config | update-sysinfo | mobile]"
	echo " scan           - only scan for access points and print them"
	echo " request-only   - one-time request: send request, print new values"
	echo " update-sysinfo - one-time request: send request, update sysinfo"
	echo " update-config  - one-time request: send request, store new coordinates in config"
	echo " mobile         - periodically update mobile geoloc"
	;;
esac
