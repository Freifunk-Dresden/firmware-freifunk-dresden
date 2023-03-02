#!/bin/sh

SYSINFO_MOBILE_GEOLOC=/var/geoloc-mobile.json

case "$(uci -q get ddmesh.system.node_type)" in
        node)   node_type="node" ;;  
        mobile) node_type="mobile" ;;
        server) node_type="server" ;;
        *) node_type="node";;
esac                             
                                  
if [ $node_type = "mobile" ]; then                      
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

case "$1" in
	png) image=".png" ;;
	*) echo "$(basename $0) [png]"
esac

wget -q -O - http://wttr.in/${gps_lat},${gps_lng}${image}?F1

