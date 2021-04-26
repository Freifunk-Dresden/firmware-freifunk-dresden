#!/bin/ash
# https://openwrt.org/docs/guide-user/base-system/led_configuration

if [ -z "$1" ]; then
	echo "ddmesh-led.sh <type> <value>"
	echo "	type: wifi | status"
	echo "	value:"
	echo "		wifi:	off|alive|freifunk|gateway"
	echo "		status: boot1|boot2|boot3|done"
	echo "		wwan:	off|2g|3g|4g"
	exit 0
fi

. /lib/functions.sh
. /lib/functions/leds.sh

eval $(cat /etc/openwrt_release)
platform="${DISTRIB_TARGET%/*}"
boardname=$(board_name) # function in function.sh

#echo "platform: $platform"
#echo "board: $boardname"

case "$platform" in

	ar71xx)
		. /etc/diag.sh
		get_status_led # /etc/diag.sh


		case  "$boardname" in
			gl-mifi) 	_led_wwan="$(uci -q get system.led_wwan.sysfs)"
				 	test -z "$_led_wwan" && _led_wwan="gl-mifi:green:net"
					_led_status="$(uci -q get system.led_wan.sysfs)"
					;;
			

			*) 		_led_wifi="$(uci -q get system.led_wlan.sysfs)"
					test -z "$_led_wifi" && _led_wifi="$(uci -q get system.led_rssimediumlow.sysfs)"
					_led_status=$status_led		
					_led_wwan=""
					;;
		esac
		;;
	
	ath79)
		case  "$boardname" in
			"ubnt,unifi")	_led_wifi="ubnt:orange:dome"
					_led_status="ubnt:green:dome"
					;;

			*) 		_led_wifi="$(uci -q get system.led_wlan.sysfs)"
					;;
		esac
		;;
		
	lantiq|ipq40xx)
		case  "$boardname" in
			*)
					for i in wifi wlan
					do
						tmp="$(ls -d /sys/class/leds/*:$i 2>/dev/null)"
						test -n "$tmp" && break
					done
					_led_wifi="$(echo $tmp | sed -n '1s#/sys/class/leds/##p')"
					_led_status="$(uci -q get system.led_dsl.sysfs)"
					;;
		esac
		;;

	ramips)
		case  "$boardname" in
			*)
					_led_wifi="$(echo /sys/class/leds/*:*:usb | sed -n '1s#/sys/class/leds/##p')"
					;;
		esac
		;;

	*)
		echo "$(basename $0): platform '$platform' not supported"
		exit 1
		;;
esac

#echo "_led_status: $_led_status"
#echo "_led_wifi: $_led_wifi"
#echo "_led_wwan: $_led_wwan"

case $1 in
	wifi)	
		case $2 in
			off)
				led_off $_led_wifi
				;;
			alive)
				led_timer $_led_wifi 30 1000
				;;
			freifunk)
				led_timer $_led_wifi 200 200
				;;
			gateway)
				led_timer $_led_wifi 60 60
				;;
		esac
		;;
	status)
		case $2 in
			boot1) 	led_timer $_led_status 30 30
				;;
			boot2)	led_timer $_led_status 60 60
				;;
			boot3)	led_timer $_led_status 110 110
				;;
			done)
				case  "$boardname" in
					"ubnt,unifi"|"gl-mifi")
						# one LED: turn green off to enable orange
						led_off $_led_status
						;;
					*)
						led_on $_led_status
						;;
				esac
				;;
		esac
		;;
	wwan)
		case $2 in
			off)
				led_off $_led_wwan
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
		;;

	*)	echo "invalid param"
		;;
esac

