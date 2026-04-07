#!/bin/ash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

delay=10	# seconds
dhcp_trigger_refresh_count=6	# refresh dhcp after x loops
uqmi_timeout_ms=1000
ping_host=8.8.8.8

lte_info_dir="/var/lib/ddmesh"
lte_info="$lte_info_dir/lte_info"

mkdir -p $lte_info_dir
wwan_device="$(uci -q get network.wwan.device)"
syslog="$(uci -q get ddmesh.network.wwan_syslog)"

# check if hw is present
if [ ! -c "$wwan_device" ]; then
	logger -s -t "lte-modem" "no LTE modem present -> exit monitor"
	exit 1
fi
logger -s -t "lte-modem" "LTE modem present"

# reconnect loop
while true
do

	# wait until netifd has brought up wwan; exit script if not up after 180s
	wait_s=10
	max_counter=18
	while true
	do
		if [ $max_counter -eq 0 ]; then
			logger -s -t "lte-modem" "LTE modem not up -> aborting"
			break
		fi

		/usr/lib/ddmesh/ddmesh-utils-network-info.sh update
		eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wwan)

		if [ "$net_up" = '1' ]; then
			logger -s -t "lte-modem" "LTE modem up -> start monitoring"
			break
		fi
		logger -s -t "lte-modem" "wait until wwan is up [$((max_counter*wait_s))]"
		sleep $wait_s
		max_counter=$((max_counter - 1))
	done


	dhcp_refresh_count=0
	while ping -c 3 -I ${net_ifname} ${ping_host}
	do
		signal="$(uqmi -t ${uqmi_timeout_ms} -s -d $wwan_device --get-signal-info)"
		status="$(uqmi -t ${uqmi_timeout_ms} -s -d $wwan_device --get-data-status)"
		pin_state="$(uqmi -t ${uqmi_timeout_ms} -s -d $wwan_device --uim-get-sim-state)"
		system_info="$(uqmi -t ${uqmi_timeout_ms} -d $wwan_device --get-system-info)"
		service="$(uqmi -t ${uqmi_timeout_ms} -s -d $wwan_device --get-serving-system)"
		phyinfo="$(uqmi -t ${uqmi_timeout_ms} -s -d $wwan_device --get-lte-cphy-ca-info)"

		eval $(echo "$system_info" | jsonfilter -e m_mcc='@.lte.mcc' -e m_mnc='@.lte.mnc')
		# https://mcc-mnc.net/
		ocode="$m_mcc:$m_mnc"
		case "${ocode}" in
			"262:01"|"262:06"|"262:78") operator="Telekom Deutschland GmbH" ;;
			"262:02"|"262:04"|"262:09") operator="Vodafone D2 GmbH" ;;
			"262:03"|"262:05"|"262:07"|"262:08"|"262:11"|"262:17"|"262:77") operator="Telefonica Germany GmbH" ;;
			"262:23") operator="Drillisch Online AG" ;;
			*) operator="$ocode" ;;
		esac


cat<<EOM > $lte_info.tmp
		{
		"signal": $signal,
		"status": $status,
		"service": $service,
		"pin_state" : $pin_state,
		"system_info" : $system_info,
		"phy_info" : $phyinfo,
		"other" : { "operator":"$operator" }
		}
EOM

		mv $lte_info.tmp $lte_info
		json="$(cat $lte_info)"
		[ "$syslog" = "1" ] && logger -t "LTE" "$json"

		# read lte status
		eval $(cat $lte_info | jsonfilter \
			-e m_type='@.signal.type' \
			-e m_rssi='@.signal.rssi' \
			-e m_rsrq='@.signal.rsrq' \
			-e m_rsrp='@.signal.rsrp' \
			-e m_snr='@.signal.snr' \
			-e m_conn='@.status' \
			-e m_mcc='@.system_info.lte.mcc' \
			-e m_mnc='@.system_info.lte.mnc' \
			-e registration='@.service.registration' \
		)

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
			kill -USR1 $(cat /var/run/udhcpc-${net_ifname}.pid)
			dhcp_refresh_count=0
		fi

		sleep $delay

	done

	# connection dead
	logger -s -t "lte-modem" "LTE modem - connection dead, re-connecting"

	ifdown wwan
	sleep 30
	ifup wwan

done
