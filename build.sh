#!/bin/bash

#usage: see below

PLATFORMS="ar71xx x86"
#PLATFORMS="x86"
#PLATFORMS="ar71xx"

DL_DIR=dl
WORK_DIR=workdir
CONFIG_DIR=lede-configs
LEDE_PATCHES_DIR=lede-patches

#use "original" or "ddmesh" lede config
CONFIG_TYPE=ddmesh

#define a list of supported versions
VERSIONS="lede"

#Black        0;30     Dark Gray     1;30
#Red          0;31     Light Red     1;31
#Green        0;32     Light Green   1;32
#Brown/Orange 0;33     Yellow        1;33
#Blue         0;34     Light Blue    1;34
#Purple       0;35     Light Purple  1;35
#Cyan         0;36     Light Cyan    1;36
#Light Gray   0;37     White         1;37
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_NONE='\033[0m' # No Color

# process argument
# check for correct argument (addtional arguments are passt to command line make) 
# last value will become DEFAULT
for v in $VERSIONS
do
	if [ "$1" = "$v" ]; then
		VER="$1"
		shift
		break;
	fi
done

#check if next argument is "menuconfig"
if [ "$1" = "menuconfig" ]; then
	MENUCONFIG=1
	shift;
fi

if [ -z "$VER" ]; then
	# create a simple menu
	echo ""
	echo "usage: $(basename $0) [lede-version] [menuconfig] [[make params] ...]"
	echo " lede-version 	- builds for specific lede version ($VERSIONS)"
	echo " menuconfig	- displays configuration menu before building images"
	echo " make params	- all paramerters that follows are passed to make command"
	echo ""
	echo "================================"
	echo " Additional make parameters: $* "
	echo " Config type: $CONFIG_TYPE"
	echo " Select lede version "
	echo "================================"
	c=1
	for VER in $VERSIONS
	do
		LOOKUP_VERSION[$c]="$VER"
		echo "$c lede $VER"
		c=$((c+1))
	done	
	echo -n " Select > "
	read answer

	# get the version from VERSIONS
	VER=${LOOKUP_VERSION[$answer]}

	echo "================================"
fi


echo "select $VER"

#lede
case "$VER" in
	lede)
		git_url="https://github.com/lede-project/source.git"
#later revision hat problems with TP-Link mr3020 dnsmasq. no resolve at all
		#lede_rev="995193ccdb2adb2bfe226965589b5f3db71bdd80" #2.4.8;
		#lede_rev="e64463ebde554071431514925825e2c30f2b6998" geht soweit 4.2.9
		lede_rev="lede-17.01" #98c003e3da5993779b9011a24072e2bac4492d86
		VER=lede
		VARIANT=".generic"
		;;
	*)
		echo "[ERROR: VERSION $VER, not defined: no git url and revision] - exit"
		exit 1
		;;
esac

#--------------------------------------------------------

lede_dl_dir="$DL_DIR/$VER"
lede_dl_tgz="$lede_dl_dir/lede-$VER-$lede_rev.tgz"
lede_patches_dir="$LEDE_PATCHES_DIR/$VER"

buildroot="$WORK_DIR/$VER/buildroot"

log_dir="logs"
script_file="$log_dir/log.common.$VER.$CONFIG_TYPE"

#delete old log file
rm -rf $log_dir
mkdir -p $log_dir

#save current directory, used by log and when copying config file
RUN_DIR=$(pwd)

#each command appends its output to the script file.
#the command is passed as argument to script-tool
#"script $script_file -a -c"
log ()
{
 echo "cmd:[$*]" >> $RUN_DIR/$script_file
 script $RUN_DIR/$script_file -q -f -a -c "$*"
}

setup_buildroot ()
{
	#check if directory exists
	if [ ! -d $buildroot ]
	then
		log echo "directory [$buildroot] not present"

		log mkdir -p $buildroot
		log mkdir -p $lede_dl_dir

		#check if we have already downloaded the lede revision
		if [ -f $lede_dl_tgz ]
		then
			#extract into buildroot dir
			log echo "using already downloaded $lede_dl_tgz"
			log tar xzf $lede_dl_tgz 
		else
			#clone from lede
			log echo "cloning lede "
			log git clone $git_url $buildroot
			log echo "switch to specific revision"
			cd $buildroot
			log git checkout $lede_rev >/dev/null
			cd $RUN_DIR
			log echo "create lede tgz"
			log tar czf $lede_dl_tgz $buildroot 
		fi

		#apply lede patches
		if [ -d $lede_patches_dir ]; then
			for i in $lede_patches_dir/*
			do
				echo "apply lede patch: $i"
				#nicht mit "log" laufen lassen. umleitung geht nicht
				patch --directory=$buildroot -p1 < $i
			done 
		fi
	else
		log echo "Buildroot [$buildroot] already present"
	fi

	log echo "create dl directory/links and feed links"
	log rm -f $buildroot/feeds.conf
	log ln -s ../../../feeds/feeds-$VER.conf $buildroot/feeds.conf
	log rm -f $buildroot/dl
	log ln -s ../../../$lede_dl_dir $buildroot/dl

	#if feeds_copied directory contains same packages as delivered with
	#lede, then assume that the packages came with lede git clone are
	#older. delete those old packages to force lede make system to use the
	#new versions of packages from feeds-copied directory

	echo "delete old packages from buildroot/package"
	for i in $(ls -1 feeds/$VER/feeds-copied) $(ls -1 feeds/$VER/feeds-own)
	do
		base=$(basename $i)
		log echo "check: [$base]"
		#	test -x $buildroot/package/$base && log echo "rm -rf $buildroot/package/$base" && rm -rf $buildroot/package/$base
		find $buildroot/package -type d -wholename "*/$base" -exec rm -rf {} \; -exec echo "  -> rm {} " \;  2>/dev/null
	done

	# copy common files first
	echo "copy rootfs: common"
	rm -rf $buildroot/files
	mkdir -p $buildroot/files
	log cp -a $RUN_DIR/files/common/* $buildroot/files/
	
	# copy specific files over (may overwrite common)
	echo "copy rootfs: $VER"
	mkdir -p $RUN_DIR/files/$VER
	test -n "$(ls $RUN_DIR/files/$VER/)" && log cp -a $RUN_DIR/files/$VER/* $buildroot/files/

	echo "create rootfs/etc/built_info file"
	mkdir -p $buildroot/files/etc
	> $buildroot/files/etc/built_info

	echo "----- generate built_info ----"
	git_lede_ref=$(cd $buildroot && git log -1 --format=%H)
	git_lede_branch=$(cd $buildroot && git symbolic-ref --short HEAD)
	echo "git_lede_ref:$git_lede_ref" >> $buildroot/files/etc/built_info
	echo "git_lede_branch:$git_lede_branch" >> $buildroot/files/etc/built_info
	
	git_ddmesh_ref=$(git log -1 --format=%H)
	git_ddmesh_branch=$(git symbolic-ref --short HEAD)
	echo "git_ddmesh_ref:$git_ddmesh_ref" >> $buildroot/files/etc/built_info
	echo "git_ddmesh_branch:$git_ddmesh_branch" >> $buildroot/files/etc/built_info
	
	echo "builtdate:$(date)" >> $buildroot/files/etc/built_info
	cat $buildroot/files/etc/built_info

} # setup_buildroot



setup_buildroot


echo "------------------------------"
echo "install feeds"
echo "change to buildroot [$buildroot]"
cd $buildroot
#log scripts/feeds clean 
log scripts/feeds update ddmesh_own 
log scripts/feeds update ddmesh_copied 
log scripts/feeds install -a -p ddmesh_own 
log scripts/feeds install -a -p ddmesh_copied 

for PLATFORM in $PLATFORMS
do
	# reset to inital directory
	cd $RUN_DIR
	
	config_file="$CONFIG_DIR/config.$PLATFORM$VARIANT.$VER.$CONFIG_TYPE"

	# platform specific
	script_file="$log_dir/log.$PLATFORM$VARIANT.$VER.$CONFIG_TYPE"

	echo "change to buildroot [$buildroot]"
	cd $buildroot

	echo "delete previous firmware: bin/$PLATFORM"
	rm -rf bin/targets/$PLATFORM

	#copy after installing feeds, because .config will be overwritten by default config
	log echo "copy configuration \($RUN_DIR/$config_file\)"
	log cp $RUN_DIR/$config_file .config 

	if [ "$MENUCONFIG" = "1" ]; then
		log echo "run menuconfig"
		log make menuconfig
	fi

	# run make command
	log time make $*

#$RUN_DIR/files/common/usr/lib/ddmesh/ddmesh-utils-check-firmware-size.sh bin/ar71xx/lede-ar71xx-generic-tl-mr3020-v1-squashfs-factory.bin

	log echo "images created in $buildroot/bin/targets/$PLATFORM/..."

done

echo ".......... complete build finished ........................"
echo ""





