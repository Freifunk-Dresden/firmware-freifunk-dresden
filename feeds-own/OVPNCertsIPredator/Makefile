#
# Copyright (C) 2006-2012 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=OVPNCertsIPredator
PKG_VERSION:=1
PKG_RELEASE:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/OVPNCertsIPredator
  SECTION:=base
  CATEGORY:=ddmesh
  DEPENDS:=+openvpn-openssl
  TITLE:=Open VPN Tunnel - Ipredator
  URL:=http://www.ipredator.se
endef

define Package/OVPNCertsIPredator/description
 Open VPN Tunnel - Ipredator 
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/OVPNCertsIPredator/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) files/openvpn.config $(1)/etc/config/openvpn
	$(INSTALL_DIR) $(1)/etc/openvpn
	$(INSTALL_DATA) files/IPredator.se.ca.crt $(1)/etc/openvpn/IPredator.se.ca.crt
	$(INSTALL_DATA) files/IPredator.se.conf $(1)/etc/openvpn/IPredator.se.conf
	$(INSTALL_DATA) files/IPredator.se.login $(1)/etc/openvpn/IPredator.se.login
	$(INSTALL_DATA) files/IPredator.se.ta.key $(1)/etc/openvpn/IPredator.se.ta.key
	$(INSTALL_DATA) files/up.sh $(1)/etc/openvpn/up.sh
	$(INSTALL_DATA) files/down.sh $(1)/etc/openvpn/down.sh
	chmod 755 $(1)/etc/openvpn/up.sh
	chmod 755 $(1)/etc/openvpn/down.sh
endef

$(eval $(call BuildPackage,OVPNCertsIPredator))
