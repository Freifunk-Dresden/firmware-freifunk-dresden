#!/bin/ash


# returns firmware name for current device. each new device must be added.
# if device is not addes, empty string is returned which is used for firmware.cgi


model="$(cat /tmp/sysinfo/model 2>/dev/null)"
board_name="$(cat /tmp/sysinfo/board_name 2>/dev/null)"
machine_type="$(uname -m)"
filesystem="$(cat /proc/cmdline | sed 's#.*rootfstype=\([a-z0-9]\+\).*$#\1#')"

case "$model" in

	"TP-Link TL-MR3020 v1")		f="openwrt-ar71xx-generic-tl-mr3020-v1-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WR740N/ND v1")	f="openwrt-ar71xx-generic-tl-wr740n-v1-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR740N/ND v3")	f="openwrt-ar71xx-generic-tl-wr740n-v3-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR740N/ND v4")	f="openwrt-ar71xx-generic-tl-wr740n-v4-squashfs-sysupgrade.bin" ;;

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
	"TP-Link TL-WR841N/ND v10")	f="openwrt-ar71xx-generic-tl-wr841n-v10-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR841N/ND v11")	f="openwrt-ar71xx-generic-tl-wr841n-v11-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WR842N/ND v1")	f="openwrt-ar71xx-generic-tl-wr842n-v1-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR842N/ND v2")	f="openwrt-ar71xx-generic-tl-wr842n-v2-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WR843N/ND v1")	f="openwrt-ar71xx-generic-tl-wr843nd-v1-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR847N/ND v8")	f="openwrt-ar71xx-generic-tl-wr847n-v8-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WA860RE v1")	f="openwrt-ar71xx-generic-tl-wa860re-v1-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WR941N/ND v2")	f="openwrt-ar71xx-generic-tl-wr941nd-v2-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR941N/ND v3")	f="openwrt-ar71xx-generic-tl-wr941nd-v3-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR941N/ND v4")	f="openwrt-ar71xx-generic-tl-wr941nd-v4-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR941N/ND v5")	f="openwrt-ar71xx-generic-tl-wr941nd-v5-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR941N/ND v6")	f="openwrt-ar71xx-generic-tl-wr941nd-v6-squashfs-sysupgrade.bin" ;;

	"TP-Link TL-WDR3600 v1")	f="openwrt-ar71xx-generic-tl-wdr3600-v1-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WDR4300 v1")	f="openwrt-ar71xx-generic-tl-wdr4300-v1-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR1043N/ND v1")	f="openwrt-ar71xx-generic-tl-wr1043nd-v1-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR1043N/ND v2")	f="openwrt-ar71xx-generic-tl-wr1043nd-v2-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR1043N/ND v3")	f="openwrt-ar71xx-generic-tl-wr1043nd-v3-squashfs-sysupgrade.bin" ;;
	"TP-Link TL-WR2543N/ND v1")	f="openwrt-ar71xx-generic-tl-wr2543-v1-squashfs-sysupgrade.bin" ;;

	"TP-Link CPE210 v1.0")		f="openwrt-ar71xx-generic-cpe210-220-510-520-squashfs-sysupgrade.bin" ;;
	"TP-Link CPE220 v1.0")		f="openwrt-ar71xx-generic-cpe210-220-510-520-squashfs-sysupgrade.bin" ;;

	"TP-LINK Archer C7")		f="openwrt-ar71xx-generic-archer-c7-v1-squashfs-sysupgrade.bin" ;;
	"TP-LINK Archer C7 v2")		f="openwrt-ar71xx-generic-archer-c7-v2-squashfs-sysupgrade.bin" ;;

	"Ubiquiti Nanostation M")	f="openwrt-ar71xx-generic-ubnt-nano-m-squashfs-sysupgrade.bin" ;;
	"Ubiquiti Rocket M")		f="openwrt-ar71xx-generic-ubnt-rocket-m-squashfs-sysupgrade.bin" ;;
	"Ubiquiti UniFi")		f="openwrt-ar71xx-generic-ubnt-unifi-squashfs-sysupgrade.bin" ;;
	"Ubiquiti Bullet M")		f="openwrt-ar71xx-generic-ubnt-bullet-m-squashfs-sysupgrade.bin" ;;

	"Linksys WRT160NL")		f="openwrt-ar71xx-generic-wrt160nl-squashfs-sysupgrade.bin" ;;

	"JCG JHR-N805R")		f="openwrt-ramips-rt305x-jhr-n805r-squashfs-sysupgrade.bin" ;;
	"JCG JHR-N825R")		f="openwrt-ramips-rt305x-jhr-n825r-squashfs-sysupgrade.bin" ;;
	"JCG JHR-N926R")		f="openwrt-ramips-rt305x-jhr-n926r-squashfs-sysupgrade.bin" ;;

	*)
		case "$machine_type" in
			i686)	# sysupgrade does not check filesystem !!! When using wrong image, configuration gets lost
				case "$filesystem" in
					ext4)		f="openwrt-x86-generic-combined-ext4.img.gz" ;;
					squashfs)	f="openwrt-x86-generic-combined-squashfs.img" ;;
					*)		f="" ;;
				esac ;;

			*) 	f="" ;;
		esac

esac

echo "$f"

