#
# Copyright (C) 2006-2012 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=OVPNCerts
PKG_VERSION:=2.5
#PKG_RELEASE:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/OVPNCerts
  SECTION:=base
  CATEGORY:=ddmesh
  DEFAULT:=m
  DEPENDS:=+openvpn-mbedtls
  TITLE:=Open VPN Tunnel
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
#	$(INSTALL_DIR) $(1)/etc/config
#	$(INSTALL_DATA) files/openvpn.config $(1)/etc/config/openvpn
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

#to overcome conficts when files are already provided by other packages (like openvpn provices /etc/config/openvpn)
#a "overlay" installation should be defined (not well documented)
define custom_install_commands
	@echo "Installing extra files"
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) files/openvpn.config $(1)/etc/config/openvpn
endef
# Append custom commands to install recipe,
# and make sure to include a newline to avoid syntax error
Package/base-files/install += $(newline)$(custom_install_commands)



$(eval $(call BuildPackage,OVPNCerts))
