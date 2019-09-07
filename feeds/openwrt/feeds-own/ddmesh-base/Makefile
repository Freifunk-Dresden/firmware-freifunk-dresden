
include $(TOPDIR)/rules.mk

PKG_NAME:=ddmesh
PKG_VERSION:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

##########################################################
define Package/$(PKG_NAME)-base
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

# This section holds only package configurations (compile switches).
# Each config may depend on some packages and is displayed if this 
# packages was selected
define Package/$(PKG_NAME)-base/config

	# menu is optional. It is directly inserted below current package menu entry (same window)
	#menu "Modules"
		# menu point is displayed when dependings are set
		#depends on PACKAGE_ddmesh-base

		# use SYMBOL of package that should be selected
		config PACKAGE_fastd
			# menu point is displayed when dependings are set
			depends on PACKAGE_ddmesh-base
			tristate "fastd"
			help
				required by firmware

		# use SYMBOL of package that should be selected
		config PACKAGE_bmxd
			# menu point is displayed when dependings are set
			depends on PACKAGE_ddmesh-base
			tristate "bmxd"
			help
				required by firmware

		# use SYMBOL of package that should be selected
		config PACKAGE_ddns-scripts
			# menu point is displayed when dependings are set
			depends on PACKAGE_ddmesh-base
			tristate "ddns-scripts"
			help
				required by firmware

		# use SYMBOL of package that should be selected
		config PACKAGE_freifunk-upload
			# menu point is displayed when dependings are set
			depends on PACKAGE_ddmesh-base
			tristate "ddns-scripts"
			help
				required by firmware

		# use SYMBOL of package that should be selected
		config PACKAGE_wshaper
			# menu point is displayed when dependings are set
			depends on PACKAGE_ddmesh-base
			tristate "wshaper"
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

define Package/$(PKG_NAME)-usb-storage
  CATEGORY:=ddmesh
  # keep it as default. if I create a new config for non-wifi targets, it would select wifi
  DEFAULT:=n
  DEPENDS:= $(PKG_NAME)-base \
		+kmod-usb-core +kmod-usb2 +kmod-usb-ohci +kmod-usb-ledtrig-usbport +kmod-usb-storage \
		+kmod-fs-vfat \
		+block-mount 

  TITLE:=Meta package to enable usb storage
endef

define Package/$(PKG_NAME)-usb-storage/description
        Meta package to enable usb storage support
endef

##########################################################

define Package/$(PKG_NAME)-usb-lte
  CATEGORY:=ddmesh
  # keep it as default. if I create a new config for non-wifi targets, it would select wifi
  DEFAULT:=n
  # usb umts/lte sticks has storage device. but I is normally not needed.
  DEPENDS:= $(PKG_NAME)-base \
		+kmod-usb-core +kmod-usb2 +kmod-usb-ohci \
		+kmod-usb-ledtrig-usbport +kmod-usb-storage \
		+usb-modeswitch \
                +kmod-mii +kmod-usb-net +kmod-usb-wdm +kmod-usb-net-qmi-wwan +uqmi \
                +kmod-usb-net-cdc-mbim +umbim \
		+kmod-usb-serial-option +kmod-usb-serial +kmod-usb-serial-wwan \
                +kmod-usb-net-cdc-ether

  TITLE:=Meta package to enable usb LTE modem support
endef

define Package/$(PKG_NAME)-usb-lte/description
        Meta package to enable usb LTE modem support
        https://openwrt.org/docs/guide-user/network/wan/wwan/ltedongle

	LTE Stick must be switch to "ndis" interface via AT commands instead of "modem"
	see: https://openwrt.org/docs/guide-user/network/wan/wwan/at_commands

	See: http://m2msupport.net/m2msupport/tutorial-for-huawei-modules/
	Huawei: https://rychly.gitlab.io/post/huawei-e173s1/

	ACHTUNG:  Never turn Off PC interface (2:PCUI in this example)!
        Denn da diese Settings persistent sind, kann man nicht mehr via terminal auf 
        den stick zu greifen und ihn mit AT commands konfigurieren


	Huawei E173
	-------------
	GSM modem (1-port) converters attached to
          - /dev/ttyUSB0 (AT commands),
          - /dev/ttyUSB1 (data),
          - /dev/ttyUSB2 (status & AT commands)

	AT Commands (general)
	  - ATI - displays gsm modul information
            Manufacturer: huawei
            Model: E173
            Revision: 11.126.29.00.1130
            IMEI: xxxxxxxx
            +GCAP: +CGSM,+DS,+ES

          - AT+COPS? – get active network Name and ID
            +COPS: 1,0,"disco",2
     
          - AT+CSQ – get signal strength as +CSQ rssi (higher is better) and ber (lower is better; 99 = unknown)

          - 
        AT Commands for Huawei
          - AT^GETPORTMODE to display a list of devices present in a USB-stick
            ^GETPORTMODE:TYPE:WCDMA:Qualcomm,MDM:0,NDIS:1,DIAG:2,PCUI:3,CDROM:4,SD:5

          - AT^SYSCFG? to display network-mode preferences
            ^SYSCFG:2,2,3FFFFFFF,1,2 

          - AT^U2DIAG? for reading/controlling default mode (an alternative to usb_modeswitch)
            276 - means: currently factory reset values are set (all enabled)

          usb_modeswitch will do all the needed steps to switch from SDCard to Modem.


        
endef

##########################################################

define Package/$(PKG_NAME)-wifi-extra
  CATEGORY:=ddmesh
  # keep it as default. if I create a new config for non-wifi targets, it would select wifi
  DEFAULT:=n
  DEPENDS:= $(PKG_NAME)-wifi \
		+kmod-usb-core +kmod-usb2 +kmod-usb-ohci \
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
        Meta package to select extra wifi drivers for usb sticks.
	This is useful for Futro with usb stick wifi support
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
  DEFAULT:=m
  # I do not select all possible modules, so I can disable them
  #DEPENDS:= +tcpdump +OVPNCerts +feinstaubsensor
  #DEPENDS:= +tcpdump +OVPNCerts

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
		# menu point is displayed when dependings are set
		# depends on PACKAGE_ddmesh-extra-modules

		# use SYMBOL of package that should be selected
		config PACKAGE_tcpdump
			# menu point is displayed when dependings are set
			depends on PACKAGE_ddmesh-extra-modules
			tristate "tcpdump"

		config PACKAGE_OVPNCerts
			# menu point is displayed when dependings are set
			depends on PACKAGE_ddmesh-extra-modules
			tristate "OVPNCerts"
			help
				Create openvpn tunnel used by router as public gateway.

		config PACKAGE_wireguard
			# menu point is displayed when dependings are set
			depends on PACKAGE_ddmesh-extra-modules
			tristate "wireguard"
			help
				Create wireguard tunnel used by router as public gateway.

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
#	endmenu

endef

##########################################################
$(eval $(call BuildPackage,$(PKG_NAME)-base))
$(eval $(call BuildPackage,$(PKG_NAME)-wifi))
$(eval $(call BuildPackage,$(PKG_NAME)-usb-storage))
$(eval $(call BuildPackage,$(PKG_NAME)-usb-lte))
$(eval $(call BuildPackage,$(PKG_NAME)-wifi-extra))
$(eval $(call BuildPackage,$(PKG_NAME)-extra-modules))

