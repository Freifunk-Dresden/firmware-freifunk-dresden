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
		dev="dummy"
		$json && echo "\"$dev\" : ["
		unset port; unset link; unset speed
		$json && {
				$comma && echo -n ","
				echo "{ \"port\":\"$port\", \"carrier\":\"$link\", \"speed\":\"$speed\"}"
		}
		$csv && echo "$port,$link,$speed"
		$json && echo "]"
	fi

	$json && echo "}"

}

get_switch_info
