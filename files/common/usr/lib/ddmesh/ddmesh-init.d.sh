#!/bin/sh /etc/rc.common
# Copyright (C) 2006 OpenWrt.org

start() {

	# enable OOM killer reboot
	sysctl -wq vm.panic_on_oom=1

	# disable cron job to avoid 'run-checks' starting services
	/etc/init.d/cron stop

	eval $(cat /etc/openwrt_release)

	/usr/lib/ddmesh/ddmesh-led.sh wifi_off
	LOGGER_TAG="ddmesh boot"

	#initial setup and node depended setup (crond calles ddmesh-register-node.sh to update node)
	logger -s -t "$LOGGER_TAG" "inital boot setting"
	#check if boot process should be stopped
	/usr/lib/ddmesh/ddmesh-bootconfig.sh || exit

	#check if we have a node
	test -z "$(uci get ddmesh.system.node)" && logger -s -t "$LOGGER_TAG" "router not registered" && exit
	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

	#setup network (routing rules) manually (no support by uci)
	logger -s -t "$LOGGER_TAG" "network"
	/usr/lib/ddmesh/ddmesh-routing.sh start

	#load splash mac from config to firewall
	logger -s -t "$LOGGER_TAG" "splash firewall"
	/usr/lib/ddmesh/ddmesh-splash.sh loadconfig

	#---- starting serivces ------

	# setup dnsmasq (BEFORE BMXD)
	logger -s -t "$LOGGER_TAG" "dnsmasq"
	/usr/lib/ddmesh/ddmesh-dnsmasq.sh start

	# AFTER dnsmasq (bmxd script will overwrite resolv.conf.final)
	logger -s -t "$LOGGER_TAG" "start service bmxd"
	/usr/lib/ddmesh/ddmesh-bmxd.sh start

	logger -s -t "$LOGGER_TAG" "start service backbone"
	/usr/lib/ddmesh/ddmesh-backbone.sh start

	logger -s -t "$LOGGER_TAG" "start service privnet"
	/usr/lib/ddmesh/ddmesh-privnet.sh start

	logger -s -t "$LOGGER_TAG" "start service openvpn"
	if [ "$DISTRIB_CODENAME" = "attitude_adjustment" ]; then
		cd /etc/openvpn
		for i in /etc/openvpn/*.conf
		do
			test -x /usr/sbin/openvpn && /usr/sbin/openvpn --config "$i" &
		done
	else
		test -x /etc/init.d/openvpn && /etc/init.d/openvpn start
	fi

	if [ -x /usr/bin/iperf3 ]; then
		logger -s -t "$LOGGER_TAG" "start service iperf3"
		iperf3 -s -D
	else
		logger -s -t "$LOGGER_TAG" "service iperf3 not installed"
	fi

	logger -s -t "$LOGGER_TAG" "register node"
	/usr/lib/ddmesh/ddmesh-register-node.sh

	logger -s -t "$LOGGER_TAG" "start cron."
	/etc/init.d/cron start

	logger -s -t "$LOGGER_TAG" "finished."
	/usr/lib/ddmesh/ddmesh-led.sh status done

	# enable hotplug events
	touch /tmp/freifunk-running
}

stop() {
	/usr/lib/ddmesh/ddmesh-backbone.sh stop
	/usr/lib/ddmesh/ddmesh-privnet.sh stop
	/usr/lib/ddmesh/ddmesh-bmxd.sh stop
	/usr/lib/ddmesh/ddmesh-dnsmasq.sh stop
	setup_routing del
}
