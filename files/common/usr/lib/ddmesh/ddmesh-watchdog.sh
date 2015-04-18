#!/bin/ash

#check wifi: read country, try to set reg, verify reg

TAG=watchdog

current_country="$(iw reg get | sed -n 's#.* \(..\):.*#\1#p')"
config_country="$(uci get wireless.radio0.country)"
logger -t $TAG "wifi: country $current_country"

if [ ! "$current_country" = "$config_country" ]; then
	logger -t $TAG "wifi: ERROR - country mismatch '$current_country' != '$config_country'"
	iw reg set "$config_country"

	#verify
	current_country="$(iw reg get | sed -n 's#.* \(..\):.*#\1#p')"
	if [ ! "$current_country" = "$config_country" ]; then
		logger -t $TAG "wifi: ERROR - rebooting router"
		sleep 10
		reboot
	fi
fi

