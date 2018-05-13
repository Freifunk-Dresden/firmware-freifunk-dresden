
include $(TOPDIR)/rules.mk

PKG_NAME:=ddmesh
PKG_VERSION:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

##########################################################
define Package/$(PKG_NAME)-base
  SECTION:=base
  CATEGORY:=ddmesh
  DEFAULT:=y
  DEPENDS:=	+kmod-ledtrig-timer +kmod-tun +libmbedtls +libustream-mbedtls \
		+uhttpd \
		+bmxd +freifunk-upload \
		+fastd +@FASTD_ENABLE_METHOD_NULL +@FASTD_ENABLE_CIPHER_NULL +@FASTD_ENABLE_CIPHER_SALSA2012 \
		+libuecc +nacl +ddns-scripts +ddns-scripts_no-ip_com \
		+px5g-mbedtls \
		+iperf3

  TITLE:=Meta package to select all needed basic packages
endef

define Package/$(PKG_NAME)-base/description
	Meta package to select all needed basic packages
endef

##########################################################

define Package/$(PKG_NAME)-wifi
  SECTION:=base
  CATEGORY:=ddmesh
  # keep it as default. if I create a new config for non-wifi targets, it would select wifi
  DEFAULT:=n
	# to enable basic wifi, kmod-mac80211 is needed
	# wpa-cli is used to set depending on whether router has internet or not.
	#
	# If wpa-mini is not selected wpa-cli will not appear in menu. And because of this
	# complete package ddmesh-wifi will also not be visible.
	# only solution is to specify dependency as "SYMBOL" to select (+@PACKAGE_wpa-cli).
	# This simply just selects wpa-cli without hiding current packet
  DEPENDS:= $(PKG_NAME)-base \
		+iw +iwinfo +wpad-mini +@PACKAGE_wpa-cli +wshaper

  TITLE:=Selects all addtional wifi tools.
endef

define Package/$(PKG_NAME)-wifi/description
  Selects all addtional wifi tools.
  When platform was selected all needed default wifi driver and tools are selected.
  This module selects some tools in additon for Freifunk Dresden firmware.
endef

##########################################################

define Package/$(PKG_NAME)-usb
  SECTION:=base
  CATEGORY:=ddmesh
  # keep it as default. if I create a new config for non-wifi targets, it would select wifi
  DEFAULT:=n
  DEPENDS:= $(PKG_NAME)-base \
		+kmod-usb-core +kmod-usb2 +kmod-usb-storage +kmod-usb-ledtrig-usbport +kmod-usb-ohci

  TITLE:=Meta package to enable usb
endef

define Package/$(PKG_NAME)-wifi/description
        Meta package to enable usb support
endef

##########################################################

define Package/$(PKG_NAME)-wifi-extra
  SECTION:=base
  CATEGORY:=ddmesh
  # keep it as default. if I create a new config for non-wifi targets, it would select wifi
  DEFAULT:=n
  DEPENDS:= $(PKG_NAME)-usb $(PKG_NAME)-wifi \
		+kmod-ath10k +kmod-ath5k +kmod-ath9k \
		+kmod-p54-usb \
		+kmod-rt2500-usb \
		+kmod-rt2800-usb \
		+kmod-rt2x00-usb \
		+kmod-rt73-usb \
		+kmod-rtl8187

  TITLE:=Meta package to select extra wifi drivers
endef

define Package/$(PKG_NAME)-wifi-extra/description
        Meta package to select extra wifi drivers.
	This is useful for Futro with usb stick wifi support
endef

##########################################################
define Package/$(PKG_NAME)-extra-modules
  SECTION:=base
  CATEGORY:=ddmesh
	
  # when this module is selected, it also selects all depending modules as module.
  # The "config" section can contain "default", but this is ignored. 
  # If the package itself setups DEFAULT, then this is used.
  # The DEFAULT of this package (ddmesh-extra-modules) overwrites the default. But it can not
  # go below package DEFAULT. Means:  N -> <N|M|Y>  OR M -> {M|Y}  OR Y -> {Y}
  # 
  # The "default" value of the menu below is completely ignored
  DEFAULT:=m
  # I do not select all possible modules, so I can disable them
  #DEPENDS:= +tcpdump +OVPNCerts +feinstaubsensor
  DEPENDS:= +tcpdump +OVPNCerts

  TITLE:=Meta package to select extra packages
  # when MENU:=1 than this package also has a submenu.
  # all under "config" section below is moved to it
  # MENU:=1
endef

define Package/$(PKG_NAME)-extra-modules/description
  Meta package to select some packages commonly included in firmware
endef

define Package/$(PKG_NAME)-extra-modules/config

	# Because "config PACKAGE_tcpdump" has same name as the normal menu location,
	# both menu places (orignal and ours) can switch on/off package and the other one is updated
	# correspontely


	# menu is optional. It is directly inserted below current package menu entry (same window)
	menu "Modules"
	# menu point is displayed when dependings are set
	depends on PACKAGE_ddmesh-extra-modules

		# use SYMBOL of package that should be selected
		config PACKAGE_tcpdump
			# menu point is displayed when dependings are set
			depends on PACKAGE_ddmesh-extra-modules
			tristate "tcpdump"

		config PACKAGE_OVPNCerts
			# menu point is displayed when dependings are set
			depends on PACKAGE_ddmesh-extra-modules
			tristate "Openvpn (used by OVPNCerts)"
			help
				Create openvpn tunel used by router as public gateway.

		config PACKAGE_feinstaubsensor
			# menu point is displayed when dependings are set
			depends on PACKAGE_ddmesh-extra-modules
			tristate "Feinstaubensor (Stuttgard Project)"
			help
				This module simply includes a menu to display
				Feinstaubsensor graphics.
				Image link must be modified to display graphic for
				your own sensor.
				See http://luftdaten.info/
	endmenu

endef

##########################################################
$(eval $(call BuildPackage,$(PKG_NAME)-base))
$(eval $(call BuildPackage,$(PKG_NAME)-wifi))
$(eval $(call BuildPackage,$(PKG_NAME)-usb))
$(eval $(call BuildPackage,$(PKG_NAME)-wifi-extra))
$(eval $(call BuildPackage,$(PKG_NAME)-extra-modules))

