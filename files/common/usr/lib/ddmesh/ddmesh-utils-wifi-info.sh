#!/bin/sh


_PRE="wifi_status"
_status="$(wifi status)"

eval $(echo "$status" | jsonfilter \
	-e "$PRE"_radio2g_up='@.radio2g.up' \
	-e "$PRE"_radio5g_up='@.radio5g.up' \
	-e _radio2g_ifname='@.radio2g.interfaces[0].ifname' \
	-e _radio5g_ifname='@.radio5g.interfaces[0].ifname' \
)

eval "$PRE"_radio2g_phy=$(iwinfo $_radio2g_ifname info | sed -n '/PHY name:/{s#.*\(phy[0-9]\)$#\1#p}')
eval "$PRE"_radio5g_phy=$(iwinfo $_radio5g_ifname info | sed -n '/PHY name:/{s#.*\(phy[0-9]\)$#\1#p}')

unset _PRE
unset _status
unset _radio2g_ifname
unset _radio5g_ifname

