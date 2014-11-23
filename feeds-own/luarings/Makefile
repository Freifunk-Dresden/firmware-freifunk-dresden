include $(TOPDIR)/rules.mk

PKG_NAME:=luarings
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

#wenn im dl-verzeichniss das file nicht da ist, wird es von URL geladen
#wenn files local liegen dann Prepare section definieren
#PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
#PKG_SOURCE_URL:=
#PKG_MD5SUM:=9b7dc52656f5cbec846a7ba3299f73bd
#PKG_CAT:=zcat

include $(INCLUDE_DIR)/package.mk

define Package/luarings
  SECTION:=base
  CATEGORY:=ddmesh
  DEFAULT:=y
  DEPENDS:=
  TITLE:=needed for wsapi used by cgilua
  URL:=http://download.ddmesh.de/
endef

define Package/luarings/description
 lua rings
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) sources/* $(PKG_BUILD_DIR)
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) CC="$(TARGET_CC)" $(TARGET_CONFIGURE_OPTS)
endef

define Package/luarings/install
	$(INSTALL_DIR) $(1)/usr/lib/lua
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/rings.so $(1)/usr/lib/lua/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/stable.lua $(1)/usr/lib/lua/
endef

$(eval $(call BuildPackage,luarings))

