#!/bin/ash
# checks or runs an firmware update. downloads firmware
# arguments: <run | check>

. /lib/functions.sh
. /lib/upgrade/common.sh
. /lib/upgrade/platform.sh
eval $(cat /etc/openwrt_release)

FIRMWARE="$(/usr/lib/ddmesh/ddmesh-get-firmware-name.sh)"
URL_RELEASE="$(uci get credentials.url.firmware_download_release)"
URL_ARCH="${DISTRIB_TARGET%/*}"
FIRMWARE_FILE="/tmp/firmware.bin"
TAG="AutoFirmwareUpdate"

enabled="$(uci get ddmesh.system.firmware_autoupdate)"

#return 0 if new > cur
compare_versions() {
	new=$1
	cur=$2
        local IFS='.';
        set $new; a1=$1; a2=$2; a3=$3
        set $cur; b1=$1; b2=$2; b3=$3

	#don't upgrade over major version changes
        [ ! "$a1" -eq "$b1" ] && return 1 

	#compare middle/minor
        [ "$a2" -lt "$b2" ] && return 1
        [ "$a2" -eq "$b2" ] &&  [ "$a3" -le "$b3" ] && return 1 
	return 0
}

check_version() {
	firmware_release_version=$(wget -O - "$URL_RELEASE/version")
	[ -z "$firmware_release_version" ] && return 1
	firmware_current_version="$(cat /etc/version)"

	logger -t "$TAG" "curver: $firmware_current_version, latest version: $firmware_release_version"
	compare_versions $firmware_release_version $firmware_current_version && return 0
	return 1
}

get_server_md5sum() {
	server_md5sum=$(wget -O - "$URL_RELEASE/$URL_ARCH/md5sums" | grep "$FIRMWARE" | cut -d ' ' -f1)
	[ -z "$server_md5sum" ] && return 1
	return 0
}

download_firmware(){
	logger -t "$TAG" "Try downloading $URL_RELEASE/$URL_ARCH/$FIRMWARE"
	wget -O $FIRMWARE_FILE "$URL_RELEASE/$URL_ARCH/$FIRMWARE" 2>&1 || return 1
	return 0
}


case "$1" in
	run)
		logger -t "$TAG" "Auto Update Enabled: $enabled"
		[ "$enabled" = "1" ] || exit 1

		check_version || exit 1
		logger -t "$TAG" "new version available"

		download_firmware || exit 1
		logger -t "$TAG" "firmware downloaded successfully"

		get_server_md5sum || exit 1
		file_md5sum=$(md5sum $FIRMWARE_FILE | cut -d' ' -f1)
		if [ "$server_md5sum" != "$file_md5sum" ]; then
			logger -t "$TAG" "ERROR: Download md5sum failed !"
			rm -f $FIRMWARE_FILE
			exit 1	
		fi
		logger -t "$TAG" "md5sum is correct: $file_md5sum"

		#check firmware (see /lib/upgrade)
		if m=$(platform_check_image $FIRMWARE_FILE) ;then 
			#update configs after firmware update
			uci set ddmesh.boot.boot_step=2
			uci commit
			sync	
			logger -t "$TAG" "sysupgrade started..."
			sysupgrade $FIRMWARE_FILE 2>&1 >/dev/null &
			exit 0
		else # firmware check
			rm -f $FIRMWARE_FILE
			logger -t "$TAG" "ERROR: wrong firmware: $m"
			exit 1
		fi
		;;

	check)
		echo "auto update enabled: $enabled"
		check_version || echo "no new firmware"
		echo "your version: $firmware_current_version"
		echo "new version: $firmware_release_version"
		exit 0
		;;

	*)
		echo "$1 <run | check>"
		;;
esac

