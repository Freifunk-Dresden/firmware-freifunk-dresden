#!/bin/ash

if [ -z "$1" ]; then
	echo "ddmesh-led.sh <type> <value>"
	echo "	type: wifi | status"
	echo "	value	wifi: off|alive|freifunk|gateway"
	echo "	status: boot1|boot2|boot3|done"
	exit 0
fi

eval $(cat /etc/openwrt_release)
platform="${DISTRIB_TARGET%/*}"

case "$platform" in

	ar71xx)
		. /lib/functions/leds.sh
		. /etc/diag.sh
		. /lib/ar71xx.sh
		;;
	*)
		echo "platform $platform not supported"
		exit 1
esac


get_wifi_led()
{
	case  $(ar71xx_board_name) in
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
			boot1) 	led_morse $status_led 200 'e '
				;;
			boot2)	led_morse $status_led 200 'ee '
				;;
			boot3)	led_morse $status_led 200 'eee '
				;;
			done)
				case  $(ar71xx_board_name) in
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

