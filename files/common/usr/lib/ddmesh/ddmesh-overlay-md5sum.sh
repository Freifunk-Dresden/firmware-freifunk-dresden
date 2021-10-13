#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

if [ -d /overlay/upper ]; then
 d="/overlay/upper"
else
 d="/overlay"
fi

md5source()
{
	# exclude directory entry for overlay file
	ls -lisaRt /overlay/upper/ | grep -v 'overlay'
	find $d ! -type l ! -name "overlay" -exec md5sum {} 2>/dev/null \;
}

md5="$(md5source | md5sum | cut -d' ' -f1)"
stored="$(uci get overlay.@overlay[0].md5sum)"

if [ "$1" = "-json" ]; then
	echo "{\"md5_current\":\"$md5\", \"md5_previous\":\"$stored\"}"
else
	echo "cur:$md5"
	echo "old:$stored"
fi

test "$1" = "write" && {
	uci set overlay.data.md5sum="$md5"
	uci_commit.sh
	echo "saved."
}

# exit code
[ "$md5" = "$stored" ] && exit 0
exit 1
