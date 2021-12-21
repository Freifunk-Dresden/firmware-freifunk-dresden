#!/bin/sh
# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

export TITLE="Verwaltung &gt; Infos: Firewall"
export HTTP_ALLOW_GET_REQUEST=1
. /usr/lib/www/page-pre.sh ${0%/*}

cat<<EOM
<h2>$TITLE</h2>
<br>
EOM

show_table()
{
 export table=$1
 export chain=$2
 export ipv=$3

 if [ "$ipv" = "ipv6" ]; then
	export ipt=ip6tables
 else
	export ipt=iptables
 fi


cat<<EOM
<fieldset class="bubble">
<legend>Iptables $ipv: $table -> $chain</legend>
<table>
EOM

$ipt -w -t $table -L $chain -vn 2>&1 | awk '
	function join(array, start, end, separator)
	{
		result=""
		for (i=start;i<=end;i++)
		{
			result = result separator array[i]
		}
		return result;
	}
	function extractComment(line)
	{
		split(line, array, " ");
		result=""
		inComment=0
		for (i=1; i<=length(array);i++)
		{
			if(inComment==0 && match(array[i],"/\\*")>0)
			{
				inComment=1
				continue
			}
			if(inComment==1 && match(array[i],"\\*/")>0)
			{
				inComment=0
				continue
			}
			if(inComment)
				result = result " " array[i]
		}
		return result;
	}


 /Chain/{
		print "<tr><th colspan=\"11\">"$0"</th></tr>";
		next
	}
 /pkts/ {
		print "<tr><th>Pkts</th><th>Bytes</th><th>Target</th><th>Prot</th><th>Opt</th><th>In</th><th>Out</th><th>Source</th><th>Destination</th><th>Params</th><th>Comment</th></tr>"
		next
	}
	{
		if(match($3,/^(ACCEPT|REJECT|LOG|QUEUE|NFQUEUE|RETURN|DROP|MASQUERADE|SNAT|DNAT)$/)!=0)
			link=$3
		else
			link="<a href=\"firewall.cgi?ipt_table="ENVIRON["table"]"&ipt_chain="$3"&ip_version="ENVIRON["ipv"]"\">"$3"</a>"


		if(toggel==1)
			toggel=2
		else
			toggel=1

		# extract params
		#  remove comment
		raw=gensub(/\/\*.*\*\//,"",1, $0)
		#  split (space separated)
		split(raw, array, " ")
		#  params are from index 10 to end
		params=join(array, 10, length(array), " ")

		# extract comment
		comment=extractComment($0)

		print "<tr class=\"colortoggle"toggel"\"><td>"$1"</td><td>"$2"</td><td>"link"</a></td><td>"$4"</td><td>"$5"</td><td>"$6"</td><td>"$7"</td><td>"$8"</td><td>"$9"</td><td>"params"</td><td>"comment"</td></tr>"

	}
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
<tr><td>IPv4:&nbsp;<a href="iptables.cgi?4filter">filter</a>&nbsp;<a href="iptables.cgi?4nat">nat</a>&nbsp;<a href="iptables.cgi?4mangle">mangle</a></td></tr>
</table>
</fieldset>
EOF
}
cat<<EOM
	<b>IPv4 Table:</b>
	<a href="firewall.cgi?ipt_table=filter&ip_version=ipv4">filter</a>,
	<a href="firewall.cgi?ipt_table=nat&ip_version=ipv4">nat</a>,
	<a href="firewall.cgi?ipt_table=mangle&ip_version=ipv4">mangle</a>
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
	ipt_table=${ipt_table:-filter}
	ip_version=${ip_version:-ipv4}

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
	esac

else
	show_table $ipt_table $ipt_chain $ip_version
fi

show_links

. /usr/lib/www/page-post.sh
