# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

include $(TOPDIR)/rules.mk

PKG_NAME:=fix_428
PKG_VERSION:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=base
  CATEGORY:=ddmesh
  DEFAULT:=n
  DEPENDS:=
  TITLE:=adds fixes to 4.2.8
  SUBMENU:=Packages
endef

define Package/$(PKG_NAME)/description
	fix firmware upgrade
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	# $(INSTALL_DIR) $(1)/usr/lib/ddmesh
	# $(INSTALL_BIN) files/ddmesh-gateway-check.sh $(1)/usr/lib/ddmesh/
	cp -a files/* $(1)/
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh

# put script here if needed

endef

$(eval $(call BuildPackage,$(PKG_NAME)))
