include $(TOPDIR)/rules.mk

PKG_NAME:=qrencode
PKG_VERSION:=3.1.0
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

#wenn im dl-verzeichniss das file nicht da ist, wird es von URL geladen
#wenn files local liegen dann Prepare section definieren
#PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
#PKG_SOURCE_URL:=
#PKG_MD5SUM:=9b7dc52656f5cbec846a7ba3299f73bd
#PKG_CAT:=zcat

include $(INCLUDE_DIR)/package.mk

define Package/qrencode
  SECTION:=base
  CATEGORY:=ddmesh
  DEFAULT:=y
  DEPENDS:=+libpng
  TITLE:=QR code encoder
  URL:=http://megaui.net/fukuchi/works/qrencode/index.en.html
endef

define Package/qrencode/description
 QR Code encoder
endef

	#export png_LIBS="-L$(STAGING_DIR)/usr/lib -lpng12" && export png_CFLAGS="-I$(STAGING_DIR)/usr/include/libpng" && cd $(PKG_BUILD_DIR) && chmod 755 ./configure && ./configure
#	$(CP) modifies/* $(PKG_BUILD_DIR)
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) sources/* $(PKG_BUILD_DIR)
endef

define Build/Compile
	export png_LIBS="-L$(STAGING_DIR)/usr/lib -lpng12" && export png_CFLAGS="-I$(STAGING_DIR)/usr/include/libpng" && $(MAKE) -C $(PKG_BUILD_DIR) CC="$(TARGET_CC)" $(TARGET_CONFIGURE_OPTS)
endef

define Package/qrencode/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/qrencode $(1)/usr/bin/
endef

$(eval $(call BuildPackage,qrencode))

