#!/bin/sh
#
#     0 - 99      vserver
#  1000           spezial:start point for registrator
#  1001 - 50999   Knotennummer für Firmware: vergeben durch registrator
# 51000 - 59999   Knotennummer für eigen Aufgebaute Knoten
# 60000 - 65278   Reserviert
# 65279           broadcast (10.200.255.255)
##############################################
export NODE_MIN=1001
export NODE_MAX=59999

export ARG1="$1"
export ARG2="$2"

if [ "$ARG1" = "" ]
then
	echo ""
        echo "ddmesh-ipcalc.sh (awk) Stephan Enderlein (c) 2015 V4"
	echo ""
        echo "Calculates all the addresses for the ddmesh freifunk node"
	echo "usage: ddmesh-ipcalc.sh [-t] [-n node] | [ipv4 ip]"
	echo "-t        run ipcalc test"
	echo "-n node   0- calulate ip"
	echo "<ipv4 ip>      caluclate node"
	echo ""
        exit 1
fi

if [ "$ARG1" = "-t" ]; then
	eval $($0 -n 0)
	n=0
	echo "Testing nodes $n-$_ddmesh_max"
	_ddmesh_max=10
	while [ $n -le $_ddmesh_max ]
	do
 		eval $($0 -n $n)
 		r=$($0 $_ddmesh_ip)
 		echo "$n - $_ddmesh_ip - $r" 
 		if [ $n -ne $r ]; then
 			echo "ERROR"
 			exit 1
 		fi
 		n=$(($n + 1))
	done
	exit 0
fi

awk -v arg1="$ARG1" -v arg2="$ARG2" '


 function lookup_ip(ip)
 {
	#parameter check
	if(!match(ip,/^10\.20[0-1]\.[0-9]+\.[0-9]+$/))
	{ print "invalid ip"; exit 1 }

	split(ip,a,".")	
	node=a[3]*255 + a[4] - 1

	if(node > ENVIRON["NODE_MAX"])
	{ print "Invalid IP"; exit 1 }

	print node
 }
 
 function lookup_node(node)
 {
	#parameter check
	if(!match(node,/^[0-9]+$/) || node > ENVIRON["NODE_MAX"] )
	{ print "invalid node"; exit 1 }

	domain  = "freifunk-dresden.de"

	_primary_major		= 200
	_nonprimary_major	= 201
	_middle			= int(node / 255) % 256
	_minor			= (node % 255) + 1 
	_meshnet		= "10"

	nodeip		= _meshnet "." _primary_major "." _middle "." _minor 
	nonprimary_ip	= _meshnet "." _nonprimary_major "." _middle "." _minor
	meshpre		= 16
	meshnetmask	= "255.255.0.0"
	meshbroadcast	= "10.255.255.255"

	mesh6pre	= "48"
	mesh6net	= "fd11:11ae:7466::"
	# client range
	
	mesh6nodenet	= "fd11:11ae:7466:" sprintf("%x", node) "::"
	mesh6ip		= mesh6nodenet "1" 
	mesh6nodepre	= "64"

	print "export _ddmesh_min=\""ENVIRON["NODE_MIN"]"\""
	print "export _ddmesh_max=\""ENVIRON["NODE_MAX"]"\""
	print "export _ddmesh_node=\""node"\""
	print "export _ddmesh_domain=\""domain"\""
	print "export _ddmesh_hostname=\"r"node"\""
	print "export _ddmesh_ip=\""nodeip"\""
	print "export _ddmesh_nonprimary_ip=\""nonprimary_ip"\""
	print "export _ddmesh_netpre=\""meshpre"\""
	print "export _ddmesh_netmask=\""meshnetmask"\""
	print "export _ddmesh_broadcast=\""meshbroadcast"\""
	print "export _ddmesh_mesh6net=\""mesh6net"\""
	print "export _ddmesh_mesh6pre=\""mesh6pre"\""
	print "export _ddmesh_mesh6nodenet=\""mesh6nodenet"\""
	print "export _ddmesh_mesh6ip=\""mesh6ip"\""
	print "export _ddmesh_mesh6nodepre=\""mesh6nodepre"\""
 }

 BEGIN {
	if(arg1=="-n")
		lookup_node(arg2)
	else
		lookup_ip(arg1)
	exit 0;
 }
'
