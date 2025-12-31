#!/bin/bash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de
# GNU General Public License Version 3

#
#
# copy firwmare,packets and generate download.json

# -------------------------------------------------------------------
VERSION="11"

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
usage()
{
cat << EOM
${0##*/} all | json | only-verify-json | pretty <json-file> |  | [directory-suffix]
Version ${VERSION}
commands:
  all              [directory-suffix]      - generates all (incl.copying files)
  json             [directory-suffix]      - only updates download.json
  only-verify-json [directory-suffix]      - only compare fileinfo.json against last generated version
  pretty <download.json | fileinfo.json>   - reads file info json from file and prints
                                               sorted (by sortkey) json on stdout
  show-multiple-used-files <download.json | fileinfo.json>
                                           - shows filenames that are used more than once

  [directory-suffix] if defined firmware files are created in different
  directory '.file.<directory_suffix>'

EOM
	exit 1
}

# DEVEL: can be set to false to when only debugging index-generation and generation of download.json stuff
case "$1" in
	"all") 	ENABLE_COPY=true
		      ENABLE_GENERATE=true
          directory_suffix=$2
		      ;;

	"json") ENABLE_COPY=false
		      ENABLE_GENERATE=true
          directory_suffix=$2
		      ;;

	"only-verify-json")
		      ENABLE_COPY=false
		      ENABLE_GENERATE=false
          directory_suffix=$2
      		;;

	"pretty")
      		if [ -z "$2" ]; then
      			printf "missing file\n"
      			exit 1
      		fi
      		cat "$2" | jq '{comment,json_version,"fileinfo": .fileinfo | sort_by(.sortkey) }'
      		exit 0
      		;;

	"show-multiple-used-files")
      		if [ -z "$2" ]; then
      			printf "missing json file\n"
      			exit 1
      		fi
      		cat "$2" | jq '[ .fileinfo[] | select(.filename | contains("sysupgrade")) ] |  (.  - unique_by(.filename))[] | .filename'
      		exit 0
      		;;

	*)
    test -n "$1" &&	printf "invalid parameter\n"
		usage
		exit 1
		;;
esac

OUTPUT_BASE_DIR="final_output"
OUTPUT_FIRMWARE_SUB_DIR="firmware"
OUTPUT_DOWNLOAD_JSON_FILENAME="download.json"
OUTPUT_DOWNLOAD_JSON_JS_FILENAME="download.json.js"
UPLOAD_INFO_DIR="fw-upload-infos"
INPUT_FILEINFO_JSON_FILENAME="fileinfo.json"
# this file is generated to reflect any updated files. means when new files are added
OUTPUT_FILEINFO_JSON_FILENAME="fileinfo.json.new-generated"
GENERATED_FIRMWARE_OUTPUT_DIR="workdir/_output"
GENERATED_FIRMWARE_VERSION_FILE="version"

#get apsolute path before changing to it.
PROJECT_DIR="$PWD"

# save PATH (needed to add build root binaries for different openwrt versions)
SAVED_SYSTEM_PATH=$PATH

fwdate="$(date)"

# when running from gitlab only specific revision is cloned. there are no branch infos.
# So I check if FF_BUILD_TAG is set and then use this. If not defined I use
# the one I can determine.
git_ddmesh_rev="$(git log -1 --format=%H)"
if [ -n "$FF_BUILD_TAG" ]; then
	git_ddmesh_branch="$FF_BUILD_TAG"
else
	git_ddmesh_branch="$(git name-rev --tags --name-only $git_ddmesh_rev | sed 's#.*/##')"

	if [ "$git_ddmesh_branch" = "undefined" ]; then
		git_ddmesh_branch="$(git branch | sed -n 's#^\* \(.*\)#\1#p')"
	fi
fi
printf "${C_LPURPLE}git_ddmesh_branch:${C_NONE} $git_ddmesh_branch\n"
printf "${C_LPURPLE}git_ddmesh_rev:${C_NONE} $git_ddmesh_rev\n"
fw_branch="$git_ddmesh_branch"
fw_rev="$git_ddmesh_rev"


#get path of this script (upload dir) and change to it
cd $PWD/${0%/*}
final_output_dir="$PWD/$OUTPUT_BASE_DIR"
info_dir="$PWD/$UPLOAD_INFO_DIR"

# check if a different directory is used to create files in
if [ -n "$directory_suffix" ]; then
	final_output_dir=$final_output_dir."$directory_suffix"
	printf "use output dir: $final_output_dir\n"
fi

mkdir -p ${final_output_dir}

#################################################################################################
# functions
#################################################################################################

gen_download_json_start()
{
	output_path="$1" # output path "firmware/4.2.15"
	fw_date="$2" # build date
	fw_branch="$3" # ddmesh repository branch or tag
	fw_rev="$4" # ddmesh git hash

# diese version wird von der alten firmware geprueft, um ein autoupdate oder ein
# update via button zu erlauben.
# neue versionen prüfen auf die firmware version innerhalb ihren eintrages.
	fw_version="9.0.0"

	printf "${C_YELLOW}create download.json${C_NONE} [$output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME]\n"

	> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME

	printf "{\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
	printf " \"json_version\":\"2\",\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
  printf " \"firmware_version\":\"$fw_version\",\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
	printf " \"firmware_date\":\"$fw_date\",\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
	printf " \"firmware_branch\":\"$fw_branch\",\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
	printf " \"firmware_rev\":\"$fw_rev\",\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
	printf " \"fileinfo\": [\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME

	# generate new input file
	> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
	printf "{\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
	printf " \"comment\":\"input file to generate final download.json via gen-upload.sh\",\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
	printf " \"json_version\":\"2\",\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
	printf " \"fileinfo\": [\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
}

# used to add a single entry
#gen_download_json_add_single_link()
#{
#  name=$1
#  file=$2
#  output_path=$3
#  printf "{ \"name\":\"$name\", \"path\":\".\", \"filename\":\"$file\", \"md5sum\":\"\",\"sha256sum\":\"\",\"comment\":\"\"},\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
#}

# isFirstFile must be global, else calling this function for different
# platforms won't insert "," after each record
isFirstFileDL=1
isFirstFileInfo=1
gen_download_json_add_data()
{
	output_path="$1" 	# output path "final_output/"
	subpath="$2" 		# relativ path to firmware "firmware/8.3.0/ramips.24.mt7621.generic"
	file_filter="$3" 	# file filter "*.{bin,trx,img,itb,dlf,gz}"
	fw_version="$4" # freifunk firmware version

	error=0

	printf "    ${C_YELLOW}adding firmware to download.json${C_NONE} - file filter: $file_filter\n"

	# progress info
	printf "    ${C_LBLUE}# model info complete${C_NONE} | ${C_ORANGE}+ partly model info missing${C_NONE} | ${C_LRED}- NO model info${C_NONE} | ${C_LPURPLE}. disabled${C_NONE}\n"
	printf "    ["

	# get info for each filename
	# eval is needed because file_filter must be evaluated
	for path in $(eval ls -1 $output_path/$subpath/$file_filter 2>/dev/null )
	do
		file=$(basename $path)
		# only contains the "device-part"
		#   freifunk-dresden-v8.2.5-22.03.6-ramips-mt76x8-tplink_re200-v2-initramfs-kernel.bin
		# becomes:  ramips-mt76x8-tplink_re200-v2-initramfs-kernel.bin
		# This is used to filter filename entries and as sort-key
		file_device_part_name="$(echo "$file" | sed 's#^freifunk-dresden-v\([0-9.]\+\)-\([0-9.]\+\)-\(snapshot-\)*##')"
#printf "$file\n"
#printf "$file_device_part_name\n"

		# defaults
		disabled="0"
		name=""
		autoupdate="0"
		model=""
		model2=""
		md5sum=""
		sha256sum=""
		filename=""
		comment=""

		# search file info. Key is the filename
		# jq: first selects the array with all entries and every entry is pass to select().
		#	select() checks a condition and returns the input data (current array entry)
		#	if condition is true
		# Die eckigen klammern erzeugt ein array, in welches alle gefundenen objekte mit gleichem FILENAMEN gesammelt werden.
		# Fuer die meisten filenamen ist das array 1 gross (firmware file nur von einem router genutzt).
		# aber fuer files die fuer verschiedene router verwendet werden, koennen mehrere eintraege enthalten sein.
		if [ -f "$info_dir/$INPUT_FILEINFO_JSON_FILENAME" ]; then
			# info_array=$(cat $info_dir/$INPUT_FILEINFO_JSON_FILENAME | jq "[ .fileinfo[] | select(.filename == \"$file\") ]")

			# first try to find exact match.
			info_array=$(cat $info_dir/$INPUT_FILEINFO_JSON_FILENAME | jq "[ .fileinfo[] | select(.filename == \"$file\") ]")

			# if nothing was found, then it is likly that the openwrt version has changed.
			# so try only "device part" of name
			if [ "$info_array" = "[]" ]; then
			 info_array=$(cat $info_dir/$INPUT_FILEINFO_JSON_FILENAME | jq "[ .fileinfo[] | select(.filename | test(\"$file_device_part_name\") ) ]")
			fi
		else
			info_array="[]"
		fi
# echo "$file=info_array:$info_array\n"


		OPT="--raw-output"

		# run through each array (siehe kommentar zuvor)
		# one file can be used for more than one device/model.
		# -> this means that we must loop through all fileinfo.json entries to find all entries that are using
		#    current filename.
		# At least run this loop once to store new file names if info_array was empty.
		idx=0
		while true
		do
			# try reading infos
			if [ "$info_array" != "[]" ]; then
				info=$(echo "$info_array" | jq ".[$idx]")
#printf "idx:%d info:$info\n" $idx

				# no more entries
				test "$info" = "null" && break;

				autoupdate="$(echo $info | jq $OPT '.autoupdate')"
				[ "$autoupdate" = "null" ] && autoupdate="0"		# default disable auto update

				# router is disabled, no error for missing files/or when router is present
				disabled="$(echo $info | jq $OPT '.disabled')"; [ "$disabled" = "null" ] && disabled="0"

				model="$(echo $info | jq $OPT '.model')"; [ "$model" = "null" ] && model=""
				model2="$(echo $info | jq $OPT '.model2')"; [ "$model2" = "null" ] && model2=""
				filename="$(echo $info | jq $OPT '.filename')"
				comment="$(echo $info | jq $OPT '.comment')"; [ "$comment" = "null" ] && comment=""
				name="$(echo $info | jq $OPT '.name')"; [ "$name" = "null" ] && name=""
			fi
#printf "##$name:$autoupdate:$model:$model2:$filename:$comment\n"

# trx file wird nur von ac68u fuer factory und sysupgrade verwendet.
			# determine "sysupgrade" files
			if [   	-z "${file/*-*-sysupgrade.*/}" \
					 -o	-z "${file/*-*-squashfs.trx*/}" \
					 -o	-z "${file/*-*-combined.img.gz*/}" \
					 -o	-z "${file/*-*-sdcard.img.gz*/}" ]
			then
				sysupgrade=1
			else
				sysupgrade=0
			fi

			# progress bar only for files where I add model/model2 information
			if [ $sysupgrade = 1 ]; then
				if [ "$disabled" = "1" ]; then
						printf "${C_LPURPLE}.${C_NONE}"
				else
					if [ -n "$model" -a -n "$model2" ]; then
						printf "${C_LBLUE}#${C_NONE}"
					else
						if [ -n "$model" -o -n "$model2" ]; then
							printf "${C_ORANGE}+${C_NONE}"
						else
							printf "${C_LRED}-${C_NONE}"
						fi
					fi
				fi
			fi

			md5sum=$(md5sum $path | cut -d' ' -f1)
			sha256sum=$(sha256sum $path | cut -d' ' -f1)


			# append comma
			if [ "$isFirstFileDL" = "0" ]; then
				if [ "$disabled" = "0" ]; then
					printf ",\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
				fi
			 fi
			if [ "$isFirstFileInfo" = "0" ]; then
				printf ",\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
			 fi

			# generate download.json and new fileinfo.json
			if [ $sysupgrade = 1 ]; then

				if [ "$disabled" = "0" ]; then
					printf "{ \"version\":\"$fw_version\", \"name\":\"$name\", \"autoupdate\":\"$autoupdate\", \"model\":\"$model\", \"model2\":\"$model2\", \"path\":\"$subpath\", \"filename\":\"$file\", \"md5sum\":\"$md5sum\", \"sha256sum\":\"$sha256sum\", \"comment\":\"$comment\"}" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
				fi

				# generate new input info file (and remember source of firmware file, for error checking during gen_upload.sh)
				printf "{ \"disabled\":\"$disabled\", \"name\":\"$name\", \"sortkey\":\"${file_device_part_name}\", \"autoupdate\":\"$autoupdate\", \"model\":\"$model\", \"model2\":\"$model2\", \"filename\":\"$file\", \"comment\":\"$comment\"}" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
			else

				if [ "$disabled" = "0" ]; then
					printf "{ \"version\":\"$fw_version\", \"name\":\"$name\", \"path\":\"$subpath\", \"filename\":\"$file\", \"md5sum\":\"$md5sum\", \"sha256sum\":\"$sha256sum\", \"comment\":\"$comment\"}" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
				fi

				# generate new input info file
				printf "{ \"disabled\":\"$disabled\", \"name\":\"$name\", \"sortkey\":\"${file_device_part_name}\", \"filename\":\"$file\", \"comment\":\"$comment\"}" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
			fi

			# enable commas
			[ "$disabled" = "0" ] && isFirstFileDL=0
			isFirstFileInfo=0

			idx=$(( idx + 1 ))

			# check if we have processed all infos. break loop if no more infos for same file or if file was new.
			# continue with next file
			if [ "$info_array" = "[]" ]; then
				break;
			fi
		done
	done

	if [ $error -eq 1 ]; then
		printf "${C_LRED}Error: there were some duplicates.${C_NONE}\n"
		exit 1
	fi
	printf "]\n"
}

gen_download_json_end()
{
	 output_path=$1

	#printf "close download.json\n"
	printf " ]\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME
	printf "}\n" >> $output_path/$OUTPUT_DOWNLOAD_JSON_FILENAME

	# close new input info file
	printf " ]\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
	printf "}\n" >> $info_dir/$OUTPUT_FILEINFO_JSON_FILENAME
}


#p=/tmp
#gen_download_json_start $p 4.2.15 master
#gen_download_json_add_data $p /home/freifunk/upload-firmware/files/4.2.15 ar71xx/generic "*.{bin,trx,itb,img,dlf,gz}"
#gen_download_json_end $p
#printf "ok\n"
#exit

#################################################################################################
# main script start
#################################################################################################

$ENABLE_COPY && {
	printf " delete old data: $final_output_dir\n"
	rm -rf $final_output_dir/*
}


#################################################################################################
# start json
#################################################################################################
$ENABLE_GENERATE && {

gen_download_json_start "$final_output_dir" "$fwdate" "$fw_branch" "$fw_rev"


#################################################################################################
# copy build dl
#################################################################################################
$ENABLE_COPY && {
	printf "${C_YELLOW}copy downloaded packages${C_NONE}\n"
	mkdir -p $final_output_dir/downloaded_packages/
	#cp -a $PROJECT_DIR/dl/* $final_output_dir/downloaded_packages/
	rsync -a --info=progress2 $PROJECT_DIR/dl/* $final_output_dir/downloaded_packages/
#	gen_download_json_add_single_link '[downloaded_packages]' 'downloaded_packages' $final_output_dir
}

#################################################################################################
# copy other files/sources
#################################################################################################

#changelog
$ENABLE_COPY && {
	printf "${C_YELLOW}copy changelog${C_NONE}\n"
	cp -a $PROJECT_DIR/changelog.txt $final_output_dir/
#	gen_download_json_add_single_link 'changelog.txt' 'changelog.txt' $final_output_dir
}

#licenses
$ENABLE_COPY && {
	printf "${C_YELLOW}copy licenses${C_NONE}\n"
	cp -a $PROJECT_DIR/license $final_output_dir/
#	gen_download_json_add_single_link '[license]' 'license' $final_output_dir
}

$ENABLE_COPY && {
	printf "${C_YELLOW}copy www${C_NONE}\n"
	cp -a $info_dir/files/index.html $final_output_dir/
	cp -a $info_dir/files/_res $final_output_dir/
}

#################################################################################################
# copy firmware
#################################################################################################
# set variable MKHASH, unless script ipkg-make-index.sh will fail
# needed since openwrt 22.03.
# I have at least one working directory. mkhash might be found several times, but are all the same.
# So I just use the first I find
export MKHASH=$(find workdir/*/staging_dir -name mkhash -print -quit)

# I generate my own package list. so find the script
IPKG_MAKE_SCRIPT_SH=$(find workdir/*/scripts -name ipkg-make-index.sh -print -quit)

# run through all openwrt version (targets may be created for different openwrt versions)
for config  in $(ls -1 $PROJECT_DIR/${GENERATED_FIRMWARE_OUTPUT_DIR})
do
	printf "${C_YELLOW}>>>>>>>> firmware config:${C_NONE}[${C_GREEN}${config}${C_NONE}]\n"

	# -> final_output/firmware/8.2.5/ramips.24.mt7621.generic
	target_dir=$final_output_dir/${OUTPUT_FIRMWARE_SUB_DIR}/$fw_version/${config}
	mkdir -p $target_dir

	# _output contains several platforms but only for exactly one freifunk firmware version
	fw_version=$(cat ${GENERATED_FIRMWARE_OUTPUT_DIR}/${config}/${GENERATED_FIRMWARE_VERSION_FILE})
	if [ -z "$fw_version" ]; then
		printf "ERROR: firmware version not detected (invalid path)\n"
		exit 1
	fi
	printf "  ${C_LPURPLE}detected firmware version:${C_NONE} $fw_version\n"
	printf "$fw_version\n" >$target_dir/version


	filefilter="*.{bin,trx,img,itb,dlf,gz,tar,vdi,vmdk}"
  $ENABLE_COPY && {
    printf "    ${C_YELLOW}copy:${C_NONE} ${config}/images/$filefilter\n"
    # use "eval" to resolv filefilter wildcards
    eval cp -a $PROJECT_DIR/${GENERATED_FIRMWARE_OUTPUT_DIR}/${config}/images/$filefilter ${target_dir}/ 2>/dev/null

    # remove not-wanted files, because those are not used and added for different openwrt versions
    # This would cause duplicate warning in gen-upload.sh
    rm -f ${target_dir}/freifunk-dresden*-{vmlinux.bin,uImage-lzma.bin,rootfs.tar.gz}
  }

  #create md5sums/sha256sum file used when automatically or manually downloading via firmware.cgi
  # solange das file erzeugen, wie software mit alter firmware drausen ist
  # oder github
  printf "    ${C_YELLOW}calculate md5sum/sha256sum${C_NONE}\n"
  (
    cd $target_dir
    md5sum * > $target_dir/md5sums 2>/dev/null
    sha256sum * > $target_dir/sha256sum 2>/dev/null
  )

  #copy packages
  mkdir -p $target_dir/packages
  printf "    ${C_YELLOW}search package dir:${C_NONE} ${GENERATED_FIRMWARE_OUTPUT_DIR}/${config}/\n"
  for package in $(cat $info_dir/packages | sed 's/#.*//;/^[	 ]*$/d')
  do
    filename=$(find ${GENERATED_FIRMWARE_OUTPUT_DIR}/${config}/ -name "$package""[0-9_]*.ipk" -print 2>/dev/null)
    printf "      ${C_YELLOW}process package: ${C_GREEN}${package}${C_NONE}... "

    $ENABLE_COPY && {
      test -n "$filename" && {
		    printf -- "--> copy ${filename}\n"
        cp -a $filename $target_dir/packages/
      }
    }

    test -z "${filename}" && printf "${C_ORANGE}WARNING: no package file found for ${C_NONE}${package}\n"

  done

  printf "    ${C_YELLOW}generate package index${C_NONE}\n"
  (
    cd $target_dir/packages/
    ${IPKG_MAKE_SCRIPT_SH} . > Packages 2>/dev/null
    gzip -f Packages
  )

	gen_download_json_add_data "$final_output_dir" "${OUTPUT_FIRMWARE_SUB_DIR}/$fw_version/${config}" "$filefilter" ${fw_version}


	printf -- "\n=========================================================\n\n"

done # _output/<configs>

gen_download_json_end $final_output_dir

# make new generated fileinfo pretty, for easier comparison
tmp=$(mktemp)
cp ${info_dir}/${OUTPUT_FILEINFO_JSON_FILENAME} ${tmp}
cat ${tmp}| jq '{comment,json_version,"fileinfo": .fileinfo | sort_by(.filename) }'  > ${info_dir}/${OUTPUT_FILEINFO_JSON_FILENAME}


# generate js file
cat << EOM > $final_output_dir/$OUTPUT_DOWNLOAD_JSON_JS_FILENAME
var data = $(cat $final_output_dir/$OUTPUT_DOWNLOAD_JSON_FILENAME) ;
EOM

# ENABLE_GENERATE
}

echo exit
exit 0

# now, all files are copied for uploading and new fileinfo.json is generated
# - check for duplicate firmware files but ignore versions in filename
printf "${C_YELLOW}checking for firmware duplicates...${C_NONE}\n"
find $final_output_dir/${OUTPUT_FIRMWARE_SUB_DIR}/ | sed -n 's#\(\(.*\)/freifunk-dresden-\([0-9.-]\+\)*\(snapshot-\)*\(.*\)$\)#\5 \1#p' \
			| sort -k1 \
			| awk '
			 BEGIN { ret = 0;}
			 { name=$1;path=$2
				 if(name==last)
				 {
					 printf("ERROR: DUPLICATE firmware found: %s\n", name);
					 printf("       -> %s\n", path);
					 printf("       -> %s\n", lastpath);
					 ret = 1;
				 }
				 last=name;
				 lastpath=path;
			 }
			 END {exit ret;}' || exit 1

printf "${C_YELLOW}checking for firmware duplicates done.${C_NONE}\n"

#------ now sort fileinfo.json and generated file. to see diffs better with diff tools (meld).------
cat ${info_dir}/${INPUT_FILEINFO_JSON_FILENAME} | jq '. |
						{ comment: (.comment)}
					+ { json_version: (.json_version)}
					+ { fileinfo: (.fileinfo | sort_by(.sortkey, .filename)) }' > ${info_dir}/${INPUT_FILEINFO_JSON_FILENAME}.sorted
mv ${info_dir}/${INPUT_FILEINFO_JSON_FILENAME}.sorted ${info_dir}/${INPUT_FILEINFO_JSON_FILENAME}

cat ${info_dir}/${OUTPUT_FILEINFO_JSON_FILENAME} | jq '. |
						{ comment: (.comment)}
					+ { json_version: (.json_version)}
					+ { fileinfo: (.fileinfo | sort_by(.sortkey, .filename)) }' > ${info_dir}/${OUTPUT_FILEINFO_JSON_FILENAME}.sorted
mv ${info_dir}/${OUTPUT_FILEINFO_JSON_FILENAME}.sorted ${info_dir}/${OUTPUT_FILEINFO_JSON_FILENAME}

#------ now compare fileinfo.json and generated file (sorting is not needed).------
printf "${C_YELLOW}check for missing firmware files (not generated)${C_NONE}\n"
#
error=0
if jq --exit-status -n --slurpfile current ${info_dir}/${INPUT_FILEINFO_JSON_FILENAME} --slurpfile generated ${info_dir}/${OUTPUT_FILEINFO_JSON_FILENAME} ' $current[0].fileinfo - $generated[0].fileinfo | if length > 0 then . else empty end'; then

# only consider filenames
#if jq --exit-status -n --slurpfile current ${info_dir}/${INPUT_FILEINFO_JSON_FILENAME} --slurpfile generated ${info_dir}/${OUTPUT_FILEINFO_JSON_FILENAME} ' ([$current[0].fileinfo[] | .filename]) - ([$generated[0].fileinfo[] | .filename]) | if length > 0 then . else empty end'; then
	echo -e "${C_RED}ERROR: missing firmware files${C_NONE}"
	error=1
fi

[ $error -eq 1 ] && echo "----------------------------------------------------"
printf "${C_YELLOW}check for new firmware files${C_NONE}\n"

if jq --exit-status -n --slurpfile current ${info_dir}/${INPUT_FILEINFO_JSON_FILENAME} --slurpfile generated ${info_dir}/${OUTPUT_FILEINFO_JSON_FILENAME} ' $generated[0].fileinfo - $current[0].fileinfo | if length > 0 then . else empty end'; then

# only consider filenames
#if jq --exit-status -n --slurpfile current ${info_dir}/${INPUT_FILEINFO_JSON_FILENAME} --slurpfile generated ${info_dir}/${OUTPUT_FILEINFO_JSON_FILENAME} ' ([$generated[0].fileinfo[] | .filename]) - ([$current[0].fileinfo[] | .filename]) | if length > 0 then . else empty end'; then
	echo -e "${C_BLUE}INFO: new devices found${C_NONE}"
	error=1
fi

[ $error -eq 1 ] && exit 1
exit 0
