#!/bin/sh
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

mode="$(uci -q get ddmesh.network.wifi5g_mode)"
[ "$mode" = "normal" ] && ifname5g="wifi5ap" || ifname5g="wifi-client5g"

prefix="wifi_status"
radio2g_present="0"
radio2g_phy=""
radio2g_dev="wifi2ap"	# use interface that is always present
radio2g_airtime=""
radio2g_mode_ap=""
radio2g_mode_mesh=""

radio5g_present="0"
radio5g_phy=""
radio5g_dev="$ifname5g"	# use interface that is always present
radio5g_airtime=""
radio5g_mode_ap=""
radio5g_mode_mesh=""

get_phy_list()
{
  local phy_list=""
  for p in $(ls -1 /sys/class/ieee80211)
  do
    phy_list="$phy_list $p"
  done
  echo "$phy_list"
}

get_htmode()
{
	phy="$1"

	# wifi config uses /lib/wifi/mac80211.uc to select htmod
	# it has a hard coded order
	htmode_order="EHT HE VHT HT"
	unset htmode

	IFS=' '
	for order in $htmode_order
	do
		for m in $(iwinfo "$phy" htmodelist)
		do
			m2="${m//[0-9]/}"
			if [ -z "$htmode" -a "$m2" = "$order" ]; then
				htmode="$order"
			fi
		done
	done
  unset IFS

	test -z "$htmode" && htmode="HT"

	echo "$htmode"
}

# gets wifi dev
# returns RAW airtime: "$ACT,$BUS,$REC,$TRA"
airtime()
{
 dev=$1

 TEMP=$(iw dev $dev survey dump 2>/dev/null | grep -e "in use" -A6)
 if [ -n "$TEMP" ]; then
		let ACT=$(echo "$TEMP" | grep active | head -n 1 | grep -o '[0-9]*')+1
		let BUS=$(echo "$TEMP" | grep busy | head -n 1 | grep -o '[0-9]*')+0
		let REC=$(echo "$TEMP" | grep receive | head -n 1 | grep -o '[0-9]*')+0
		let TRA=$(echo "$TEMP" | grep transmit | head -n 1 | grep -o '[0-9]*')+0
 fi
 echo "$ACT,$BUS,$REC,$TRA"
}


if [ "$1" == "store" ]; then

	# ensure we have a file (uci needs it)
	touch /etc/config/wireless

	for phy in $(get_phy_list)
	do
#echo "[phy=$phy]"

		htmode="$(get_htmode "$phy")"
#echo "[htmode=$htmode]"

		unset freq2
		unset freq5

		# check for channel (one radio might support 2.4 and 5GHz)
		# prefer 2g
		freq2="$(iwinfo $phy freqlist | sed -n 's#[ *]*\([0-9]\).*$#\1#;/^2/{p;q}')"
		freq5="$(iwinfo $phy freqlist | sed -n 's#[ *]*\([0-9]\).*$#\1#;/^5/{p;q}')"

#echo "[freq2=$freq2; freq5=$freq5]"

		# get wifi capabilities
		eval $(iw $phy info | awk '
			BEGIN{found=0;};
			/^\tvalid interface combinations:/{found=1;next};
			/^\t[[:alpha:]]/{found=0};
			found{
				mode_ap=0
				mode_mesh=0
				split($0,a,"#");
				for(e in a)
				{
					line=a[e];
					split(line,count,"=")
					if(match(line,/AP/)){mode_ap=count[2];}
					if(match(line,/mesh point/)){mode_mesh=count[2];}
				}
				found=0
			}
			END{ printf("mode_ap=%d; mode_mesh=%d", mode_ap, mode_mesh);}
		')
#echo "[mode_ap=$mode_ap; mode_mesh=$mode_mesh]"
#echo "$freq2, $radio2g_present"

		if [ "$freq2" = "2" ] && [ "$radio2g_present" != "1" ]; then
			radio2g_present=1
			radio2g_phy=$phy
			radio2g_mode_ap="$mode_ap"
			radio2g_mode_mesh="$mode_mesh"
			radio2g_htmode="$htmode"

		elif [ "$freq5" = "5" ]; then
			radio5g_present=1
			radio5g_phy=$phy
			radio5g_mode_ap="$mode_ap"
			radio5g_mode_mesh="$mode_mesh"
			radio5g_htmode="$htmode"
		fi
	done

	# store in /etc/wireless for faster access (/dev/null to suppress output)
	test -z "$(uci -q get wireless.ddmesh)" && uci -q add wireless ddmesh >/dev/null
	uci -q rename wireless.@ddmesh[-1]='ddmesh'
	uci -q set wireless.ddmesh.radio2g_present="${radio2g_present:=0}"
	uci -q set wireless.ddmesh.radio2g_phy="$radio2g_phy"
	uci -q set wireless.ddmesh.radio2g_mode_ap="$radio2g_mode_ap"
	uci -q set wireless.ddmesh.radio2g_mode_mesh="$radio2g_mode_mesh"
	uci -q set wireless.ddmesh.radio2g_htmode="$radio2g_htmode"

	uci -q set wireless.ddmesh.radio5g_present="${radio5g_present:=0}"
	uci -q set wireless.ddmesh.radio5g_phy="$radio5g_phy"
	uci -q set wireless.ddmesh.radio5g_mode_ap="$radio5g_mode_ap"
	uci -q set wireless.ddmesh.radio5g_mode_mesh="$radio5g_mode_mesh"
	uci -q set wireless.ddmesh.radio5g_htmode="$radio5g_htmode"
	uci -q commit
fi

_radio2g_present="$(uci -q get wireless.ddmesh.radio2g_present)"
echo export $prefix"_radio2g_present"="$(uci -q get wireless.ddmesh.radio2g_present)"
if [ "$_radio2g_present" = "1" ]; then
	echo export $prefix"_radio2g_phy"="$(uci -q get wireless.ddmesh.radio2g_phy)"
	echo export $prefix"_radio2g_mode_ap"="$(uci -q get wireless.ddmesh.radio2g_mode_ap)"
	echo export $prefix"_radio2g_mode_mesh"="$(uci -q get wireless.ddmesh.radio2g_mode_mesh)"
	echo export $prefix"_radio2g_htmode"="$(uci -q get wireless.ddmesh.radio2g_htmode)"
	echo export $prefix"_radio2g_airtime"="$(airtime ${radio2g_dev})"
fi

_radio5g_present="$(uci -q get wireless.ddmesh.radio5g_present)"
echo export $prefix"_radio5g_present"="$(uci -q get wireless.ddmesh.radio5g_present)"
if [ "$_radio5g_present" = "1" ]; then
	echo export $prefix"_radio5g_phy"="$(uci -q get wireless.ddmesh.radio5g_phy)"
	echo export $prefix"_radio5g_mode_ap"="$(uci -q get wireless.ddmesh.radio5g_mode_ap)"
	echo export $prefix"_radio5g_mode_mesh"="$(uci -q get wireless.ddmesh.radio5g_mode_mesh)"
	echo export $prefix"_radio5g_htmode"="$(uci -q get wireless.ddmesh.radio5g_htmode)"
	echo export $prefix"_radio5g_airtime"="$(airtime ${radio5g_dev})"
fi
