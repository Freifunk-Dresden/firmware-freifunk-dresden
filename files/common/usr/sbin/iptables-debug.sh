#!/bin/ash
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

#1. move iptables to iptables.exe
#2. rename this script to "iptables"

logger -s -t IPTABLES "iptables $*"
iptables.exe iptables -w $*
