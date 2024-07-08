#!/bin/sh

start=true

# first try to open ttyS1. only start getty, if writing
# is ok. else syslog gets flooded
case "$2" in
  ttyS0)	start=false ;;
  ttyS*)	echo "" > /dev/$2 2>/dev/null || start=false ;;
  ttyUSB*)	start=true ;;
  *)		start=false ;;
esac

[ -x /usr/sbin/agetty ] && ${start} && exec /usr/sbin/agetty $*
