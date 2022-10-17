#!/bin/bash

BMXD_DEBUG_LEVEL=4
PIP="10.200.99.99"
LinkIP="10.201.99.99"
BROADCAST="10.255.255.255"

PrimeDEV="bmx_prime" # empty bridge
LanDEV="enp7s0"
VLAN=9
LinkDEV="${LanDEV}.${VLAN}"   # vlan 9


if [ $(id -u) != "0" ]
then
	echo "Run this script as root"
	exit 1
fi

usage()
{
	echo "Usage: $(basename) [run | setup-if | clean-if | bmxd]"
	echo "run - run bmxd in forground (-d${BMXD_DEBUG_LEVEL})"
	echo "setup-if - only setup interfaces"
	echo "clean-if - delete interfaces"
	echo "bmxd     - calles bmxd and pass all other arguments to it"
	echo ""
	echo "PIP:      $PIP"
	echo "LinkIP:   $LinkIP"
	echo "PrimeDEV: $PrimeDEV"
	echo "LinkDEV:  $LinkDEV"
}

setup()
{
	# primary interface
	ip link show dev ${PrimeDEV} 2>/dev/null || {
		echo "create bmxd prime interface: ${PrimeDEV}: ${PIP}"
		ip link add ${PrimeDEV} type bridge
		ip addr add ${PIP}/16 broadcast ${BROADCAST} dev ${PrimeDEV}
	}
	ip link set ${PrimeDEV} up

	# vlan
	ip link add link ${LanDEV} ${LinkDEV} type vlan id ${VLAN} 
	ip addr add ${LinkIP}/16 broadcast ${BROADCAST} dev ${LinkDEV}
	ip link set ${LinkDEV} up
	ip rule add to 10.200.0.0/16 ta 64
}

clean()
{
		ip link set ${LinkDEV} down
		ip link del ${LinkDEV}

		ip link set ${PrimeDEV} down
		ip link del ${PrimeDEV}
		ip rule del to 10.200.0.0/16 ta 64
}

# Run the Valgrind tool called toolname, e.g. memcheck, cachegrind, callgrind, helgrind, drd, massif,
# dhat, lackey, none, exp-sgcheck, exp-bbv, etc.
VALGRIND_OPT="--tool=memcheck --show-error-list=yes --leak-check=full -s --track-origins=yes --show-leak-kinds=all"

# https://baptiste-wicht.com/posts/2011/09/profile-c-application-with-callgrind-kcachegrind.html
# apt install kcachegrind graphviz
#VALGRIND_OPT="--tool=callgrind"

case "$1" in
	run)
		setup

		# wenn dns nicht mehr geht, dann resolver nochmal starten
		systemctl restart systemd-resolved

		# when USE_BAT was define when compiling
		# CMD="./sources/bmxd --network 10.200.0.0/16 --netid 0 --throw-rules 0 --prio-rules 0 --gateway_tunnel_network 10.200.0.0/16 --gateway_hysteresis 20 --path_hysteresis 3  -r 3 -p 10.200.1.2 --ogm_broadcasts 100 --udp_data_size 512 --ogm_interval 5000 --purge_timeout i35 -d${BMXD_DEBUG_LEVEL} dev=${PrimeDEV} /linklayer 0 dev=${LinkDEV} /linklayer 1"

		# no USE_BAT defined when compiling
		CMD="./sources/bmxd --network 10.200.0.0/16 --netid 0 --gateway_hysteresis 20 --path_hysteresis 3  -r 3 -p 10.200.1.2 --ogm_broadcasts 100 --udp_data_size 512 --ogm_interval 5000 --purge_timeout 35 -d${BMXD_DEBUG_LEVEL} dev=${PrimeDEV} /linklayer 0 dev=${LinkDEV} /linklayer 1"
		echo "valgrind: [${VALGRIND_OPT}]"
		echo "cmd: [${CMD}]"
		valgrind ${VALGRIND_OPT} ${CMD}
		clean
		;;
	bmxd)
		shift
		valgrind ${VALGRIND_OPT} ./sources/bmxd $@
		;;
	setup-if)  setup;;
	clean-if)  clean;;
	*) usage; exit 1 ;;
esac
