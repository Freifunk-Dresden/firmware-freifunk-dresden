include $(TOPDIR)/rules.mk

PKG_NAME:=freifunk-upload
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

define Package/freifunk-upload
  SECTION:=base
  CATEGORY:=ddmesh
  DEFAULT:=y
  DEPENDS:
  TITLE:=Altes Firmware Upload Tool
  URL:=http://download.ddmesh.de/
endef

define Package/freifunk-upload/description
 freifunk firmware upload tool (alt)
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) sources/* $(PKG_BUILD_DIR)
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) CC="$(TARGET_CC)" $(TARGET_CONFIGURE_OPTS)
endef

define Package/freifunk-upload/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/freifunk-upload $(1)/usr/bin/
endef

$(eval $(call BuildPackage,freifunk-upload))

