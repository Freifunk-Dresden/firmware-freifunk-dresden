#!/bin/sh

export TITLE="Verwaltung > Expert >Traffic Shaping"
. /usr/lib/www/page-pre.sh ${0%/*}


if [ -n "$form_wshaper_submit" ]; then
	uci set ddmesh.network.wan_speed_up="$form_wshaper_wan_upload"
	uci set ddmesh.network.wan_speed_down="$form_wshaper_wan_download"
	uci set ddmesh.network.lan_speed_up="$form_wshaper_lan_upload"
	uci set ddmesh.network.lan_speed_down="$form_wshaper_lan_download"
	#update temp config
	uci set wshaper.wan_settings.uplink="$form_wshaper_wan_upload"
	uci set wshaper.wan_settings.downlink="$form_wshaper_wan_download"
	uci set wshaper.lan_settings.uplink="$form_wshaper_wan_upload"
	uci set wshaper.lan_settings.downlink="$form_wshaper_wan_download"
	uci commit
	/etc/init.d/wshaper restart
	notebox "Die ge&auml;nderten Einstellungen wurden &uuml;bernommen. Die Einstellungen sind erst beim n&auml;chsten <A HREF="firmware.cgi">Neustart</A> aktiv."
fi

cat<<EOM
<form name="form_wshaper" action="wshaper.cgi" method="POST">
<fieldset class="bubble">
<legend>Traffic Shaping</legend>
<table>
<tr><td colspan="2">Traffic Shaping begrenzt die Upload/Download Geschwindigkeit. Meist wird der Freifunk Router an einen anderen Router
	angeschlossen. Um im privaten Netz weiterhin gen&uuml;gend Bandbreite zur Verf&uuml;gung zu haben, kann hier der Freifunkbedarf
 	begrenzt werden.</td></tr>
EOM

eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wan)          
if [ -n "$net_device" ]; then 

cat<<EOM
<tr><th width="120">WAN-Upload-Rate:</th>
<td class="nowrap"><input name="form_wshaper_wan_upload" size="10" type="text" value="$(uci get ddmesh.network.wan_speed_up)"> kbits/s</td></tr>
<tr><th >WAN-Download-Rate:</th>
<td class="nowrap"><input name="form_wshaper_wan_download" size="10"  type="text" value="$(uci get ddmesh.network.wan_speed_down)"> kbits/s</td></tr>
EOM
fi

cat<<EOM
<tr><th width="120">LAN-Upload-Rate:</th>
<td class="nowrap"><input name="form_wshaper_lan_upload" size="10" type="text" value="$(uci get ddmesh.network.lan_speed_up)"> kbits/s</td></tr>
<tr><th >LAN-Download-Rate:</th>
<td class="nowrap"><input name="form_wshaper_lan_download" size="10"  type="text" value="$(uci get ddmesh.network.lan_speed_down)"> kbits/s</td></tr>
<TR>
	<td colspan="2" class="nowrap"><input name="form_wshaper_submit" title="Die Einstellungen &uuml;bernehmen. Diese werden erst nach einem Neustart wirksam." type="SUBMIT" value="&Uuml;bernehmen">&nbsp;&nbsp;&nbsp;<input name="form_wshaper_abort" title="Abbruch dieser Dialogseite" type="submit" value="Abbruch"></td> </tr>
</table>
</fieldset>
</form>
EOM

. /usr/lib/www/page-post.sh ${0%/*}
