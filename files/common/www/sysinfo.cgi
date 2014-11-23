#!/bin/sh

echo 'Content-type: text/plain txt'
echo ''

BMXD_DB_PATH=/var/lib/ddmesh/bmxd
eval $(/usr/bin/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))
test -z "$_ddmesh_node" && exit

eval $(ddmesh_ipcalc.sh -n $ddmesh_node -e)

#node info
contact_name="$(uci get ddmesh.contact.name)"
contact_loc="$(uci get ddmesh.contact.location)"
contact_mail="$(uci get ddmesh.contact.email)"
contact_note="$(uci get ddmesh.contact.note)"
echo c:Dresden,$_ddmesh_node,$_ddmesh_domain,$_ddmesh_ip,$(uci get ddmesh.gps.longitude),$(uci get ddmesh.gps.latitude),$(uci get ddmesh.gps.altitude),$contact_name,$contact_loc,$contact_mail,$contact_note

#routes
ip route list table bat_route | sed 's#\(.*\)#R:\1#'
ip route list table bat_hna | sed 's#\(.*\)#H:\1#'
ip route list table bat_default | sed 's#\(.*\)#T:\1#'

#gateways
#ip route list table local_gateway | grep default | sed 's#\(.*\)#G:\1#'
#ip route list table public_gateway | grep default | sed 's#\(.*\)#G:\1#'

#notes
#echo "N:$(uci get ddmesh.contact.note)"

#batmand
cat $BMXD_DB_PATH/details | sed -n '/^WARNING/ {n}; s#\(^.*$\)#B:\1#g;p'
cat $BMXD_DB_PATH/gateways | sed -n '/^WARNING/ {n}; s#\(^.*$\)#b:\1#g;p'
bmxd -ci | sed 's#^[ 	]*\(.*\)$#i:\1#'

        
