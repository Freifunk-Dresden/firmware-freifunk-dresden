#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

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
