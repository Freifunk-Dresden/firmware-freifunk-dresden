#
# Copyright (C) 2012-2014 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=libuecc
#PKG_VERSION:=4
#PKG_RELEASE:=1

#PKG_MAINTAINER:=Matthias Schiffer <mschiffer@universe-factory.net>
#PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.xz
#PKG_SOURCE_URL:=https://projects.universe-factory.net/attachments/download/71
#PKG_MD5SUM:=7f44df5dc69cb8686947562e2a11eea9

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://git.universe-factory.net/libuecc
PKG_REV:=7c9a6f6af088d0764e792cf849e553d7f55ff99e
#sha256sum (PKG_HASH is used to check if local downloaded files matches. if so, it will be use
#           instead of downloaded each time. github has a download rate constrictions)
PKG_HASH:=b069ffebb499afe3353d42ba1baf362d99ad11916b2e14fbf1b43cf9dfe7a83f
PKG_SOURCE_VERSION:=$(PKG_REV)
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_REV)
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.gz
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)
PKG_VERSION:=7

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/libuecc
  CATEGORY:=ddmesh
  TITLE:=Very small Elliptic Curve Cryptography library
  URL:=http://git.universe-factory.net/libuecc/
  SUBMENU:=Packages
endef

TARGET_CFLAGS += -ffunction-sections -fdata-sections

CMAKE_OPTIONS += \
	-DCMAKE_BUILD_TYPE:String="MINSIZEREL"


define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_INSTALL_DIR)/usr/include/libuecc-$(PKG_VERSION) $(1)/usr/include/
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libuecc.a $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/libuecc.pc $(1)/usr/lib/pkgconfig/
endef

$(eval $(call BuildPackage,libuecc))
