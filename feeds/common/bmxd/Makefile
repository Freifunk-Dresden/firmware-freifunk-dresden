# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

include $(TOPDIR)/rules.mk

PKG_NAME:=bmxd
PKG_VERSION:=1.1-freifunk-dresden
PKG_RELEASE:=2

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

#wenn im dl-verzeichniss das file nicht da ist, wird es von URL geladen
#wenn files local liegen dann Prepare section definieren
#PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
#PKG_SOURCE_URL:=
#PKG_MD5SUM:=9b7dc52656f5cbec846a7ba3299f73bd
#PKG_CAT:=zcat

include $(INCLUDE_DIR)/package.mk

define Package/bmxd
  CATEGORY:=ddmesh
  DEFAULT:=y
  DEPENDS:=
  TITLE:=BMXD-Routing Protocol
#  URL:=https://gitlab.freifunk-dresden.de/
  SUBMENU:=Packages
endef

define Package/bmxd/description
 Modifiziertes bmxd: Beim Gateway umschalten wird /etc/batmand.gw.sh
 aufgerufen. Einige Bufixes.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) sources/* $(PKG_BUILD_DIR)
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) CC="$(TARGET_CC)" clean
	$(MAKE) -C $(PKG_BUILD_DIR) CC="$(TARGET_CC)"
endef

define Package/bmxd/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bmxd $(1)/usr/bin/
endef

$(eval $(call BuildPackage,bmxd))
