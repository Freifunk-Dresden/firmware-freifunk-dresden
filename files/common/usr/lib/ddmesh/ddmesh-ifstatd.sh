#/bin/sh

#run as "deamon" to detect ethernet cable carrier changes
#for each interface change, process is called with
#   "interface" <interface> <state>
#   "network" <network> <state>  

process()
{
 # $1 - type (interface oder network)
 # $2 - ifname
 # $3 - state
 # $4 - network (if type is network)
 
# echo "process: type=$1, if=$2, state=$3, network=$4"
 test "$ddmesh_hotplug_type" = "network" && logger -t "ddmesh_hotplug" "type:$ddmesh_hotplug_type, ifname=$ddmesh_hotplug_ifname, state=$ddmesh_hotplug_state, network=$ddmesh_hotplug_network"
 IFS='
'
 for hps in $(ls -1 /etc/ddmesh.hotplug.d/* | sort)
 do
 	export ddmesh_hotplug_type=$1
 	export ddmesh_hotplug_ifname=$2
 	export ddmesh_hotplug_state=$3
 	export ddmesh_hotplug_network=$4
 	$hps $1 $2 $3 $4
 done
  
}

update ()
{
 # $1 - if not empty, process data

 # speed-up; build lookup network->interface
 # only use interfaces that are "ubus: up", because those have an IP (needed for iptables rules)
 networks=""
 interfaces=""
 IFS='
'
 for network in $(ubus list | sed -n '/network.interface./s#.\+\.##p')
 do
	eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh $network)
	# only interfaces that have one real interface (e.g:no vpn+)
	if [ "$net_up" = "1" -a -n "${net_device/*+/}" ]; then	
		networks="$networks $network"
		interfaces="$interfaces $net_device"
 		eval network_if_$network=$net_device
 	fi
 done
#echo "networks:$networks"
#echo "interfaces:$interfaces"

 IFS=' '
 for network in $networks
 do
 	eval iface=\$network_if_$network
 	
	eval previous_state=\$prev_state_$network
	state="$(cat /sys/class/net/$iface/operstate)"
		
# echo "[$iface] cur=$state, previous=$previous_state"

	if [ "$previous_state" != "$state" ];then
		process "network" $iface $state $network
		eval prev_state_$network=$state
	fi
done
}


while true
do
	update true
	sleep 1 
done

