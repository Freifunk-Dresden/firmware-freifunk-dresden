#!/bin/sh

# only display if arg1 is not "no-html-header"
test -z $1 && {
echo 'Content-type: text/plain txt'
echo ''
}

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi_adhoc)
WIDTH=150

eval "$(cat /etc/openwrt_release)"
if [ ! "$DISTRIB_TARGET" = "brcm-2.4" ]; then

cat<<EOM
<table>
 <TR><TH width="$WIDTH">SSID</TH><TH>Kanal</TH><TH>Ad-Hoc/Mesh</TH><TH>Offen</TH><TH>Signal</TH><TH>Signal (dBm)</TH><TH>Uptime</TH><TH>BSSID</TH></TR>
 <pre>
EOM

T=1
/usr/sbin/iw dev $net_ifname scan | sed 's#\\x00.*##' | sed -ne'
s#^BSS \(..:..:..:..:..:..\).*#wifi_bssid="\1";wifi_mode="managed";wifi_uptime="";wifi_essid="";wifi_signal="0";wifi_open="yes";#p
s#	TSF:[^(]*(\([^)]*\).*#wifi_uptime="\1";#p
s#	SSID: \(.*\)#wifi_essid="\1";#p
s#	WPA:.*#wifi_open="no";#p
s#	WPE:.*#wifi_open="no";#p
s#	RSN:.*#wifi_open="no";#p
s#	freq: \(.*\)#wifi_freq="\1";#p
s#	signal: -*\([^. ]*\).*#wifi_signal="\1";#p
s#	capability: IBSS.*#wifi_mode="ad-hoc";#p
}' | sed ':a;N;$!ba;s#\n##g;s#;wifi_bssid#\nwifi_bssid#g'  | while read line; do
	eval $line

	#clean essid
	wifi_essid_clean="$(echo $wifi_essid | sed 's#[$`]# #g')"

	#if essid hidden -> no info for encryption
	test -z "$wifi_essid" && wifi_open="no"

	#check if this is my own adhoc signal
	test $wifi_signal -eq 0 && continue

	gif=5
	test $wifi_signal -gt 50 && gif=4
	test $wifi_signal -gt 60 && gif=3
	test $wifi_signal -gt 70 && gif=2
	test $wifi_signal -gt 80 && gif=1
	test $wifi_signal -gt 89 && gif=0

	#convert freq to channel
	case "$wifi_freq" in
		"2412") wifi_channel=1 ;;
		"2417") wifi_channel=2 ;;
		"2422") wifi_channel=3 ;;
		"2427") wifi_channel=4 ;;
		"2432") wifi_channel=5 ;;
		"2437") wifi_channel=6 ;;
		"2442") wifi_channel=7 ;;
		"2447") wifi_channel=8 ;;
		"2452") wifi_channel=9 ;;
		"2457") wifi_channel=10 ;;
		"2462") wifi_channel=11 ;;
		"2467") wifi_channel=12 ;;
		"2472") wifi_channel=13 ;;
		"2484") wifi_channel=14 ;;
		*) wifi_channel="unknown";;
	esac

	wifi_adhoc="no"
	test "$wifi_mode" = "ad-hoc" && wifi_adhoc="yes"
	style="vertical-align:middle;white-space: nowrap;"
	cat<<EOM
EOM
	class=colortoggle$T
	# Mesh-Net
	A=$(echo "$wifi_bssid" | tr 'abcdef' 'ABCDEF')
	B=$(echo "$(uci get wireless.@wifi-iface[0].bssid)" | tr 'abcdef' 'ABCDEF')
	if [ "$A" = "$B" ]; then
		style="$style font-weight:bold;"
		class="selected"
	fi
	# Freifunk (ap) check that community name is in essid
	A="$(uci get ddmesh.system.community)"
	B="${wifi_essid/$A/}"
	if [ "$wifi_essid" != "$B" ]; then
		style="$style font-weight:bold;"
		class="selected_ap"
	fi

	cat<<EOM
<TR class="$class" >
<TD style="$style" width="$WIDTH">$wifi_essid_clean</TD>
<TD style="$style">$wifi_channel</TD>
<TD style="$style"><IMG SRC="/images/$wifi_adhoc.png" ALT="$wifi_adhoc" TITLE="Ad-Hoc/Mesh mode"></TD>
<TD style="$style"><IMG SRC="/images/$wifi_open.png" ALT="$wifi_open"></TD>
<TD style="$style"><IMG SRC="/images/power$gif.png" ALT="P=$gif" TITLE="Signal: $wifi_signal dBm, Noise: $wifi_noise dBm"></TD>
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

else #BROADCOM

cat<<EOM
<table>
 <TR><TH width="$WIDTH">SSID</TH><TH>Kanal</TH><TH>Ad-Hoc/Mesh</TH><TH>Open</TH><TH>Signal</TH><TD>RSSI&nbsp;(dBm)</TD><TD>Noise&nbsp;(dBm)</TD><TH>BSSID</TH></TR>
EOM

T=1
/usr/sbin/iwlist $net_ifname scanning | sed -ne'
/^$/d
s/^[ 	]*//
s/Cell.*Address:[ 	]*\([^ 	]*\).*/wifi_bssid="\1";/p
s/ESSID:[ 	]*"\([^"]*\)".*/wifi_essid="\1";/p
s/Mode:[ 	]*\([^ 	]*\).*/wifi_mode="\1";/p
s/Channel:[ 	]*\([^ 	]*\).*/wifi_channel="\1";/p
s/Quality:\([^ 	]\+\)[ 	]*Signal level:\([^ 	]\+\)[ 	]\+dBm[ 	]\+Noise level:\([^ 	]\+\)[ 	]\+dBm.*/wifi_quality="\1";wifi_signal="\2";wifi_noise="\3";/p
s/Encryption key:off.*/wifi_open="yes";/p
s/Encryption key:on.*/wifi_open="no";/p
' | sed -n '
/wifi_open/{H;g;s#\n##g;p;s#.*##;h;}
H
' | while read line; do
	eval $line
	gif=${wifi_quality%/*}

	test $gif -gt 5 && gif=5
	test $gif -lt 0 && gif=0
	wifi_adhoc="no"
	test "$wifi_mode" = "Ad-Hoc" && wifi_adhoc="yes"
	style="vertical-align:middle;white-space: nowrap;"
	cat<<EOM
<TR class="colortoggle$T" >
EOM
	A=$(echo "$wifi_bssid" | tr 'abcdef' 'ABCDEF')
	B=$(echo "$(uci get wireless.@wifi-iface[0].bssid)" | tr 'abcdef' 'ABCDEF')
	if [ "$A" = "$B" ]; then
		style="$style font-weight:bold;"
	fi
	cat<<EOM
<TD style="$style" width="$WIDTH">$wifi_essid</TD>
<TD style="$style">$wifi_channel</TD>
<TD style="$style"><IMG SRC="/images/$wifi_adhoc.png" ALT="$wifi_adhoc" TITLE="Ad-Hoc/Mesh mode"></TD>
<TD style="$style"><IMG SRC="/images/$wifi_open.png" ALT="$wifi_open" TITLE="offen"></TD>
<TD style="$style"><IMG SRC="/images/power$gif.png" ALT="P=$gif" TITLE="Signal: $wifi_signal dBm, Noise: $wifi_noise dBm"></TD>
<TD style="$style">$wifi_signal</TD>
<TD style="$style">$wifi_noise</TD>
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

fi #BROADCOM

