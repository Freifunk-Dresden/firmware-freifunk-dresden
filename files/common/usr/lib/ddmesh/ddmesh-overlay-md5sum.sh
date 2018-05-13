#!/bin/sh

if [ -d /overlay/upper ]; then
 d="/overlay/upper"
else
 d="/overlay"
fi

md5="$(find $d ! -type l ! -name "overlay" -exec md5sum {} 2>/dev/null \; | md5sum | cut -d' ' -f1)"

if [ "$1" = "-json" ]; then
	echo "{\"md5_current\":\"$md5\", \"md5_previous\":\"$(uci get overlay.@overlay[0].md5sum)\"}"
else
	echo "cur:$md5"
	echo "old:$(uci get overlay.@overlay[0].md5sum)"
fi

test "$1" = "write" && {
	uci set overlay.data.md5sum="$md5"
	uci_commit.sh
	echo "saved."
}

