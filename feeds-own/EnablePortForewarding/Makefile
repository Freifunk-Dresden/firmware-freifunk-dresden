include $(TOPDIR)/rules.mk

PKG_NAME:=EnablePortforwarding
PKG_VERSION:=2
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/EnablePortforwarding
  SECTION:=base
  CATEGORY:=ddmesh
  DEFAULT:=m
  DEPENDS:=
  TITLE:=Enable Portforwarding
endef

define Package/EnablePortforwarding/description
	Add missing menu entry for port forwarding
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/EnablePortforwarding/install
	$(INSTALL_DIR) $(1)/www/admin
	$(INSTALL_DATA) files/62-portfw $(1)/www/admin/62-portfw
	$(INSTALL_DIR) $(1)/usr/lib/ddmesh
	$(INSTALL_DATA) files/ddmesh-portfw.sh $(1)/usr/lib/ddmesh/ddmesh-portfw.sh
	chmod 755 $(1)/usr/lib/ddmesh/ddmesh-portfw.sh
	
endef

$(eval $(call BuildPackage,EnablePortforwarding))
