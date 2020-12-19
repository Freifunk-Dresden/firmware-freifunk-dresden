#!/bin/ash

# only display if arg1 is not "no-html-header"
test -z $1 && {
echo 'Content-type: text/plain txt'
echo ''
}

WIDTH=150


eval $(/usr/lib/ddmesh/ddmesh-utils-wifi-info.sh)



SCAN_RESULT=/tmp/wifi_scan

/usr/sbin/iw dev wifi2ap scan > $SCAN_RESULT
[ "$wifi_status_radio5g_up" = "1" ] && /usr/sbin/iw dev wifi5ap scan >> $SCAN_RESULT

json="{ \"stations\": [  $(cat $SCAN_RESULT | sed 's#\\x00.*##' | sed -ne' 
s#^BSS \(..:..:..:..:..:..\).*#wifi_bssid="\1";wifi_mode="managed";wifi_uptime="";wifi_essid="";wifi_meshid="";wifi_signal="0";wifi_open="yes";#p
s#	TSF:[^(]*(\([^)]*\).*#wifi_uptime="\1";#p
s#	SSID: \(.*\)#wifi_essid="\1";#p
s#	MESH ID: \(.*\)#wifi_meshid="\1";#p
s#	WPA:.*#wifi_open="no";#p
s#	WPE:.*#wifi_open="no";#p
s#	RSN:.*#wifi_open="no";#p
s#	freq: \(.*\)#wifi_freq="\1";#p
s#	signal: -*\([^. ]*\).*#wifi_signal="\1";#p
s#	capability: IBSS.*#wifi_mode="ad-hoc";#p
}' | sed ':a;N;$!ba;s#\n##g;s#;wifi_bssid#\nwifi_bssid#g'  | while read line; do
#echo "### $line ###" >>/tmp/weg
	eval $line

	#clean essid
	wifi_essid_clean="$(echo $wifi_essid | sed 's#[$`]# #g')"
	wifi_meshid_clean="$(echo $wifi_meshid | sed 's#[$`]# #g')"

	#if essid hidden -> no info for encryption
	test -z "$wifi_essid_clean" && wifi_open="no"

	# use mesh id if present
	if [ -z "$wifi_essid_clean" -a "$wifi_meshid_clean" ]; then
		wifi_essid_clean="$wifi_meshid_clean"
		wifi_mode="mesh"
	fi

	#check if this is my own adhoc signal
	test $wifi_signal -eq 0 && continue

	# calulate channel
	if [ "$wifi_freq" -lt 5000 ]; then
		wifi_channel=$(( ($wifi_freq-2412)/5 + 1 ))
	else
		wifi_channel=$(( ($wifi_freq-5180)/5 + 36 ))
	fi

	wifi_adhoc="no"
	test "$wifi_mode" = "ad-hoc" && wifi_adhoc="yes"
	test "$wifi_mode" = "mesh" && wifi_adhoc="yes"
	cat<<EOM
EOM

	type=""

	# Mesh-Net
	A="$(uci get ddmesh.network.essid_adhoc)"
	if [ "$wifi_essid_clean" = "$A" ]; then
		type="ffmesh"
	fi

	# check for meshid
	A="$(uci -q get credentials.network.wifi_mesh_id)"
	if [ "$wifi_essid_clean" = "$A" ]; then
		type="ffmesh"
	fi

	# Freifunk (ap) check that community name is in essid
	A="$(uci get ddmesh.system.community)"
	B="${wifi_essid_clean/$A/}"
	if [ "$wifi_essid_clean" != "$B" ]; then
		type="ffap"
	fi

	line="{\"type\": \"$type\", \"ssid\": \"$wifi_essid_clean\", \"channel\": \"$wifi_channel\","
	line="$line  \"open\": \"$wifi_open\", \"adhoc\": \"$wifi_adhoc\",\"signal\": \"$wifi_signal\","
	line="$line  \"uptime\": \"$wifi_uptime\", \"bssid\": \"$wifi_bssid\"},"

	# output line from subshell
	echo "$line"	
done ) ]}"

#echo "$json" >/tmp/wegj

cat<<EOM
<table>
 <TR><TH width="$WIDTH">SSID</TH><TH>Kanal</TH><TH>Ad-Hoc/Mesh</TH><TH>Offen</TH><TH>Signal</TH><TH>Signal (dBm)</TH><TH>Uptime</TH><TH>BSSID</TH></TR>
 <pre>
EOM

base_style="vertical-align:middle;white-space: nowrap;"

T=1
idx=0
while true
do

	line=$(echo "$json" | jsonfilter  -e "@.stations[$idx]")
	let "idx++"

	[ -z "$line" ] && break;

	eval $(echo "$line" | jsonfilter -e wifi_type='@.type' -e wifi_ssid='@.ssid' -e wifi_channel='@.channel' \
					 -e wifi_open='@.open' -e wifi_adhoc='@.adhoc' -e wifi_signal='@.signal' \
					 -e wifi_uptime='@.uptime' -e wifi_bssid='@.bssid')

	gif=5
	test $wifi_signal -gt 50 && gif=4
	test $wifi_signal -gt 60 && gif=3
	test $wifi_signal -gt 70 && gif=2
	test $wifi_signal -gt 80 && gif=1
	test $wifi_signal -gt 89 && gif=0


	case "$wifi_type" in
		ffmesh)
			style="$base_style font-weight:bold;"
			class="selected"
			;;
		ffap)
			style="$base_style font-weight:bold;"
			class="selected_ap"
			;;
		*)
			class=colortoggle$T
			style="$base_style"
			;;
	esac

cat<<EOM
<TR class="$class" >
<TD style="$style" width="$WIDTH">$wifi_ssid</TD>
<TD style="$style">$wifi_channel</TD>
<TD style="$style"><IMG SRC="/images/$wifi_adhoc.png" ALT="$wifi_adhoc" TITLE="Ad-Hoc/Mesh mode"></TD>
<TD style="$style"><IMG SRC="/images/$wifi_open.png" ALT="$wifi_open"></TD>
<TD style="$style"><IMG SRC="/images/power$gif.png" ALT="P=$gif" TITLE="Signal: $wifi_signal dBm"></TD>
<TD style="$style">- $wifi_signal</TD>
<TD style="$style">$wifi_uptime</TD>
<TD style="$style">$wifi_bssid</TD></tr>
EOM
	if [ $T -eq 1 ]; then
		T=2
	else
		T=1
	fi

done

cat<<EOM
</table>
EOM
