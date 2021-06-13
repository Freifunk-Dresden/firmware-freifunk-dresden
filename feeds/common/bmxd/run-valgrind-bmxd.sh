#!/bin/bash

if [ $(id -u) != "0" ];
then
	echo "Run this script as root"
	exit 1
fi

usage()
{
	echo "Usage: $(basename) [server | client]"
	echo "server - run bmxd in forground (-d0)"
	echo "client - run bmxd as client (-lcd0)"
}

PDEV="bmx"
PIP="10.200.99.99"
LinkDEV="bmx0"
LinkIP="10.201.99.99"

ip link show dev ${PDEV} || {
	echo "create bmxd prime interface: ${PDEV}: ${PIP}"
	ip link add ${PDEV} type bridge
	ip addr add ${PIP} dev ${PDEV}
}
ip link set ${PDEV} up

ip link show dev ${LinkDEV} || {
	echo "create bmxd prime interface: ${LinkDEV}: ${LinkIP}"
	ip link add ${LinkDEV} type bridge
	ip addr add ${LinkIP} dev ${LinkDEV}
}
ip link set ${LinkDEV} up

# Run the Valgrind tool called toolname, e.g. memcheck, cachegrind, callgrind, helgrind, drd, massif,
# dhat, lackey, none, exp-sgcheck, exp-bbv, etc.
VALGRIND_OPT="--show-error-list=yes --tool=memcheck --leak-check=full -s"

case "$1" in
	server)
		valgrind ${VALGRIND_OPT} ./sources/bmxd -d0 dev=${PDEV} dev=${LinkDEV} /linklayer 1
		;;
	client)
		valgrind ${VALGRIND_OPT} ./sources/bmxd -lcd0 dev=${PDEV} dev=${LinkDEV} /linklayer 1
		;;
	*) usage; exit 1 ;;
esac