#!/bin/sh /etc/rc.common
# Copyright (C) 2006 OpenWrt.org 


start() {

	eval $(cat /etc/openwrt_release)
	
	LOGGER_TAG="ddmesh boot"

	#initial setup and node depended setup (crond calles ddmesh-register-node.sh to update node)
	logger -t $LOGGER_TAG "inital boot setting"
	/usr/lib/ddmesh/ddmesh-bootconfig.sh

	logger -t $LOGGER_TAG "run ddmesh upgrade"
	/usr/lib/ddmesh/ddmesh-upgrade.sh

	#check if we have a node
	test -z "$(uci get ddmesh.system.node)" && echo "router not registered" && exit
	eval $(/usr/bin/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
	
	#setup network (routing rules) manually (no support by uci)
	logger -t $LOGGER_TAG "network"
	echo "setup network"
	/usr/lib/ddmesh/ddmesh-routing.sh add

	#load splash mac from config to firewall
	logger -t $LOGGER_TAG "splash firewall"
	/usr/lib/ddmesh/ddmesh-splash.sh loadconfig

	logger -t $LOGGER_TAG "portforwarding"
	/usr/lib/ddmesh/ddmesh-portfw.sh init
	
	#---- starting serivces ------

	#setup dnsmasq
	logger -t $LOGGER_TAG "dnsmasq"
	echo "setup dnsmasq"
	/usr/lib/ddmesh/ddmesh-dnsmasq.sh start

	logger -t $LOGGER_TAG "start service bmxd"
	echo "start service bmxd"
	/usr/lib/ddmesh/ddmesh-bmxd.sh start

	logger -t $LOGGER_TAG "start service backbone"
	echo "backbone"
	/usr/lib/ddmesh/ddmesh-backbone.sh start

	logger -t $LOGGER_TAG "start service private vpn"
	echo "private vpn"
	/usr/lib/ddmesh/ddmesh-vpn.sh start

	logger -t $LOGGER_TAG "start service openvpn"
	echo "openvpn"
	if [ "$DISTRIB_CODENAME" = "attitude_adjustment" ]; then
		cd /etc/openvpn
		for i in /etc/openvpn/*.conf
		do
			test -x /usr/sbin/openvpn && /usr/sbin/openvpn --config $i &
		done
	else
		test -x /etc/init.d/openvpn && /etc/init.d/openvpn start
	fi

	logger -t $LOGGER_TAG "start service nuttcp"     
	echo "nuttcp"                            
	nuttcp -S -P5010

	logger -t $LOGGER_TAG "generate qr code"     
	echo "qrencode"                            
	/usr/lib/ddmesh/ddmesh-qrencode.sh

	logger -t $LOGGER_TAG "register node"     
	echo "register node"                            
	/usr/bin/ddmesh-register-node.sh

	logger -t $LOGGER_TAG "rdate"     
	echo "rdate"                            
	/usr/lib/ddmesh/ddmesh-rdate.sh start	

	logger -t $LOGGER_TAG "ifstatd"     
	echo "run ifstatd"                            
	/usr/lib/ddmesh/ddmesh-ifstatd.sh &

	logger -t $LOGGER_TAG "finished."     
}

stop() {
	/usr/lib/ddmesh/ddmesh-backbone.sh stop
	/usr/lib/ddmesh/ddmesh-vpn.sh stop		
	/usr/lib/ddmesh/ddmesh-bmxd.sh stop
	/usr/lib/ddmesh/ddmesh-dnsmasq.sh stop
	setup_routing del 
}


