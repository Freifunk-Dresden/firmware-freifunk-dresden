#!/bin/sh

USER=root
PASSWORD=

arg_filename="$1"
arg_ip="$2"

if [ -z "$arg_filename" -o -z "$arg_ip" ]; then
	echo "Upload firmware via htts"
	echo "$(basename $0) <firmware-file> <router-ip>"
	exit 1 
fi

test -z "$PASSWORD" && echo "Password needed. Please add password in script" && exit 1

MD5_LOCAL=$(md5sum $arg_filename | awk '{print $1}')
FILENAME="$(basename $arg_filename)"


RESPONSE="$(curl --insecure --form "form_action=upload" --form "filename=@\"$arg_filename\";filename=\"$FILENAME\"" https://$USER:$PASSWORD@$arg_ip/admin/firmware.cgi)"

test "$?" != "0" && exit 1

MD5_REMOTE=$(echo "$RESPONSE" | sed -n '/Firmware-MD5-Summe/{s#.*<td>\([0-9a-z]\+\)[ ]*</td>.*#\1#p}')

echo "local md5: $MD5_LOCAL"
echo "remote md5: $MD5_REMOTE"

if [ "$MD5_LOCAL" != "$MD5_REMOTE" ]; then
	echo "ERROR: uploading (different md5sum)"
	exit 1
fi

echo "flashing..."
curl --insecure --form "form_action=flash" https://$USER:$PASSWORD@$arg_ip/admin/firmware.cgi >/dev/null

exit 0

