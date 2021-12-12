#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

. /lib/functions.sh

LOGGER_TAG="backbone"
WG_BIN=$(which wg)

test -z "$WG_BIN" && { echo "wg not found"; exit 1;}

node="$(uci get ddmesh.system.node)"

usage()
{
	echo "usage: $(basename $0) [info <host>]"
}

returnJsonError()
{
 reason="$1"
 echo "{\"status\" : \"error\", \"reason\":\"$reason\"}"
}

# possible status code:
#  NotConfigured,
#  NotRestricted,
#  Restricted,
#  RequestAccepted,
#  RequestAlreadyRegistered,
#  RequestFailed,

getServerInfo()
{
	host="$1"
	[ -z "$host" ] && return 1

	json="$(wget -qO - "http://${arg}/wg.cgi" 2>/dev/null)"
	[ -z "$json" ] && { returnJsonError "connection failed";	exit 1; }

	echo "$json"
	return 0
}

backbone_register()
{
	host="$1"
	[ -z "$host" ] && return 1

	privKey="$(uci -q get credentials.backbone_secret.wireguard_key)"
	[ -z "$privKey" ] && { returnJsonError "no private wg key";	exit 1; }

	pubKey="$(echo "$privKey" | wg pubkey)"
	[ -z "$privKey" ] && { returnJsonError "no public wg key";	exit 1; }

	json="$(wget -qO - "http://${host}/wg.cgi?node=${node}&key=${pubKey}" 2>/dev/null)"
	[ -z "$json" ] && { returnJsonError "connection failed";	exit 1; }

	echo ${json}

	return 0
}

callback_outgoing_wireguard()
{
	local config="$1"

	local vhost
	local vtype
	local vdisabled

	config_get vhost "$config" host
	config_get vtype "$config" type
	config_get vdisabled "$config" disabled

	#echo "wg process out: disabled:$disabled, cfgtype:$type, host:$host, port:$port, key:$key, target node:$node"
	if [ "$vdisabled" != "1" -a "$vtype" == "wireguard" -a -n "${vhost}" ]; then
		eval $(backbone_register "${vhost}" | jsonfilter -e 'j_status=@.status')
		logger -t "${LOGGER_TAG}" "wireguard registration: status:[$j_status], host: ${vhost}"
	fi
}

updateAllRegistrations()
{
	config_load ddmesh
	config_foreach callback_outgoing_wireguard backbone_client
}


cmd="$1"
arg="$2"
case "${cmd}" in
	"info")
		getServerInfo "$arg" || { usage; exit 1; }
		;;
	"register")
		backbone_register "$arg" || { usage; exit 1; }
		;;
	"refresh")
		updateAllRegistrations
		;;
	*) usage ; exit 1 ;;
esac
