#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

json=false
csv=false

isDsa()
{
	for i in /sys/class/net/*
	do
		ifname="${i##*/}"
		dsa="$(grep DEVTYPE=dsa $i/uevent)"
		if [ -n "$dsa" ]; then
			echo "1"
			return 1
		fi
	done
	echo "0"
	return 0
}

getDsaInterfaces()
{
	for i in /sys/class/net/*
	do
		ifname="${i##*/}"
		dsa="$(grep DEVTYPE=dsa $i/uevent)"
		if [ -n "$dsa" ]; then
			echo "$ifname"
		fi
	done
}

case $1 in
	json)	json=true ;;
	csv)	csv=true ;;
	isdsa)	isDsa && exit 1 || exit 0;;
	*)
		echo "usage: $(basename $0) json | csv | isdsa"
		exit 1
		;;
esac

get_switch_info()
{
	local comma=false

	$json && echo "{"

	if [ "$(isDsa)" = "0" ]; then
	  $json && echo "\"dsa\": false,"
		if [ -n "$(which swconfig)" ]; then
			for dev in $(swconfig list | awk '{print $2}')
			do
				$json && echo "\"$dev\" : ["
				for entry in $(swconfig dev $dev show | awk '/link:/{$0=gensub(/([^ ]*):/,"\\1=","g"); print $2";"$3";"$4}')
				do
					unset port; unset link; unset speed
					eval $entry
					$json && {
							$comma && echo -n ","
							echo "{ \"port\":\"$port\", \"carrier\":\"$link\", \"speed\":\"$speed\"}"
					}
					comma=true
					$csv && echo "$port,$link,$speed"
				done
				$json && echo "]"
				break; # only one switch
			done
		fi
	else
		$json && echo "\"dsa\": true,"
		$json && echo "\"switch\" : ["
		for dev in $(getDsaInterfaces)
		do
			class_path="/sys/class/net/${dev}"
			if [ -d "${class_path}" ]; then
				unset port; unset link; unset speed

				# get device path
				dp="$(readlink ${class_path} | sed 's#.*\(/devices/.*\)$#/sys\1#')"

				phys_port_name="$(cat ${dp}/phys_port_name)"
				port="${phys_port_name:1:2} (${dev})"

				link="$(cat ${dp}/carrier)"
				speed="$(cat ${dp}/speed)"
				[ $speed -lt 0 ] && speed=0

				$json && {
					$comma && echo -n ","
					echo "{ \"port\":\"$port\", \"carrier\":\"$link\", \"speed\":\"$speed\"}"
				}
				comma=true
				$csv && echo "$port,$link,$speed"
			fi
		done
		$json && echo "]"
	fi

	$json && echo "}"

}

get_switch_info
