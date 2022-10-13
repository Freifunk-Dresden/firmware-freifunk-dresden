#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

prefix="wifi_status"
radio2g_up=""
radio2g_phy=""
radio2g_dev="wifi2ap"	# use interface that is always present
radio2g_config_index=""
radio2g_airtime=""

radio5g_up=""
radio5g_phy=""
radio5g_dev="wifi5ap"	# use interface that is always present
radio5g_config_index=""
radio5g_airtime=""

# gets wifi dev
# returns RAW airtime: "$ACT,$BUS,$REC,$TRA"
airtime()
{
 dev=$1

 TEMP=$(iw dev $dev survey dump 2>/dev/null | grep -e "in use" -A6)
 if [ -n "$TEMP" ]; then
		let ACT=$(echo "$TEMP" | grep active | head -n 1 | grep -o '[0-9]*')+1
		let BUS=$(echo "$TEMP" | grep busy | head -n 1 | grep -o '[0-9]*')+0
		let REC=$(echo "$TEMP" | grep receive | head -n 1 | grep -o '[0-9]*')+0
		let TRA=$(echo "$TEMP" | grep transmit | head -n 1 | grep -o '[0-9]*')+0
 fi
 echo "$ACT,$BUS,$REC,$TRA"
}

# assume maximal 2 phy.
# Either we have two hardware chips with one phyX each
# or one hardware chip with two phyX
idx=0
if [ "$1" == "store" ]; then
	# get phyX name for each wifi radio
	while [ $idx -le 1 ]
	do
#echo idx=$idx
		dev_path=$(uci -q get wireless.@wifi-device[$idx].path)
		[ -z "$dev_path" ] && break

		devpath="/sys/devices/${dev_path}"
		# check if path exists. if not prepend "platform". Somehow openwrt21 does not
		# add "platform" for ramips boards
		if [ ! -d "${devpath}" ]; then
			devpath="/sys/devices/platform/${dev_path}"
		fi
		[ -d "${devpath}" ] || break;

		# devices with one wlan chip but with more phy
		phy_count=0
		for phy in $(ls ${devpath}/ieee80211/)
		do
#echo idx2=$idx
			# can not rely on dev after firmware update, because openwrt uses old wireless config
			# with old interface names (if renamed).
			# ${devpath}/net/ | sed -n '1p'

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
			elif [ "$freq5" = "5" ]; then
				radio5g_up=1
				radio5g_phy=$phy
				radio5g_config_index=$idx
			fi
			phy_count=$(( phy_count + 1 ))
			idx=$(( idx + 1 ))
		done

		# continue with next device if no phy was found
		[ $phy_count -eq 0 ] && idx=$(( idx + 1 ))

	done

 # store in /etc/wireless for faster access (/dev/null to suppress output)
 test -z "$(uci -q get wireless.ddmesh)" && uci -q add wireless ddmesh >/dev/null
 uci -q rename wireless.@ddmesh[-1]='ddmesh'
 uci -q set wireless.ddmesh.radio2g_up="$radio2g_up"
 uci -q set wireless.ddmesh.radio2g_phy="$radio2g_phy"
 uci -q set wireless.ddmesh.radio2g_config_index="$radio2g_config_index"

 uci -q set wireless.ddmesh.radio5g_up="$radio5g_up"
 uci -q set wireless.ddmesh.radio5g_phy="$radio5g_phy"
 uci -q set wireless.ddmesh.radio5g_config_index="$radio5g_config_index"
 uci -q commit
fi

_radio2g_up="$(uci -q get wireless.ddmesh.radio2g_up)"
echo export $prefix"_radio2g_up"="$_radio2g_up"
if [ "$_radio2g_up" = "1" ]; then
	echo export $prefix"_radio2g_phy"="$(uci -q get wireless.ddmesh.radio2g_phy)"
	echo export $prefix"_radio2g_config_index"="$(uci -q get wireless.ddmesh.radio2g_config_index)"
	echo export $prefix"_radio2g_airtime"="$(airtime ${radio2g_dev})"
fi

_radio5g_up="$(uci -q get wireless.ddmesh.radio5g_up)"
echo export $prefix"_radio5g_up"="$_radio5g_up"
if [ "$_radio5g_up" = "1" ]; then
	echo export $prefix"_radio5g_phy"="$(uci -q get wireless.ddmesh.radio5g_phy)"
	echo export $prefix"_radio5g_config_index"="$(uci -q get wireless.ddmesh.radio5g_config_index)"
	echo export $prefix"_radio5g_airtime"="$(airtime ${radio5g_dev})"
fi
