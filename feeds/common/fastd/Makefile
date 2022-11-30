#
# Copyright (C) 2012-2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=fastd
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/NeoRaider/fastd.git
PKG_REV:=0f47d83eac2047d33efdab6eeaa9f81f17e3ebd1
PKG_SOURCE_VERSION:=$(PKG_REV)
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_REV)
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.gz
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)
PKG_VERSION:=$(PKG_REV)


PKG_LICENSE:=BSD-2-Clause
PKG_LICENSE_FILES:=COPYRIGHT

PKG_CONFIG_DEPENDS:=\
  CONFIG_FASTD_ENABLE_METHOD_CIPHER_TEST \
  CONFIG_FASTD_ENABLE_METHOD_COMPOSED_GMAC \
  CONFIG_FASTD_ENABLE_METHOD_COMPOSED_UMAC \
  CONFIG_FASTD_ENABLE_METHOD_GENERIC_GMAC \
  CONFIG_FASTD_ENABLE_METHOD_GENERIC_POLY1305 \
  CONFIG_FASTD_ENABLE_METHOD_GENERIC_UMAC \
  CONFIG_FASTD_ENABLE_METHOD_NULL \
  CONFIG_FASTD_ENABLE_CIPHER_NULL \
  CONFIG_FASTD_ENABLE_CIPHER_SALSA20 \
  CONFIG_FASTD_ENABLE_CIPHER_SALSA2012 \
  CONFIG_FASTD_ENABLE_MAC_GHASH \
  CONFIG_FASTD_ENABLE_MAC_UHASH \
  CONFIG_FASTD_WITH_CAPABILITIES \
  CONFIG_FASTD_WITH_CMDLINE_USER \
  CONFIG_FASTD_WITH_CMDLINE_LOGGING \
  CONFIG_FASTD_WITH_CMDLINE_OPERATION \
  CONFIG_FASTD_WITH_CMDLINE_COMMANDS \
  CONFIG_FASTD_WITH_DYNAMIC_PEERS \
  CONFIG_FASTD_WITH_STATUS_SOCKET

# ddmesh: IMPORTANT: nacl can be replaced by libsodium. but this would increase size by 110kbyte
#            Also a more efficient chiper 20/12 is not supported by libsodium
PKG_BUILD_DEPENDS:= nacl libuecc libjson-c
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk


# openwrt 18 has no python3 but meson/ninja/fastd needs it. I can not install
# python3 into openwrt18 as this would conflict openwrt builds.
# Because staging_dir/host/bin/ onyl contains symlinks into ubuntu, I add a symlink
# if no python3 was found.
# see: https://openwrt.org/docs/guide-developer/package-policies
# I create my own prepare and call then default
define Build/Prepare
	test -x "$(STAGING_DIR_HOST)/bin/python3" || ln -s /usr/bin/python3 $(STAGING_DIR_HOST)/bin/python3
	$(call Build/Prepare/Default)
endef

# the different openwrt versions use different path to meson.mk
# openwrt 22 already has meson+ninja in buildroot
# openwrt 21 needs extra devel packages
# openwrt 18 does not have any meson nor ninja
#  -> I created a patch that adds both  to openwrt 18 tools

# openwrt22 + openwrt18 patched
ifneq ("$(wildcard $(INCLUDE_DIR)/meson.mk)","")
  include $(INCLUDE_DIR)/meson.mk
endif

# openwrt 21 (extra packet)
ifneq ("$(wildcard $(TOPDIR)/feeds/packages/devel/meson/meson.mk)","")
  include $(TOPDIR)/feeds/packages/devel/meson/meson.mk
endif

# ddmesh: add "+@FASTD_ENABLE_METHOD_NULL +@FASTD_ENABLE_CIPHER_NULL +@FASTD_ENABLE_CIPHER_SALSA2012"
# because we need it
define Package/fastd
  CATEGORY:=ddmesh
  #  no dependencies to +libuecc +nacl (they are linked, not installed)
  DEPENDS:=+kmod-tun +kmod-l2tp-eth +libpthread +libmnl +FASTD_WITH_STATUS_SOCKET:libjson-c +FASTD_WITH_CAPABILITIES:libcap \
           +@FASTD_ENABLE_METHOD_NULL +@FASTD_ENABLE_CIPHER_NULL +@FASTD_ENABLE_CIPHER_SALSA2012 +@FASTD_ENABLE_METHOD_GENERIC_UMAC
  TITLE:=Fast and Secure Tunneling Daemon
  URL:=https://github.com/NeoRaider/fastd/
  SUBMENU:=Packages
endef

define Package/fastd/config
  source "$(SOURCE)/Config.in"
endef

feature = $(if $(CONFIG_FASTD_$(1)),enabled,disabled)

MESON_ARGS += \
  -Dcapabilities=$(call feature,WITH_CAPABILITIES) \
  -Dcipher_aes128-ctr=disabled \
  -Dcipher_null=$(call feature,ENABLE_CIPHER_NULL) \
  -Dcipher_salsa20=$(call feature,ENABLE_CIPHER_SALSA20) \
  -Dcipher_salsa2012=$(call feature,ENABLE_CIPHER_SALSA2012) \
  -Dcmdline_commands=$(call feature,WITH_CMDLINE_COMMANDS) \
  -Dcmdline_logging=$(call feature,WITH_CMDLINE_LOGGING) \
  -Dcmdline_operation=$(call feature,WITH_CMDLINE_OPERATION) \
  -Dcmdline_user=$(call feature,WITH_CMDLINE_USER) \
  -Ddynamic_peers=$(call feature,WITH_DYNAMIC_PEERS) \
  -Dmac_ghash=$(call feature,ENABLE_MAC_GHASH) \
  -Dmac_uhash=$(call feature,ENABLE_MAC_UHASH) \
  -Dmethod_cipher-test=$(call feature,ENABLE_METHOD_CIPHER_TEST) \
  -Dmethod_composed-gmac=$(call feature,ENABLE_METHOD_COMPOSED_GMAC) \
  -Dmethod_composed-umac=$(call feature,ENABLE_METHOD_COMPOSED_UMAC) \
  -Dmethod_generic-gmac=$(call feature,ENABLE_METHOD_GENERIC_GMAC) \
  -Dmethod_generic-poly1305=$(call feature,ENABLE_METHOD_GENERIC_POLY1305) \
  -Dmethod_generic-umac=$(call feature,ENABLE_METHOD_GENERIC_UMAC) \
  -Dmethod_null=$(call feature,ENABLE_METHOD_NULL) \
  -Dstatus_socket=$(call feature,WITH_STATUS_SOCKET) \
  -Dsystemd=disabled \
  -Duse_nacl=true \
  -Db_lto=true \
  -Dprefix=/usr

define Package/fastd/description
 Fast and secure tunneling daemon, which is optimized on small code size and few dependencies
endef

# use tabs
define Package/fastd/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/fastd $(1)/usr/bin/
endef

$(eval $(call BuildPackage,fastd))
