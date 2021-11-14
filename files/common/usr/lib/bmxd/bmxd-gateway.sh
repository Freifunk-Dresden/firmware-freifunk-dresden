#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

RESOLV_PATH="/tmp/resolv.conf.d"
RESOLV_CONF_FINAL="${RESOLV_PATH}/resolv.conf.final"
RESOLV_CONF_AUTO="${RESOLV_PATH}/resolv.conf.auto"
TAG="BMXD-SCRIPT[$$]"

if [ -z "$1" ]; then
 echo "missing params"
 exit 0
fi

toggle_ssid()
{
 # $1 - true if internet is present
	json=$(wifi status)
	# loop max through 3 interfaces
	for radio in radio2g radio5g; do
		for i in 0 1 2 3; do
			unset wifi_dev
			unset wifi_network

			eval $(echo $json | jsonfilter -e wifi_dev=@.${radio}.interfaces[$i].ifname \
				-e wifi_network=@.${radio}.interfaces[$i].config.network[0] \
				-e wifi_ssid=@.${radio}.interfaces[$i].config.ssid)

			if [ "$wifi_network" = "wifi2" -a -n "$wifi_dev" ]; then
				if [ "$1" = "true" ]; then
					logger -s -t $TAG "$wifi_dev ssid: $wifi_ssid"
					wpa_cli -p /var/run/hostapd -i $wifi_dev set ssid "$wifi_ssid" >/dev/null
				else
					logger -s -t $TAG "$wifi_dev ssid: "FF no-inet [$(uci -q get ddmesh.system.node)]""
					wpa_cli -p /var/run/hostapd -i $wifi_dev set ssid "FF no-inet [$(uci -q get ddmesh.system.node)]" >/dev/null
				fi
			fi
		done
	done
}

# script is called by:
# - bmxd calles it with: gateway,del,IP
# - boot and wan hotplug: init
case $1 in
	gateway)
		logger -s -t $TAG "GATEWAY"

		/usr/lib/ddmesh/ddmesh-setup-network.sh setup_ffgw_tunnel "gateway"

		# use symlink. because resolv.conf.auto can be set later by wwan
		rm $RESOLV_CONF_FINAL
		ln -s $RESOLV_CONF_AUTO $RESOLV_CONF_FINAL
		/usr/lib/ddmesh/ddmesh-led.sh wifi gateway
		toggle_ssid true
		;;

	del|init)
		# check if this router is a gateway
		gw="$(ip ro li ta public_gateway | grep default)"

		# set when "del" or if empty
		if [ -z "$gw" -a "$1" = "del" -o -z "$(grep nameserver $RESOLV_CONF_FINAL)" ]; then
			logger -s -t $TAG "remove GATEWAY (del)"

			# Dont set link ffgw down, it will delete default route.
			# There is no need to change ffgw, when removing gw.

			# use symlink. because resolv.conf.auto can be set later by wwan
			rm $RESOLV_CONF_FINAL
			ln -s $RESOLV_CONF_AUTO $RESOLV_CONF_FINAL
			/usr/lib/ddmesh/ddmesh-led.sh wifi alive
			toggle_ssid false
		fi
		;;

	*)
		# update gateway ip
		/usr/lib/ddmesh/ddmesh-setup-network.sh setup_ffgw_tunnel "$1"

		logger -s -t $TAG "nameserver $1"
		# delete initial symlink
		rm $RESOLV_CONF_FINAL
		echo "nameserver $1" >$RESOLV_CONF_FINAL
		/usr/lib/ddmesh/ddmesh-led.sh wifi freifunk
		toggle_ssid true
		;;
esac

# restart dnsmasq, as workaround for dead dnsmasq
/etc/init.d/dnsmasq restart


GW_STAT="/var/statistic/gateway_usage"
count=$(sed -n "/$1:/s#.*:##p" $GW_STAT)
if [ -z $count ]; then
	echo "$1:1" >> $GW_STAT
else
	count=$(( $count + 1 ))
	sed -i "/$1/s#:.*#:$count#" $GW_STAT
fi
