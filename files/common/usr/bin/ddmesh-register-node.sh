#!/bin/sh

LOGGER_TAG="register.node"
AUTO_REBOOT=1

#check if initial setup was run before
if [ ! -f /etc/config/ddmesh ]; then logger -t $LOGGER_TAG "ddmesh not ready - ignore register.node" ; exit; fi

node="$(uci get ddmesh.system.node)"
key="$(uci get ddmesh.system.register_key)"
eval $(/usr/bin/ddmesh-ipcalc.sh -n $node)

echo "local node: [$node]"
echo "local key: [$key]"

arg1="$1"

if [ -z "$arg1" ]; then
	echo "usage: register_node.sh [new_node]"
	echo ""
fi

#check if user want's to register with a different node
test -n "$arg1" && node=$arg1

test -z "$node" && {
	echo "node number not set or passed as parameter"
	exit 1	
}

test -z "$key" && {
	echo "no register key"
	exit 1	
}

echo "Try to register node [$node], key [$key]"
n="$(wget -O - "$(uci get credentials.registration.register_service_url)$key" 2>/dev/null)"

cmd=$(echo "$n" | sed -n '/^OK/p;/^ERROR/p;/^INFO/p' )
case "$cmd" in
	OK*) 
			node=$(echo $n | sed 's#.*:\([0-9]\+\).*#\1#')
			logger -t $LOGGER_TAG "SUCCESS: node=[$node]; key=[$key] registered."
			
			echo "node=$node"
			#if node wasn't stored before
			[ -n "$node" ] && [ "$(uci get ddmesh.system.node)" != "$node" ] && {

				echo "commit node [$node]"	
				uci set ddmesh.system.node=$node
				#config depending on node must be updated and causes a second reboot
				uci set ddmesh.boot.boot_step=2
			  	uci commit	
				
				if [ $AUTO_REBOOT -eq 1 ]; then
					echo "rebooting..."
					reboot
				else
					logger -t $LOGGER_TAG "node stored. reboot needed."
					echo "reboot needed"
				fi
				
			}
			echo "updated."
			
		;;
	ERROR*) 	echo $n
			logger -t $LOGGER_TAG "$n"
		;;
	INFO*)		echo $n
			logger -t $LOGGER_TAG "$n"
		;;
	*)		echo Error: connect error
			logger -t $LOGGER_TAG "ERROR: connect error!"
		;;
esac
 



