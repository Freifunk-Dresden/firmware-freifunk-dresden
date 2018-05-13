#!/bin/ash

ARG=$1

if [ "$ARG" = "testing" ]; then
	URL_DL="$(uci get credentials.url.firmware_download_testing)"
else
	URL_DL="$(uci get credentials.url.firmware_download_release)"
fi

DL_INFO_FILE="download.json"
CERT="--ca-certificate=/etc/ssl/certs/download.crt"
LOCAL_FILE="/tmp/download.json"

eval $(cat /etc/board.json | jsonfilter -e model='@.model.id' -e model2='@.model.name')
model="$(echo $model | sed 's#[ 	]*\(\1\)[ 	]*#\1#')"
model2="$(echo $model2 | sed 's#[ 	]*\(\1\)[ 	]*#\1#')"

rm -f $LOCAL_FILE

uclient-fetch $CERT -O $LOCAL_FILE "$URL_DL/$DL_INFO_FILE" ||  error=1
if [ "$error" = "1" ]; then
	echo "{\"error\":\"downloading $URL_DL/$DL_INFO_FILE\"}"
	exit 1
fi

version=$(cat $LOCAL_FILE | jsonfilter -e "@.firmware_version")
entry=$(cat $LOCAL_FILE | jsonfilter -e "@.fileinfo[@.model='$model' && @.model2='$model2']")

if [ -z "$entry" ]; then
	echo "{\"error\":\"file info not found\"}"
	exit 1
fi

eval $(echo $entry | jsonfilter -e subpath='@.path' -e filename='@.filename')

url="$URL_DL/$subpath/$filename"
echo "{ \"firmware_version\":\"$version\", \"url\":\"$url\", \"fileinfo\": $entry }"


