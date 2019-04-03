#!/bin/bash

#usage: see below
SCRIPT_VERSION="4"

# target file
PLATFORMS="build.targets"

DL_DIR=dl
WORK_DIR=workdir
CONFIG_DIR=openwrt-configs
OPENWRT_PATCHES_DIR=openwrt-patches

#define a list of supported versions
VERSIONS="openwrt lede"

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

listTargets()
{
cat $RUN_DIR/$PLATFORMS | sed -n "
#delete comments
s/#.*//

# delete empty lines
# delete leading and tailing spaces
s/^[ 	]*//
s/[ 	]*$//
/^$/d

# replace spaces with new lines, in case more targets are specified
# in one line
s/[ 	]\+/\n/g

p
"
}

getTargets()
{
# $1 - os version (lede/openwrt/trunk) which should be filterred
# $2 - optional: regex (grep) to filter more
os="$1"
os="${os:=.*}"		# if os is empty, then display all
regex="$2"
regex="${regex:=.*}" 	# when 'openwrt:' was given, then $2 would be empty.
			# to default assign, I need a variable
# echo "#### REGEX [$regex]"

cat $RUN_DIR/$PLATFORMS | sed -n "
#delete comments
s/#.*//

# delete empty lines
# delete leading and tailing spaces
s/^[ 	]*//
s/[ 	]*$//
/^$/d

# replace spaces with new lines, in case more targets are specified
# in one line
s/[ 	]\+/\n/g

# only consider os
s/^$os:\(.*\)/\1/p
" | sed -n "/$regex/p"
}

#----------------- process argument ----------------------------------
#check if next argument is "menuconfig"
if [ "$1" = "list" ]; then
	listTargets
	exit 0
fi

# check for correct argument (addtional arguments are passt to command line make) 
# last value will become DEFAULT
_os="${1%%:*}"
FILTER="${1#*:}" #if no filter then this will also contain 'openwrt'
		 #then I need to filter all
test "$_os" = "$FILTER" && FILTER=".*"
echo "### $_os filter:[$FILTER]"
#echo $(getTargets $_os "$FILTER")
#exit 0

for v in $VERSIONS
do
	if [ "$_os" = "$v" ]; then
		VER="$_os"
		shift
		break;
	fi
done

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

if [ -z "$VER" ]; then
	# create a simple menu
	echo "Version: $SCRIPT_VERSION"
	echo "usage: $(basename $0) [list] | openwrt-version [menuconfig | clean | <make params ...> ]"
	echo " list             - lists all available targets"
	echo " openwrt-version  - builds for specific openwrt version ($VERSIONS)"
	echo "                  - filters can be added to only process subset of targets"
	echo "                    that are defined by build.targets"
	echo "                    e.g.: 'openwrt' - all targets for this os"
	echo "                    'openwrt:ramips.rt305x.generic' - exact this target"
	echo "                    'openwrt:^rt30.*' - filter all that start with rt30"
	echo " menuconfig       - displays configuration menu before building images"
	echo " clean            - cleans buildroot/bin and buildroot/build_dir (keeps toolchains)"
	echo " make params      - all paramerters that follows are passed to make command"
	echo ""
	exit 1
fi


echo "select $VER"

#openwrt
case "$VER" in
	openwrt)
		git_url="https://git.openwrt.org/openwrt/openwrt.git"
		#openwrt_rev="19a6c4b2b3df775b3e57fa3a6f790cd08b17955e"	# branch v18.06 / Mon Feb 11 11:25:54 2019 
		openwrt_rev="70255e3d624cd393612069aae0a859d1acbbeeae"	# tag 18.6.1
		#openwrt_rev="a02809f61bf9fda0387d37bd05d0bcfe8397e25d"	# tag 18.6.2
		VER=openwrt
		;;
	lede)
		git_url="https://github.com/lede-project/source.git"
		lede_rev="3ca1438ae0f780664e29bf0d102c1c6f9a99ece7"	# since 5.0.2 (branch 17.01)
		VER=lede
		;;
	*)
		echo "[ERROR: VERSION $VER, not defined: no git url and revision] - exit"
		exit 1
		;;
esac

#--------------------------------------------------------

openwrt_dl_dir="$DL_DIR/$VER"
openwrt_dl_tgz="$openwrt_dl_dir/openwrt-$openwrt_rev.tgz"
openwrt_patches_dir="$OPENWRT_PATCHES_DIR/$VER"

buildroot="$WORK_DIR/$VER/buildroot"

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
			log $log_file echo "cloning openwrt "
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
	log $log_file ln -s ../../../feeds/feeds-$VER.conf $buildroot/feeds.conf
	log $log_file rm -f $buildroot/dl
	log $log_file ln -s ../../../$openwrt_dl_dir $buildroot/dl

	#if feeds_copied directory contains same packages as delivered with
	#openwrt, then assume that the packages came with openwrt git clone are
	#older. delete those old packages to force openwrt make system to use the
	#new versions of packages from feeds-copied directory

	echo -e $C_PURPLE "delete old packages from buildroot/package"$C_NONE
	for i in $(ls -1 feeds/$VER/feeds-copied) $(ls -1 feeds/$VER/feeds-own)
	do
		base=$(basename $i)
		echo -e "$C_PURPLE""check$C_NONE: [$C_GREEN$base$C_NONE]"
		#	test -x $buildroot/package/$base && log $log_file echo "rm -rf $buildroot/package/$base" && rm -rf $buildroot/package/$base
		find $buildroot/package -type d -wholename "*/$base" -exec rm -rf {} \; -exec echo "  -> rm {} " \;  2>/dev/null
	done

	# copy common files first
	echo -e $C_PURPLE"copy rootfs$C_NONE: $C_GREEN""common"$C_NONE
	rm -rf $buildroot/files
	mkdir -p $buildroot/files
	log $log_file cp -a $RUN_DIR/files/common/* $buildroot/files/
	
	# copy specific files over (may overwrite common)
	echo -e $C_PURPLE"copy rootfs$C_NONE: $C_GREEN$VER"$C_NONE
	mkdir -p $RUN_DIR/files/$VER
	test -n "$(ls $RUN_DIR/files/$VER/)" && log $log_file cp -a $RUN_DIR/files/$VER/* $buildroot/files/

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

} # setup_buildroot



setup_buildroot


echo "------------------------------"
echo -e $C_PURPLE"install feeds"$C_NONE
echo "change to buildroot [$buildroot]"
cd $buildroot
#log scripts/feeds clean 
log $log_file scripts/feeds update ddmesh_own 
log $log_file scripts/feeds update ddmesh_copied 
log $log_file scripts/feeds install -a -p ddmesh_own 
log $log_file scripts/feeds install -a -p ddmesh_copied 

for p in $(getTargets $VER $FILTER)
do
	IFS='.'
	set $p		# split name
	PLATFORM=$1
	VARIANT=$2
	DEVICE=$3	# this is optional
	unset IFS

	echo -e $C_GREY"--------------------"$C_NONE
	echo -e $C_YELLOW"Platform$C_NONE: $C_BLUE$PLATFORM"$C_NONE
	echo -e $C_YELLOW"Variant$C_NONE:  $C_BLUE$VARIANT"$C_NONE
	echo -e $C_YELLOW"Device$C_NONE:   $C_BLUE$DEVICE"$C_NONE
	echo -e $C_GREY"--------------------"$C_NONE	

	# reset to inital directory
	cd $RUN_DIR

	# check for optional parameter "DEVICE"
	# platform specific
	if [ -n "$DEVICE" ]; then
		config_file="$CONFIG_DIR/$VER/config.$PLATFORM.$VARIANT.$DEVICE"
		log_file="build.$PLATFORM.$VARIANT.$DEVICE.$VER.log"
	else
		config_file="$CONFIG_DIR/$VER/config.$PLATFORM.$VARIANT"
		log_file="build.$PLATFORM.$VARIANT.$VER.log"
	fi


	echo "change to buildroot [$buildroot]"
	cd $buildroot
echo "********* TODO: pfad anpassen fuer DEVICE**************"
	# only delete when no specific device is built
	if [ -z "$DEVICE" ]; then
		echo -e $C_PURPLE"delete previous firmware$C_NONE: $C_GREEN""bin/targets/$PLATFORM/$VARIANT"
		log $log_file rm -rf bin/targets/$PLATFORM/$VARIANT
	else
		echo -e $C_PURPLE"DO NOT delete previous firmware$C_NONE: $C_GREEN""bin/targets/$PLATFORM/$VARIANT"
	fi

	#copy after installing feeds, because .config will be overwritten by default config
	echo -e $C_PURPLE"copy configuration$C_NONE: $C_GREEN$RUN_DIR/$config_file$C_NONE"
	rm -f .config		# delete previous config in case we have no $RUN_DIR/$config_file yet and want to
				# create a new config
	log $log_file cp $RUN_DIR/$config_file .config 

	if [ "$MENUCONFIG" = "1" ]; then
		echo -e $C_PURPLE"run menuconfig"$C_NONE
		log $log_file make menuconfig
		echo -e "Please call '$C_GREEN./$(basename $0) $VER'$C_NONE to build firmware."
		exit 0
	fi

	if [ "$MAKE_CLEAN" = "1" ]; then
		echo -e $C_PURPLE"run clean"$C_NONE
		log $log_file make clean
		# continue with next target in build.targets	
	else

		# run make command
		echo -e $C_PURPLE"time make$C_NONE $C_GREEN$BUILD_PARAMS"
		log $log_file time -p make $BUILD_PARAMS
		# continue with next target in build.targets	
	fi

echo "********* TODO: pfad anpassen fuer DEVICE**************"
	echo -e $C_PURPLE"images created in$C_NONE $C_GREEN$buildroot/bin/targets/$PLATFORM/$VARIANT/..."$C_NONE

done

echo -e $C_PURPLE".......... complete build finished ........................"$C_NONE
echo ""

