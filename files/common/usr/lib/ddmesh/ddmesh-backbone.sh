#!/bin/sh

test -x /usr/bin/vtund || exit

. /lib/functions.sh

VTUND=/usr/bin/vtund
CONF=/var/etc/vtund-backbone.conf
STATUS_DIR=/var/vtund/backbone
NETWORK_DEV=tbb
PROTO=tcp
NUMBER_OF_CLIENTS=$(uci get ddmesh.backbone.number_of_clients)
DEFAULT_PORT=$(uci get ddmesh.backbone.default_server_port)
DEFAULT_PASSWORD=$(uci get credentials.backbone.default_passwd)

backbone_server_port=$(uci get ddmesh.backbone.server_port)
backbone_server_port=${backbone_server_port:-$DEFAULT_PORT}
backbone_server_enabled=$(uci get ddmesh.backbone.server_enabled)
backbone_server_enabled=${backbone_server_enabled:-0}
backbone_clients_enabled=$(uci get ddmesh.backbone.clients_enabled)
backbone_clients_enabled=${backbone_clients_enabled:-0}

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
#bsp: backbone-r100 freifunk incomming-r100
#status_id: unterscheidet sich bei client oder server. benutzt um verbindung zu erkennen im webinterface
#bei up: wird %% umbenannt, bei down wird es zurueck benannt, damit vtun dass entsprechende
#tapX loescht. Ich nehme an, dass vtun sich den tapX namen merkt und dieses loeschen will
addconf() {
 cat << EOM >>$CONF
$1 {
 passwd a$(echo "$2" | md5sum | sed 's# .*$##')78; 
 type ether;
 proto $PROTO;
 compress no;
 encrypt no;
 stat no;
 keepalive 10:1;
#only one client;to ensure that the old interface is deleted before creating new one (in case connection is dead and client creates a new one.e.g. IP address change on DSL line)
 multi no;
 persist yes;
 up { 
  program $CMD_IP "link set %% down" wait;
  program $CMD_IP "link set %% promisc off" wait;
  program $CMD_IP "addr add $_ddmesh_nonprimary_ip/$_ddmesh_netpre broadcast $_ddmesh_broadcast dev %%" wait;
  program $CMD_IP "link set %% up" wait;
  program /usr/lib/ddmesh/ddmesh-bmxd.sh "addif %%" wait;
  program $CMD_TOUCH "$STATUS_DIR/$3" wait;
 };
 down {
  program /usr/lib/ddmesh/ddmesh-bmxd.sh "delif %%" wait;
  program $CMD_IP "link set %% down" wait;
  program $CMD_IP "addr del $_ddmesh_nonprimary_ip/$_ddmesh_netpre broadcast $_ddmesh_broadcast dev %%" wait;
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

	password=${password:-$DEFAULT_PASSWORD}
	
	echo incomming line:$i $name,$password
	if [ -n "$name" -a -n "$password" ]; then
		addconf backbone2-$name $password incomming_$name
	fi
}
				
callback_outgoing_config ()
{
	local config="$1"
	local host  #hostname or ip
	local port 
	local password
	
	config_get host "$config" host
	config_get port "$config" port 
	config_get password "$config" password

	password=${password:-$DEFAULT_PASSWORD}
	
	echo outgoing line:$i: $host,$port,$password
	if [ -n "$host" -a -n "$port" -a -n "$password" ]; then
		echo "host=[$host:$port:$password]"
		CONF_NAME="backbone2-$_ddmesh_hostname"
		addconf	$CONF_NAME $password outgoing_$host"_"$port

		$VTUND -f $CONF -P $port $CONF_NAME $host -I "vtund-tbb[c]: "
		echo "vtund - client $host:$port started."
	fi

	#dont use hostnames, can not be resolved	
	iptables -A output_backbone_accept -p $PROTO --dport $port -j ACCEPT
	iptables -A output_backbone_reject -p $PROTO --dport $port -j reject

}
				
if [ "$1" = "start" ]; then
	echo "Starting backbone..."

	mkdir -p $STATUS_DIR
	mkdir -p /var/lock/vtund
	
	createconf
	
	iptables -F input_backbone_accept
	iptables -F input_backbone_reject

 	if [ "$backbone_server_enabled" = "1" ]; then
 		config_load ddmesh
 		config_foreach callback_accept_config backbone_accept

  		iptables -A input_backbone_accept -p $PROTO --dport $backbone_server_port -j ACCEPT
  		iptables -A input_backbone_reject -p $PROTO --dport $backbone_server_port -j reject

		$VTUND -s -f $CONF -P $backbone_server_port -I "vtund-tbb[s]: "
		echo "vtund - server started."
	fi

	iptables -F output_backbone_accept
	iptables -F output_backbone_reject

 	if [ "$backbone_clients_enabled" = "1" ]; then	
 		config_load ddmesh
 		config_foreach callback_outgoing_config backbone_client

	fi
fi

if [ "$1" = "stop" ]; then
	echo "Stopping backbone network..."
	for i in $(ps | sed -n '/sed/d;/vtund-tbb/s#^[	 ]*\([0-9]\+\).*$#\1#p')
	do
		kill $i
	done
fi


if [ "$1" = "restart" ]; then
	$0 stop
	sleep 2
	$0 start
fi


