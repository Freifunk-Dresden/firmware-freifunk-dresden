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

eval $(cat /etc/openwrt_release)
platform="${DISTRIB_TARGET%/*}"
boardname="none"

case "$platform" in

	ar71xx)
		. /etc/diag.sh
		boardname=$(board_name) # function in function.sh
		;;
	*)
		echo "$(basename $0): platform '$platform' not supported"
		exit 1
esac

#echo "platform: $platform"
#echo "board: $boardname"

wifi_led_inverted=0
get_wifi_led()
{
	case  "$boardname" in
		unifi)
			wifi_led="ubnt:orange:dome"
			;;
		jt-or750i)
			wifi_led=$status_led
			wifi_led_inverted=1
			;;
		*)
			wifi_led="$(uci -q get system.led_wlan.sysfs)"
			test -z "$wifi_led" && wifi_led="$(uci -q get system.led_rssimediumlow.sysfs)"
			;;
	esac
}

get_wwan_led()
{
	case  "$boardname" in
		gl-mifi)
			wwan_led="$(uci -q get system.led_wwan.sysfs)"
			test -z "$wwan_led" && wwan_led="gl-mifi:green:net"
			;;
		*)
			wwan_led=""
			;;
	esac
}
get_status_led # /etc/diag.sh
get_wifi_led
get_wwan_led

#echo "status-led: $status_led"
#echo "wifi-led: $wifi_led"
#echo "wwan-led: $wwan_led"

case $1 in
	wifi)	# direct
		if [ "$wifi_led_inverted" = 0 ]; then
			case $2 in
				off)
					led_off $wifi_led
					;;
				alive)
					led_timer $wifi_led 30 1000
					;;
				freifunk)
					led_timer $wifi_led 200 200
					;;
				gateway)
					led_timer $wifi_led 60 60
					;;
			esac
		else
			case $2 in
				off)
					led_on $wifi_led
					;;
				alive)
					led_timer $wifi_led 1000 30
					;;
				freifunk)
					led_timer $wifi_led 200 200
					;;
				gateway)
					led_timer $wifi_led 60 60
					;;
			esac
		fi
		;;
	status)
		case $2 in
			boot1) 	led_timer $status_led 30 30
				;;
			boot2)	led_timer $status_led 60 60
				;;
			boot3)	led_timer $status_led 110 110
				;;
			done)
				case  "$boardname" in
					unifi)
						# one LED: turn green off to enable orange
						led_off $status_led
						;;
					*)
						led_on $status_led
						;;
				esac
				;;
		esac
		;;
	wwan)
		case $2 in
			off)
				led_off $wwan_led
				;;
			2g)
				led_timer $wwan_led 1000 1000
				;;
			3g)
				led_timer $wwan_led 300 200
				;;
			4g)
				led_timer $wwan_led 40 40
				;;
		esac
		;;
esac
