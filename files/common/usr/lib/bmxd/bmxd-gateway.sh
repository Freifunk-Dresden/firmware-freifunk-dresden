#!/bin/sh

RESOLV_CONF_FINAL="/tmp/resolv.conf.final"
RESOLV_CONF_AUTO="/tmp/resolv.conf.auto"
TAG="BMXD-SCRIPT[$$]"

if [ -z "$1" ]; then
 echo "missing params"
 exit 0
fi

toggle_ssid()
{
	# determin wifi interface, uses same section as defined in /etc/config/wireless
	json=$(wifi status)

	# loop max through 3 interfaces
	for i in 0 1 2; do
		eval $(echo $json | jsonfilter -e wifi_section=@.radio0.interfaces[$i].section -e wifi_dev=@.radio0.interfaces[$i].ifname)
		if [ "$wifi_section" = "@wifi-iface[1]" ]; then
			echo " $wifi_dev"
			break;
		fi
	done

	if [ -n "$wifi_dev" ]; then
		if [ "$1" = "true" ]; then
			logger -s -t $TAG "ssid: $(uci -q get wireless.@wifi-iface[1].ssid)"
			wpa_cli -p /var/run/hostapd -i $wifi_dev set ssid "$(uci -q get wireless.@wifi-iface[1].ssid)"
		else
			logger -s -t $TAG "ssid: "FF no-inet [$(uci -q get ddmesh.system.node)]""
			wpa_cli -p /var/run/hostapd -i $wifi_dev set ssid "FF no-inet [$(uci -q get ddmesh.system.node)]"
		fi
	fi
}

# bmxd calles it with: gateway,del,IP
# boot and wan hotplug: init 
case $1 in
	gateway)
		logger -s -t $TAG "GATEWAY"
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
			# use symlink. because resolv.conf.auto can be set later by wwan
			rm $RESOLV_CONF_FINAL
			ln -s $RESOLV_CONF_AUTO $RESOLV_CONF_FINAL
			/usr/lib/ddmesh/ddmesh-led.sh wifi alive
			toggle_ssid false 
		fi
	;;
	*)
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


