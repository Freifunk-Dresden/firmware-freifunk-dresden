#!/bin/sh

export TITLE="Infos: Firewall"
export HTTP_ALLOW_GET_REQUEST=1
. $DOCUMENT_ROOT/page-pre.sh ${0%/*}

cat<<EOM
<h2>$TITLE</h2>
<br>
EOM

show_table()
{
 table=$1
 chain=$2
 ip_version=$3

 if [ "$ip_version" = "ipv6" ]; then
	ipt=ip6tables
 else
	ipt=iptables
 fi


cat<<EOM
<fieldset class="bubble">
<legend>Iptables $ip_version: $table -> $chain</legend>
<table>
EOM

$ipt -t $table -L $chain -vn 2>&1 | sed -n '
:m
/Chain/{
s#^.*#<tr><th colspan="15"><hr size=1></th></tr><tr><th colspan="15">&</th></tr>#
p
n
b m
}
/pkts/{
s#[ 	]\+#;#g
s#;\+$##
s#^;#<tr><th>#
s#;#</th><th>#g
s#$#</th></tr>#
p
n
b m
}
:a
/^[ 	]*$/{
n
b m
}
s#^[ 	]*#;#
s#[ 	]\+#;#g
/^;[^;]\+;[^;]\+;ACCEPT/b b
/^;[^;]\+;[^;]\+;REJECT/b b
/^;[^;]\+;[^;]\+;LOG/b b
/^;[^;]\+;[^;]\+;QUEUE/b b
/^;[^;]\+;[^;]\+;NFQUEUE/b b
/^;[^;]\+;[^;]\+;RETURN/b b
/^;[^;]\+;[^;]\+;DROP/b b
/^;[^;]\+;[^;]\+;MASQUERADE/b b
/^;[^;]\+;[^;]\+;SNAT/b b
/^;[^;]\+;[^;]\+;DNAT/b b
s#^;\([^;]\+\);\([^;]\+\);\([^;]\+\)#;\1;\2;<a href="firewall.cgi?ipt_table='$table'\&ipt_chain=\3\&ip_version='$ip_version'">\3</a>#
:b
s#^;#<tr class="colortoggle1"><td>#
s#;\+$##
s#;#</td><td>#g
s#$#</td></tr>#
p
n
/Chain/b m
/pkts/b m
/^[ 	]*$/{
n
b m
}
s#^[ 	]*#;#
s#[ 	]\+#;#g
s#[ 	]\+#;#g
/^;[^;]\+;[^;]\+;ACCEPT/b c
/^;[^;]\+;[^;]\+;REJECT/b c
/^;[^;]\+;[^;]\+;LOG/b c
/^;[^;]\+;[^;]\+;QUEUE/b c
/^;[^;]\+;[^;]\+;NFQUEUE/b c
/^;[^;]\+;[^;]\+;RETURN/b c
/^;[^;]\+;[^;]\+;DROP/b c
/^;[^;]\+;[^;]\+;MASQUERADE/b c
/^;[^;]\+;[^;]\+;SNAT/b c
/^;[^;]\+;[^;]\+;DNAT/b c
s#^;\([^;]\+\);\([^;]\+\);\([^;]\+\)#;\1;\2;<a href="firewall.cgi?ipt_table='$table'\&ipt_chain=\3\&ip_version='$ip_version'">\3</a>#
:c
s#^;#<tr class="colortoggle2"><td>#
s#;\+$##
s#;#</td><td>#g
s#$#</td></tr>#
p
'

cat<<EOF
</table>
</fieldset>
EOF
}

show_links()
{
cat<<EOF
<br/><br/>
<fieldset class="bubble">
<legend>Iptables Download</legend>
<table>
<tr><td>IPv4:&nbsp;<a href="iptables.cgi?4filter">filter</a>&nbsp;<a href="iptables.cgi?4nat">nat</a>&nbsp;<a href="iptables.cgi?4mangle">mangle</a>&nbsp;<a href="iptables.cgi?4raw">raw</a></td></tr>
</table>
</fieldset>
EOF
}
cat<<EOM
	<b>IPv4 Table:</b>
	<a href="firewall.cgi?ipt_table=filter&ip_version=ipv4">filter</a>,
	<a href="firewall.cgi?ipt_table=nat&ip_version=ipv4">nat</a>,
	<a href="firewall.cgi?ipt_table=mangle&ip_version=ipv4">mangle</a>,
	<a href="firewall.cgi?ipt_table=raw&ip_version=ipv4">raw</a>
EOM
if [ "$(uci get ddmesh.system.disable_splash)" != "1" ]; then
cat<<EOM
	,<a href="firewall.cgi?ipt_table=filter&ipt_chain=SPLASH&ip_version=ipv4">filter::SPLASH</a>,
	<a href="firewall.cgi?ipt_table=nat&ipt_chain=SPLASH&ip_version=ipv4">nat::SPLASH</a>
EOM
fi
cat<<EOM
	<br/>
	<br/>
EOM
	${ipt_table:=filter}
	${ip_version:=ipv4}

if [ -z "$ipt_table" -o -z "$ipt_chain" -o -z "$ip_version" ]; then

	case $ipt_table in
		filter)
			show_table $ipt_table INPUT $ip_version
			show_table $ipt_table FORWARD $ip_version
			show_table $ipt_table OUTPUT $ip_version
			;;
		nat)
			show_table $ipt_table PREROUTING $ip_version
			show_table $ipt_table INPUT $ip_version
			show_table $ipt_table OUTPUT $ip_version
			show_table $ipt_table POSTROUTING $ip_version
			;;
		mangle)
			show_table $ipt_table PREROUTING $ip_version
			show_table $ipt_table INPUT $ip_version
			show_table $ipt_table FORWARD $ip_version
			show_table $ipt_table OUTPUT $ip_version
			show_table $ipt_table POSTROUTING $ip_version
			;;
		raw)
			show_table $ipt_table PREROUTING $ip_version
			show_table $ipt_table OUTPUT $ip_version
			;;
	esac

else
	show_table $ipt_table $ipt_chain $ip_version
fi

show_links

. $DOCUMENT_ROOT/page-post.sh
