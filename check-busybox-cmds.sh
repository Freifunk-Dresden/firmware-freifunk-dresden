#!/bin/bash

# das script sucht alle commands; die von busybox bereitgestellt werden im
# filesystem.
# CMD enthält alle busybox commands
# das script sucht vom aktuellen directory aus, alle text files

CMD="arping, ash, awk, basename, brctl, bunzip2, bzcat, cat, chgrp, chmod, chown, chroot, clear, cmp, cp, crond, crontab, cut, date, dd, devmem, df, dirname, dmesg, du, echo, egrep, env, expr, false, fgrep, find, free, fsync, grep, gunzip, gzip, halt, head, hexdump, hostid, hwclock, id, ifconfig, kill, killall, less, ln, lock, logger, ls, md5sum, mkdir, mkfifo, mknod, mkswap, mktemp, mount, mv, nc, netmsg, netstat, nice, nslookup, ntpd, passwd, pgrep, pidof, ping, ping6, pivot_root, poweroff, printf, ps, pwd, readlink, reboot, reset, rm, rmdir, route, sed, seq, sh, sleep, sort, start-stop-daemon, strings, switch_root, sync, sysctl, tail, tar, tee, telnet, telnetd, test, time, top, touch, tr, traceroute, true, udhcpc, umount, uname, uniq, uptime, vconfig, vi, wc, wget, which, xargs, yes, zcat"

UNUSED=$CMD

IFS=', '

for c in $CMD
do
 echo "[$c]"

 x=$(find ./ -type f ! -name 'jquery.js' ! -wholename './usr/lib/opkg/*' -name '*' -exec grep -I --color=always -w $c {} \; -print)
 test -n "$x" &&  echo "$x ->used" && UNUSED=${UNUSED/[, ]$c[, ]/;}

 echo "--------------------------------------------------"
done

echo "CMD: $CMD"
echo "UN-USED: $UNUSED"
