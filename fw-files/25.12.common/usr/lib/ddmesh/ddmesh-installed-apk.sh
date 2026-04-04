#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

format="$1"
spaces="$2"

if [ "$format" = "json" ]; then
	json=$(echo $json | sed 's#,$##')
	echo $spaces'	"packages": ['
	echo $spaces"		$json"
	echo $spaces'	]'
fi
