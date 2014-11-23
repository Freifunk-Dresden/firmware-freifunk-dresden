# 
# Copyright (C) 2007-2011 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=cgilua
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/cgilua
  SECTION:=base
  CATEGORY:=ddmesh
  DEFAULT:=n
  DEPENDS:=+luarings
  TITLE:=cgilua
  URL:=
  PKGARCH:=all
endef

define Package/cgilua/description
 A lua cgi enviroment
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/cgilua/install
	$(INSTALL_DIR) $(1)/www/cgilua
	$(INSTALL_BIN) ./files/* $(1)/www/cgilua/
endef

define Package/cgilua/conffiles
endef

$(eval $(call BuildPackage,cgilua))
