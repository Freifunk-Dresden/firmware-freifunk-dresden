#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3
. /usr/lib/www/page-functions.sh
echo "$0 [$host]" >/tmp/xxx
echo 'Content-type: text/plain txt'
echo ''

/usr/lib/ddmesh/ddmesh-backbone-regwg.sh register "${host}"
