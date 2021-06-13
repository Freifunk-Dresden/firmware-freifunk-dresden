#!/bin/bash

BMXD_DEBUG_LEVEL=4
PrimeDEV="bmx_prime"
PIP="10.200.99.99"
LinkDEV="br-bmx0"				# empty bridge
LinkIP="10.201.99.99"
BROADCAST="10.255.255.255"

LAN_DEV="enp7s0"		# will be added to bridge (mesh on lan)

if [ $(id -u) != "0" ]
then
	echo "Run this script as root"
	exit 1
fi

usage()
{
	echo "Usage: $(basename) [server | client]"
	echo "server - run bmxd in forground (-d${BMXD_DEBUG_LEVEL})"
	echo "client - run bmxd as client (-lcd${BMXD_DEBUG_LEVEL})"
}

setup()
{
	ip link show dev ${PrimeDEV} || {
		echo "create bmxd prime interface: ${PrimeDEV}: ${PIP}"
		ip link add ${PrimeDEV} type bridge
		ip addr add ${PIP}/16 broadcast ${BROADCAST} dev ${PrimeDEV}
	}
	ip link set ${PrimeDEV} up

	ip link show dev ${LinkDEV} || {
		echo "create bmxd prime interface: ${LinkDEV}: ${LinkIP}"
		ip link add ${LinkDEV} type bridge
		ip addr add ${LinkIP}/16 broadcast ${BROADCAST} dev ${LinkDEV}
		brctl addif ${LinkDEV} ${LAN_DEV}
	}
	ip link set ${LinkDEV} up
}

clean()
{
		ip link set ${LinkDEV} down
		ip link del ${LinkDEV}

		ip link set ${PrimeDEV} down
		ip link del ${PrimeDEV}
}

# Run the Valgrind tool called toolname, e.g. memcheck, cachegrind, callgrind, helgrind, drd, massif,
# dhat, lackey, none, exp-sgcheck, exp-bbv, etc.
VALGRIND_OPT="--show-error-list=yes --tool=memcheck --leak-check=full -s"

case "$1" in
	server)
		setup
		valgrind ${VALGRIND_OPT} ./sources/bmxd -d${BMXD_DEBUG_LEVEL} dev=${PrimeDEV} /linklayer 0 dev=${LinkDEV} /linklayer 1
		clean
		;;
	client)
		valgrind ${VALGRIND_OPT} ./sources/bmxd -lcd${BMXD_DEBUG_LEVEL}
		;;
	*) usage; exit 1 ;;
esac
