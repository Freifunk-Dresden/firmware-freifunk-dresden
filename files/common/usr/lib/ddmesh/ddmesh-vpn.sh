#!/bin/sh

test -x /usr/bin/vtund || exit

. /lib/functions.sh

VTUND=/usr/bin/vtund
CONF=/var/etc/vtund-vpn.conf
STATUS_DIR=/var/vtund/vpn
NETWORK_DEV=vpn
NUMBER_OF_CLIENTS=$(uci get ddmesh.vpn.number_of_clients)
DEFAULT_PORT=$(uci get ddmesh.vpn.default_server_port)

vpn_server_port=$(uci get ddmesh.vpn.server_port)
vpn_server_port=${vpn_server_port:-$DEFAULT_PORT}
vpn_server_enabled=$(uci get ddmesh.vpn.server_enabled)
vpn_server_enabled=${vpn_server_enabled:-0}
vpn_clients_enabled=$(uci get ddmesh.vpn.clients_enabled)
vpn_clients_enabled=${vpn_clients_enabled:-0}

eval $(/usr/bin/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

CMD_IP="$(type -p ip)"                                                
CMD_TOUCH="$(type -p touch)"                                          
CMD_RM="$(type -p rm)"
CMD_BRCTL="$(type -p brctl)"

createconf () {
 cat<<EOM >$CONF
options {
 syslog daemon;
 timeout 30;
 ifname $NETWORK_DEV;
}
default {
 speed 0;
}
EOM
}

#addconf <name> <pw> <status_id>
#bsp: vpn-r100 freifunk incomming-r100
#status_id: unterscheidet sich bei client oder server. benutzt um verbindung zu erkennen im webinterface
#bei up: wird %% umbenannt, bei down wird es zurueck benannt, damit vtun dass entsprechende
#tapX loescht. Ich nehme an, dass vtun sich den tapX namen merkt und dieses loeschen will
addconf() {
 cat << EOM >>$CONF
$1 {
 passwd a$(echo "$2" | md5sum | sed 's# .*$##')78; 
 type ether;
 proto tcp;
 compress no;
 encrypt yes;
 stat no;
 keepalive yes;
#only one client;to ensure that the old interface is deleted before creating new one (in case connection is dead and client creates a new one.e.g. IP address change on DSL line)
 multi no;
 persist yes;
 up { 
  program $CMD_IP "link set %% down" wait;
  program $CMD_IP "link set %% promisc off" wait;
  #program $CMD_IP "link set %% mtu 1450" wait;
  program $CMD_IP "link set %% up" wait;
  program $CMD_BRCTL "addif br-lan %%" wait;
  program $CMD_TOUCH "$STATUS_DIR/$3" wait;
 };
 down {
  program $CMD_BRCTL "delif br-lan %%" wait;
  program $CMD_IP "link set %% down" wait;
  program $CMD_RM "$STATUS_DIR/$3" wait;
 };
}
EOM
}

callback_accept_config ()
{
	local config="$1"
	local name
	local password
	 
	config_get name "$config" name 
	config_get password "$config" password
	
	echo incomming line:$i $name,$password
	if [ -n "$name" -a -n "$password" ]; then
		addconf vpn-$name $password incomming_$name
	fi
}
				
callback_outgoing_config ()
{
	local config="$1"
	local name #node name "r100"
	local port 
	local password
	
	config_get name "$config" name 
	config_get port "$config" port 
	config_get password "$config" password
	
	echo outgoing line:$i: $name,$port,$password
	if [ -n "$name" -a -n "$port" -a -n "$password" ]; then
		echo "config=[$name:$port:$password]"
		CONF_NAME="vpn-$_ddmesh_hostname"
		addconf	$CONF_NAME $password outgoing_$name"_"$port

		#get ip from node name
		host=$(ddmesh-ipcalc.sh -n ${name#*r} | grep _ddmesh_ip | cut -d'=' -f2)
		$VTUND -f $CONF -P $port $CONF_NAME $host -I "vtund-vpn[c]: "
		echo "vtund - client $host:$port started."
	fi
}
				
if [ "$1" = "start" ]; then
	echo "Starting vpn network ..."

	mkdir -p $STATUS_DIR
	mkdir -p /var/lock/vtund
	
	createconf

	iptables -F input_vpn_accept
	iptables -F input_vpn_reject

 	if [ "$vpn_server_enabled" = "1" ]; then
 		config_load ddmesh
 		config_foreach callback_accept_config vpn_accept

  		iptables -A input_vpn_accept -p tcp --dport $vpn_server_port -j ACCEPT
  		iptables -A input_vpn_reject -p tcp --dport $vpn_server_port -j reject

		$VTUND -s -f $CONF -P $vpn_server_port -I "vtund-vpn[s]: "
		echo "vtund - server started."
	fi

 	if [ "$vpn_clients_enabled" = "1" ]; then	
 		config_load ddmesh
 		config_foreach callback_outgoing_config vpn_client

	fi
fi

if [ "$1" = "stop" ]; then
	echo "Stopping vpn network..."
	for i in $(ps | sed -n '/sed/d;/vtund-vpn/s#^[	 ]*\([0-9]\+\).*$#\1#p')
	do
		kill $i
	done
fi


if [ "$1" = "restart" ]; then
	$0 stop
	sleep 2
	$0 start
fi


