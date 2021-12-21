#!/bin/sh

# script allows to upload/install firmware via GUI. It can be run in an outer loop in case 
# a router is not accessable (turned on) continously. 
# It does the following steps:
# - calculates md5sum of firmware
# - uploads the image via gui
# - extracts the md5sum from gui and compares it to local md5sum
# - it activates firmare upgrade

 
USER=root
PASSWORD=

TIMEOUT=10

arg_filename="$1"
arg_ip="$2"

if [ -z "$arg_filename" -o -z "$arg_ip" ]; then
	echo "Upload firmware via https"
	echo "$(basename $0) <firmware-file> <router-ip>"
	exit 1 
fi

test -z "$PASSWORD" && echo "Password needed. Please add password in script" && exit 1

MD5_LOCAL=$(md5sum $arg_filename | awk '{print $1}')
FILENAME="$(basename $arg_filename)"


RESPONSE="$(curl --connect-timeout $TIMEOUT --insecure --form "form_action=upload" --form "filename=@\"$arg_filename\";filename=\"$FILENAME\"" https://$USER:$PASSWORD@$arg_ip/admin/firmware.cgi)"

test "$?" != "0" && exit 1

MD5_REMOTE=$(echo "$RESPONSE" | sed -n '/Firmware-MD5-Summe/{s#.*<td>\([0-9a-z]\+\)[ ]*</td>.*#\1#p}')

echo "local md5: $MD5_LOCAL"
echo "remote md5: $MD5_REMOTE"

if [ "$MD5_LOCAL" != "$MD5_REMOTE" ]; then
	echo "ERROR: uploading (different md5sum)"
	exit 1
fi

echo "flashing..."
curl --connect-timeout $TIMEOUT --insecure --form "form_action=flash" https://$USER:$PASSWORD@$arg_ip/admin/firmware.cgi >/dev/null

exit 0

