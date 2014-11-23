#!/bin/bash

#usage: build.ar71xx.sh [VER]
#       VER: openwrt version. default is "12.09"
#excample: build.ar71xx.sh
#excample: build.ar71xx.sh 12.09

PLATFORM=ar71xx
DL_DIR=dl
WORK_DIR=workdir
CONFIG_DIR=openwrt-configs
OPENWRT_PATCHES_DIR=openwrt-patches

#use "original" or "ddmesh" openwrt config
CONFIG_TYPE=ddmesh

#define a list of supported versions
VERSIONS="12.09"


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

if [ -z "$VER" ]; then
	# create a simple menu
	echo "================================"
	echo " Arguments: $* "
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
	12.09)
		git_url="git://git.openwrt.org/$VER/openwrt.git"
		openwrt_rev="80c728365438d670bca4ed30251bfd00d773bae8"
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

 log mkdir -p $openwrt_dl_dir

 #check if we have already downloaded the openwrt revision
 if [ -f $openwrt_dl_tgz ]
 then
 	#extract into buildroot dir
 	log echo "using already downloaded $openwrt_dl_tgz"
 	log mkdir -p $buildroot
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

 log echo "create dl directory/links and feed links"
 log ln -s ../../../feeds.conf/feeds-$VER.conf $buildroot/feeds.conf
 log ln -s ../../../$openwrt_dl_dir $buildroot/dl
else
 log echo "Buildroot [$buildroot] already present"
fi

#if feeds_copied directory contains same packages as delivered with
#openwrt, then assume that the packages came with openwrt git clone are
#older. delete those old packages to force openwrt make system to use the
#new versions of packages from feeds-copied directory

echo "delete old packages from buildroot/package"
for i in feeds-copied/* feeds-own/*
do
	base=$(basename $i)
	log echo "$i [$buildroot/package/$base]"
#	test -x $buildroot/package/$base && log echo "rm -rf $buildroot/package/$base" && rm -rf $buildroot/package/$base
	find $buildroot/package -type d -wholename "*/$base" -exec rm -rf {} \;
done

#now copy rootfs files to builddir
echo "copy rootfs"
rm -rf $buildroot/files
mkdir -p $buildroot/files
log cp -a $RUN_DIR/files/common/* $buildroot/files/
log cp -a $RUN_DIR/files/$VER/* $buildroot/files/

echo "create rootfs/etc/built_info file"
echo "#git revision" > $buildroot/files/etc/built_info
git --no-pager log -n 1 | sed -n '1,1s#^[^ ]*[ ]*#revision:#p' >> $buildroot/files/etc/built_info
echo "builtdate:$(date)" >> $buildroot/files/etc/built_info


echo "change to buildroot [$buildroot]"
cd $buildroot

echo "install feeds"
log scripts/feeds update -a
log scripts/feeds install -a

#copy after install feeds, because .config will be overwritten by default config
log echo "copy configuration \($RUN_DIR/$config_file\)"
log cp $RUN_DIR/$config_file .config 

log echo "run menuconfig"
log make menuconfig
log time make $*

$RUN_DIR/files/common/usr/lib/ddmesh/ddmesh-utils-check-firmware-size.sh bin/ar71xx/openwrt-ar71xx-generic-tl-mr3020-v1-squashfs-factory.bin

log echo "images created in $buildroot/bin/..."

