#!/bin/sh

prefix="wifi_status"
radio2g_up=""
radio2g_phy=""
radio2g_config_index=""
radio5g_up=""
radio5g_phy=""
radio5g_config_index=""

# get phyX name for each wifi radio
for idx in 0 1
do
	dev_path=$(uci -q get wireless.@wifi-device[$idx].path)
	[ -z "$dev_path" ] && break

	phy=$(ls /sys/devices/$dev_path/ieee80211/)

	unset ch11
	unset ch36

	# check for channel (one radio might support 2.4 and 5GHz)
	# Use ch 11 which is present for all countries. (nanostation has no 12+13 during boot)
	ch11="$(iwinfo $phy freqlist | sed -n 's#.*Channel \([0-9]\+\).*#\1#;/^11$/p')"
	ch36="$(iwinfo $phy freqlist | sed -n 's#.*Channel \([0-9]\+\).*#\1#;/^36$/p')"

	if [ -n "$ch11" ]; then
		radio2g_up=1
		radio2g_phy=$phy
		radio2g_config_index=$idx
	else
		radio5g_up=1
		radio5g_phy=$phy
		radio5g_config_index=$idx
	fi

done

echo export $prefix"_radio2g_up"="$radio2g_up"
echo export $prefix"_radio2g_phy"="$radio2g_phy"
echo export $prefix"_radio2g_config_index"="$radio2g_config_index"
echo export $prefix"_radio5g_up"="$radio5g_up"
echo export $prefix"_radio5g_phy"="$radio5g_phy"
echo export $prefix"_radio5g_config_index"="$radio5g_config_index"

