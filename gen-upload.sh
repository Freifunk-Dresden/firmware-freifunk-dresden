#!/bin/bash
#
#
# copy firwmare,packets and generate download.json 

# -------------------------------------------------------------------

#Black        0;30     Dark Gray     1;30
#Red          0;31     Light Red     1;31
#Green        0;32     Light Green   1;32
#Brown/Orange 0;33     Yellow        1;33
#Blue         0;34     Light Blue    1;34
#Purple       0;35     Light Purple  1;35
#Cyan         0;36     Light Cyan    1;36
#Light Gray   0;37     White         1;37
C_NONE='\033[0m' # No Color
C_GREY='\033[1;30m'
C_RED='\033[0;31m'
C_LRED='\033[1;31m'
C_GREEN='\033[0;32m'
C_LGREEN='\033[1;32m'
C_ORANGE='\033[0;33m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_LBLUE='\033[1;34m'
C_PURPLE='\033[0;35m'
C_LPURPLE='\033[1;35m'
C_CYAN='\033[0;36m'
C_LCYAN='\033[1;36m'
C_GREY='\033[0;37m'
C_LGREY='\033[1;37m'

#################################################################################################
# parameter check and define variables 
#################################################################################################

#parameter check
if [ -z "$1" ]; then
	printf "${0##*/} <all | json>[<directory-suffix>]\n"
	printf "Version 5\n"
	printf "   all                  - generates all (incl.copying files)\n"
	printf "   json                 - only updates download.json\n"
	printf "   directory-suffix     - optional. if defined firmware files are created in different directory '.file.<directory_suffix>'\n"
	printf "\n"
	exit 1
fi

# DEVEL: can be set to false to when only debugging index-generation and generation of download.json stuff
case "$1" in
	"all") 	ENABLE_COPY=true
		;;
	"json") ENABLE_COPY=false
		;;
	*) 	printf "invalid parameter\n"
		exit 1
		;;
esac

OUTPUT_BASE_DIR="final_output"
OUTPUT_DOWNLOAD_JSON_FILENAME="download.json"
OUTPUT_DOWNLOAD_JSON_JS_FILENAME="download.json.js"
UPLOAD_INFO_DIR="upload-infos"
INPUT_FILEINFO_JSON_FILENAME="fileinfo.json"
# this file is generated to reflect any updated files. means when new files are added
OUTPUT_FILEINFO_JSON_FILENAME="fileinfo.json.new-generated"

#get apsolute path before changing to it.
firmwareroot="$PWD"
directory_suffix=$2

# save PATH (needed to add build root binaries for different openwrt versions)
SAVED_SYSTEM_PATH=$PATH

#extract version files to extract directory components
fwversion="$(cat $firmwareroot/files/common/etc/version)"
fwdate="$(date)"

if [ -z "$fwversion" ]; then
	printf "ERROR: firmware version not detected (invalid path)\n"
	exit 1
fi

printf "detected firmware version: $fwversion\n"

#get path of this script (upload dir) and change to it
cd $PWD/${0%/*}
output_dir="$PWD/$OUTPUT_BASE_DIR"
info_dir="$PWD/$UPLOAD_INFO_DIR"

# check if a different directory is used to create files in
if [ -n "$directory_suffix" ]; then
	output_dir=$output_dir."$directory_suffix"
	printf "use output dir: $output_dir\n"
fi

target_dir=$output_dir/$fwversion

#################################################################################################
# functions 
#################################################################################################

gen_download_json_start()
{
  output_path="$1" # output path "firmware/4.2.15"
  fw_version="$2" # firmware version
  fw_date="$3" # build date

	printf $C_YELLOW"create download.json"$C_NONE"\n"

	> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME

	printf "{\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
	printf " \"json_version\":\"1\",\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
	printf " \"firmware_version\":\"$fw_version\",\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
	printf " \"firmware_date\":\"$fw_date\",\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
	printf " \"fileinfo\": [\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME

	# generate new input file
	> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
	printf "{\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
	printf " \"comment\":\"input file to generate final download.json via gen-upload.sh\",\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
	printf " \"json_version\":\"1\",\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
	printf " \"fileinfo\": [\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
}

# used to add a single entry
#gen_download_json_add_single_link()
#{
#  name=$1
#  file=$2
#  output_path=$3
#  printf "{ \"name\":\"$name\", \"path\":\".\", \"filename\":\"$file\", \"md5sum\":\"\",\"comment\":\"\"},\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
#}

# isFirstFile must be global, else calling this function for different
# platforms won't insert "," after each record
isFirstFile=true
gen_download_json_add_data()
{
  output_path=$1 	# output path "firmware/4.2.15"
  subpath=$2 		# relativ path to firmware "ar71xx/generic" 
  file_filter=$3 	# file filter "*.{bin,trx,img,dlf,gz}"

	printf "add files to download.json\n"
	# progress info
	printf $C_LBLUE"# info complete"$C_ORANGE"	+ some info missing"$C_LRED"	- NO info"$C_NONE"\n"

	# get info for each filename
	# eval is needed because file_filter must be avaluated
	for path in $(eval ls -1 $output_path/$subpath/$file_filter 2>/dev/null )
	do
		file=$(basename $path)
#printf "$file\n"
		# defaults
		name=""
		autoupdate="0"
		model=""
		model2=""
		md5sum=""
		filename=""
		comment="new file"

		# search file info 
		# jq: first selects the array with all entries and every entry is pass it to select().
		#	select() checks a condition and returns the input data (current array entry)
		#	if condition is true
		# Die eckigen klammern erzeugt ein array, in welches alle gefundenen objekte mit gleichem FILENAMEN gesammelt werden.
		# Fuer die meisten filenamen ist das array 1 gross. aber fuer files die fuer verschiedene router
		# verwendet werden, koennen mehrere eintraege sein.
		info_array=$(cat $info_dir/$INPUT_FILEINFO_JSON_FILENAME | jq "[ .fileinfo[] | select(.filename == \"$file\") ]")
#printf "info_array:$info_array\n"


		OPT="--raw-output"

		# run through each array (siehe kommentar zuvor)
		idx=0
		while true
		do
			# in case new files are present which are not in fileinfo, we need to create empty entries in
			# download.json and fileinfo.json
			if [ "$info_array" = "[]" ]; then
				# on second loop we need to break 
				test "$idx" != "0" && break;
			else
				info=$(echo "$info_array" | jq ".[$idx]")
#printf "idx:%d info:$info\n" $idx
				#info_array holds one entry for each device that is using same firmware image
				#Normally it contains only one entry. 
				test "$info" = "null" && break;
	
				autoupdate="$(echo $info | jq $OPT '.autoupdate')"
				[ "$autoupdate" = "null" ] && autoupdate="0"		# default disable auto update

				model="$(echo $info | jq $OPT '.model')"
				model2="$(echo $info | jq $OPT '.model2')"
				filename="$(echo $info | jq $OPT '.filename')"
				comment="$(echo $info | jq $OPT '.comment')"
				name="$(echo $info | jq $OPT '.name')"
			fi
#printf "##$name:$autoupdate:$model:$model2:$filename::$comment\n"

			# determine "sysupgrade" files
			if [   	-z "${file/*sysupgrade*/}" \
			     -o	-z "${file/*x86-generic*/}" ]
			then
				sysupgrade=1
			else
				sysupgrade=0
			fi

			# progress bar only for files where I add model/model2 information
			if [ $sysupgrade = 1 ]; then
				if [ -n "$model" -a -n "$model2" ]; then
					printf $C_LBLUE"#"$C_NONE
				else
					if [ -n "$model" -o -n "$model2" ]; then
						printf $C_ORANGE"+"$C_NONE
					else
						printf $C_LRED"-"$C_NONE
					fi
				fi
			fi

			md5sum=$(md5sum $path | cut -d' ' -f1)

			# append comma
			$isFirstFile || {
				printf ",\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
				printf ",\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
			}
			isFirstFile=false

			# generate download.json and new fileinfo.json
			if [ $sysupgrade = 1 ]; then
				printf "{ \"name\":\"$name\", \"autoupdate\":\"$autoupdate\", \"model\":\"$model\", \"model2\":\"$model2\", \"path\":\"$subpath\", \"filename\":\"$file\", \"md5sum\":\"$md5sum\", \"comment\":\"$comment\"}" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME

				# generate new input info file
				printf "{ \"name\":\"$name\", \"autoupdate\":\"$autoupdate\",  \"model\":\"$model\", \"model2\":\"$model2\", \"filename\":\"$file\", \"comment\":\"$comment\"}" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
			else
				printf "{ \"name\":\"$name\", \"path\":\"$subpath\", \"filename\":\"$file\", \"md5sum\":\"$md5sum\", \"comment\":\"$comment\"}" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME

				# generate new input info file
				printf "{ \"name\":\"$name\", \"filename\":\"$file\", \"comment\":\"$comment\"}" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
			fi

			idx=$(( idx + 1 ))
		done
	done
	printf "\n"
}

gen_download_json_end()
{
 	output_path=$1	# output path "firmware/4.2.15"

	printf "close download.json\n"
	printf " ]\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
	printf "}\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME

	# close new input info file
	printf " ]\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
	printf "}\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
}


#p=/tmp
#gen_download_json_start $p 4.2.15
#gen_download_json_add_data $p /home/freifunk/upload-firmware/files/4.2.15 ar71xx/generic "*.{bin,trx,img,dlf,gz}"
#gen_download_json_end $p
#printf "ok\n"
#exit

#################################################################################################
# main script start 
#################################################################################################

#################################################################################################
# prepare output dir  
#################################################################################################
mkdir -p $output_dir
$ENABLE_COPY && {
	printf " delete old directory: $target_dir\n"
	rm -rf $target_dir
}

mkdir -p $target_dir
mkdir -p $target_dir/downloaded_packages
#mkdir -p $target_dir/sources
printf "$fwversion\n" >$target_dir/version

#################################################################################################
# start json
#################################################################################################
gen_download_json_start "$target_dir" "$fwversion" "$fwdate"


#################################################################################################
# copy build dl  
#################################################################################################
$ENABLE_COPY && {
	printf $C_YELLOW"copy downloaded packages"$C_NONE"\n"
	cp -a $firmwareroot/dl/* $target_dir/downloaded_packages/
#	gen_download_json_add_single_link '[downloaded_packages]' 'downloaded_packages' $target_dir
}

#################################################################################################
# copy other files/sources  
#################################################################################################

#changelog
$ENABLE_COPY && {
	printf $C_YELLOW"copy changelog"$C_NONE"\n"
	cp -a $firmwareroot/changelog.txt $target_dir/
#	gen_download_json_add_single_link 'changelog.txt' 'changelog.txt' $target_dir
}

#licenses
$ENABLE_COPY && {
	printf $C_YELLOW"copy licenses"$C_NONE"\n"
	cp -a $firmwareroot/license $target_dir/
#	gen_download_json_add_single_link '[license]' 'license' $target_dir
}

$ENABLE_COPY && {
	printf $C_YELLOW"copy www"$C_NONE"\n"
	cp -a $info_dir/files/index.html $target_dir/
	cp -a $info_dir/files/_res $target_dir/
}
printf "finished.\n"

#################################################################################################
# copy firmware 
#################################################################################################



# run through all openwrt version (targets may be created for different openwrt versions)
for _buildroot in $(ls -1 $firmwareroot/workdir/)
do
	printf $C_YELLOW"build root:"$C_NONE"["$C_GREEN"$_buildroot"$C_NONE"]\n"

	buildroot=$firmwareroot/workdir/$_buildroot

	# add binaries to host tools so mkhash will be found when
	# calling ipkg-make-index.sh
	export PATH=$SAVED_SYSTEM_PATH:$buildroot/staging_dir/host/bin/

	_platforms=$buildroot/bin/targets

#	# add directory entry into download json, so it can be displayed in dataTable (index.html)
#	for platform in $(ls $_platforms)
#	do
#		gen_download_json_add_single_link "[$platform]" "$platform" $target_dir
#	done

	for platform in $(ls $_platforms)
	do
		printf $C_YELLOW"platform:"$C_NONE" ["$C_GREEN"$platform"$C_NONE"]\n"

		mkdir -p $target_dir/$platform
	
		for subplatform in $(ls $buildroot/bin/targets/$platform)
		do
			mkdir -p $target_dir/$platform/$subplatform

			filefilter="*.{bin,trx,img,dlf,gz,tar}"
			$ENABLE_COPY && {
				printf "copy $buildroot/bin/targets/$platform/$subplatform/$filefilter $target_dir/$platform/$subplatform\n"
				# use "eval" to resolv filefilter wildcards
				eval cp -a $buildroot/bin/targets/$platform/$subplatform/$filefilter $target_dir/$platform/$subplatform 2>/dev/null
			}

			#create md5sums file used when automatically or manually downloading via firmware.cgi
			# solange das file erzeugen, wie software mit alter firmware drausen ist
			# oder github 
			p=$(pwd)
			cd $target_dir/$platform/$subplatform
			printf $C_YELLOW"calculate md5sum"$C_NONE"\n"
			md5sum * > $target_dir/$platform/$subplatform/md5sums
			cd $p

			#copy packages 
			mkdir -p $target_dir/$platform/$subplatform/packages
			printf "search package dir: $buildroot/bin/targets/$platform/$subplatform/packages/\n"
			for package in $(cat $info_dir/packages)
			do
				printf $C_YELLOW"process package: "$C_GREEN"$package"$C_NONE"\n"
				filename=$(find $buildroot/bin/targets/$platform/$subplatform/packages/ -name "$package""_*.ipk" -print 2>/dev/null)
	#			printf "package filename: $filename\n"

				test -z "$filename" && printf $C_ORANGE"WARNING: no package file found for "$C_NONE"$package\n"
				$ENABLE_COPY && {
	#			printf "copy package: $package -> [$filename]\n"
					test -n "$filename" && cp -a $filename $target_dir/$platform/$subplatform/packages/
				}
			done

			printf $C_YELLOW"generate package index"$C_NONE"\n"
			p=$(pwd)
			cd $target_dir/$platform/$subplatform/packages/
			$buildroot/scripts/ipkg-make-index.sh . > Packages
			gzip -f Packages
			cd $p
		
			gen_download_json_add_data $target_dir $platform/$subplatform $filefilter
		done # for sub platform
	done	# for platform
done # for buildroot

gen_download_json_end $target_dir

# generate js file
cat << EOM > $target_dir/$OUTPUT_DOWNLOAD_JSON_JS_FILENAME
var data = $(cat $target_dir/$OUTPUT_DOWNLOAD_JSON_FILENAME) ;
EOM


printf "FINISHED: files are copied to directory [$target_dir]\n"


