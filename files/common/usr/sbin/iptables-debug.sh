#!/bin/ash

#1. move iptables to iptables.exe
#2. rename this script to "iptables"

logger -s -t IPTABLES "iptables $*"
iptables.exe iptables -w $*
