#!/bin/bash

inputfile=fileinfo.json		# contains only filename (no model,model2 is set)
lookupfile=y.json		# contains model,model2,filename
outputfile=fileinfo.out.json	# merged new file

OPT="--raw-output"

>$outputfile


# run through each record and check
i=0
while true
do
 r=$(cat $inputfile | jq $OPT '.fileinfo['$i']')
 test "$r" = "null" && break

 _filename="$(echo "$r" | jq $OPT '.filename')"

 echo "filename: $_filename"

 r="$(cat $lookupfile | jq '.fileinfo[] | select(.filename == "'$_filename'")')"
#echo "################################################"
#echo $r
 _name="$(echo "$r" | jq $OPT '.name')"
 _u="$(echo "$r" | jq $OPT '.autoupdate')"
 _m1="$(echo "$r" | jq $OPT '.model')"
 _m2="$(echo "$r" | jq $OPT '.model2')"
 _f="$(echo "$r" | jq $OPT '.filename')"
 _c="$(echo "$r" | jq $OPT '.comment')"

 test "$_name" = "null" && _name=""
 test "$_u" = "null" && _u="0"
 test "$_m1" = "null" && _m1=""
 test "$_m2" = "null" && _m2=""
 test "$_c" = "null" && _c=""

# echo "name:$_name"
# echo "u:$_u"
# echo "m1:$_m1"
# echo "m2:$_m2"
# echo "f:$_f"
# echo "c:$_c"

 if [ "${_filename/sysupgrade/}" = "$_filename" ]; then
	# factory
	printf '{ "name":"%s", "filename":"%s", "comment":"%s"},\n' "$_name" "$_filename" "$_c" >>$outputfile
 else
	# sysupgrade
	printf '{ "name":"%s", "autoupdate":"%s", "model":"%s", "model2":"%s", "filename":"%s", "comment":"%s"},\n' "$_name" "$_u" "$_m1" "$_m2" "$_filename" "$_c" >>$outputfile
 fi

 i=$((i+1))
done
exit

