#!/bin/ash

# determines ip address/country for ipv6 and ipv4 of running openvpn (dev vpn)
# information was extracted from url that is used in http://ipv6-test.com/api/:
# http://ipv6-test.com/api/widget.php

. /usr/share/libubox/jshn.sh

DATA=/var/lib/ddmesh/tunnel_info

eval $(ip ro list ta public_gateway | sed -n 's#default.*[ ]\([0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\) dev \([^ ]\+\).*#via=\1; dev=\2#p')
test -z "$via" && exit 0

if [ -f $DATA -a "$1" = "cache" ]; then
	cat $DATA
	exit 0
fi

ip4=$(nslookup v4.ipv6-test.com | sed '1,4d;s#.*: \(.*\) .*#\1#')
#ip6=$(nslookup v6.ipv6-test.com | sed '1,4d;s#.*: \(.*\) .*#\1#')

test -n "$ip4" && {

 ip rule add prio 200 to $ip4 table public_gateway
 ip route add $ip4 via $via dev $dev table public_gateway
 
 v4="$(wget -O - http://v4.ipv6-test.com/json/widgetdata.php 2>/dev/null | sed -n 's#(\(.*\))#\1#p')"
 #v6="$(wget -O - http://v6.ipv6-test.com/json/widgetdata.php 2>/dev/null | sed -n 's#(\(.*\))#\1#p')"

 ip rule del prio 200 to $ip4 table public_gateway
 ip route del $ip4 via $via dev $dev table public_gateway

> $DATA

 test -n "$v4" && {
  json_load "$v4"
  json_get_var country4 "country"
  json_get_var country_code4 "country_code"
  json_get_var address4 "address"
  img4="http://ipv6-test.com/img/flags-round/${country_code4}.png"
  
  echo "iptest_address4=\"$address4\""
  echo "iptest_country4=\"$country4\""
  echo "iptest_country_code4=\"$country_code4\""
  echo "iptest_imgurl4=\"$img4\""
 } >> $DATA

 test -n "$v6" && {
  json_load "$v6"
  json_get_var country6 "country"
  json_get_var country_code6 "country_code"
  json_get_var address6 "address"
  img6="http://ipv6-test.com/img/flags-round/${country_code6}.png"
  
  echo "iptest_address6=\"$address6\""
  echo "iptest_country6=\"$country6\""
  echo "iptest_country_code6=\"$country_code6\""
  echo "iptest_imgurl6=\"$img6\""
 } >> $DATA
}

cat $DATA
