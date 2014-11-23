#!/bin/ash

test ! -f "$1" && echo "missing filename" &&  exit 0 

export firmware_default_partition_size=0x3d0000
export jffs2_min_size=0x50000

export firmware_size=$(hexdump -C $1 | sed -n '/^[0-9a-fA-F]\+[ 	]\+de ad c0 de/s#^[ 	]*\([0-9a-zA-Z]\+\).*#0x\1#p')
export firmware_partition_size=$(cat /proc/mtd | sed -n '/"firmware"/s#mtd[^ 	]\+[ 	]\+\([0-9a-fA-F]\+\).*#0x\1#p')
export jffs2_partition_size=$(cat /proc/mtd | sed -n '/"rootfs_data"/s#mtd[^ 	]\+[ 	]\+\([0-9a-fA-F]\+\).*#0x\1#p')

test -z "$firmware_partition_size" && printf "no firmware partition size detected. using default size $firmware_default_partition_size\n" && firmware_partition_size=$firmware_default_partition_size
export resulting_jffs2_size=$(($firmware_partition_size-$firmware_size))

printf "Firmware partition size (fix): 0x%x (%d)\n" $firmware_partition_size $firmware_partition_size
printf "Current JFFS2 partition size (variable): 0x%x (%d)\n" $jffs2_partition_size $jffs2_partition_size
printf "Minimal JFFS2 size: 0x%x (%d)\n" $jffs2_min_size $jffs2_min_size
printf "Firmware size: 0x%x (%d)\n" $firmware_size $firmware_size
printf "Final JFFS2 partition size: 0x%x (%d)\n" $resulting_jffs2_size $resulting_jffs2_size

_result=$(($resulting_jffs2_size-$jffs2_min_size))
test $_result -lt 0 && printf "Firmware too big!!!\n"


