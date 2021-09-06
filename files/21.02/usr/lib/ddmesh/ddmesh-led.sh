#!/bin/ash
# https://openwrt.org/docs/guide-user/base-system/led_configuration

ARG_LED="$1"
ARG_CMD="$2"

if [ -z "$ARG_CMD" ]; then
	echo "ddmesh-led.sh <type> <value>"
	echo "	type: wifi | status"
	echo "	value:"
	echo "		wifi:	off|on|alive|freifunk|gateway"
	echo "		status: boot1|boot2|boot3|done|off|on"
	echo "		wwan:	off|on|2g|3g|4g"
	exit 0
fi

. /lib/functions.sh
. /lib/functions/leds.sh

eval $(cat /etc/openwrt_release)
platform="${DISTRIB_TARGET%/*}"
boardname=$(board_name) # function in function.sh

echo "platform: $platform"
echo "board: $boardname"

# try to detect led (keep order)
eval $(ddmesh-utils-wifi-info.sh)

#---- wifi2g
# "link2" nanostation
for i in wifi wlan wlan2g link2 ${wifi_status_radio2g_phy} usb
do
	tmp="$(ls -d /sys/class/leds/*${i} 2>/dev/null | sed -n '1p')"
	test -n "$tmp" && break
done
_led_wifi2g="$(echo $tmp | sed -n '1s#/sys/class/leds/##p')"

#---- wifi5g
for i in wlan5g ${wifi_status_radio5g_phy}
do
	tmp="$(ls -d /sys/class/leds/*${i} 2>/dev/null | sed -n '1p')"
	test -n "$tmp" && break
done
_led_wifi5g="$(echo $tmp | sed -n '1s#/sys/class/leds/##p')"

#---- status
# "link1" nanostation
for i in system info power wps usb link1
do
	tmp="$(ls -d /sys/class/leds/*${i} 2>/dev/null | sed -n '1p')"
	test -n "$tmp" && break
done
_led_status="$(echo $tmp | sed -n '1s#/sys/class/leds/##p')"

#---- wwan
_led_wwan=""


case "$platform" in

	ath79)
		case  "$boardname" in
			"ubnt,unifi")	_led_wifi2g="ubnt:orange:dome"
					_led_status="ubnt:green:dome"
					;;
			"gl-mifi") 	_led_wwan="$(uci -q get system.led_wwan.sysfs)"
				 	test -z "$_led_wwan" && _led_wwan="gl-mifi:green:net"
					_led_status="$(uci -q get system.led_wan.sysfs)"
					;;
		esac
		;;

	lantiq|ipq40xx)
		case  "$boardname" in
			*)
					_led_status="$(uci -q get system.led_dsl.sysfs)"
					;;
		esac
		;;
esac

echo "_led_status: $_led_status"
echo "_led_wifi2g: $_led_wifi2g"
echo "_led_wifi5g: $_led_wifi5g"
echo "_led_wwan: $_led_wwan"

case "$ARG_LED" in
	wifi)
		case "$(uci -q get ddmesh.led.wifi)" in
			on)	ARG_CMD="on" ;;
			off)	ARG_CMD="off" ;;
		esac

		if [ -n "$_led_wifi2g" ]; then
			case $ARG_CMD in
				off)
					led_off $_led_wifi2g
					;;
				on)
					led_on $_led_wifi2g
					;;
				alive)
					led_timer $_led_wifi2g 30 1000
					;;
				freifunk)
					led_timer $_led_wifi2g 200 200
					;;
				gateway)
					led_timer $_led_wifi2g 60 60
					;;
			esac
		fi
		if [ -n "$_led_wifi5g" ]; then
			case $ARG_CMD in
				off)
					led_off $_led_wifi5g
					;;
				on)
					led_on $_led_wifi5g
					;;
				alive)
					led_timer $_led_wifi5g 30 1000
					;;
				freifunk)
					led_timer $_led_wifi5g 200 200
					;;
				gateway)
					led_timer $_led_wifi5g 60 60
					;;
			esac
		fi
		;;
	status)
		case "$(uci -q get ddmesh.led.status)" in
			on)	ARG_CMD="on" ;;
			off)	ARG_CMD="off" ;;
		esac

		if [ -n "$_led_status" ]; then
			case $ARG_CMD in
				boot1) 	led_timer $_led_status 50 50
					;;
				boot2)	led_timer $_led_status 100 100
					;;
				boot3)	led_timer $_led_status 150 150
					;;
				done|off)  led_off $_led_status
					;;
				on)	led_on $_led_status
					;;
			esac
		fi
		;;
	wwan)
		case "$(uci -q get ddmesh.led.wwan)" in
			on)	ARG_CMD="on" ;;
			off)	ARG_CMD="off" ;;
		esac

		if [ -n "$_led_wwan" ]; then
			case $ARG_CMD in
				off)
					led_off $_led_wwan
					;;
				on)
					led_on $_led_wwan
					;;
				2g)
					led_timer $_led_wwan 1000 1000
					;;
				3g)
					led_timer $_led_wwan 300 200
					;;
				4g)
					led_timer $_led_wwan 40 40
					;;
			esac
		fi
		;;

	*)	echo "invalid param"
		;;
esac
