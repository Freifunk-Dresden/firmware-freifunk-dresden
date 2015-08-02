include $(TOPDIR)/rules.mk

PKG_NAME:=addon_319_01
PKG_VERSION:=2

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=base
  CATEGORY:=ddmesh
  DEFAULT:=m
  DEPENDS:=
  TITLE:=Addon to disable Nodes via wifi 
endef

define Package/$(PKG_NAME)/description
	Allows to disable nodes via wifi to prefer backbone connection
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/www/admin
	$(INSTALL_BIN) files/32-ignore $(1)/www/admin
	$(INSTALL_BIN) files/ignore.cgi $(1)/www/admin
	$(INSTALL_DIR) $(1)/usr/lib/ddmesh
	$(INSTALL_BIN) files/ddmesh-firewall-addons.sh $(1)/usr/lib/ddmesh/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
