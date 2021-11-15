#!/bin/bash

# simple template to do same job on different routers
ROUTER="${ROUTER} 10.200.4.100" 
ROUTER="${ROUTER} 10.200.4.177"
ROUTER="${ROUTER} 10.200.5.222"
ROUTER="${ROUTER} 10.200.19.156"
ROUTER="${ROUTER} 10.200.19.160"
ROUTER="${ROUTER} 10.200.19.166"
ROUTER="${ROUTER} 10.200.5.152"
ROUTER="${ROUTER} 10.200.6.71"

for i in ${ROUTER}
do
	echo $i
#	scp files/common/etc/config/firewall root@$i:/etc/config
#	ssh -x root@$i "(sleep 20;reboot)&"
	ssh -x root@$i "bmxd -c --status"
done
