#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

killall -9 uhttpd;sleep 2;/etc/init.d/uhttpd start;sleep 2; ps | grep uhttpd
