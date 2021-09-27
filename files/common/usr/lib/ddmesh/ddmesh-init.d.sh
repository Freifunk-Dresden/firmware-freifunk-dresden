#!/bin/sh /etc/rc.common
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

LOGGER_TAG="ddmesh-boot"

wait_for_wifi()
{
	c=0
	max=60
	while [ $c -lt $max ]
	do
		# use /tmp/state  instead of ubus because up-state is wrong.
		# /tmp/state is never set back (but this can be ignored here. if needed use /etc/hotplug.d/iface)
		wifi2_up="$(uci -q -P /tmp/state get network.wifi2.up)"

		logger -s -t "$LOGGER_TAG" "Wait for WIFI up: $c/$max (wifi2:$wifi_up)"

		if [ "$wifi2_up" = 1 ]; then
			logger -s -t "$LOGGER_TAG" "WIFI is up -> continue"
			/usr/lib/ddmesh/ddmesh-led.sh wifi alive
			break;
		fi
		sleep 1
		c=$((c+1))
	done
}

start() {

	# enable OOM killer reboot
	sysctl  -wq vm.panic_on_oom=1

	# disable cron job to avoid 'run-checks' starting services
	/etc/init.d/cron stop

	eval $(cat /etc/openwrt_release)

	/usr/lib/ddmesh/ddmesh-led.sh wifi_off

	#initial setup and node depended setup (crond calles ddmesh-register-node.sh to update node)
	logger -s -t $LOGGER_TAG "inital boot setting"
	#check if boot process should be stopped
	/usr/lib/ddmesh/ddmesh-bootconfig.sh || exit

	# wait for wifi before setting firewall, because it would be run parallel
	[ -d /sys/class/ieee80211/phy0 ] && wait_for_wifi

	# need to wait, until async netifd has finished. (there is no event/condition to wait for)
	logger -t "SLEEP" "SLEEP START"
	sleep 60
	logger -t "SLEEP" "SLEEP END"

	logger -s -t $LOGGER_TAG "restart firewall"
	fw3 restart
	# manually update (firmware still not running)
	/usr/lib/ddmesh/ddmesh-firewall-addons.sh init-update
	/usr/lib/ddmesh/ddmesh-firewall-addons.sh firewall-update
	/usr/lib/ddmesh/ddmesh-backbone.sh firewall-update
	/usr/lib/ddmesh/ddmesh-privnet.sh firewall-update
	/usr/lib/ddmesh/ddmesh-splash.sh firewall-update

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

	# AFTER dnsmasq (bmxd script will set resolv.conf.final)
	logger -s -t $LOGGER_TAG "start service bmxd"
	/usr/lib/ddmesh/ddmesh-bmxd.sh start

	logger -s -t $LOGGER_TAG "start service backbone"
	/usr/lib/ddmesh/ddmesh-backbone.sh start

	logger -s -t $LOGGER_TAG "start service privnet"
	/usr/lib/ddmesh/ddmesh-privnet.sh start

	logger -s -t $LOGGER_TAG "start service openvpn"
	test -f /etc/config/openvpn.ffdd && mv /etc/config/openvpn.ffdd /etc/config/openvpn
	test -x /etc/init.d/openvpn && /etc/init.d/openvpn start

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

	logger -s -t $LOGGER_TAG "register node"
	/usr/lib/ddmesh/ddmesh-register-node.sh

	logger -s -t $LOGGER_TAG "start cron"
	/etc/init.d/cron start

	/usr/lib/ddmesh/ddmesh-led.sh status done

	# enable hotplug some more events
	touch /tmp/freifunk-running

	logger -s -t $LOGGER_TAG "finished."
}

stop() {
	/usr/lib/ddmesh/ddmesh-backbone.sh stop
	/usr/lib/ddmesh/ddmesh-privnet.sh stop
	/usr/lib/ddmesh/ddmesh-bmxd.sh stop
	/usr/lib/ddmesh/ddmesh-dnsmasq.sh stop
	setup_routing del
}
