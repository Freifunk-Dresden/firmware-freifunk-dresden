#
# Copyright (C) 2008-2011 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=batmand
PKG_REV:=036aea1fe69d275aecae64cc643e8e34fac550a0
PKG_VERSION:=r$(PKG_REV)
PKG_RELEASE:=2
PKG_EXTRA_CFLAGS=-DDEBUG_MALLOC -DMEMORY_USAGE -DPROFILE_DATA -DREVISION_VERSION=\"\ rv$(PKG_REV)\"

PKG_SOURCE_PROTO:=git
PKG_SOURCE_VERSION:=$(PKG_REV)
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE_URL:=git://git.open-mesh.org/batmand.git
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.gz
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

include $(INCLUDE_DIR)/package.mk

define Package/batmand/Default
  URL:=http://www.open-mesh.org/
  MAINTAINER:=Marek Lindner <lindner_marek@yahoo.de>
endef

define Package/batmand
$(call Package/batmand/Default)
  SECTION:=net
  CATEGORY:=ddmesh
  SUBMENU:=Routing
  DEPENDS:=+libpthread +kmod-tun
  TITLE:=B.A.T.M.A.N. layer 3 routing daemon
endef

define Package/batmand/description
B.A.T.M.A.N. layer 3 routing daemon
endef

define Package/vis
$(call Package/batmand/Default)
  SECTION:=net
  CATEGORY:=ddmesh
  SUBMENU:=Routing
  DEPENDS:=+libpthread
  TITLE:=visualization server for B.A.T.M.A.N. layer 3
endef
        
define Package/vis/description
visualization server for B.A.T.M.A.N. layer 3
endef

MAKE_BATMAND_ARGS += \
	EXTRA_CFLAGS='$(TARGET_CFLAGS) $(PKG_EXTRA_CFLAGS)' \
	CCFLAGS="$(TARGET_CFLAGS)" \
	OFLAGS="$(TARGET_CFLAGS)" \
	REVISION="$(PKG_REV)" \
	CC="$(TARGET_CC)" \
	NODEBUG=1 \
	UNAME="Linux" \
	INSTALL_PREFIX="$(PKG_INSTALL_DIR)" \
	STRIP="/bin/true" \
	batmand install
	
MAKE_VIS_ARGS += \
	EXTRA_CFLAGS='$(TARGET_CFLAGS) $(PKG_EXTRA_CFLAGS)' \
	CCFLAGS="$(TARGET_CFLAGS)" \
	OFLAGS="$(TARGET_CFLAGS)" \
	REVISION="$(PKG_REV)" \
	CC="$(TARGET_CC)" \
	NODEBUG=1 \
	UNAME="Linux" \
	INSTALL_PREFIX="$(PKG_INSTALL_DIR)" \
	STRIP="/bin/true" \
	vis install

define Build/Configure
endef

ifneq ($(DEVELOPER)$(CONFIG_PACKAGE_batmand),)
	BUILD_BATMAND := $(MAKE) -C $(PKG_BUILD_DIR) $(MAKE_BATMAND_ARGS)
endif

ifneq ($(DEVELOPER)$(CONFIG_PACKAGE_vis),)
	BUILD_VIS := $(MAKE) -C $(PKG_BUILD_DIR)/vis $(MAKE_VIS_ARGS)
endif
	
define Build/Compile
	$(BUILD_BATMAND)
	$(BUILD_VIS)
endef

define Package/batmand/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/config $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/sbin/batmand $(1)/usr/sbin/
	$(INSTALL_BIN) ./files/etc/init.d/batmand $(1)/etc/init.d
	$(INSTALL_DATA) ./files/etc/config/batmand $(1)/etc/config
endef

define Package/batmand/conffiles
/etc/config/batmand
endef

define Package/vis/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/config $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/sbin/vis $(1)/usr/sbin/
	$(INSTALL_BIN) ./files/etc/init.d/vis $(1)/etc/init.d
	$(INSTALL_DATA) ./files/etc/config/vis $(1)/etc/config
endef

define Package/vis/conffiles
/etc/config/vis
endef

$(eval $(call BuildPackage,batmand))
$(eval $(call BuildPackage,vis))
