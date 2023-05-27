#!/bin/ash

if [ -z "$1" ]; then
  echo "$(basename $0) [msg \"text\"] | update | boot | reboot | factory"
  exit 1
fi

. /lib/functions.sh
boardname=$(board_name) # function in function.sh
[ "${boardname}" = "glinet,gl-e750" ] || exit 0

TTY="/dev/ttyS0"
sysinfo=/tmp/sysinfo.json

eval $(/usr/lib/ddmesh/ddmesh-utils-wifi-info.sh)
eval $(ddmesh-utils-network-info.sh lan lan)

#echo '{ "ssid_5g": "GL-E750-719", "up_5g": "1", "key_5g": "goodlife", "ssid": "GL-E750-719
#", "up": "1",
#"key": "goodlife", "work_mode": "Router", "lan_ip": "192.168.82.1",  "vpn_status": "connected", "vpn_type"
#: "openvpn", "vpn_server": "Gateway: [12345]", "clients": "5", "clock": "'$(date +"%H:%M")'",
#"mcu_status": "1" , "signa
#l": "4", "modem_mode": "4G", "carrier": "Freifunk Dresden", "SIM": "0" , "modem_up": "1", ", "msg": "Freifunk Dresden 10
#.200.123.123 Searching...x" }'

# $(uci -q get ddmesh.system.mesh_network_id)

update()
{
  eval $(cat ${sysinfo} | jsonfilter \
      -e gateway_ip='@.data.bmxd.gateways.selected' \
      -e community='@.data.common.community' \
      -e clients2g='@.data.statistic.client2g["15min"]' \
      -e clients5g='@.data.statistic.client5g["15min"]' \
        )

  json="{ "
  json="${json} \"ssid\": \"$(uci get wireless.wifi2_2g.ssid)\","
  json="${json} \"up\": \"${wifi_status_radio2g_up}\","
  json="${json} \"ssid_5g\": \"$(uci get wireless.wifi2_5g.ssid)\","
  json="${json} \"up_5g\": \"${wifi_status_radio5g_up}\","
  json="${json} \"key\": \"no-key\","
  json="${json} \"key_5g\": \"no-key\","

  json="${json} \"work_mode\": \"Router\","
  json="${json} \"lan_ip\": \"${lan_ipaddr}\","

  #get gateway
  if [ -n "$gateway_ip" ]; then
    json="${json} \"vpn_status\": \"connected\","
    json="${json} \"vpn_server\": \"Node: $(/usr/lib/ddmesh/ddmesh-ipcalc.sh $gateway_ip)\","
    #json="${json} \"vpn_type\": \"\","
  else
    json="${json} \"vpn_status\": \"connecting\","  |
    json="${json} \"vpn_server\": \"local/none\","
  fi

  json="${json} \"clients\": \"$((clients2g + clients5g))\","
  json="${json} \"clock\": \"$(date +"%H:%M")\","

  # read lte status
  lte_info_dir="/var/lib/ddmesh"
  lte_info="$lte_info_dir/lte_info"
  signal=0
  if [ -f "$lte_info" ]; then
    eval $(cat $lte_info | jsonfilter -e m_type='@.signal.type' \
            -e m_rssi='@.signal.rssi' -e m_rsrq='@.signal.rsrq' \
            -e m_rsrp='@.signal.rsrp' -e m_snr='@.signal.snr' \
            -e m_conn='@.status' -e m_reg='@.registration')


    case "$m_type" in
      lte)    m_type="4G" ;;
      wcdma)  m_type="3G" ;;
      gsm)    m_type="2G" ;;
      *)  m_type="" ;;
    esac
    json="${json} \"modem_mode\": \"$m_type\","

    signal=4
    test $m_rssi -lt -60 && signal=3
    test $m_rssi -lt -70 && signal=2
    test $m_rssi -lt -80 && signal=1
    test $m_rssi -lt -90 && signal=0
    json="${json} \"signal\": \"${signal}\","

    if [ "$m_conn" = "connected" ]; then
      json="${json} \"modem_up\": \"1\","
    else
      json="${json} \"modem_up\": \"0\","
    fi

    case "$m_reg" in
      registered) sim="0" ;;
      searching) sim="NO_REG" ;;
      *) sim="NO_SIM" ;;
    esac
    json="${json} \"SIM\": \"${sim}\","

  else
    json="${json} \"modem_up\": \"0\","
    json="${json} \"SIM\": \"NO_SIM\","
  fi

  json="${json} \"carrier\": \"$(printf '%.16s' "${community}")\","

  json="${json} \"\": \"\","
  json="${json} \"\": \"\","
  json="${json} \"\": \"\","
  json="${json} \"\": \"\","
  json="${json} \"\": \"\","
  json="${json} \"\": \"\","
  json="${json} \"\": \"\","
  json="${json} \"\": \"\","
  json="${json} \"\": \"\","

  #json="${json} \"mcu_status\": \"1\""
  json="${json} }"
  # echo "${json}" > ${TTY} ; cat ${TTY}
  echo "${json}" > ${TTY}
}

msg()
{
  message="$1"
  json="{ \"msg\": \"$(printf "%.64s" "${message}")\" }"
  echo "${json}" > ${TTY}
}

system()
{
  mode="$1"
  json="{ \"system\": \"${mode}\" }"
  echo "${json}" > ${TTY}
}

case "$1" in
  msg) msg "$2" ;;
  update) update ;;
  boot) system "boot" ;;
  reboot) system "reboot" ;;
  factory) system "reft" ;;
  *) echo "invalid command" ;;
esac