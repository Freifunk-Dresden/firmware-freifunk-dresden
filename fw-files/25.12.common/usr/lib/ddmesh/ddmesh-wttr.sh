#!/bin/sh

SYSINFO_MOBILE_GEOLOC=/var/geoloc-mobile.json
CHECK_IP='8.8.8.8'

case "$(uci -q get ddmesh.system.node_type)" in
        node)   node_type="node" ;;
        mobile) node_type="mobile" ;;
        server) node_type="server" ;;
        *) node_type="node";;
esac

if [ $node_type = "mobile" -a -f "$SYSINFO_MOBILE_GEOLOC" ]; then
        eval $(cat $SYSINFO_MOBILE_GEOLOC | jsonfilter \
                -e gps_lat='@.location.lat' \
                -e gps_lng='@.location.lng' )
        gps_alt=0
else
        gps_lat=$(uci -q get ddmesh.gps.latitude)
        gps_lng=$(uci -q get ddmesh.gps.longitude)
        gps_alt=$(uci -q get ddmesh.gps.altitude)
fi
gps_lat=$(printf '%f' ${gps_lat:=0} 2>/dev/null)
gps_lng=$(printf '%f' ${gps_lng:=0} 2>/dev/null)
gps_alt=$(printf '%d' ${gps_alt:=0} 2>/dev/null)

# hide gps address
case "$1" in
	-url) echo "https://wttr.in/${gps_lat},${gps_lng}.png?nAQF1&background=404040" ;;
	-term) ip ro get ${CHECK_IP} >/dev/null 2>/dev/null && wget -T 1 -q -O - https://wttr.in/${gps_lat},${gps_lng}?nAQF0 2>/dev/null;;
	*) echo "$(basename $0) [-url | -term]" ;;
esac
