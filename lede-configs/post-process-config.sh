#!/bin/bash


# this script patches the default generated config file, that
# is saved after calling "build.sh lede menuconfig"

usage() 
{
cat <<EOM
# Creating config:
# freifunk firmware build needs to configure openwrt.
# Because config file for each platform differs heavily configuration
# is directly patched to openwrt sources.
#
# lede-patches/lede/config-* contains the neede patches to set
# "default" settings (for packages, busybox...) and removes some
# extra packages that would be installed on each platformm (ipv6,ppp,odhcpd)
#
# Steps to create config:
# 1. ensure that there is no configuration for new platform in lede-config/
# 2. call "build.sh lede menuconfig"
# 3. select three main platform configurations
# 4. save config to correct new config file with secific filename 
#    (which is parsed by build.sh)
# 5. run this script (post-process-config.sh)
# 6. call "build.sh lede menuconfig" 
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
  s/.*CONFIG_PER_FEED_REPO[ =].*/# CONFIG_PER_FEED_REPO is not set/
  s/.*CONFIG_DEVEL[ =].*/CONFIG_DEVEL=y/
  s/.*CONFIG_CCACHE[ =].*/CONFIG_CCACHE=y/

  # disable USB support by default.
#  s/.*CONFIG_USB_SUPPORT[ =].*/# CONFIG_USB_SUPPORT is not set/
  s/.*CONFIG_PACKAGE_kmod-usb-core[ =].*/# CONFIG_PACKAGE_kmod-usb-core is not set/
  s/.*CONFIG_PACKAGE_kmod-usb-ledtrig-usbport[ =].*/# CONFIG_PACKAGE_kmod-usb-ledtrig-usbport is not set/
  s/.*CONFIG_PACKAGE_kmod-usb-ohci[ =].*/# CONFIG_PACKAGE_kmod-usb-ohci is not set/
  s/.*CONFIG_PACKAGE_kmod-usb2[ =].*/# CONFIG_PACKAGE_kmod-usb2 is not set/
  s/.*CONFIG_PACKAGE_kmod-usb3[ =].*/# CONFIG_PACKAGE_kmod-usb3 is not set/

' $1


