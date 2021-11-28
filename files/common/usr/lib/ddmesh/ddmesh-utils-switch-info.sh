#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

json=false
csv=false

case $1 in
	json)	json=true ;;
	csv)	csv=true ;;
	*)
		echo "usage: $(basename $0) json | csv"
		exit 1
		;;
esac


get_switch_info()
{
	local comma=false

	$json && echo "{"

	if [ -x /sbin/swconfig ]; then
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
	else
		$json && echo "\"switch\" : ["
		for dev in wan lan1 lan2 lan3 lan4
		do
			class_path="/sys/class/net/${dev}"
			if [ -d "${class_path}" ]; then
				unset port; unset link; unset speed

				# get device path
				dp="$(readlink ${class_path} | sed 's#.*\(/devices/.*\)$#/sys\1#')"

				phys_port_name="$(cat ${dp}/phys_port_name)"
				port="${phys_port_name:1:2}"

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
