#!/bin/bash


# this script patches the default generated config file, that
# is saved after calling "build.sh openwrt menuconfig"

usage() 
{
cat <<EOM
# Creating config:
# freifunk firmware build needs to configure openwrt.
# Because config file for each platform differs heavily configuration
# is directly patched to openwrt sources.
#
# openwrt-patches/openwrt/config-* contains the neede patches to set
# "default" settings (for packages, busybox...) and removes some
# extra packages that would be installed on each platformm (ipv6,ppp,odhcpd)
#
# Steps to create config:
# 1. ensure that there is no configuration for new platform in openwrt-config/
# 2. call "build.sh openwrt menuconfig"
# 3. select three main platform configurations (Target System, Subtarget, Target Profile)
#    e.g.: 
	Target System:	Atheros AR7xxxx/AR9xxx
	Subtarget:	Devices with small flash (this is new since Openwrt 18
						  which per default creates only >= 8Mbyte flaesh devices)
	Target Profile:	Default Profile (all drivers)
#
# 4. save config to correct new config file with secific filename 
#    Filename is parsed by build.sh. 
#      The format is: 
#        config.<platform>.<subplatform>
#      or
#        config.<platform>.<subplatform>.<device>
#    look at directory structure at https://downloads.openwrt.org/releases/18.06.1/targets/
#  
# 5. run this script (post-process-config.sh)
# 6. call "build.sh openwrt menuconfig" 
# 7. optional select ddmesh-wifi package for images with wifi support
# 8. optional select "extra-packages" (in ddmesh) to select all optional packages
#    that should be available for manuall installation
# 9. optional select usb support
#10. save config to correct new config file with secific filename 
EOM
}


if [ -z "$1" ]; then
	echo "missing config file name to modify"
	echo ""
	usage
	exit 1
fi

sed -i '
  s/.*CONFIG_IMAGEOPT[ =].*/CONFIG_IMAGEOPT=y/
  s/.*\(CONFIG_PER_FEED_REPO\)[ =].*/# CONFIG_PER_FEED_REPO is not set/
  s/.*CONFIG_DEVEL[ =].*/CONFIG_DEVEL=y/
  s/.*CONFIG_CCACHE[ =].*/CONFIG_CCACHE=y/
  s/.*CONFIG_TARGET_ROOTFS_TARGZ[ =].*/CONFIG_TARGET_ROOTFS_TARGZ=y/

  # this setting creates for each device its own set packages. if not selected
  # (was default) all images contain all packages, also if not used.
  # This setting must be done BEFORE calling menuconfig, as per default
  # all packages are set. later change to this option will then have no effect.
  # see "help" of this option when calling menuconfig
  s/.*CONFIG_TARGET_PER_DEVICE_ROOTFS[ =].*/CONFIG_TARGET_PER_DEVICE_ROOTFS=y/

  # - increment squashfs block size from 256 to 512kbyte to get a better compression.
  # - this gives me one flash sector more for rootfs
  # - value must be muliple of power 2
  # - a value of 1024 does not increment rootfs size (rootfs final squash file size is 
  #   a little more than 256, so compression will improve with blocksize 512kbyte but not
  #   with higher values
  # see: https://openwrt.org/docs/guide-user/additional-software/saving_space
  #
  s/.*CONFIG_TARGET_SQUASHFS_BLOCK_SIZE[ =].*/CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=512/

  # disable USB support by default.
#  s/.*\(CONFIG_USB_SUPPORT\)[ =].*/# \1 is not set/
  s/.*\(CONFIG_PACKAGE_kmod-usb-core\)[ =].*/# \1 is not set/
  s/.*\(CONFIG_PACKAGE_kmod-usb-ledtrig-usbport\)[ =].*/# \1 is not set/
  s/.*\(CONFIG_PACKAGE_kmod-usb-ohci\)[ =].*/# \1 is not set/
  s/.*\(CONFIG_PACKAGE_kmod-usb2\)[ =].*/# \1 is not set/
  s/.*\(CONFIG_PACKAGE_kmod-usb3\)[ =].*/# \1 is not set/

 # disable other options per default 
  s/.*\(CONFIG_PACKAGE_kmod-nls-base\)[ =].*/# \1 is not set/
  s/.*\(CONFIG_PACKAGE_kmod-ppp\)[ =].*/# \1 is not set/
  s/.*\(CONFIG_PACKAGE_kmod-slhc\)[ =].*/# \1 is not set/
  s/.*\(CONFIG_PACKAGE_kmod-gpio-button-hotplug\)[ =].*/# \1 is not set/
  s/.*\(CONFIG_PACKAGE_kmod-lib-crc-ccitt\)[ =].*/# \1 is not set/
  s/.*\(CONFIG_PACKAGE_odhcpd-ipv6only\)[ =].*/# \1 is not set/
  s/.*\(CONFIG_PACKAGE_ppp\)[ =].*/# \1 is not set/

 # wpad-basic is used for some targets, but in ff firmware 
 # I specifiy which version should be used.
 # so disable 
  s/.*\(CONFIG_PACKAGE_wpad-basic\)[ =].*/# \1 is not set/

' $1


