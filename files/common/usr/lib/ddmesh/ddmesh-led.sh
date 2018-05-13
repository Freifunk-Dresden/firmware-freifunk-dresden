#!/bin/ash

if [ -z "$1" ]; then
	echo "ddmesh-led.sh <type> <value>"
	echo "	type: wifi | status"
	echo "	value	wifi: off|alive|freifunk|gateway"
	echo "	status: boot1|boot2|boot3|done"
	exit 0
fi

. /lib/functions.sh

eval $(cat /etc/openwrt_release)
platform="${DISTRIB_TARGET%/*}"
boardname="none"

case "$platform" in

	ar71xx)
		. /etc/diag.sh
		ar71xx_board_detect
		boardname=$AR71XX_BOARD_NAME
		;;
	*)
		echo "$(basename $0): platform '$platform' not supported"
		exit 1
esac

echo "platform: $platform"
echo "board: $boardname"

get_wifi_led()
{
	case  "$boardname" in
		unifi)
			wifi_led=ubnt:orange:dome
			;;
		*)
			led="$(uci show system 2>/dev/null | sed -n '/system.led_wlan.*\.sysfs=/s#.*=\(.*\)$#\1#p')"
			test -z "$led" && led="$(uci show system 2>/dev/null | sed -n '/system.led_rssimediumlow.*\.sysfs=/s#.*=\(.*\)$#\1#p')"
			wifi_led=$(echo $led | sed s#\'##g)
			;;
	esac
}

get_status_led
get_wifi_led

echo "status-led: $status_led"
echo "wifi-led: $wifi_led"

case $1 in
	wifi)
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
esac

