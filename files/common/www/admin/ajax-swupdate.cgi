#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

echo 'Content-Type: application/json;charset=UTF-8'
echo ''


#return 0 if new > cur
compare_versions() {
	new=$1
	cur=$2
	local IFS='.';
	set $new; a1=$1; a2=$2; a3=$3
	set $cur; b1=$1; b2=$2; b3=$3
	[ "$a1" -lt "$b1" ] && return 1
		[ "$a1" -eq "$b1" ] && {
		[ "$a2" -lt "$b2" ] && return 1
			[ "$a2" -eq "$b2" ] &&  [ "$a3" -le "$b3" ] && return 1
		}
	return 0
}

download_file_info()
{
	# download file info
	RELEASE_FILE_INFO_JSON="$(/usr/lib/ddmesh/ddmesh-get-firmware-name.sh)"
	error=$(echo $RELEASE_FILE_INFO_JSON | jsonfilter -e '@.error')
	test -n "$error" && RELEASE_FILE_INFO_JSON=""

	TESTING_FILE_INFO_JSON="$(/usr/lib/ddmesh/ddmesh-get-firmware-name.sh testing)"
	error=$(echo $TESTING_FILE_INFO_JSON | jsonfilter -e '@.error')
	test -n "$error" && TESTING_FILE_INFO_JSON=""

	firmware_release_version=$(echo $RELEASE_FILE_INFO_JSON | jsonfilter -e '@.firmware_version')
	firmware_release_url="$(echo $RELEASE_FILE_INFO_JSON | jsonfilter -e '@.firmware_url')"
	firmware_release_md5sum="$(echo $RELEASE_FILE_INFO_JSON | jsonfilter -e '@.fileinfo.md5sum')"
	firmware_release_filename="$(echo $RELEASE_FILE_INFO_JSON | jsonfilter -e '@.fileinfo.filename')"
	firmware_release_comment="$(echo $RELEASE_FILE_INFO_JSON | jsonfilter -e '@.fileinfo.comment')"

	firmware_testing_version=$(echo $TESTING_FILE_INFO_JSON | jsonfilter -e '@.firmware_version')
	firmware_testing_url="$(echo $TESTING_FILE_INFO_JSON | jsonfilter -e '@.firmware_url')"
	firmware_testing_md5sum="$(echo $TESTING_FILE_INFO_JSON | jsonfilter -e '@.fileinfo.md5sum')"
	firmware_testing_filename="$(echo $TESTING_FILE_INFO_JSON | jsonfilter -e '@.fileinfo.filename')"
	firmware_testing_comment="$(echo $TESTING_FILE_INFO_JSON | jsonfilter -e '@.fileinfo.comment')"
}

download_file_info

cur_version="$(cat /etc/version)"

firmware_release_version_ok=0
if [ -n "$RELEASE_FILE_INFO_JSON" ]; then
	compare_versions "$firmware_release_version" "$cur_version" && firmware_release_version_ok=1
fi

firmware_testing_version_ok=0
if [ -n "$TESTING_FILE_INFO_JSON" ]; then
	keep_btn_enabled="$(uci -q get ddmesh.system.fwupdate_always_allow_testing)"
	compare_versions "$firmware_testing_version" "$cur_version" || [ "$keep_btn_enabled" = "1" ] && firmware_testing_version_ok=1
fi

# pass variables via stdout json
cat <<EOM
{
"firmware_release_version" : "${firmware_release_version}",
"firmware_release_url" : "${firmware_release_url}",
"firmware_release_md5sum" : "${firmware_release_md5sum}",
"firmware_release_filename" : "${firmware_release_filename}",
"firmware_release_comment" : "${firmware_release_comment}",
"firmware_release_enable_button" : "$firmware_release_version_ok",

"firmware_testing_version" : "${firmware_testing_version}",
"firmware_testing_url" : "${firmware_testing_url}",
"firmware_testing_md5sum" : "${firmware_testing_md5sum}",
"firmware_testing_filename" : "${firmware_testing_filename}",
"firmware_testing_comment" : "${firmware_testing_comment}",
"firmware_testing_enable_button" : "$firmware_testing_version_ok"
}
EOM
