#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

# https://openwrt.org/docs/guide-user/base-system/led_configuration

. /lib/functions.sh
. /lib/functions/leds.sh

eval $(cat /etc/openwrt_release)
platform="${DISTRIB_TARGET%/*}"
boardname=$(board_name) # function in function.sh

echo "platform: $platform"
echo "board: $boardname"

ARG_LED="$1"
ARG_CMD="$2"

# try to detect led (keep order)
eval $(/usr/lib/ddmesh/ddmesh-utils-wifi-info.sh)

#---- wifi2g
# "link2" nanostation
for i in wifi wlan wifi2g wlan2g link2 ${wifi_status_radio2g_phy} usb
do
	tmp="$(ls -d /sys/class/leds/*${i} 2>/dev/null | sed -n '1p')"
	test -n "$tmp" && break
done
_led_wifi2g="$(echo $tmp | sed -n '1s#/sys/class/leds/##p')"

#---- wifi5g
for i in wifi5g wlan5g ${wifi_status_radio5g_phy}
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
# default "done" = on
_led_flag_status_done="on"

#---- wwan
_led_wwan=""

case "$platform" in
	ath79)
		case  "$boardname" in
			"ubnt,unifi")
					_led_wifi2g="orange:dome"
					_led_status="green:dome"
					;;
			"glinet,gl-mifi")
					_led_wwan="$(uci -q get system.led_3gnet.sysfs)"
					_led_status="$(uci -q get system.led_wan.sysfs)"
					;;
			"tplink,eap225-outdoor-v1")
					_led_wifi2g="green:status"
					_led_wifi5g=""
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

	ramips)
		case  "$boardname" in
			"xiaomi,mi-router-4a-gigabit")
					_led_wifi2g="blue:status"
					_led_wifi5g=""
					_led_status="yellow:status"
					_led_flag_status_done="off"
					;;
		esac
		;;
esac

echo "LED status: $_led_status"
echo "LED wifi2g: $_led_wifi2g"
echo "LED wifi5g: $_led_wifi5g"
echo "LED wwan: $_led_wwan"

if [ -z "$ARG_CMD" ]; then
	echo ""
	echo "ddmesh-led.sh <type> <value>"
	echo "	type: wifi | status | wwan"
	echo "	value:"
	echo "		wifi:	off|on|alive|freifunk|gateway"
	echo "		status: boot1|boot2|boot3|done|off|on"
	echo "		wwan:	off|on|2g|3g|4g"
	exit 0
fi

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
				off)	led_off $_led_status
					;;
				on)	led_on $_led_status
					;;
				done)
					if [ "${_led_flag_status_done}" = "on" ]; then
						led_on $_led_status
					else
						led_off $_led_status
					fi
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
