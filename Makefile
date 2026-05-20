#
# Copyright (C) 2024 OpenWrt Client Manager
#
# This is free software, licensed under the Apache License, Version 2.0.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-clientmanager
PKG_VERSION:=1.1.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Your Name <your.email@example.com>
PKG_LICENSE:=Apache-2.0

LUCI_TITLE:=LuCI Client Manager - Network Client Management
LUCI_DEPENDS:=+luci-base +luci-compat +iptables +ip6tables +kmod-nft-netdev
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/clientmanager
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	if [ -f /etc/uci-defaults/luci-clientmanager ]; then
		( . /etc/uci-defaults/luci-clientmanager ) && rm -f /etc/uci-defaults/luci-clientmanager
	fi
	/etc/init.d/clientmanager enable 2>/dev/null
fi
exit 0
endef

define Package/$(PKG_NAME)/postrm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/etc/init.d/clientmanager disable 2>/dev/null
	/etc/init.d/clientmanager stop 2>/dev/null
	iptables -F CLIENTMGR_ACCT 2>/dev/null
fi
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
