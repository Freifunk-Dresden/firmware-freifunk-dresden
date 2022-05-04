# Copyright (C) 2010 Stephan Enderlein <stephan@freifunk-dresden.de>
# GNU General Public License Version 3

include $(TOPDIR)/rules.mk

PKG_NAME:=feinstaubsensor
PKG_VERSION:=2

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=base
  CATEGORY:=ddmesh
  TITLE:=Feinstaubsensor Project
  SUBMENU:=Packages
endef

define Package/$(PKG_NAME)/description
	Adds displaying fine particles graphic to gui (http://luftdaten.info/)
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/www
	$(INSTALL_DIR) $(1)/www/admin
	$(INSTALL_DIR) $(1)/etc/config
	cp files/05-fineparticle $(1)/www/
	cp files/fineparticle.cgi $(1)/www/
	cp files/admin_81-fineparticle $(1)/www/admin/81-fineparticle
	cp files/admin_fineparticle.cgi $(1)/www/admin/fineparticle.cgi
	$(INSTALL_CONF) files/fine-particle.config $(1)/etc/config/fine-particle
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh

# put script here if needed

endef

$(eval $(call BuildPackage,$(PKG_NAME)))
