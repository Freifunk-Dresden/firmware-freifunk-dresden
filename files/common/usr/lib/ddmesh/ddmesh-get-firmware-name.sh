#!/bin/ash


# returns firmware name for current device. each new device must be added.
# if device is not addes, empty string is returned which is used for firmware.cgi


model="$(cat /tmp/sysinfo/model)"
board_name="$(cat /tmp/sysinfo/board_name)"

case "$model" in

	"TP-Link TL-MR3020 v1")		f="openwrt-ar71xx-generic-tl-mr3020-v1-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WR740N/ND v1")	f="openwrt-ar71xx-generic-tl-wr740nd-v1-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR740N/ND v3")	f="openwrt-ar71xx-generic-tl-wr740nd-v3-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR740N/ND v4")	f="openwrt-ar71xx-generic-tl-wr740nd-v4-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WR741N/ND v1")	f="openwrt-ar71xx-generic-tl-wr741nd-v1-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR741N/ND v2")	f="openwrt-ar71xx-generic-tl-wr741nd-v2-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR741N/ND v4")	f="openwrt-ar71xx-generic-tl-wr741nd-v4-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WR743N/ND v1")	f="openwrt-ar71xx-generic-tl-wr743nd-v1-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR743N/ND v2")	f="openwrt-ar71xx-generic-tl-wr743nd-v2-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WR841N/ND v3")	f="openwrt-ar71xx-generic-tl-wr841nd-v3-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR841N/ND v5")	f="openwrt-ar71xx-generic-tl-wr841nd-v5-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR841N/ND v7")	f="openwrt-ar71xx-generic-tl-wr841nd-v7-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR841N/ND v8")	f="openwrt-ar71xx-generic-tl-wr841n-v8-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR841N/ND v9")	f="openwrt-ar71xx-generic-tl-wr841n-v9-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WR842N/ND v1")	f="openwrt-ar71xx-generic-tl-wr842n-v1-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WR941N/ND v2")	f="openwrt-ar71xx-generic-tl-wr941n-v2-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR941N/ND v3")	f="openwrt-ar71xx-generic-tl-wr941n-v3-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR941N/ND v4")	f="openwrt-ar71xx-generic-tl-wr941n-v4-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WDR3600 v1")	f="openwrt-ar71xx-generic-tl-wdr3600-v1-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WDR4300 v1")	f="openwrt-ar71xx-generic-tl-wdr4300-v1-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR1043N/ND v1")	f="openwrt-ar71xx-generic-tl-wr1043nd-v1-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR1043N/ND v2")	f="openwrt-ar71xx-generic-tl-wr1043nd-v2-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR2543N/ND v1")	f="openwrt-ar71xx-generic-tl-wr2543-v1-squashfs-sysupgrade.bin" ;;


	"TP-LINK Archer C7")		f="openwrt-ar71xx-generic-archer-c7-v1-squashfs-sysupgrade.bin" ;;
	"TP-LINK Archer C7 v2")		f="openwrt-ar71xx-generic-archer-c7-v2-squashfs-sysupgrade.bin" ;;

	"Ubiquiti Nanostation M")	f="openwrt-ar71xx-generic-ubnt-nano-m-squashfs-sysupgrade.bin" ;;
	"Ubiquiti Rocket M")		f="openwrt-ar71xx-generic-ubnt-rocket-m-squashfs-sysupgrade.bin" ;;
	
	*) f="" ;;
esac

echo "$f"
