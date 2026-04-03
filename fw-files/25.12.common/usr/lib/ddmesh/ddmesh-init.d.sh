#!/bin/sh /etc/rc.common
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

LOGGER_TAG="ddmesh-boot"
POST_SCRIPT="/etc/ddmesh/post-init.sh"


start() {

	# enable OOM killer reboot
	sysctl  -wq vm.panic_on_oom=1

	# disable cron job to avoid 'run-checks' starting services
	/etc/init.d/cron stop

	eval $(cat /etc/openwrt_release)

	#initial setup and node depended setup (crond calles ddmesh-register-node.sh to update node)
	logger -s -t $LOGGER_TAG "starting freifunk ddmesh-init.d.sh"
	#check if boot process should be stopped
	/usr/lib/ddmesh/ddmesh-bootconfig.sh || exit

	# depends on ddmesh-bootconfig.sh
	/usr/lib/ddmesh/ddmesh-led.sh wifi off

	#check if we have a node
	test -z "$(uci get ddmesh.system.node)" && logger -s -t $LOGGER_TAG "router not registered" && exit
	eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

	#setup network (routing rules) manually (no support by uci)
	logger -s -t $LOGGER_TAG "setup routing"
	/usr/lib/ddmesh/ddmesh-routing.sh start

	#---- starting serivces ------

	# setup dnsmasq (BEFORE BMXD)
	logger -s -t $LOGGER_TAG "dnsmasq"
	/usr/lib/ddmesh/ddmesh-dnsmasq.sh start

	logger -s -t $LOGGER_TAG "start service backbone"
	/usr/lib/ddmesh/ddmesh-backbone.sh start

	logger -s -t $LOGGER_TAG "start service privnet"
	/usr/lib/ddmesh/ddmesh-privnet.sh start

	if [ -x /usr/bin/iperf3 ]; then
		logger -s -t $LOGGER_TAG "start service iperf3"
		iperf3 -s -D
	else
		logger -s -t $LOGGER_TAG "service iperf3 not installed"
	fi

	if [ -x /sbin/uqmi ]; then
		logger -s -t $LOGGER_TAG "start lte monitor"
		/usr/lib/ddmesh/ddmesh-lte-monitor.sh &
	fi

	if [ "$(uci -q get ddmesh.system.node_type)" = "mobile" ]; then
		/usr/lib/ddmesh/ddmesh-geoloc.sh mobile &
	fi

	if [ -x "${POST_SCRIPT}" ]; then
		logger -s -t $LOGGER_TAG "call: ${POST_SCRIPT}"
		${POST_SCRIPT}
	fi

	logger -s -t $LOGGER_TAG "register node"
	/usr/lib/ddmesh/ddmesh-register-node.sh

	logger -s -t $LOGGER_TAG "start cron"
	/etc/init.d/cron start

	# enable hotplug events, and bmxd-gateway.sh calles before starting bmxd
	# to avoid missing events
	touch /tmp/freifunk-running

	# update firewall (after touching /tmp/freifunk-running)
	fw4 restart

	# need to restart wifi, because on openwrt 25 mesh2g-80211s does not come up correclty
	logger -s -t $LOGGER_TAG "restart wifi"
	wifi down && sleep 10 && wifi up

	# AFTER dnsmasq (bmxd script will set resolv.conf.final)
	# and at latest as possible (causes hotplug events and possible ubus call deadlock)
	logger -s -t $LOGGER_TAG "start service bmxd"
	/usr/lib/ddmesh/ddmesh-bmxd.sh start

	# no update, sysinfo not ready yet
	/usr/lib/ddmesh/ddmesh-display.sh msg "Running"
	/usr/lib/ddmesh/ddmesh-display.sh boot
	/usr/lib/ddmesh/ddmesh-led.sh status done

	logger -s -t $LOGGER_TAG "finished."
}

stop() {
	/usr/lib/ddmesh/ddmesh-backbone.sh stop
	/usr/lib/ddmesh/ddmesh-privnet.sh stop
	/usr/lib/ddmesh/ddmesh-bmxd.sh stop
	/usr/lib/ddmesh/ddmesh-dnsmasq.sh stop
	setup_routing del
}
