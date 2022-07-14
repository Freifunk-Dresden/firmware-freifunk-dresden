#!/bin/bash

# simple template to do same job on different routers
ROUTER="${ROUTER} 10.200.3.249" 
ROUTER="${ROUTER} 10.200.4.46" 
ROUTER="${ROUTER} 10.200.4.100" 
ROUTER="${ROUTER} 10.200.4.177"
ROUTER="${ROUTER} 10.200.5.152"
ROUTER="${ROUTER} 10.200.5.198"
ROUTER="${ROUTER} 10.200.5.222"
ROUTER="${ROUTER} 10.200.6.71"
ROUTER="${ROUTER} 10.200.6.103"
ROUTER="${ROUTER} 10.200.6.117"
ROUTER="${ROUTER} 10.200.6.118"
ROUTER="${ROUTER} 10.200.6.192"
ROUTER="${ROUTER} 10.200.6.196"
ROUTER="${ROUTER} 10.200.6.197"
ROUTER="${ROUTER} 10.200.7.22"
ROUTER="${ROUTER} 10.200.19.156"
ROUTER="${ROUTER} 10.200.19.160"
ROUTER="${ROUTER} 10.200.19.162"
ROUTER="${ROUTER} 10.200.19.166"
ROUTER="${ROUTER} 10.200.19.206"
ROUTER="${ROUTER} 10.200.19.207"
ROUTER="${ROUTER} 10.200.19.208"
ROUTER="${ROUTER} 10.200.19.209"
ROUTER="${ROUTER} 10.200.19.210"
ROUTER="${ROUTER} 10.200.19.211"

for i in ${ROUTER}
do
	echo $i
#	COMMAND="(sleep 20;reboot)&"
#	COMMAND="bmxd -c --status --links"

#	COMMAND="uci set ddmesh.system.fwupdate_always_allow_testing=1 && uci set credentials.url.firmware_download_testing=https://selfsigned.download.freifunk-dresden.de/firmware/.nightly && uci commit"	
	COMMAND="uci set ddmesh.system.fwupdate_always_allow_testing=1 && uci set credentials.url.firmware_download_testing=https://selfsigned.download.freifunk-dresden.de/firmware/.8.0.7 && uci commit"	

#	COMMAND="uci set ddmesh.system.fwupdate_always_allow_testing=1 && uci set credentials.url.firmware_download_testing=https://selfsigned.download.freifunk-dresden.de/firmware/testing && uci commit"	

	ssh -x root@$i "${COMMAND}"
done
