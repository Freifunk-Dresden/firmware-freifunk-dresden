#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
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

# if [ "$ipv" = "ipv6" ]; then
#	export NFT=nft
# else
	export NFT=nft
# fi

# need to convert 'null' to string, so I can test for "accept","drop",....
JSON="$($NFT -j list chain inet fw4 ${chain} | sed 's#null#"null"#g')"
eval $(echo "${JSON}" | jsonfilter -e chain_family='@.nftables[@.chain].chain.family' -e chain_type='@.nftables[@.chain].chain.type' -e policy='@.nftables[@.chain].chain.policy')

cat<<EOM
<fieldset class="bubble">
<legend>Family: $chain_family, Table: $chain_type -> $chain [$policy]</legend>
<table>
<tr><th>Pkts</th><th>Bytes</th><th>Target</th><th>Prot</th><th>Opt</th><th>In</th><th>Out</th><th>Source</th><th>Destination</th><th>Params</th><th>Comment</th></tr>
EOM

IFS='
'
T=1
for rule in $(echo "${JSON}" | jsonfilter -e '@.nftables[@.rule].*')
do

	# get rule globals
  eval $(echo "$rule" | jsonfilter \
		-e comment='@.comment' \
		-e expr_n='@.expr' \
	)

	# expr contains array indexes as string. extract last number to get n.
	# run through all expr and collect data
	unset pkg bytes
	unset in_op in_target in_drop in_accept in_left in_left_payload in_left_proto in_left_field in_right in_key
	unset in_ct_key in_right_array in_left_set in_right_set in_right_prefix_addr in_right_prefix_len
  unset op target drop accept left left_payload left_proto left_field right key ct_key right_array left_set
	unset right_set right_prefix_addr right_prefix_len

	for i in $(seq 0 ${expr_n##* })
	do
		eval $(echo "$rule" | jsonfilter \
				-e obj="@.expr[$i]" \
				-e pkg="@.expr[$i].counter.packets" \
				-e bytes="@.expr[$i].counter.bytes" \
				-e in_target="@.expr[$i].jump.target" \
				-e in_drop="@.expr[$i].drop" \
				-e in_accept="@.expr[*].accept" \
				-e in_op="@.expr[$i].match.op" \
				-e in_left="@.expr[$i].match.left.*" \
				-e in_left_payload="@.expr[$i].match.left[*][*].*" \
				-e in_left_proto="@.expr[$i].match.left.payload.protocol" \
				-e in_left_field="@.expr[$i].match.left.payload.field" \
				-e in_right="@.expr[$i].match.right" \
				-e in_key="@.expr[$i].match.left.meta.key" \
				-e in_ct_key="@.expr[$i].match.left.ct.key" \
				-e in_right_array="@.expr[$i].match.right.*" \
				-e in_left_set="@.expr[$i].match.left.set.*" \
				-e in_right_set="@.expr[$i].match.right.set.*" \
				-e in_right_prefix_addr="@.expr[$i].match.right.prefix.addr" \
				-e in_right_prefix_len="@.expr[$i].match.right.prefix.len" \
		)

		# only set values if available
		[ -n "$in_op" ] && op="$in_op"
		[ -n "$in_target" ] && target="$in_target"
		[ -n "$in_drop" ] && drop="$in_drop"
		[ -n "$in_accept" ] && accept="$in_accept"
		[ -n "$in_left" ] && left="$in_left"
		[ -n "$in_left_payload" ] && left_payload="$in_left_payload"
		[ -n "$in_left_field" ] && left_field="$in_left_field"
		[ -n "$in_left_proto" ] && left_proto="$in_left_proto"
		[ -n "$in_right" ] && right="$in_right"
		[ -n "$in_key" ] && key="$in_key"
		[ -n "$in_ct_key" ] && ct_key="$in_ct_key"
		[ -n "$in_right_array" ] && right_array="$in_right_array"
		[ -n "$in_left_set" ] && left_set="$in_left_set"
		[ -n "$in_right_set" ] && right_set="$in_right_set"
		[ -n "$in_right_prefix_addr" ] && right_prefix_addr="$in_right_prefix_addr"
		[ -n "$in_right_prefix_len" ] && right_prefix_len="$in_right_prefix_len"

#		echo "<pre>[$i] ($obj) $rule</pre>"
#		echo "<pre>[$i] $in_target,$drop,$accept,$left,$right</pre>"

		if [ -n "${target}" ]; then
			link="<a href=\"firewall.cgi?ipt_table=${table}&ipt_chain=${target}\">${target}</a>"
		else
			[ -n "$drop" ] && link="drop"
			[ -n "$accept" ] && link="accept"
		fi

		unset iface_in
		unset iface_out
		unset prot
		unset params
		unset opt
		unset src dest

		if [ "$op" = "==" ]; then
			[ "$key" = "iifname" ] && iface_in="$right"
			[ "$key" = "oifname" ] && iface_out="$right"
			[ "$key" = "l4proto" ] && prot="$right"
			if [ -n "$in_left_proto" ]; then
			 	prot="$in_left_proto"
				params="$params $in_left_field: $right"
			fi
			if [ -n "$left_payload" ]; then
				params="$params $left_payload"
#				unset iface_in
#				unset iface_out
			fi
			if [ "$left_field" = "saddr" ]; then
				src="$right_prefix_addr/$right_prefix_len"
			fi
			if [ "$left_field" = "daddr" ]; then
				dest="$right_prefix_addr/$right_prefix_len"
			fi
			[ -n "$left_set" ] && iface_in="$(echo $left_set | sed 's# #<br>#g')"
			[ -n "$right_set" ] && iface_in="$(echo $right_set | sed 's# #<br>#g')"
		fi

		if [ "$op" = "in" ]; then
			[ "$ct_key" = "state" ] && params="$params state: $right_array"
		fi

		#opt="[$left_field] $right_prefix_addr/$right_prefix_len"
	done
	echo "<tr class=\"colortoggle"${T}"\"><td>${pkg}</td><td>${bytes}</td><td>${link}</td><td>${prot}</td><td>$opt</td><td>$iface_in</td><td>$iface_out</td><td>${src}</td><td>${dest}</td><td>${params}</td><td>"${comment}"</td></tr>"

	if [ $T = 1 ]; then
		T=2
	else
		T=1
	fi
done

cat<<EOF
</table>
</fieldset>
EOF
}

cat<<EOM
	<b>nft:</b>	<a href="nft.json">json dump</a>
	<br/>
	<br/>
EOM

ipt_table=${ipt_table:-filter}
ip_version=${ip_version:-ipv4}

if [ -z "$ipt_table" -o -z "$ipt_chain" -o -z "$ip_version" ]; then

	case $ipt_table in
		filter)
			show_table $ipt_table input $ip_version
			show_table $ipt_table forward $ip_version
			show_table $ipt_table output $ip_version
			;;
		nat)
			show_table $ipt_table prerouting $ip_version
			show_table $ipt_table input $ip_version
			show_table $ipt_table output $ip_version
			show_table $ipt_table postrouting $ip_version
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

. /usr/lib/www/page-post.sh
