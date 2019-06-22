#!/bin/sh

json=false
env=false

case $1 in
	json)	json=true ;;
	env)	env=true ;; 
	*)
		echo "usage: $(basename $0) json | env"
		exit 1
		;;
esac

# get interfaces
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh list)

# get global status
eval $(ip link | awk '
	BEGIN{ FS="[ :]" }
	/^[0-9]:/{
		carrier=0
		if(gsub("NO-CARRIER",$5)) carrier=1
		
		if($3=="'$net_lan'") { print "carrier_lan="carrier }
		if($3=="'$net_wan'") { print "carrier_wan="carrier }
		if($3=="'$net_mesh_lan'") { print "carrier_mesh_lan="carrier }
		if($3=="'$net_mesh_wan'") { print "carrier_mesh_wan="carrier }
	}
')

status_wan="down"
[ "$carrier_wan" = "1" ] && status_wan="up"
[ "$carrier_mesh_wan" = "1" ] && status_wan="mesh up"


if $json; then
	echo -n "{"
	echo -n "\"wan\":\"$status_wan\","
else
	echo "sw_status_wan=$status_wan"
fi

# get switch status
IFS='
'
for dev in $(swconfig list | awk '{print $2}')
do
	$json && echo -n "\"lan\" : ["

	#check for switch
	if [ -n "$(swconfig dev $dev show | sed -n '/enable_vlan:[ 	]*1/p' )" ]; then
		comma=0
		for entry in $(swconfig dev $dev show | sed -n 's#.*link: port:\([0-9]\+\) link:\(.*\+\)[ ]*$#\1=\2#p')
		do
			port=${entry%%=*}
			state=${entry#*=}
			status_port="down"
			if [ ! $state = "down" ]; then
				[ "$carrier_lan" = "1" ] && status_port="$state"
				[ "$carrier_mesh_lan" = "1" ] && status_port="mesh $state"
			fi
			if $json; then
				[ $comma -eq 1 ] && echo -n ","
				echo -n "{\"$port\":\"$status_port\"}"
			else
				echo sw_status_lan_$port="$status_port"
			fi
			comma=1
		done
	else
		status_lan="down"
		[ "$carrier_lan" = "1" ] && status_lan="up"
		[ "$carrier_mesh_lan" = "1" ] && status_lan="mesh up"

		if  $json; then
			echo -n "{\"0\":\"$status_lan\"}"
		else
			echo sw_status_lan_0="$status_lan"
		fi
	fi
	$json && echo -n "]"
done

if $json; then
	echo "}"
fi


