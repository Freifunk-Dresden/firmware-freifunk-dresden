#!/bin/bash

# simple template to do same job on different routers
#ROUTER="${ROUTER} 10.200.3.249"
#ROUTER="${ROUTER} 10.200.4.46"
#ROUTER="${ROUTER} 10.200.4.100"
 #ROUTER="${ROUTER} 10.200.4.177"
 #ROUTER="${ROUTER} 10.200.5.198"
#ROUTER="${ROUTER} 10.200.5.222"
#ROUTER="${ROUTER} 10.200.6.103"
#ROUTER="${ROUTER} 10.200.6.117"
#ROUTER="${ROUTER} 10.200.6.118"
#ROUTER="${ROUTER} 10.200.6.192"
#ROUTER="${ROUTER} 10.200.6.196"
#ROUTER="${ROUTER} 10.200.6.197"
#ROUTER="${ROUTER} 10.200.6.251"
#ROUTER="${ROUTER} 10.200.7.22"
#ROUTER="${ROUTER} 10.200.7.249"
ROUTER="${ROUTER} 10.200.19.156"
ROUTER="${ROUTER} 10.200.19.160"
ROUTER="${ROUTER} 10.200.19.162"
#ROUTER="${ROUTER} 10.200.19.166"
#ROUTER="${ROUTER} 10.200.19.206"
#ROUTER="${ROUTER} 10.200.19.207"
 #ROUTER="${ROUTER} 10.200.19.208"
#ROUTER="${ROUTER} 10.200.19.209"
#ROUTER="${ROUTER} 10.200.19.210"
#ROUTER="${ROUTER} 10.200.19.211"

# ROUTER="${ROUTER} 10.200.5.152"
# ROUTER="${ROUTER} 10.200.6.71"


#RW
#ROUTER="${ROUTER} 10.200.5.223"
#ROUTER="${ROUTER} 10.200.4.194"
#ROUTER="${ROUTER} 10.200.6.17"
#ROUTER="${ROUTER} 10.200.4.35"
#ROUTER="${ROUTER} 10.200.5.11"
#ROUTER="${ROUTER} 10.200.4.152"
#ROUTER="${ROUTER} 10.200.5.210"
#ROUTER="${ROUTER} 10.200.4.180"
#ROUTER="${ROUTER} 10.200.5.24"
#ROUTER="${ROUTER} 10.200.5.30"
#ROUTER="${ROUTER} 10.200.4.39"

#ambross
#ROUTER="${ROUTER} 10.200.11.219"
#ROUTER="${ROUTER} 10.200.11.218"
#ROUTER="${ROUTER} 10.200.11.217"
#ROUTER="${ROUTER} 10.200.11.220"
#ROUTER="${ROUTER} 10.200.11.216"

#radebeul
#ROUTER="${ROUTER} 10.200.11.206"
#ROUTER="${ROUTER} 10.200.11.207"
#ROUTER="${ROUTER} 10.200.11.208"
#ROUTER="${ROUTER} 10.200.11.209"

#rietz
#ROUTER="${ROUTER} 10.200.11.196"
#ROUTER="${ROUTER} 10.200.11.198"
#ROUTER="${ROUTER} 10.200.11.199"

for i in ${ROUTER}
do
	echo $i
#	COMMAND="(sleep 20;reboot)&"
#	COMMAND="bmxd -c --status --links"

#	COMMAND="uci set ddmesh.system.fwupdate_always_allow_testing=1 && uci set credentials.url.firmware_download_release=https://selfsigned.download.freifunk-dresden.de/firmware/latest && uci set credentials.url.firmware_download_testing=https://selfsigned.download.freifunk-dresden.de/firmware/testing && uci commit"

#	COMMAND="uci set ddmesh.system.fwupdate_always_allow_testing=1 && uci set credentials.url.firmware_download_testing=https://selfsigned.download.freifunk-dresden.de/firmware/testing && uci commit"

#	COMMAND="uci set ddmesh.system.maintenance_time='20' && uci set ddmesh.boot.boot_step=2 && uci commit && echo 1 >/var/state/allow_autoupdate && sleep 2 && reboot"

	ssh -x root@$i "${COMMAND}"
done
