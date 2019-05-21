#!/bin/bash

#usage: see below
SCRIPT_VERSION="5"

# target file
PLATFORMS_JSON="build.json"

DL_DIR=dl
WORK_DIR=workdir
CONFIG_DIR=openwrt-configs
OPENWRT_PATCHES_DIR=openwrt-patches

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
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_GREY='\033[1;30m'
C_LGREY='\033[0;37m'
C_YELLOW='\033[1;33m'
C_PURPLE='\033[0;35m'
C_BLUE='\033[0;32m'
C_ORANGE='\033[0;33m'

#save current directory, used by log and when copying config file
RUN_DIR=$(pwd)

# jq: first selects the array with all entries and every entry is pass it to select().
#       select() checks a condition and returns the input data (current array entry)
#       if condition is true
# Die eckigen klammern aussenherum erzeugt ein array, in welches alle gefundenen objekte gesammelt werden.
# Fuer die meisten filenamen ist das array 1 gross. aber fuer files die fuer verschiedene router
# verwendet werden, koennen mehrere eintraege sein.

getTargetsJson()
{
cat $RUN_DIR/$PLATFORMS_JSON | sed -n "
#delete comments
s/#.*//

# delete empty lines
# delete leading and tailing spaces
s/^[ 	]*//
s/[ 	]*$//
/^$/d
p
" | jq "[ .targets[] ]" 
}


listTargets()
{
 OPT="--raw-output" # do not excape values

 cleanJson=$(getTargetsJson)
 targetIdx=0
 while true
 do
 	entry=$(echo "$cleanJson" | jq ".[$targetIdx]")
	if [ "$entry" = "null" ]; then
 		target=""
	else
		_target=$(echo $entry | jq $OPT '.target')
		_subtarget=$(echo $entry | jq $OPT '.subtarget')
		_variant=$(echo $entry | jq $OPT '.variant')

		target=$_target.$_subtarget
		test -n "$_variant" && target="$target.$_variant"
	fi 
	test -z "$target" && break
	echo "$target"
	targetIdx=$(( targetIdx + 1 ))
 done
}


setup_dynamic_firmware_config()
{
	FILES=./files/common/

	# modify registration credentials from envronment variable passed in by gitlabs
	# FF_REGISTERKEY_PREFIX is set in gitlab UI of freifunk-dresden-firmware: settings->CI/CD->Environment
	sed -i "/register_service_url/s#registerkey='#registerkey=${FF_REGISTERKEY_PREFIX//_/:}'#" $FILES/etc/config/credentials
}



#----------------- process argument ----------------------------------
#check if next argument is "menuconfig"
if [ "$1" = "list" ]; then
	listTargets
	exit 0
fi

# get target (addtional arguments are passt to command line make) 
# last value will become DEFAULT
regex="$1"
regex="${regex:=.*}" 
echo "### regex:[$regex]"
shift

#check if next argument is "menuconfig"
if [ "$1" = "menuconfig" ]; then
	MENUCONFIG=1
	shift;
fi

#check if next argument is "clean"
#it only cleans /bin and /build_dir of openwrt directory. toolchains and staging_dir ar kept
if [ "$1" = "clean" ]; then
	MAKE_CLEAN=1
	shift;
fi

BUILD_PARAMS=$*

if [ -z "$regex" ]; then
	# create a simple menu
	echo "Version: $SCRIPT_VERSION"
	echo "usage: $(basename $0) [list] | target [menuconfig | clean | <make params ...> ]"
	echo " list             - lists all available targets"
	echo " target           - target to build (can have regex)"
	echo "                    that are defined by build.json"
	echo "                    e.g.: 'ramips.*'"
	echo "                    'ramips.rt305x.generic' - exact this target"
	echo "                    '^rt30.*' - filter all that start with rt30"
	echo " menuconfig       - displays configuration menu before building images"
	echo " clean            - cleans buildroot/bin and buildroot/build_dir (keeps toolchains)"
	echo " make params      - all paramerters that follows are passed to make command"
	echo ""
	exit 1
fi




log_dir="logs"
log_file="build.common.log"   # when compiling targets, this is overwritten

#delete old log file
mkdir -p $log_dir
rm -rf $log_dir/*

#each command appends its output to the script file.
#the command is passed as argument to script-tool
#"script $log_file -a -c"
log ()
{
 sf=$1
 shift
 echo "*************** [$*]" >> $RUN_DIR/$log_dir/$sf
 $*  | tee -a $RUN_DIR/$log_dir/$sf
}

setup_buildroot ()
{
 buildroot=$1
 openwrt_rev=$2
 openwrt_dl_dir=$3
 openwrt_patches_dir=$4
 selector=$5
 
 openwrt_dl_tgz="$openwrt_dl_dir/openwrt-$openwrt_rev.tgz"

 git_url="https://git.openwrt.org/openwrt/openwrt.git"

	#check if directory exists
	if [ ! -d $buildroot ]
	then
		log $log_file echo "directory [$buildroot] not present"

		log $log_file mkdir -p $buildroot
		log $log_file mkdir -p $openwrt_dl_dir

		#check if we have already downloaded the openwrt revision
		if [ -f $openwrt_dl_tgz ]
		then
			#extract into buildroot dir
			log $log_file echo "using already downloaded $openwrt_dl_tgz"
			log $log_file tar xzf $openwrt_dl_tgz 
		else
			#clone from openwrt
			log $log_file echo "cloning openwrt"
			log $log_file git clone $git_url $buildroot
			log $log_file echo "switch to specific revision"
			cd $buildroot
			log $log_file git checkout $openwrt_rev >/dev/null
			cd $RUN_DIR
			log $log_file echo "create openwrt tgz"
			log $log_file tar czf $openwrt_dl_tgz $buildroot 
		fi

		#apply openwrt patches
		if [ -d $openwrt_patches_dir ]; then
			for i in $openwrt_patches_dir/*
			do
				echo "apply openwrt patch: $i"
				#nicht mit "log" laufen lassen. umleitung geht nicht
				patch --directory=$buildroot -p1 < $i
			done 
		fi
	else
		echo -e $C_PURPLE"Buildroot [$buildroot] already present"$C_NONE
	fi

	echo -e $C_PURPLE"create dl directory/links and feed links"$C_NONE
	log $log_file rm -f $buildroot/feeds.conf
	log $log_file ln -s ../../feeds/feeds-$selector.conf $buildroot/feeds.conf
	log $log_file rm -f $buildroot/dl
	log $log_file ln -s ../../$openwrt_dl_dir $buildroot/dl

	#if feeds_copied/feeds_own directory contains same packages as delivered with
	#openwrt, then assume that the packages came with openwrt git clone are
	#older. delete those old packages to force openwrt make system to use the
	#new versions of packages from feeds-copied directory

	echo -e $C_PURPLE "delete old packages from buildroot/package"$C_NONE
	# extract feeds directory from feeds-xxxxxx.conf , and list the content of 
	# feed directories
	pwd
	for d in $(cat feeds/feeds-$selector.conf  | awk '/src-link/{print substr($3,7)}')
	do
		for i in eval $(ls -1 $d)
		do
			base=$(basename $i)
			echo -e "$C_PURPLE""check$C_NONE: [$C_GREEN$base$C_NONE]"
			#	test -x $buildroot/package/$base && log $log_file echo "rm -rf $buildroot/package/$base" && rm -rf $buildroot/package/$base
			find $buildroot/package -type d -wholename "*/$base" -exec rm -rf {} \; -exec echo "  -> rm {} " \;  2>/dev/null
		done
	done

	# copy common files first
	echo -e $C_PURPLE"copy rootfs$C_NONE: $C_GREEN""common"$C_NONE
	rm -rf $buildroot/files
	mkdir -p $buildroot/files
	log $log_file cp -a $RUN_DIR/files/common/* $buildroot/files/
	
	# copy specific files over (may overwrite common)
	echo -e $C_PURPLE"copy rootfs"$C_NONE
	mkdir -p $RUN_DIR/files/$openwrt_rev
	test -n "$(ls $RUN_DIR/files/$selector/)" && log $log_file cp -a $RUN_DIR/files/$selector/* $buildroot/files/

	echo -e $C_PURPLE"create rootfs/etc/built_info file"$C_NONE
	mkdir -p $buildroot/files/etc
	> $buildroot/files/etc/built_info

	echo "----- generate built_info ----"
	git_openwrt_rev=$(cd $buildroot && git log -1 --format=%H)
	git_openwrt_branch=$(cd $buildroot && git name-rev --name-only $git_openwrt_rev | sed 's#.*/##')
	echo "git_openwrt_rev:$git_openwrt_rev" >> $buildroot/files/etc/built_info
	echo "git_openwrt_branch:$git_openwrt_branch" >> $buildroot/files/etc/built_info
	
	git_ddmesh_rev=$(git log -1 --format=%H)
	git_ddmesh_branch=$(git name-rev --name-only $git_ddmesh_rev | sed 's#.*/##')
	echo "git_ddmesh_rev:$git_ddmesh_rev" >> $buildroot/files/etc/built_info
	echo "git_ddmesh_branch:$git_ddmesh_branch" >> $buildroot/files/etc/built_info
	
	echo "builtdate:$(date)" >> $buildroot/files/etc/built_info

	cat $buildroot/files/etc/built_info

	# more dynamic changes
	setup_dynamic_firmware_config

} # setup_buildroot


# process all targets
OPT="--raw-output" # do not excape values
targetIdx=0
while true
do
	cd $RUN_DIR

	# get next potential target
 	entry=$(getTargetsJson | jq ".[$targetIdx]")
	targetIdx=$(( targetIdx + 1 ))
	test "$entry" = "null" && break
 
	_target=$(echo $entry | jq $OPT '.target')
	_subtarget=$(echo $entry | jq $OPT '.subtarget')
	_variant=$(echo $entry | jq $OPT '.variant')
	_name=$(echo $entry | jq $OPT '.name')
	_selector=$(echo $entry | jq $OPT '.selector')
	_openwrt_rev=$(echo $entry | jq $OPT '.openwrt_rev')
	_packages=$(echo $entry | jq '.packages')


	#build target name to filter on
	target=$_target.$_subtarget
	test -n "$_variant" && target="$target.$_variant"

	filterred=$(echo $target | sed -n "/$regex/p")
	test -z "$filterred" && continue

	echo -e $C_GREY"--------------------"$C_NONE
	echo -e $C_YELLOW"Name$C_NONE      : $C_BLUE$_name"$C_NONE
	echo -e $C_YELLOW"Target$C_NONE    : $C_BLUE$_target"$C_NONE
	echo -e $C_YELLOW"Sub-Target$C_NONE: $C_BLUE$_subtarget"$C_NONE
	echo -e $C_YELLOW"Variant$C_NONE   : $C_BLUE$_variant"$C_NONE
	echo -e $C_GREY"--------------------"$C_NONE	


	config_file="$CONFIG_DIR/$_selector/config.$target"
	log_file="build.$target.log"
	buildroot="$WORK_DIR/$_openwrt_rev"
	openwrt_dl_dir="$DL_DIR"
	openwrt_patches_dir="$OPENWRT_PATCHES_DIR/$_selector"

	setup_buildroot $buildroot $_openwrt_rev $openwrt_dl_dir $openwrt_patches_dir $_selector 

	echo "------------------------------"
	echo "change to buildroot [$buildroot]"
	cd $buildroot

	echo -e $C_PURPLE"install feeds"$C_NONE
	#log scripts/feeds clean 
	log $log_file scripts/feeds update ddmesh_copied 
	log $log_file scripts/feeds update ddmesh_own 
	log $log_file scripts/feeds install -a -p ddmesh_copied 
	log $log_file scripts/feeds install -a -p ddmesh_own 


	# delete target dir, but only delete when no specific device/variant is built.
	# generic targets (that contains all devices) must come before specific targets.
	if [ -z "$_variant" ]; then
		echo -e $C_PURPLE"delete previous firmware$C_NONE: $C_GREEN""bin/targets/$_target/$_subtarget"
		log $log_file rm -rf bin/targets/$_target/$_subtarget
	else
		echo -e $C_PURPLE"DO NOT delete previous firmware$C_NONE: $C_GREEN""bin/targets/$_target/$_subtarget"
	fi

	#copy after installing feeds, because .config will be overwritten by default config
	echo -e $C_PURPLE"copy configuration$C_NONE: $C_GREEN$RUN_DIR/$config_file$C_NONE"
	rm -f .config		# delete previous config in case we have no $RUN_DIR/$config_file yet and want to
				# create a new config
	log $log_file cp $RUN_DIR/$config_file .config 

	if [ "$MENUCONFIG" = "1" ]; then
		echo -e $C_PURPLE"run menuconfig"$C_NONE
		log $log_file make menuconfig
		exit 0
	fi

	if [ "$MAKE_CLEAN" = "1" ]; then
		echo -e $C_PURPLE"run clean"$C_NONE
		log $log_file make clean
		# continue with next target in build.targets	
	else

		# run defconfig to correct config dependencies if those have changed.

		echo -e $C_PURPLE"run defconfig"$C_NONE
		log $log_file make defconfig

		echo -e $C_PURPLE"copy back configuration$C_NONE: $C_GREEN$RUN_DIR/$config_file$C_NONE"
		log $log_file cp .config $RUN_DIR/$config_file

		
		# run make command
		echo -e $C_PURPLE"time make$C_NONE $C_GREEN$BUILD_PARAMS"
		log $log_file time -p make $BUILD_PARAMS
		# continue with next target in build.targets	
	fi

	echo -e $C_PURPLE"images created in$C_NONE $C_GREEN$buildroot/bin/targets/$_target/$_subtarget/..."$C_NONE

done

echo -e $C_PURPLE".......... complete build finished ........................"$C_NONE
echo ""

