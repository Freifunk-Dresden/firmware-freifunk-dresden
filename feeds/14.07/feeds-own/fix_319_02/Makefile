include $(TOPDIR)/rules.mk

PKG_NAME:=fix_319_02
PKG_VERSION:=1

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
	corrects statistic for dhcp user 
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/www/
	$(INSTALL_BIN) files/sysinfo-json.cgi $(1)/www/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
