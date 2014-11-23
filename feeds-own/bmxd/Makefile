include $(TOPDIR)/rules.mk

PKG_NAME:=bmxd
PKG_VERSION:=0.3rv1885
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

#wenn im dl-verzeichniss das file nicht da ist, wird es von URL geladen
#wenn files local liegen dann Prepare section definieren
#PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
#PKG_SOURCE_URL:=
#PKG_MD5SUM:=9b7dc52656f5cbec846a7ba3299f73bd
#PKG_CAT:=zcat

include $(INCLUDE_DIR)/package.mk

define Package/bmxd
  SECTION:=base
  CATEGORY:=ddmesh
  SUBMENU:=Routing
  DEFAULT:=y
  DEPENDS:=
  TITLE:=BMXD-Routing Protocol
  URL:=http://download.ddmesh.de/
endef

define Package/bmxd/description
 Modifiziertes bmxd: Beim Gateway umschalten wird /etc/batmand.gw.sh
 aufgerufen.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) sources/* $(PKG_BUILD_DIR)
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) CC="$(TARGET_CC)"
endef

define Package/bmxd/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bmxd $(1)/usr/bin/
endef

$(eval $(call BuildPackage,bmxd))

