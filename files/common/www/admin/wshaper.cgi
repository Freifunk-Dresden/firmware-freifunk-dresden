#!/bin/sh

export TITLE="Verwaltung > Konfiguration > Bandbreiten Einstellungen (Traffic Shaping)"

. /usr/lib/www/page-pre.sh ${0%/*}


if [ -n "$form_wshaper_submit" ]; then
	uci set ddmesh.network.speed_up="${form_wshaper_upload:=0}"
	uci set ddmesh.network.speed_down="${form_wshaper_download:=0}"
	uci set ddmesh.network.speed_network="${form_wshaper_network:=0}"
	uci set ddmesh.network.speed_enabled="${form_wshaper_enabled:=0}"

	#update temp config
	uci set wshaper.settings.uplink="$form_wshaper_upload"
	uci set wshaper.settings.downlink="$form_wshaper_download"
	uci set wshaper.settings.network="$form_wshaper_network"

	uci_commit.sh
	/etc/init.d/wshaper restart
	notebox "Die Einstellungen wurden &uuml;bernommen. Die Einstellungen sind sofort aktiv."
fi

cat<<EOM
<form name="form_wshaper" action="wshaper.cgi" method="POST">
<fieldset class="bubble">
<legend>Traffic-Shaping</legend>
<table>
<tr><td colspan="2">Traffic-Shaping begrenzt die Upload-/Download-Geschwindigkeit.
	Meist wird der Freifunk-Router an einen anderen Router
	angeschlossen &ndash; um im privaten Netz weiterhin gen&uuml;gend Bandbreite zur Verf&uuml;gung zu haben,
	kann hier der Freifunk-Bedarf begrenzt werden.</td></tr>
<tr><td width="120" colspan="2">&nbsp;</td></tr>
EOM

speed_network="$(uci get ddmesh.network.speed_network)"
speed_network=${speed_network:-lan}

if [ "$wan_iface_present" = "1" -a "$speed_network" = "wan" ]; then
	checked_wan='checked="checked"'
else
	checked_lan='checked="checked"'
fi

if [ "$(uci get ddmesh.network.speed_enabled)" = "1" ]; then
	speed_enabled='checked="checked"'
fi

cat<<EOM
<tr><th class="nowrap">Traffic-Shaping einschalten:</th><td><input name="form_wshaper_enabled" type="checkbox" value="1" $speed_enabled ></td></tr>
<tr><th width="120" colspan="1">Gateway-Netzwerk:</th>
<td class="nowrap">
EOM

if [ "$wan_iface_present" = "1" ]; then
cat<<EOM
<input name="form_wshaper_network" type="radio" value="wan" $checked_wan>WAN
EOM
fi

cat<<EOM
<input name="form_wshaper_network" type="radio" value="lan" $checked_lan>LAN
</td></tr>
<tr><td width="120" colspan="2">&nbsp;</td></tr>
EOM

cat<<EOM
<tr><th width="120">Upload-Rate (ausgehend):</th>
<td class="nowrap"><input name="form_wshaper_upload" size="10" type="text" value="$(uci get ddmesh.network.speed_up)"> kbits/s (z. B.: 5000)</td></tr>
<tr><th>Download-Rate (ankommend):</th>
<td class="nowrap"><input name="form_wshaper_download" size="10"  type="text" value="$(uci get ddmesh.network.speed_down)"> kbits/s (z. B.: 200000)</td></tr>
<tr><td colspan="2">(Die Datenraten werden aus Sicht des Routers angegeben.)</td></tr>
<tr><td width="120" colspan="2">&nbsp;</td></tr>
<tr><td colspan="2" class="nowrap"><input name="form_wshaper_submit" title="Einstellungen &uuml;bernehmen. Diese werden erst nach einem Neustart wirksam." type="SUBMIT" value="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<input name="form_wshaper_abort" title="Abbrechen und &Auml;nderungen verwerfen." type="submit" value="Abbrechen"></td></tr>
</table>
</fieldset>
</form>
EOM

. /usr/lib/www/page-post.sh ${0%/*}
