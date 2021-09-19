#!/bin/ash
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

j=$1
spaces="$2"


IFS='
'

#generates: p=paket v=version [installed=true] clear
#'clear' is just a separator and used to do the action. all other are used to set variables via eval
for i in $(cat /usr/lib/opkg/status | sed -n '
/^Package:.*/{s#^Package: \(.*\)#p="\1"#;h}
/^Version:.*/{s#^Version: \(.*\)#v="\1"#;H}
/^Status:.*/{s#^Status: \(.*\)#s="\1"#;H}
/^$/{x;a \
clear
p
}')
do
	if [ "$i" = "clear" ]; then
		test -z "$p" && continue
		test -z "$v" && continue
		test -z "$s" && continue

		#only own installed packages
		test "${s/ok/}" = "$s" && continue

		if [ -n "$j" ]; then
			json="$json { \"package\":\"$p\", \"version\":\"$v\"},"
		else
			echo "$p:$v:$s"
		fi

		#del old values
		unset p
		unset v
		unset installed
	else
		#set environment variables created via sed above
		eval $i
	fi
done


if [ -n "$j" ]; then
	json=$(echo $json | sed 's#,$##')
	echo $spaces'	"packages": ['
	echo $spaces"		$json"
	echo $spaces'	]'
fi
