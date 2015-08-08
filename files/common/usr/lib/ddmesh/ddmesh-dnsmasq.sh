#!/bin/sh
#creates manually the config because of special wifi ranges
#file is linked via /etc/dnsmasq.conf

CONF=/var/etc/dnsmasq.conf.manual
mkdir -p /var/etc

eval $(/usr/bin/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

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

#read upstream server from resolv.conf.auto instead resolv.conf
all-servers
resolv-file=/tmp/resolv.conf.auto
EOM


nameserver="$(uci get ddmesh.network.internal_dns | sed -n '/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$/p')"
if [ -n "$nameserver" ]; then
	echo "rebind-domain-ok=/ffdd/mei/" >>$CONF
	echo "server=/ffdd/$nameserver" >>$CONF
	echo "server=/mei/$nameserver" >>$CONF
	echo "server=//#" >>$CONF
fi

eval $(/usr/lib/ddmesh_ddmesh-utils-network-info.sh wan wan)
# wenn das waninterface an ist
if [ $wan_up == '1' ] ; then
    echo "server=freifunk-dresden.de/$wan_dns" >> $CONF
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
cat >>$CONF <<EOM
#------ wifi2 ---------
dhcp-range=set:wifi2,$(uci get ddmesh.network.wifi2_dhcpstart),$(uci get ddmesh.network.wifi2_dhcpend),$(uci get ddmesh.network.wifi2_dhcplease)
dhcp-option=wifi2,6,$(uci get ddmesh.network.wifi2_dns)
dhcp-option=wifi2,3,$(uci get ddmesh.network.wifi2_ip)
dhcp-option=wifi2,1,$(uci get ddmesh.network.wifi2_netmask)
dhcp-option=wifi2,12,$_ddmesh_hostname
EOM

/etc/init.d/dnsmasq stop
test "$1" == "start" && /etc/init.d/dnsmasq start



