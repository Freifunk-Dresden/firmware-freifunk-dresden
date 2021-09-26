#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3
#
#     0 -   256   vserver
#   900 -   999   temp Knoten, bei Inbetriebnahme
#  1000           spezial:start point for registrator
#  1001 - 50999   Knotennummer fuer Firmware: vergeben durch registrator
# 51000 - 59999   Knotennummer fuer eigen aufgebaute Knoten
# 60000 - 65767   Reserviert
##############################################
export NODE_MIN=1001
export NODE_MAX=59999

export ARG1="$1"
export ARG2="$2"

if [ "$ARG1" = "" ]
then
	echo ""
	echo "ddmesh-ipcalc.sh (awk) Stephan Enderlein (c) 2021 V6"
	echo ""
	echo "Calculates all the addresses for the ddmesh freifunk node"
	echo "usage: ddmesh-ipcalc.sh [-t] [-n node] | [ipv4 ip]"
	echo "-t        run ipcalc test"
	echo "-n node   calculates ip addresses"
	echo "<ipv4 ip> calculates node"
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
	_wireguard_major	= 203
	_middle			= int(node / 255) % 256
	_minor			= (node % 255) + 1
	_meshnet		= "10"

	nodeip		= _meshnet "." _primary_major "." _middle "." _minor
	nonprimary_ip	= _meshnet "." _nonprimary_major "." _middle "." _minor
	wireguard_ip	= _meshnet "." _wireguard_major "." _middle "." _minor
	meshpre		= 16
	meshnetwork	= _meshnet "." _primary_major ".0.0"
	meshnetmask	= "255.255.0.0"
	meshbroadcast	= "10.255.255.255"
	wireguard_network = _meshnet "." _wireguard_major ".0.0"

	mesh6pre	= "48"
	mesh6net	= "fd11:11ae:7466::"
	# client range

	mesh6nodenet	= "fd11:11ae:7466:" sprintf("%x", node) "::"
	mesh6ip		= mesh6nodenet "1"
	mesh6nodepre	= "64"

	meshnet		= "10.200.0.0/16"
	linknet		= "10.201.0.0/16"
	fullnet		= "10.200.0.0/15"
	wifi2net	= "100.64.0.0/10"
	wifi2ip		= "100.64.0.1"

	# ----- new wifi2 ip calulation with roaming
	# 100.64.0.0/10       01100100.01-000000.00000000.0-0000000
	# 100.127.0.0/10      01100100.01-111111.00000000.0-0000000
	# clients/knoten                                    ^^^^^^^ (7bit-128 clients)
	# knotennummer                    ^^^^^^ ^^^^^^^^ ^ (15bit - 32768 knotennummern)
	#
	#
	# knoten 0
	#  min client: # 01100100.01-000000.00000000.0-0000001
	#  max client: # 01100100.01-000000.00000000.0-1111110
	#
	# knoten 32767
	#  min client: # 01100100.01-111111.11111111.1-0000001
	#  max client: # 01100100.01-111111.11111111.1-1111110
	#
	# network   100.127.0.0     # 01100100.01-000000.00000000.0-0000000
	# broadcast 100.127.255.255 # 01100100.01-111111.11111111.1-1111111
  # netmask   255.
	# Roaming only upto node 32766.
	# Calulated values for number 32767 (highest possible number)
	# are used for all nodes above 32766. Those nodes must not support
	# roaming (using ssid "Freifunk Dresden")

	_roaming=1
	_roaming_node = node	# node used to calulate wifi2dhcp
	if ( _roaming_node > 32766 )
	{
		_roaming_node=32767
		_roaming=0
	}

	b1 = 100
	b2 = or(0x40, and( rshift(_roaming_node, 9), 0x3f))
	b3 = and(rshift(_roaming_node, 1), 0xff)
	b4 = and(lshift(_roaming_node, 7), 0x80)
	b4FixIpStart	= b4 + 1		# very start for ip range
	b4FixIpEnd 		= b4 + 10		# very start for ip range
	b4min = b4FixIpEnd + 1		# dhcp start; keep some room for portforwardings
	b4max = b4 + 126	# dhcp end; letzte client IP, da bei max knoten 32767 die broadcast ip
										# noch moeglich sein muss

	wifi2roaming 		= _roaming
	wifi2FixIpStart	= b1"."b2"."b3"."b4FixIpStart
	wifi2FixIpEnd		= b1"."b2"."b3"."b4FixIpEnd
	wifi2dhcpstart	= b1"."b2"."b3"."b4min
	wifi2dhcpnum		= b4max - b4min + 1
	wifi2dhcpend		= b1"."b2"."b3"."b4max
	wifi2broadcast	= "100.127.255.255"
	wifi2netmask		= "255.192.0.0"



	print "export _ddmesh_min=\""ENVIRON["NODE_MIN"]"\""
	print "export _ddmesh_max=\""ENVIRON["NODE_MAX"]"\""
	print "export _ddmesh_node=\""node"\""
	print "export _ddmesh_domain=\""domain"\""
	print "export _ddmesh_hostname=\"r"node"\""
	print "export _ddmesh_ip=\""nodeip"\""
	print "export _ddmesh_nonprimary_ip=\""nonprimary_ip"\""
	print "export _ddmesh_wireguard_ip=\""wireguard_ip"\""
	print "export _ddmesh_wireguard_network=\""wireguard_network"\""
	print "export _ddmesh_network=\""meshnetwork"\""
	print "export _ddmesh_netpre=\""meshpre"\""
	print "export _ddmesh_netmask=\""meshnetmask"\""
	print "export _ddmesh_broadcast=\""meshbroadcast"\""
	print "export _ddmesh_mesh6net=\""mesh6net"\""
	print "export _ddmesh_mesh6pre=\""mesh6pre"\""
	print "export _ddmesh_mesh6nodenet=\""mesh6nodenet"\""
	print "export _ddmesh_mesh6ip=\""mesh6ip"\""
	print "export _ddmesh_mesh6nodepre=\""mesh6nodepre"\""
	print "export _ddmesh_meshnet=\""meshnet"\""
	print "export _ddmesh_linknet=\""linknet"\""
	print "export _ddmesh_fullnet=\""fullnet"\""
	print "export _ddmesh_wifi2net=\""wifi2net"\""
	print "export _ddmesh_wifi2ip=\""wifi2ip"\""
	print "export _ddmesh_wifi2roaming=\""wifi2roaming"\""
	print "export _ddmesh_wifi2FixIpStart=\""wifi2FixIpStart"\""
	print "export _ddmesh_wifi2FixIpEnd=\""wifi2FixIpEnd"\""
	print "export _ddmesh_wifi2dhcpstart=\""wifi2dhcpstart"\""
	print "export _ddmesh_wifi2dhcpnum=\""wifi2dhcpnum"\""
	print "export _ddmesh_wifi2dhcpend=\""wifi2dhcpend"\""
	print "export _ddmesh_wifi2broadcast=\""wifi2broadcast"\""
	print "export _ddmesh_wifi2netmask=\""wifi2netmask"\""
 }

 BEGIN {
	if(arg1=="-n")
		lookup_node(arg2)
	else
		lookup_ip(arg1)
	exit 0;
 }
'
