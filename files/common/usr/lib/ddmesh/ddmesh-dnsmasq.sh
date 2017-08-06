#!/bin/sh
#creates manually the config because of special wifi ranges
#file is linked via /etc/dnsmasq.conf
# see http://www.faqs.org/rfcs/rfc2132.html for more dhcp options

CONF=/var/etc/dnsmasq.conf.manual
FINAL=/tmp/resolv.conf.final
AUTO=/tmp/resolv.conf.auto
mkdir -p /var/etc

# link to resolv.conf.auto as long as bmxd has not written resolv.conf.final
touch $AUTO
test -f $FINAL || ln -s $AUTO $FINAL

eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

#create LAN DHCP: IP,NETMASK,BROADCAST,NETWORK,PREFIX,START,END
eval $(ipcalc.sh $(uci get network.lan.ipaddr) $(uci get network.lan.netmask) $(uci get ddmesh.network.dhcp_lan_offset) $(uci get ddmesh.network.dhcp_lan_limit))


cat >$CONF <<EOM
#config file created by $0

# filter what we send upstream
#domain-needed
bogus-priv
stop-dns-rebind

#enable filterwin2k if dial-on-demand is used (not used at moment)
#filterwin2k
user=root
group=root
dhcp-authoritative
dhcp-fqdn
no-negcache
cache-size=0
local-ttl=0
neg-ttl=0
max-ttl=0
max-cache-ttl=0

#read upstream server from resolv.conf.auto instead resolv.conf
all-servers
resolv-file=$FINAL
EOM


nameserver="$(uci get ddmesh.network.internal_dns | sed -n '/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$/p')"
if [ -n "$nameserver" ]; then
	# allow private ip ranges in answer
	echo "rebind-domain-ok=/ffdd/mei/" >>$CONF
	# ns for ffdd
	echo "server=/ffdd/$nameserver" >>$CONF
	# ns for mei
	echo "server=/mei/$nameserver" >>$CONF
	# use standard for all without domain
	echo "server=//#" >>$CONF
fi

cat >>$CONF <<EOM

# allow /etc/hosts and dhcp lookups via *.lan
#addn-hosts=/etc/local.hosts
expand-hosts

# no dns queries from the wan
except-interface=$(uci get network.wan.ifname 2>/dev/null)

dhcp-leasefile=/tmp/dhcp.leases
dhcp-script=/etc/dnsmasq.script
#don't use 'freifunk-dresden.de' as domain!
domain=freifunk

# allow a /etc/ethers for static hosts
read-ethers
log-facility=/dev/null
EOM


if [ -n "$(uci get ddmesh.network.dhcp_lan_limit)" -a "$(uci get ddmesh.network.dhcp_lan_limit)" != 0 ]; then
cat >>$CONF <<EOM
#------ lan ---------
dhcp-range=wired,$START,$END,$NETMASK,$BROADCAST,$(uci get ddmesh.network.dhcp_lan_lease)
#dns
dhcp-option=wired,6,$IP
#default route
dhcp-option=wired,3,$IP
#subnet mask
dhcp-option=wired,1,$NETMASK
#broadcast
dhcp-option=wired,28,$BROADCAST
#hostname
dhcp-option=wired,12,$_ddmesh_hostname
#domain name
#dhcp-option=wired,15,$_ddmesh_domain
#domain search path
#dhcp-option=wired,119,$_ddmesh_domain
EOM
fi

#dns:6
#default route:3
#subnet mask:1
#hostname:12
#domain name:15
#domain search:119

dns2=$(uci get ddmesh.network.fallback_dns | sed 's#[ 	+]##g')
test -n "$dns2" && dns2=",$dns2"

cat >>$CONF <<EOM
#------ wifi2 ---------
dhcp-range=set:wifi2,$_ddmesh_wifi2dhcpstart,$_ddmesh_wifi2dhcpend,$(uci get ddmesh.network.wifi2_dhcplease)
dhcp-option=wifi2,6,$_ddmesh_wifi2ip$dns2
dhcp-option=wifi2,3,$_ddmesh_wifi2ip
dhcp-option=wifi2,1,$_ddmesh_wifi2netmask
dhcp-option=wifi2,12,$_ddmesh_hostname
EOM

/etc/init.d/dnsmasq stop 2>/dev/null

test "$1" == "start" && /etc/init.d/dnsmasq start
test "$1" == "restart" && /etc/init.d/dnsmasq start

