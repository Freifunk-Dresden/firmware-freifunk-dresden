include $(TOPDIR)/rules.mk

PKG_NAME:=fix_319_01
PKG_VERSION:=1
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=base
  CATEGORY:=ddmesh
  DEFAULT:=m
  DEPENDS:=
  TITLE:=minor fixes for main release 
endef

define Package/$(PKG_NAME)/description
	corrects firmware filenames, gateway-check when using static ip for lan/wan, gui routes.cgi
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_DATA) files/ddmesh-gateway-check.sh $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/lib/ddmesh
	$(INSTALL_DATA) files/ddmesh-get-firmware-name.sh $(1)/usr/lib/ddmesh/
	$(INSTALL_DIR) $(1)/www/admin
	$(INSTALL_DATA) files/routes.cgi $(1)/www/admin/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
