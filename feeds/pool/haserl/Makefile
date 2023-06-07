include $(TOPDIR)/rules.mk

PKG_NAME:=haserl
PKG_VERSION:=0.9.33
PKG_RELEASE:=1


PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=http://downloads.sourceforge.net/project/haserl/haserl-devel
PKG_MD5SUM:=a9decddb508944d56f71dd2f821e2ec5

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/haserl
  SECTION:=base
  CATEGORY:=ddmesh
  DEFAULT:=n
  DEPENDS:=
  TITLE:=Haserl CGI Processor
  URL:=http://sourceforge.net/projects/haserl/
  SUBMENU:=Packages
endef

define Package/haserl/description
 A tiny (<30K) cgi wrapper that uses a UNIX shell or a Lua VM to provide PHP-like scripting for dynamic web content. It transparently parses form data, including mime-formatted file uploads.
endef

define Build/Configure
	(cd $(PKG_BUILD_DIR); $(TARGET_CONFIGURE_OPTS); ./configure --prefix '/usr/bin');
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) CC="$(TARGET_CC)"
endef

define Package/haserl/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/haserl $(1)/usr/bin/
endef

$(eval $(call BuildPackage,haserl))
