#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

delay=10	# seconds
dhcp_trigger_refresh_count=6	# refresh dhcp after x loops

lte_info_dir="/var/lib/ddmesh"
lte_info="$lte_info_dir/lte_info"

mkdir -p $lte_info_dir
wwan_device="$(uci -q get network.wwan.device)"
syslog="$(uci -q get ddmesh.network.wwan_syslog)"

dhcp_refresh_count=0
while true;
do

	# kill is needed to avoid deadlocks
	killall uqmi 2>/dev/null

	signal="$(uqmi -s -d $wwan_device --get-signal-info)"
	status="$(uqmi -s -d $wwan_device --get-data-status)"
	pin_state="$(uqmi -s -d $wwan_device --uim-get-sim-state)"
	system_info="$(uqmi -d $wwan_device --get-system-info)"
	service="$(uqmi -s -d $wwan_device --get-serving-system)"

cat<<EOM > $lte_info.tmp
	{
	"signal": $signal,
	"status": $status,
	"service": $service,
	"pin_state" : $pin_state,
	"system_info" : $system_info
	}
EOM
	mv $lte_info.tmp $lte_info
	json="$(cat $lte_info)"
	[ "$syslog" = "1" ] && logger -t "LTE" "$json"

	# read lte status
	eval $(cat $lte_info | jsonfilter -e m_type='@.signal.type' -e m_rssi='@.signal.rssi' -e m_rsrq='@.signal.rsrq' -e m_rsrp='@.signal.rsrp' -e m_snr='@.signal.snr' -e m_conn='@.status' -e registration='@.service.registration')

	if [ "$m_conn" = "connected" -a "$registration" = "registered" ]; then
		case "$m_type" in
			gsm) /usr/lib/ddmesh/ddmesh-led.sh wwan 2g ;;
			wcdma) /usr/lib/ddmesh/ddmesh-led.sh wwan 3g ;;
			lte) /usr/lib/ddmesh/ddmesh-led.sh wwan 4g ;;
			*) /usr/lib/ddmesh/ddmesh-led.sh wwan off ;;
		esac
	else
		/usr/lib/ddmesh/ddmesh-led.sh wwan off
	fi

	dhcp_refresh_count=$((dhcp_refresh_count + 1))
	if [ $dhcp_refresh_count -gt $dhcp_trigger_refresh_count ];then
		kill -USR1 $(cat /var/run/udhcpc-wwan0.pid)
		dhcp_refresh_count=0
	fi

	sleep $delay
done
