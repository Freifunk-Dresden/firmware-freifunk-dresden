#!/bin/sh


prefix="wifi_status"
status="$(wifi status)"

eval $(echo "$status" | jsonfilter \
	-e _radio2g_up='@.radio2g.up' \
	-e _radio5g_up='@.radio5g.up' \
	-e _radio2g_ifname='@.radio2g.interfaces[0].ifname' \
	-e _radio5g_ifname='@.radio5g.interfaces[0].ifname' \
)

_radio2g_phy=$(iwinfo $_radio2g_ifname info | sed -n '/PHY name:/{s#.*\(phy[0-9]\)$#\1#p}')
_radio5g_phy=$(iwinfo $_radio5g_ifname info | sed -n '/PHY name:/{s#.*\(phy[0-9]\)$#\1#p}')

echo export $prefix"_radio2g_up"="$_radio2g_up"
echo export $prefix"_radio2g_phy"="$_radio2g_phy"
echo export $prefix"_radio5g_up"="$_radio5g_up"
echo export $prefix"_radio5g_phy"="$_radio5g_phy"
