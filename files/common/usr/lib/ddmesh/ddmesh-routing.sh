#!/bin/sh

# set when called from commmand line                                                              
test -z "$_ddmesh_ip" && eval "$(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n "$(uci get ddmesh.system.node)")"

setup() {
	# $1 - add | del

	#priority 99 is used for ping gateway check

	#speedtest through gateway tunnel:
	#router is client: 169.254.x.y allow packets going to bat0
	#router is gatway: 169.254.x.y allow packets going to bat0
	ip rule "$1" to 169.254.0.0/16 table bat_default priority 301
	ip rule "$1" to 169.254.0.0/16 table main priority 302

	#bypass wifi2
	ip rule "$1" to 100.64.0.0/16 table main priority 350

	#route local and lan traffic through own internet gateway
	#route public traffic via second table (KEEP ORDER!)
	ip rule "$1" iif "$(uci get network.loopback.ifname)" table local_gateway priority 400
	test "$(uci -q get ddmesh.network.lan_local_internet)" = "1" && ip rule "$1" iif br-lan table local_gateway priority 401
	ip rule "$1" table public_gateway priority 402

	#byepass private ranges (not freifunk ranges) after processing specific default route
	ip rule "$1" to 192.168.0.0/16 table main priority 450

	# avoid fastd going through mesh/bat (in case WAN dhcp did not get ip)
	ip rule add fwmark 0x5002 table unreachable prio 460

	ip rule "$1" to "$_ddmesh_fullnet" table bat_route priority 500

	#avoid ip packages go through bmx_gateway if bmx6 has removed entries from its tables
	#at this point only let inet ips go further. let all other network ips (10er) be unreachable
	#to speed up routing and avoid loops within same node
	ip rule "$1" to 10.0.0.0/8 table unreachable priority 503
	ip rule "$1" to 172.16.0.0/12 table unreachable priority 504

	ip rule "$1" table bat_default priority 505

	#stop any routing here, to avoid using default gatways in default routing table
	#those gateways are checked and added to gateway table if valid
	ip rule "$1" table unreachable priority 600
	ip route "$1" unreachable default table unreachable

	#return a quick answer instead running in timeout
	#(will disturb adding default gateway)
	#ip route $1 prohibit default
}

clean() {
	# search freifunk routing rules
	for i in $(ip rule | sed 's#:.*##')
	do
		[ "$i" -gt 10 ] && [ "$i" -lt 30000 ] && {
			ip rule del prio "$i"
		}
	done

	ip route del unreachable default table unreachable
}

get_bypass_ip_list() {
	tmp_ipd='/tmp/bypass-ips'
	test ! -d "$tmp_ipd" && mkdir -p "$tmp_ipd"

	# wiki.debian.org 
	nslookup wiki.debian.org | sed -n 's/Address 1:\s*//p' >> "$tmp_ipd"/final_ip-list

	# Netflix get IPs from BGP-AS
	for AS in 2906 55095 40027 394406 136292
	do
		echo '!gas'"$AS" | nc whois.radb.net 43 | sed "1 d" | sed "$ d" >> "$tmp_ipd"/tmp_list1
	done

	#Leerzeichen zu Zeilenvorschub
	sed ':a;N;$!ba;s/ /\n/g' < "$tmp_ipd"/tmp_list1 >> "$tmp_ipd"/tmp_list2

	#IPv4/Maske zu DezimalIP/Maskeb und list2 zu list3
	subnet='0'
	while read -r subnet
	do
		subnetipdec="$(echo "$subnet" | tr . '\n' | awk '{s =s*256 + $1} END{print s}')"
		mask="$(echo "$subnet" | grep -o '..$')"
		echo "$subnetipdec"/"$mask" >> "$tmp_ipd"/tmp_list3
	done < "$tmp_ipd"/tmp_list2

	sort "$tmp_ipd"/tmp_list3 >> "$tmp_ipd"/tmp_list4

	#Aus vorsortierter Liste jeweils $ipa (IPAdress) und $mka (Maske) holen, Anzahl der $adr (Adressen) berechnen.
	#Schauen aktuelle $ipa (IPaktuell) in den Adressbereich $lwr (last write range) passt,
	#sofern selbige in diesen Bereich passt diesen ignorieren und weiter mit naechster $ipa, 
	#ansonnsten $ipa+$mka(Mask Aktuell) in die Ausgabeliste schreiben und zu $lwa bzw. $lwr schlagen 

	rm -f "$tmp_ipd"/final_ip-list
	lwa=''
	while read -r ip
	do
		ipa="${ip%/*}"
		mka="$(echo "$ip" | grep -o '..$')"
		adr="$(( (1<<32-mka) ))"
		adr="$(( ipa+adr ))"

		if ! [ "$lwa" ]; then
			lwm='32'; lwa="$ipa"; lwr="$adr"
		fi

		if [ "$ipa" -lt "$lwr" ] && [ "$mka" -ge "$lwm" ] && [ "$ipa" -ge "$lwa" ]; then
			true
		else
			echo "$(echo "$ipa" | awk '{print rshift(and($1, 0xFF000000), 24) "." rshift(and($1, 0x00FF0000), 16) "." rshift(and($1, 0x0000FF00), 8) "." and($1, 0x000000FF) }')"/"$mka" >> "$tmp_ipd"/final_ip-list
			lwm="$mka"; lwa="$ipa"; lwr="$adr"
		fi
	done < "$tmp_ipd"/tmp_list4

	rm -f "$tmp_ipd"/tmp_list*
}

set_bypass() {
	#bypass Streaming Traffic
	#if [ "$(uci -q get ddmesh.network.bypass)" = '1' ] && [ "$(grep -c 'tbb_fastd' /var/lib/ddmesh/bmxd/links)" -ge '1' ]; then
	if [ "$(uci -q get ddmesh.network.bypass)" = '1' ]; then
		. /lib/functions/network.sh
		network_get_device default_wan_ifname wan
		via="$(ip route | sed -n "/default via [0-9.]\+ dev $default_wan_ifname/{s#.*via \([0-9.]\+\).*#\1#p}")"

		ip rule add table bypass priority 360

		get_bypass_ip_list
		while read -r ip
		do
			ip route add "$ip" via "$via" dev br-wan table bypass
			#iptables -I output_rule 1 -o br-wan -d "$ip" -j ACCEPT
		done < /tmp/bypass-ips/final_ip-list
	fi
}

clean_bypass() {
	ip rule del table bypass priority 360
	ip route flush table bypass
#	if [ -f /tmp/bypass-ips/final_ip-list ]; then
#		while read -r ip
#		do
#			iptables -D output_rule -d "$ip" -o br-wan -j ACCEPT >/dev/null 2>&1
#		done < /tmp/bypass-ips/final_ip-list
#	fi
}


case "$1" in
	start | restart)
		clean
		setup add
	;;

	stop)
		clean
		clean_bypass
	;;

	bypass)
		clean_bypass
		set_bypass
	;;

	clean_bypass)
		clean_bypass
	;;

	*)
		echo "usage $0 [ start | stop | restart ]"
	;;
esac
