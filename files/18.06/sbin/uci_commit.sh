#!/bin/ash
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

# helper to commit all temporary configuration, because
# /sbin/uci commit can not handle symlink config files
# This is only used by freifunk-dresden /www/admin or /usr/lib/ddmesh/

TMP_CONFIG_DIR=/var/etc/config

# get all symlinks and commit them.
# IMPORTANG: specify config names !!!

# uci -c option mixes up /etc/config/... with /var/etc/config...
# result: options are stored uncontrolled at wrong locations.
# -> NEVER use this option some where else

for config in $(ls -1F  /etc/config | sed -n 's#@$##p')
do
	uci -q -c $TMP_CONFIG_DIR commit $config
done

# then commit all others to flash
/sbin/uci -q commit

# sync file systems (ext4)
sync

