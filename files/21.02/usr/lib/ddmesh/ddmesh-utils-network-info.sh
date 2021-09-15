#!/bin/sh
#$1 -network name
#$2 -variable prefix

CACHEDIR=/var/cache
CACHE_DATA=$CACHEDIR/netdata

ARG="$1"
PREFIX="$2"

test -z "$ARG" && {
	echo "$0 <list> | <network-name> | update"
	echo "  network name (wan,wifi,wifi2,mesh_lan,mesh_wan,vpn,...) or all"
	echo "  list - lists network interfaces"
	exit 1
}

# always create cache
if [ $ARG = "update" -o ! -f "$CACHE_DATA" ]; then

 mkdir -p $CACHEDIR
 > $CACHE_DATA

 #get network info as json struct and rename key (workaround for jsonfilter)
 json="$(ubus call network.interface dump | sed 's#ipv\([46]\)-address#ipv\1_address#g;s#dns-server#dns_server#g')"

 # check if we have wwan_4 or only wwan
 idx=0
 wwan_4=0
 while true
 do

	ifdata=$(echo "$json" | jsonfilter  -e "@.interface[$idx]")
	if [ -z "$ifdata" ]; then
		break
	fi

	unset net_name
	unset net_error

	eval $(echo "$ifdata" | jsonfilter -e net_name='@.interface' -e net_error='@.errors[0].code')

	if [ "$net_name" = "wwan" ]; then
		wwan_error="$net_error" # remember error if no wwan_4 is present
	fi
	if [ "$net_name" = "wwan_4" ]; then
		wwan_4=1
	fi
	idx=$(( idx + 1 ))
 done

 # retrieve all data
 idx=0
 while true
 do

	ifdata=$(echo "$json" | jsonfilter  -e "@.interface[$idx]")
	if [ -z "$ifdata" ]; then
		break
	fi

	unset net_name
	unset net_iface_present
	unset net_mask
	unset net_ipaddr
	unset net_netmask
	unset net_broadcast
	unset net_gateway
	unset net_dns
	unset net_connect_time
	unset net_ifname
	unset net_up
	unset net_network
	unset net_error

	eval $(echo "$ifdata" | jsonfilter \
		-e net_name='@.interface' \
		-e net_ifname='@.device' \
		-e net_up='@.up' \
		-e net_connect_time='@.uptime' \
		-e net_dns='@.dns_server[0]' \
		-e net_ipaddr='@.ipv4_address[0].address' \
		-e net_mask='@.ipv4_address[0].mask' \
		-e net_gateway='@.route[0].nexthop' \
		-e net_available='@.available' \
		-e net_error='@.errors[0].code' \
	)

	# when we have wwan_4 ignore "wwan" because there is a "wwan_4" created by
	# qmi.sh (lte modem) that has the valid data
	if [ "$wwan_4" = 1 -a "$net_name" = "wwan" ]; then
		idx=$(( idx + 1 ))
		continue
	fi

	# if present then rename wwan_4 to generic name "wwan"
	if [ "$net_name" = "wwan_4" ]; then
		net_name="wwan"
		net_error="$wwan_error" #
	fi

	#if net_name matches requested network, stay in this entry

		if [ "$net_available" = 1 ]; then
			# check if ll_ifname is really present
			ll_ifname="$(uci -q get network.${net_name}.ll_ifname)"
			if [ -n "$ll_ifname" ]; then
				ip link show dev ${ll_ifname} 2>/dev/null >/dev/null && net_iface_present=1
			else
				net_iface_present=1
			fi
		fi

		#calculate rest
		[ "$net_up" = "1" ] &&  [ -n "$net_ipaddr" ] && {
				eval $(ipcalc.sh $net_ipaddr/$net_mask)
				net_broadcast=$BROADCAST
				net_netmask=$NETMASK
				net_network=$NETWORK
		}


		echo export $net_name"_iface_present=$net_iface_present" >> $CACHE_DATA
		echo export $net_name"_mask=$net_mask" >> $CACHE_DATA
		echo export $net_name"_ipaddr=$net_ipaddr" >> $CACHE_DATA
		echo export $net_name"_netmask=$net_netmask" >> $CACHE_DATA
		echo export $net_name"_broadcast=$net_broadcast" >> $CACHE_DATA
		echo export $net_name"_gateway=$net_gateway" >> $CACHE_DATA
		echo export $net_name"_dns=$net_dns" >> $CACHE_DATA
		echo export $net_name"_connect_time=$net_connect_time" >> $CACHE_DATA
		echo export $net_name"_ifname=$net_ifname" >> $CACHE_DATA
		echo export $net_name"_up=$net_up" >> $CACHE_DATA
		echo export $net_name"_network=$net_network" >> $CACHE_DATA
		echo export $net_name"_error=$net_error" >> $CACHE_DATA

#	fi
	idx=$(( idx + 1 ))
 done

fi # update cache data


#-------------------------------------------

case "$ARG" in
	list)
		cat $CACHE_DATA | sed -n "s#export \(.*\)_ifname=\(.*\)#net_\1=\2#p" 
		;;

	all) 	cat $CACHE_DATA
		;;

	*)
		# replace "-" with "_" to allow network names with "-" in there names
		# but have valid variable names
		pfx=${PREFIX:-net}
		pfx=${pfx/-/_}

		cat $CACHE_DATA | sed -n "/^export ${ARG}_/s#export ${ARG}_\(.*\)#export ${pfx}_\1#p" 
		;;
esac

