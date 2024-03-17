
#
# Copyright (C) 2017 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
include $(TOPDIR)/rules.mk

PKG_NAME:=gl-e750-mcu
PKG_VERSION:=3.0.50
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

PKG_CONFIG_DEPENDS += CONFIG_BUSYBOX_DEFAULT_TIMEOUT

define Package/gl-e750-mcu/Default
	SECTION:=base
	CATEGORY:=ddmesh
	SUBMENU:=Packages
	TITLE:=GL-iNet mcu interface
	DEPENDS:=+libjson-c +libpthread +libuci +libblobmsg-json +libiwinfo +libubox +libubus +libuuid
endef

Package/gl-e750-mcu = $(Package/gl-e750-mcu/Default)

define Package/gl-e750-mcu/description
GL-E750 mcu data interface for build-in display
endef


define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)
	$(CP) ./files/* $(PKG_BUILD_DIR)
endef

define Package/gl-e750-mcu/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/e750-mcu $(1)/usr/bin

	$(INSTALL_DIR) $(1)/etc/init.d
	$(CP) $(PKG_BUILD_DIR)/e750_mcu $(1)/etc/init.d

	$(INSTALL_DIR) $(1)/etc/config
	$(CP) $(PKG_BUILD_DIR)/mcu $(1)/etc/config

	$(INSTALL_DIR) $(1)/etc/hotplug.d/ntp
	$(CP) $(PKG_BUILD_DIR)/01-check_sync $(1)/etc/hotplug.d/ntp

	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(CP) $(PKG_BUILD_DIR)/18-mcu-notify $(1)/etc/hotplug.d/iface

	$(INSTALL_DIR) $(1)/usr/lib/gl
	$(CP) $(PKG_BUILD_DIR)/libglmcu.so $(1)/usr/lib/gl
	$(LN) /usr/lib/gl/libglmcu.so $(1)/usr/lib/

endef

$(eval $(call BuildPackage,gl-e750-mcu))
