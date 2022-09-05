# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de>
# GNU General Public License Version 3

include $(TOPDIR)/rules.mk

PKG_NAME:=OVPNCerts
PKG_VERSION:=2.5
#PKG_RELEASE:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/OVPNCerts
  SECTION:=base
  CATEGORY:=ddmesh
  DEFAULT:=n
  DEPENDS:=+openvpn-mbedtls
  TITLE:=Open VPN Tunnel
  SUBMENU:=Packages
endef

define Package/OVPNCerts/description
 Open VPN Tunnel - allows to installed cert.tgz files to setup internet tunnel.
 A script parses the configuration and creates it dynamically
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/OVPNCerts/install
	$(INSTALL_DIR) $(1)/etc/config
	# copy as openvpn.ffdd because of install conflics when OVPNCerts
	# is included directly into firmware
	# it will be renamed in ddmesh-init.d.sh
	$(INSTALL_DATA) files/openvpn.config $(1)/etc/config/openvpn.ffdd
	$(INSTALL_DIR) $(1)/etc/openvpn
	$(INSTALL_DATA) files/up.sh $(1)/etc/openvpn/up.sh
	$(INSTALL_DATA) files/down.sh $(1)/etc/openvpn/down.sh
	$(INSTALL_DATA) files/gen-config.sh $(1)/etc/openvpn/gen-config.sh
	chmod 755 $(1)/etc/openvpn/up.sh
	chmod 755 $(1)/etc/openvpn/down.sh
	chmod 755 $(1)/etc/openvpn/gen-config.sh
	$(INSTALL_DIR) $(1)/www/admin
	$(INSTALL_DATA) files/36-tunnel $(1)/www/admin
	$(INSTALL_DATA) files/tunnel.cgi $(1)/www/admin
endef

$(eval $(call BuildPackage,OVPNCerts))
