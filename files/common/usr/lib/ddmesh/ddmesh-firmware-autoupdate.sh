#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

# checks or runs an firmware update. downloads firmware
# arguments: <run | check>

TAG="AutoFirmwareUpdate"
FIRMWARE_FILE="/tmp/firmware.bin"
ERROR_FILE=/tmp/wget.error
REGISTER_FW_UPDATE_STATE_FILE="/var/state/node_autoupdate_allowed"

usage() {
	echo "$0 <run [nightly] | check | compare new old>"
}

if [ -z "$1" ]; then
	usage
	exit 1
fi

eval $(cat /etc/openwrt_release)

# download file info
FILE_INFO_JSON="$(/usr/lib/ddmesh/ddmesh-get-firmware-name.sh)"
error=$(echo $FILE_INFO_JSON | jsonfilter -e '@.error')
if [ -z "$FILE_INFO_JSON" -o -n "$error" ]; then
	logger -s -t "$TAG" "Error: failed to download file information"
	exit 1
fi

rm -f $ERROR_FILE

node_autoupdate_allowed="$(cat ${REGISTER_FW_UPDATE_STATE_FILE} 2>/dev/null)"
node_autoupdate_allowed=${node_autoupdate_allowed:=0}
cfg_autoupdate_enabled="$(uci get ddmesh.system.firmware_autoupdate)"
cfg_autoupdate_enabled=${cfg_autoupdate_enabled:=1}

#return 0 if new > cur
compare_versions() {
	new=$1
	cur=$2
	local IFS='.';
	set $new; a1=$1; a2=$2; a3=$3
	set $cur; b1=$1; b2=$2; b3=$3

	#compare major/middle/minor
	if [ "$a1" -gt "$b1" ]; then return 0; fi
	if [ "$a1" -eq "$b1" ]; then
		if [ "$a2" -gt "$b2" ]; then return 0; fi
		if [ "$a2" -eq "$b2" ]; then
			if [ "$a3" -gt "$b3" ]; then return 0; fi
		fi
	fi
	return 1
}

check_version() {
	firmware_release_version=$(echo $FILE_INFO_JSON | jsonfilter -e '@.firmware_version')
	firmware_current_version="$(cat /etc/version)"

	logger -s -t "$TAG" "curver: $firmware_current_version, latest version: $firmware_release_version"
	compare_versions $firmware_release_version $firmware_current_version && return 0
	return 1
}

download_firmware(){
	url=$(echo $FILE_INFO_JSON | jsonfilter -e '@.firmware_url')
	logger -s -t "$TAG" "Try downloading $url"
	wget -O $FIRMWARE_FILE "$url" 2>$ERROR_FILE || {
		logger -s -t "$TAG" "Error: $(cat $ERROR_FILE)"
		return 1
	}
	return 0
}


case "$1" in
	run)
		nightly=$2

		firmware_autoupdate_enabled=$(echo $FILE_INFO_JSON | jsonfilter -e '@.fileinfo.autoupdate')

		logger -s -t "$TAG" "Auto Update: Router enabled: $cfg_autoupdate_enabled; firmware enabled: $firmware_autoupdate_enabled; node autoupdate allowed: $node_autoupdate_allowed"
		[ "$node_autoupdate_allowed" = "1" -a "$cfg_autoupdate_enabled" = "1" -a "$firmware_autoupdate_enabled" = "1" ] || exit 1

		check_version || exit 1
		logger -s -t "$TAG" "new version available"

		download_firmware || exit 1
		logger -s -t "$TAG" "firmware downloaded successfully"

		server_md5sum=$(echo $FILE_INFO_JSON | jsonfilter -e '@.fileinfo.md5sum')
		file_md5sum=$(md5sum $FIRMWARE_FILE | cut -d' ' -f1)
		if [ -z "$server_md5sum" -o "$server_md5sum" != "$file_md5sum" ]; then
			logger -s -t "$TAG" "ERROR: Download md5sum failed !"
			rm -f $FIRMWARE_FILE
			exit 1
		fi
		logger -s -t "$TAG" "md5sum is correct: $file_md5sum"

		#check firmware
		if m=$(sysupgrade -T $FIRMWARE_FILE) ;then
			#update configs after firmware update
			uci set ddmesh.boot.boot_step=2
			# used for update history
			test -n "$nightly" && uci set ddmesh.boot.nightly_upgrade_running=1
			# used to reset overlay md5sum
			uci set ddmesh.boot.upgrade_running=1
			uci_commit.sh
			sync
			logger -s -t "$TAG" "sysupgrade started..."
			sysupgrade $FIRMWARE_FILE 2>&1 >/dev/null &
			exit 0
		else # firmware check
			rm -f $FIRMWARE_FILE
			logger -s -t "$TAG" "ERROR: wrong firmware: $m"
			exit 1
		fi
		;;

	check)
		firmware_autoupdate_enabled=$(echo $FILE_INFO_JSON | jsonfilter -e '@.fileinfo.autoupdate')

		echo "Auto Update: Router enabled: $cfg_autoupdate_enabled; Firmware enabled: $firmware_autoupdate_enabled; Node autoupdate allowed: $node_autoupdate_allowed"

		check_version || echo "no new firmware"
		echo "your version: $firmware_current_version"
		echo "version on server: $firmware_release_version"
		run="no"
		[ "$node_autoupdate_allowed" = "1" -a "$cfg_autoupdate_enabled" = "1" -a "$firmware_autoupdate_enabled" = "1" ] && run="yes"
	       	echo "-> run: $run"
		exit 0
		;;

	compare)
		# new old
		compare_versions $2 $3 && echo "newer"
		;;

	*)
		usage
		;;
esac
