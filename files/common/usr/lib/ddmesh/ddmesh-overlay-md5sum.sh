#!/bin/sh

md5="$(find /overlay ! -regex '/overlay/etc/config/overlay' -exec md5sum {} 2>/dev/null \; | md5sum | cut -d' ' -f1)"
echo "cur:$md5"
echo "old:$(uci get overlay.@overlay[0].md5sum)"

test "$1" = "write" && {
	uci set overlay.@overlay[0].md5sum="$md5"
	uci commit
	echo "saved."
}

