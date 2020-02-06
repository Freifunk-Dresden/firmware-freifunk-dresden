#!/bin/sh

PRE="wifi_status"
status="$(wifi status)"

eval $(echo "$status" | jsonfilter -e "$PRE"_radio2g_up='@.radio2g.up' -e "$PRE"_radio5g_up='@.radio5g.up')

