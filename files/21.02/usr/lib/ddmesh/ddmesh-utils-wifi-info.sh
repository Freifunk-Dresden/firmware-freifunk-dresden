#!/bin/sh

prefix="wifi_status"
radio2g_up=""
radio2g_phy=""
radio2g_config_index=""
radio2g_airtime=""
radio5g_up=""
radio5g_phy=""
radio5g_config_index=""
radio5g_airtime=""

# gets wifi dev
# returns RAW airtime: "$ACT,$BUS,$REC,$TRA"
airtime()
{
 dev=$1

 TEMP=$(iw dev $dev survey dump | grep -e "in use" -A6)

 let ACT=$(echo "$TEMP" | grep active | head -n 1 | grep -o '[0-9]*')+1
 let BUS=$(echo "$TEMP" | grep busy | head -n 1 | grep -o '[0-9]*')+0
 let REC=$(echo "$TEMP" | grep receive | head -n 1 | grep -o '[0-9]*')+0
 let TRA=$(echo "$TEMP" | grep transmit | head -n 1 | grep -o '[0-9]*')+0
 echo "$ACT,$BUS,$REC,$TRA"
}

# get phyX name for each wifi radio
for idx in 0 1
do
	dev_path=$(uci -q get wireless.@wifi-device[$idx].path)
	[ -z "$dev_path" ] && break

	phy=$(ls /sys/devices/$dev_path/ieee80211/)
	dev=$(ls /sys/devices/$dev_path/net/ | sed -n '1p')

	unset freq2 
	unset freq5

	# check for channel (one radio might support 2.4 and 5GHz)
	# prefer 2g
	freq2="$(iwinfo $phy freqlist | sed -n 's#[ *]*\([0-9]\).*$#\1#;/^2/{1p}')"
	freq5="$(iwinfo $phy freqlist | sed -n 's#[ *]*\([0-9]\).*$#\1#;/^5/{1p}')"

	#echo "[$freq2:$freq5]"

	if [ "$freq2" = "2" ]; then
		radio2g_up=1
		radio2g_phy=$phy
		radio2g_config_index=$idx
		radio2g_airtime=$(airtime $dev)
	elif [ "$freq5" = "5" ]; then
		radio5g_up=1
		radio5g_phy=$phy
		radio5g_config_index=$idx
		radio5g_airtime=$(airtime $dev)
	fi

done

echo export $prefix"_radio2g_up"="$radio2g_up"
echo export $prefix"_radio2g_phy"="$radio2g_phy"
echo export $prefix"_radio2g_config_index"="$radio2g_config_index"
echo export $prefix"_radio2g_airtime"="$radio2g_airtime"
echo export $prefix"_radio5g_up"="$radio5g_up"
echo export $prefix"_radio5g_phy"="$radio5g_phy"
echo export $prefix"_radio5g_config_index"="$radio5g_config_index"
echo export $prefix"_radio5g_airtime"="$radio5g_airtime"

