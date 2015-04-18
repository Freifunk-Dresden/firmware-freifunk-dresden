#!/bin/ash


# pre defined led states
# ddmesh-led.sh <type> <value>
# type: wifi | status
# value	wifi: off|alive|freifunk|gateway
#	status: boot1|boot2|boot3|done

get_wlan_led()
{
 wlan_led="$(uci show system.system 2>/dev/null | sed -n '/system.led_wlan.*\.sysfs=/s#.*=\(.*\)$#\1#p')"
 test -z "$wlan_led" && wlan_led="$(uci show system.system 2>/dev/null | sed -n '/system.led_rssimediumlow.*\.sysfs=/s#.*=\(.*\)$#\1#p')"
}

. /lib/functions/leds.sh
. /etc/diag.sh
get_status_led
get_wlan_led

case $1 in
	wifi)
		case $2 in
			off)
				led_off $wlan_led
				;;
			alive)
				led_timer $wlan_led 30 1000
				;;
			freifunk)
				led_timer $wlan_led 200 200
				;;
			gateway)
				led_timer $wlan_led 60 60
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
			done)	led_on $status_led
				;;
		esac
		;;
esac

