#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

echo 'Content-type: text/plain txt'
echo ''

/usr/lib/ddmesh/ddmesh-geoloc.sh request-only
