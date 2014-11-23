#!/bin/sh

killall -9 uhttpd;sleep 2;/etc/init.d/uhttpd start;sleep 2; ps | grep uhttpd

