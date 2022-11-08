# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

include $(TOPDIR)/rules.mk

PKG_NAME:=ddmesh
PKG_VERSION:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

# when a additional package should be selected when another gets selected
#+PACKAGE_wireguard-tools:kmod-ipip \

##########################################################
define Package/$(PKG_NAME)-base
  CATEGORY:=ddmesh
  DEFAULT:=y
  DEPENDS:=	+base-files +busybox +dnsmasq +firewall +logd +uci +dropbear \
    +firewall +iptables +kmod-nf-flow +kmod-ipt-offload \
    +ip-tiny \
    +mtd +opkg \
    +uhttpd \
    +kmod-leds-gpio +kmod-gpio-button-hotplug \
    +kmod-tun \
    +libmbedtls +libustream-mbedtls +px5g-mbedtls \
    +bmxd +freifunk-upload \
    +iperf3 \
    +kmod-ipip \
    +PACKAGE_fastd:nacl \
    +PACKAGE_fastd:libuecc \
    +PACKAGE_fastd:libmnl \
    +PACKAGE_fastd:kmod-l2tp-eth

  TITLE:=Meta package to select all needed basic packages
endef

define Package/$(PKG_NAME)-base/description
  Meta package to select all needed basic packages
endef

# This section holds only package configurations (compile switches).
# Each config may depend on some packages and is displayed if this
# packages was selected
define Package/$(PKG_NAME)-base/config

 # menu is optional. It is directly inserted below current package menu entry (same window)
 #menu "Modules"
   # menu point is displayed when dependencies are selected
   #depends on PACKAGE_ddmesh-base

   # use SYMBOL of package that should be selected
   config PACKAGE_fastd
     # menu point is displayed when dependencies are selected
     depends on PACKAGE_ddmesh-base
     tristate "fastd"
     help
       Create fastd tunnel to backbone servers.

   config PACKAGE_wireguard-tools
     # menu point is displayed when dependencies are selected
     depends on PACKAGE_ddmesh-base
     tristate "wireguard"
     help
       Create wireguard tunnel to backbone servers.

   # use SYMBOL of package that should be selected
   config PACKAGE_bmxd
     # menu point is displayed when dependencies are selected
     depends on PACKAGE_ddmesh-base
     tristate "bmxd"
     help
       required by firmware

   # use SYMBOL of package that should be selected
   config PACKAGE_freifunk-upload
     # menu point is displayed when dependencies are selected
     depends on PACKAGE_ddmesh-base
     tristate "freifunk-upload"
     help
       required by firmware

 #endmenu

endef
##########################################################

define Package/$(PKG_NAME)-wifi
  CATEGORY:=ddmesh
  # keep it as default. if I create a new config for non-wifi targets, it would select wifi
  DEFAULT:=n
  # to enable basic wifi, kmod-mac80211 is needed
  #
  # If wpa-basic is not selected wpa-cli will not appear in menu. And because of this
  # the complete package "ddmesh-wifi" will also not be visible.
  # only solution is to specify dependency as "SYMBOL" to select (+@PACKAGE_wpa-cli).
  # This simply just selects wpa-cli without hiding current packet
  DEPENDS:= $(PKG_NAME)-base \
            +iw +iwinfo +wpad-mini +kmod-owl-loader +@PACKAGE_wpa-cli

  TITLE:=Selects all addtional wifi tools.

endef

define Package/$(PKG_NAME)-wifi/description
  Selects all addtional wifi tools.
  When platform was selected all needed default wifi driver and tools are selected.
  This module selects some tools in additon for Freifunk Dresden firmware.
endef

##########################################################

define Package/$(PKG_NAME)-usb-storage
  CATEGORY:=ddmesh
  # keep it as default. if I create a new config for non-wifi targets, it would select wifi
  DEFAULT:=n
  DEPENDS:= $(PKG_NAME)-base \
            +kmod-nls-base +kmod-usb-core +kmod-usb2 +kmod-usb2-pci +kmod-usb3 \
            +kmod-usb-ehci +kmod-usb-ohci +kmod-usb-ohci-pci \
            +kmod-usb-uhci +kmod-usb-dwc2 +kmod-usb-dwc3 \
            +kmod-usb-ledtrig-usbport \
            \
            +kmod-usb-storage +kmod-fs-vfat +block-mount \
            \
            +usbutils

  TITLE:=Meta package to enable usb storage
endef

define Package/$(PKG_NAME)-usb-storage/description
        Meta package to enable usb storage support
endef

##########################################################
# https://openwrt.org/docs/guide-user/network/wan/smartphone.usb.tethering

define Package/$(PKG_NAME)-tethering
  CATEGORY:=ddmesh
  DEFAULT:=n
  DEPENDS:= $(PKG_NAME)-base \
            +kmod-nls-base +kmod-usb-core +kmod-usb2 +kmod-usb2-pci +kmod-usb3 \
            +kmod-usb-ehci +kmod-usb-ohci +kmod-usb-ohci-pci \
            +kmod-usb-uhci +kmod-usb-dwc2 +kmod-usb-dwc3 \
            +kmod-usb-ledtrig-usbport \
            \
            +kmod-mii +kmod-usb-net \
            +kmod-usb-net-cdc-ether \
            +kmod-usb-net-rndis \
            +comgt-ncm +kmod-usb-net-huawei-cdc-ncm \
            +kmod-usb-net-ipheth +usbmuxd +libimobiledevice \
            +kmod-usb-wdm +kmod-usb-net-qmi-wwan +uqmi \
            +kmod-usb-net-cdc-mbim +umbim \
            \
            +kmod-usb-storage \
            +kmod-usb-serial-option +kmod-usb-serial +kmod-usb-serial-wwan \
            +usb-modeswitch \
            +usbutils

  TITLE:=Meta package to enable usb smartphone/LTE router tethering
endef

define Package/$(PKG_NAME)-tethering/description
        Meta package to enable usb smartphone and LTE router tethering.
        - used for Gl.inet GL-Mifi router with built in LTE module
        - android usb tethering (usb network interface)
        - LTE Router. Some LTE Router usb sticks
        offer also a network interface directly via cdc-ether (ZTE MF79U)
endef

##########################################################
define Package/$(PKG_NAME)-extra-modules
  CATEGORY:=ddmesh

  # when this module is selected, it also selects all depending modules as module.
  # The "config" section can contain "default", but this is ignored.
  # If the package itself setups DEFAULT, then this is used.
  # The DEFAULT of this package (ddmesh-extra-modules) overwrites the default. But it can not
  # go below package DEFAULT. Means:  N -> <N|M|Y>  OR M -> {M|Y}  OR Y -> {Y}
  #
  # The "default" value of the menu below is completely ignored
  # DEFAULT:=y

  DEPENDS:= $(PKG_NAME)-base

  TITLE:=Meta package to select extra packages
  # when MENU:=1 than this package also has a submenu.
  # all under "config" section below is moved to it
  # MENU:=1
endef

define Package/$(PKG_NAME)-extra-modules/description
  Meta package to select some packages commonly included in firmware
endef

define Package/$(PKG_NAME)-extra-modules/config

  # menu is optional. It is directly inserted below current package menu entry (same window)
  # menu "Modules"
    # menu point is displayed when dependencies are selected
    # depends on PACKAGE_ddmesh-extra-modules

    # use SYMBOL of package that should be selected
    config PACKAGE_tcpdump
      # menu point is displayed when dependencies are selected
      depends on PACKAGE_ddmesh-extra-modules
      tristate "tcpdump"

#    config PACKAGE_OVPNCerts
#      # menu point is displayed when dependencies are selected
#      depends on PACKAGE_ddmesh-extra-modules
#      tristate "OVPNCerts"
#      help
#        Create openvpn tunnel used by router as public gateway.

#    config PACKAGE_feinstaubsensor
#      # menu point is displayed when dependencies are selected
#      depends on PACKAGE_ddmesh-extra-modules
#      tristate "Feinstaubensor (Stuttgard Project)"
#      help
#        This module simply includes a menu to display
#        Feinstaubsensor graphics.
#        Image link must be modified to display graphic for
#        your own sensor.
#        See http://luftdaten.info/

  # endmenu

endef

##########################################################
$(eval $(call BuildPackage,$(PKG_NAME)-base))
$(eval $(call BuildPackage,$(PKG_NAME)-wifi))
$(eval $(call BuildPackage,$(PKG_NAME)-usb-storage))
$(eval $(call BuildPackage,$(PKG_NAME)-tethering))
$(eval $(call BuildPackage,$(PKG_NAME)-extra-modules))
