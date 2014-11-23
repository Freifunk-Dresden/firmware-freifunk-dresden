#!/bin/sh

if [ "$1" = "" ]
then
	echo ""
        echo "ddmesh-ipcalc.sh (lua) Stephan Enderlein (c) 2014 V2"
	echo ""
        echo "Calculates all the addresses for the ddmesh freifunk node"
	echo "usage: ddmesh-ipcalc.sh [-t] [-n node] | [ipv4 ip]"
	echo "-t        run ipcalc test"
	echo "-n node   0- calulate ip"
	echo "<ipv4 ip>      caluclate node"
	echo ""
        exit 1
fi

if [ "$1" = "-t" ]; then
	eval $(lua -lddmesh -e "ipcalc.print(0)")
	n=0
	echo "Testing nodes $n-$_ddmesh_max"
	_ddmesh_max=10
	while [ $n -lt $_ddmesh_max ]
	do
 		eval $(ddmesh-ipcalc.sh -n $n)
 		r=$(ddmesh-ipcalc.sh $_ddmesh_ip)
 		echo "$n - $_ddmesh_ip - $r" 
 		if [ $n -ne $r ]; then
 			echo "ERROR"
 			exit 1
 		fi
 		n=$(($n + 1))
	done
	exit 0
fi

if [ "$1" = "-n" ]; then
	node=`echo "$2" | sed 's/[\$\`\(\)]/0/g'`
	lua -lddmesh -e "ipcalc.print($node)"
else
	ip=`echo "$1" | sed 's/[\$\`\(\)]/0/g'`
	lua -lddmesh -e "print(iplookup(\"$ip\"))"
fi

