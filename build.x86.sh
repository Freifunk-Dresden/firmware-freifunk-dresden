#!/bin/bash

#usage: see below

PLATFORM=x86
DL_DIR=dl
WORK_DIR=workdir
CONFIG_DIR=openwrt-configs
OPENWRT_PATCHES_DIR=openwrt-patches

#use "original" or "ddmesh" openwrt config
CONFIG_TYPE=ddmesh

#define a list of supported versions
VERSIONS="trunk 15.05 lede"


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
	echo "usage: $(basename $0) [openwrt-version] [menuconfig] [[make params] ...]"
	echo " openwrt-version 	- builds for specific openwrt version ($VERSIONS)"
	echo " menuconfig	- displays configuration menu before building images"
	echo " make params	- all paramerters that follows are passed to make command"
	echo ""
	echo "================================"
	echo " Additional make parameters: $* "
	echo " Config type: $CONFIG_TYPE"
	echo " Select openwrt version "
	echo "================================"
	c=1
	for VER in $VERSIONS
	do
		LOOKUP_VERSION[$c]="$VER"
		echo "$c openwrt $VER"
		c=$((c+1))
	done	
	echo -n " Select > "
	read answer

	# get the version from VERSIONS
	VER=${LOOKUP_VERSION[$answer]}

	echo "================================"
fi


echo "select $VER"

#openwrt
case "$VER" in
	trunk)
		git_url="git://git.openwrt.org/openwrt.git"
		openwrt_rev="9b4650b3b92e6246b986ac9e3d7c2a80d66b805b"
		;;
	15.05)
		git_url="git://git.openwrt.org/$VER/openwrt.git"
		openwrt_rev="03d52cfcff87c0e8e09e7a455a6fdefb7138e369"
		;;
	lede)
		git_url="https://github.com/lede-project/source.git"
		openwrt_rev="70395ae8cbe0bc7d0d0b27b5088b9ac4b2f67f86"
		;;
	*)
		echo "[ERROR: VERSION $VER, not defined: no git url and revision] - exit"
		exit 1
		;;
esac

#--------------------------------------------------------

buildroot="$WORK_DIR/$VER/buildroot"
config_file="$CONFIG_DIR/config.$PLATFORM.$VER.$CONFIG_TYPE"
openwrt_dl_dir="$DL_DIR/$VER"
openwrt_dl_tgz="$openwrt_dl_dir/openwrt-$VER-$openwrt_rev.tgz"
log_dir="logs"
script_file="$log_dir/log.$PLATFORM.$VER.$CONFIG_TYPE"
openwrt_patches_dir="$OPENWRT_PATCHES_DIR/$VER"

#save current directory, used by log and when copying config file
RUN_DIR=$(pwd)

#delete old log file
mkdir -p $RUN_DIR/$log_dir
rm -f $RUN_DIR/$script_file

#each command appends its output to the script file.
#the command is passed as argument to script-tool
#"script $script_file -a -c"
log ()
{
 echo "cmd:[$*]" >> $RUN_DIR/$script_file
 script $RUN_DIR/$script_file -q -f -a -c "$*"
}


#check if directory exists
if [ ! -d $buildroot ]
then
 log echo "directory [$buildroot] not present"

 log mkdir -p $buildroot
 log mkdir -p $openwrt_dl_dir

 #check if we have already downloaded the openwrt revision
 if [ -f $openwrt_dl_tgz ]
 then
 	#extract into buildroot dir
 	log echo "using already downloaded $openwrt_dl_tgz"
 	log tar xzf $openwrt_dl_tgz 
 else
 	#clone from openwrt
 	log echo "cloning openwrt "
 	log git clone $git_url $buildroot
	log echo "switch to specific revision"
	cd $buildroot
	log git checkout $openwrt_rev >/dev/null
	cd $RUN_DIR
	log echo "create openwrt tgz"
 	log tar czf $openwrt_dl_tgz $buildroot 
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
 log echo "Buildroot [$buildroot] already present"
fi

log echo "create dl directory/links and feed links"
log rm $buildroot/feeds.conf
log ln -s ../../../feeds/feeds-$VER.conf $buildroot/feeds.conf
log rm $buildroot/dl
log ln -s ../../../$openwrt_dl_dir $buildroot/dl

#if feeds_copied directory contains same packages as delivered with
#openwrt, then assume that the packages came with openwrt git clone are
#older. delete those old packages to force openwrt make system to use the
#new versions of packages from feeds-copied directory

echo "delete old packages from buildroot/package"
for i in $(ls -1 feeds/$VER/feeds-copied) $(ls -1 feeds/$VER/feeds-own)
do
	base=$(basename $i)
	log echo "check: [$base]"
#	test -x $buildroot/package/$base && log echo "rm -rf $buildroot/package/$base" && rm -rf $buildroot/package/$base
	find $buildroot/package -type d -wholename "*/$base" -exec echo "  -> rm {} " \;  -exec rm -rf {} \;
done

#now copy rootfs files to builddir
echo "copy rootfs"
rm -rf $buildroot/files
mkdir -p $buildroot/files
log cp -a $RUN_DIR/files/common/* $buildroot/files/
# always recreated version specific file directory (removed by git if empty). this is just to
# know that there is such a directory ;-)
mkdir -p $RUN_DIR/files/$VER
log cp -a $RUN_DIR/files/$VER/* $buildroot/files/

echo "create rootfs/etc/built_info file"
mkdir -p $buildroot/files/etc
echo "#git revision" > $buildroot/files/etc/built_info
git --no-pager log -n 1 | sed -n '1,1s#^[^ ]*[ ]*#revision:#p' >> $buildroot/files/etc/built_info
echo "builtdate:$(date)" >> $buildroot/files/etc/built_info


echo "change to buildroot [$buildroot]"
cd $buildroot

echo "delete previous firmware: bin/$PLATFORM"
rm -rf bin/$PLATFORM

echo "install feeds"
#log scripts/feeds clean 
log scripts/feeds update ddmesh_own 
log scripts/feeds update ddmesh_copied 
log scripts/feeds install -a -p ddmesh_own 
log scripts/feeds install -a -p ddmesh_copied 

#copy after install feeds, because .config will be overwritten by default config
log echo "copy configuration \($RUN_DIR/$config_file\)"
log cp $RUN_DIR/$config_file .config 

if [ "$MENUCONFIG" = "1" ]; then
	log echo "run menuconfig"
	log make menuconfig
fi

# run make command
log time make $*

$RUN_DIR/files/common/usr/lib/ddmesh/ddmesh-utils-check-firmware-size.sh bin/ar71xx/openwrt-ar71xx-generic-tl-mr3020-v1-squashfs-factory.bin

log echo "images created in $buildroot/bin/..."

