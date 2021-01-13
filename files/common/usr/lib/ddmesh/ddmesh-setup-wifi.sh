#!/bin/ash

LOGGER_TAG="ddmesh-wifi"

node=$(uci get ddmesh.system.node)
setup_wireless()
{
 rm -f /etc/config/wireless
 wifi config

 #ensure we have valid country,with supportet channel and txpower
 test -z "$(uci -q get ddmesh.network.wifi_country)" && uci set ddmesh.network.wifi_country="DE"

 # update mesh_key from rom
 wifi_mesh_key="$(uci -c /rom/etc/config get credentials.network.wifi_mesh_key)"

 # --- detect 2/5GHz radios
 eval $(/usr/lib/ddmesh/ddmesh-utils-wifi-info.sh)
 test -n "$wifi_status_radio2g_config_index" && uci -q rename wireless.@wifi-device[$wifi_status_radio2g_config_index]='radio2g'
 test -n "$wifi_status_radio5g_config_index" && uci -q rename wireless.@wifi-device[$wifi_status_radio5g_config_index]='radio5g'

 # --- devices ---
 # 2.4Ghz
 uci -q delete wireless.radio2g.disabled
 uci set wireless.radio2g.hwmode="11n"
 uci set wireless.radio2g.country="$(uci -q get ddmesh.network.wifi_country)"
 uci set wireless.radio2g.channel="$(uci get ddmesh.network.wifi_channel)"
 uci set wireless.radio2g.txpower="$(uci get ddmesh.network.wifi_txpower)"

 #setup wifi rates
 uci -q delete wireless.radio2g.basic_rate
 uci -q delete wireless.radio2g.supported_rates
 if [ "$(uci -q get ddmesh.network.wifi_slow_rates)" != "1" ]; then
	uci add_list wireless.radio2g.basic_rate='6000 9000 12000 18000 24000 36000 48000 54000'
	uci add_list wireless.radio2g.supported_rates='6000 9000 12000 18000 24000 36000 48000 54000'
 fi

# wird auf HT20 gesetzt oder bei usbsticks auf nix, wenn kein support da ist.
# falsche werte sorgen fuer nicht funktionieren von wifi
 #test -z "$(uci -q get ddmesh.network.wifi_htmode)" && uci set ddmesh.network.wifi_htmode="HT20"
 #uci set wireless.radio2g.htmode="$(uci get ddmesh.network.wifi_htmode)"

 # 5 GHz
 if [ -n "$wifi_status_radio5g_up" ]; then
 	uci -q delete wireless.radio5g.disabled
 	uci set wireless.radio5g.country="$(uci -q get ddmesh.network.wifi_country)"
	if [ "$(uci -q get ddmesh.network.wifi_indoor_5g)" = "1" ]; then
		uci set wireless.radio5g.channel="$(uci -q get ddmesh.network.wifi_channel_5g)"
	else
		uci set wireless.radio5g.channel="auto"
		uci set wireless.radio5g.channels="$(uci -q get ddmesh.network.wifi_channels_5g_outdoor)"
	fi
	uci set wireless.radio5g.txpower="$(uci get ddmesh.network.wifi_txpower_5g)"
 	uci set wireless.radio5g.legacy_rates="0"
 fi

 # --- interfaces ---
 # delete all interfaces if any
 while uci -q delete wireless.@wifi-iface[0]; do true; done

 # - wifi -

 case "$(uci -q get ddmesh.network.mesh_mode)" in
	mesh)		wifi_mode_mesh=1
			wifi_mode_adhoc=1
	;;
	adhoc+mesh)	wifi_mode_mesh=1
			wifi_mode_adhoc=1
	;;
	*)		wifi_mode_mesh=0
			wifi_mode_adhoc=1
	;;
 esac

 iface=0
 if [ $wifi_mode_adhoc = 1 ]; then
 	test -z "$(uci -q get wireless.@wifi-iface[$iface])" && uci -q add wireless wifi-iface
	uci rename wireless.@wifi-iface[$iface]='wifi_adhoc'
 	uci set wireless.@wifi-iface[$iface].device='radio2g'
	uci set wireless.@wifi-iface[$iface].network='wifi_adhoc'
	uci set wireless.@wifi-iface[$iface].mode='adhoc'
	uci set wireless.@wifi-iface[$iface].ifname='mesh-adhoc'
 	uci set wireless.@wifi-iface[$iface].bssid="$(uci -q get credentials.wifi_2g.bssid)"
 	uci set wireless.@wifi-iface[$iface].encryption='none'
 	test "$(uci -q get ddmesh.network.wifi_slow_rates)" != "1" && uci set wireless.@wifi-iface[$iface].mcast_rate='6000'
 	essid="$(uci -q get ddmesh.network.essid_adhoc)"
 	essid="${essid:-Freifunk-Mesh-Net}"
 	uci set wireless.@wifi-iface[$iface].ssid="${essid:0:32}"
 	iface=$((iface + 1))
 fi

 if [ $wifi_mode_mesh = 1 ]; then
 	test -z "$(uci -q get wireless.@wifi-iface[$iface])" && uci -q add wireless wifi-iface
	uci rename wireless.@wifi-iface[$iface]='wifi_mesh2g'
 	uci set wireless.@wifi-iface[$iface].device='radio2g'
	uci set wireless.@wifi-iface[$iface].network='wifi_mesh2g'
	uci set wireless.@wifi-iface[$iface].ifname='mesh2g-80211s'
	uci set wireless.@wifi-iface[$iface].mode='mesh'
 	uci set wireless.@wifi-iface[$iface].mesh_id="$(uci -q get credentials.network.wifi_mesh_id)"
 	uci set wireless.@wifi-iface[$iface].key="$wifi_mesh_key"
 	uci set wireless.@wifi-iface[$iface].encryption='none' # key still used for authentication
 	uci set wireless.@wifi-iface[$iface].mesh_fwding='0'
 	test "$(uci -q get ddmesh.network.wifi_slow_rates)" != "1" && uci set wireless.@wifi-iface[$iface].mcast_rate='6000'
 	iface=$((iface + 1))
 fi


 # - wifi2 - 2G

 if [ "$(uci -q get ddmesh.network.custom_essid)" = "1" ]; then
	custom="$(uci -q get ddmesh.network.essid_ap)"
	if [ -n "$(echo "$custom" | sed 's#^ *$##')" ]; then
		essid2="$(uci -q get ddmesh.system.community):$(uci get ddmesh.network.essid_ap)"
		essid5="$(uci -q get ddmesh.system.community) 5GHz:$(uci get ddmesh.network.essid_ap)"
	else
		essid2="$(uci -q get ddmesh.system.community)"
		essid5="$(uci -q get ddmesh.system.community) 5GHz"
	fi
 else
	essid2="$(uci -q get ddmesh.system.community) [$node]"
	essid5="$(uci -q get ddmesh.system.community) 5GHz [$node]"
 fi

 test -z "$(uci -q get wireless.@wifi-iface[$iface])" && uci -q add wireless wifi-iface
 uci rename wireless.@wifi-iface[$iface]='wifi2_2g'
 uci set wireless.@wifi-iface[$iface].device='radio2g'
 uci set wireless.@wifi-iface[$iface].network='wifi2'
 uci set wireless.@wifi-iface[$iface].ifname='wifi2ap'
 uci set wireless.@wifi-iface[$iface].mode='ap'
 uci set wireless.@wifi-iface[$iface].encryption='none'
 isolate="$(uci -q get ddmesh.network.wifi2_isolate)"
 isolate="${isolate:-1}" #default isolate
 uci set wireless.@wifi-iface[$iface].isolate="$isolate"
 uci set wireless.@wifi-iface[$iface].ssid="${essid2:0:32}"
 test "$(uci -q get ddmesh.network.wifi_slow_rates)" != "1" && uci set wireless.@wifi-iface[$iface].mcast_rate='6000'
 #uci set wireless.@wifi-iface[$iface].wpa_disable_eapol_key_retries='1'
 #uci set wireless.@wifi-iface[$iface].tdls_prohibit='1'
 #uci set wireless.@wifi-iface[$iface].ieee80211w='1'
 iface=$((iface + 1))

 # - wifi2 - 5G

 # add 5GHz
 if [ -n "$wifi_status_radio5g_up" ]; then
	test -z "$(uci -q get wireless.@wifi-iface[$iface])" && uci add wireless wifi-iface
	uci rename wireless.@wifi-iface[$iface]='wifi2_5g'
	uci set wireless.@wifi-iface[$iface].device='radio5g'
	uci set wireless.@wifi-iface[$iface].network='wifi2'
 	uci set wireless.@wifi-iface[$iface].ifname='wifi5ap'
	uci set wireless.@wifi-iface[$iface].mode='ap'
	uci set wireless.@wifi-iface[$iface].encryption='none'
	isolate="$(uci -q get ddmesh.network.wifi2_isolate)"
	isolate="${isolate:-1}" #default isolate
	uci set wireless.@wifi-iface[$iface].isolate="$isolate"
	uci set wireless.@wifi-iface[$iface].ssid="${essid5:0:32}"
	#uci set wireless.@wifi-iface[$iface].wpa_disable_eapol_key_retries='1'
	#uci set wireless.@wifi-iface[$iface].tdls_prohibit='1'
	#uci set wireless.@wifi-iface[$iface].ieee80211w='1'
	iface=$((iface + 1))

	# 5ghz mesh only for indoor
	if [ $wifi_mode_mesh = 1 -a "$(uci -q get ddmesh.network.wifi_indoor_5g)" = "1" ]; then
 		test -z "$(uci -q get wireless.@wifi-iface[$iface])" && uci -q add wireless wifi-iface
 		uci rename wireless.@wifi-iface[$iface]='wifi_mesh5g'
	 	uci set wireless.@wifi-iface[$iface].device='radio5g'
		uci set wireless.@wifi-iface[$iface].network='wifi_mesh5g'
		uci set wireless.@wifi-iface[$iface].ifname='mesh5g-80211s'
		uci set wireless.@wifi-iface[$iface].mode='mesh'
	 	uci set wireless.@wifi-iface[$iface].mesh_id="$(uci -q get credentials.network.wifi_mesh_id)"
 		uci set wireless.@wifi-iface[$iface].key="$wifi_mesh_key"
	 	uci set wireless.@wifi-iface[$iface].encryption='none' # key still used for authentication
 		uci set wireless.@wifi-iface[$iface].mesh_fwding='0'
	 	test "$(uci -q get ddmesh.network.wifi_slow_rates)" != "1" && uci set wireless.@wifi-iface[$iface].mcast_rate='6000'
 		iface=$((iface + 1))
	fi
 fi

 # - wifi3-2g (private AP)
 if [ "$(uci -q get ddmesh.network.wifi3_2g_enabled)" = "1" -a -n "$(uci -q get credentials.wifi_2g.private_ssid)" ] && [ "$(uci -q get ddmesh.network.wifi3_2g_security)" != "1" -o -n "$(uci -q get credentials.wifi_2g.private_key)" ]; then
	test -z "$(uci -q get wireless.@wifi-iface[$iface])" && uci add wireless wifi-iface
 	uci rename wireless.@wifi-iface[$iface]='wifi2priv'
	uci set wireless.@wifi-iface[$iface].device='radio2g'
	uci set wireless.@wifi-iface[$iface].network="$(uci -q get ddmesh.network.wifi3_2g_network)"
 	uci set wireless.@wifi-iface[$iface].ifname='wifi2prv'
	uci set wireless.@wifi-iface[$iface].mode='ap'
	if [ "$(uci -q get ddmesh.network.wifi3_2g_security)" = "1" ]; then
		uci set wireless.@wifi-iface[$iface].encryption='psk2'
		uci set wireless.@wifi-iface[$iface].key="$(uci -q get credentials.wifi_2g.private_key)"
	else
		uci set wireless.@wifi-iface[$iface].encryption='none'
	fi

	uci set wireless.@wifi-iface[$iface].isolate='0'
	ssid="$(uci -q get credentials.wifi_2g.private_ssid)"
	uci set wireless.@wifi-iface[$iface].ssid="${ssid:0:32}"
	#uci set wireless.@wifi-iface[$iface].wpa_disable_eapol_key_retries='1'
	#uci set wireless.@wifi-iface[$iface].tdls_prohibit='1'
	#uci set wireless.@wifi-iface[$iface].ieee80211w='1'
	iface=$((iface + 1))
 fi

 # - wifi3-5g (private ap)
 if [ -n "$wifi_status_radio5g_up" ]; then
	if [ "$(uci -q get ddmesh.network.wifi3_5g_enabled)" = "1" -a -n "$(uci -q get credentials.wifi_5g.private_ssid)" ] && [ "$(uci -q get ddmesh.network.wifi3_5g_security)" != "1" -o -n "$(uci -q get credentials.wifi_5g.private_key)" ]; then
		test -z "$(uci -q get wireless.@wifi-iface[$iface])" && uci add wireless wifi-iface
		uci rename wireless.@wifi-iface[$iface]='wifi5priv'
		uci set wireless.@wifi-iface[$iface].device='radio5g'
		uci set wireless.@wifi-iface[$iface].network="$(uci -q get ddmesh.network.wifi3_5g_network)"
		uci set wireless.@wifi-iface[$iface].ifname='wifi5prv'
		uci set wireless.@wifi-iface[$iface].mode='ap'
		if [ "$(uci -q get ddmesh.network.wifi3_5g_security)" = "1" ]; then
			uci set wireless.@wifi-iface[$iface].encryption='psk2'
			uci set wireless.@wifi-iface[$iface].key="$(uci -q get credentials.wifi_5g.private_key)"
		else
			uci set wireless.@wifi-iface[$iface].encryption='none'
		fi

		uci set wireless.@wifi-iface[$iface].isolate='0'
		ssid="$(uci -q get credentials.wifi_5g.private_ssid)"
		uci set wireless.@wifi-iface[$iface].ssid="${ssid:0:32}"
		#uci set wireless.@wifi-iface[$iface].wpa_disable_eapol_key_retries='1'
		#uci set wireless.@wifi-iface[$iface].tdls_prohibit='1'
		#uci set wireless.@wifi-iface[$iface].ieee80211w='1'
		iface=$((iface + 1))
	fi
 fi

 uci commit
}

#boot_step is empty for new devices
boot_step="$(uci get ddmesh.boot.boot_step)"

if [ "$boot_step" = "2" -o ! -f /etc/config/wireless ];
then
	logger -s -t "$LOGGER_TAG" "update wifi config"
	setup_wireless
fi
exit 0
