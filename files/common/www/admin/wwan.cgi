#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Konfiguration: WWAN"
. /usr/lib/www/page-pre.sh ${0%/*}

# wwan interface present?
if [ "$wwan_iface_present" = "1" ]; then

if [ -z "$QUERY_STRING" ]; then

# read lte status
lte_info_dir="/var/lib/ddmesh"
lte_info="$lte_info_dir/lte_info"
if [ -f "$lte_info" ]; then
	eval $(cat $lte_info | jsonfilter -e m_type='@.signal.type' \
		-e m_rssi='@.signal.rssi' -e m_rsrq='@.signal.rsrq' \
		-e m_rsrp='@.signal.rsrp' -e m_snr='@.signal.snr' \
		-e m_conn='@.status' -e m_reg='@.service.registration' \
		-e m_pin1_status='@.pin_state.pin1_status' \
		-e m_pin1_verify_tries='@.pin_state.pin1_verify_tries' \
		-e m_pin1_unlock_tries='@.pin_state.pin1_unlock_tries' \
		-e m_roaming='@.system_info.lte.roaming_status'
	)

	gif=5
	test $m_rssi -lt -60 && gif=4
	test $m_rssi -lt -65 && gif=3
	test $m_rssi -lt -76 && gif=2
	test $m_rssi -lt -88 && gif=1
	test $m_rssi -lt -95 && gif=0
else
	gif=0
fi

cat<<EOM
<fieldset class="bubble">
<legend>WWAN-Einstellungen</legend>
<table>
<tr><th>WANN-Protokoll:</th><td>DHCP</td></tr>
<tr><th>WAN-IP:</th><td>$wwan_ipaddr</td></tr>
<tr><th>WAN-Netzmaske:</th><td>$wwan_netmask</td></tr>
<tr><th>WAN-Broadcast:</th><td>$wwan_broadcast</td></tr>
<tr><th>WAN-Gateway:</th><td>$wwan_gateway</td></tr>
<tr><th>WAN-DNS-IP:</th><td>$wwan_dns</td></tr>
</table>
</fieldset>
<br/>
<fieldset class="bubble">
<legend>Signal-Information</legend>
<table>
<tr><th>Type</th><td>$m_type</td></tr>
<tr><th>RSSI</th><td><img src="/images/power$gif.png"> $m_rssi</td></tr>
<tr><th>RSRQ</th><td>$m_rsrq</td></tr>
<tr><th>RSRP</th><td>$m_rsrp</td></tr>
<tr><th>SNR</th><td>$m_snr</td></tr>
<tr><th>Connection</th><td>$m_conn</td></tr>
<tr><th>Registration</th><td>$m_reg</td></tr>
<tr><th>Roaming</th><td>$m_roaming</td></tr>
</table>
</fieldset>

EOM

	if [ -n "$wwan_error" ]; then
cat <<EOM
<fieldset class="bubble">
<legend>Fehler-Information</legend>
		$(notebox "$wwan_error")
</fieldset>
EOM
	fi

wwan_apn="$(uci -q get ddmesh.network.wwan_apn)"
wwan_pincode="$(uci -q get ddmesh.network.wwan_pincode)"

cat<<EOM
<form action="wwan.cgi" method="POST">
<fieldset class="bubble">
<legend>Mobile SIM Karte - Einstellungen</legend>
<table>

<tr><th>APN:</th><td><input name="form_wwan_apn" size="30" type="text" value="$wwan_apn"> </td></tr>
<tr><th>Pin 1:</th> <td> <input name="form_wwan_pincode" size="30" type="text" value="$wwan_pincode"></td></tr>
<tr><th></th><td><b>Achtung:</b> Pin wird nicht gepr&uuml;ft. Eine falsche PIN kann die SIM-Karte sperren. Dann muss die Karte in einem Mobiltelefon entsperrt werden.<br>
PIN kann vorher im Smartphone deaktiviert werden.
</td></tr>
<tr><td COLSPAN="2">&nbsp;</td></tr>
<tr><th>Status:</th><td>$m_pin1_status</td></tr>
<tr><th>Versuche:</th><td>$m_pin1_verify_tries</td></tr>
<tr><td COLSPAN="2">&nbsp;</td></tr>

<tr> <td COLSPAN="2">
<input name="form_submit" title="Die Einstellungen &uuml;bernehmen. Diese werden erst nach einem Neustart wirksam." type="SUBMIT" value="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;
<input name="form_abort" title="Abbruch dieser Dialogseite" type="SUBMIT" value="Abbruch"></td> </tr>

</table>
</fieldset>
</form>
EOM

else # query

	if [ -n "$form_submit" ]; then
		uci set ddmesh.network.wwan_apn="$(uhttpd -d "$form_wwan_apn")"
		uci set ddmesh.network.wwan_pincode="$(uhttpd -d "$form_wwan_pincode")"
		uci set ddmesh.boot.boot_step=2
		uci commit
		notebox "Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst beim n&auml;chsten <A HREF="reset.cgi">Neustart</A> aktiv."
	fi
fi # query

fi # iface present

. /usr/lib/www/page-post.sh ${0%/*}
