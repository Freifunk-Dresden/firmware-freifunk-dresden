

# to compile for Yohua (mipsel) with target compiler set
# export CC=../../../../workdir/b4d7885/staging_dir/toolchain-mipsel_24kc_gcc-8.4.0_musl/bin/mipsel-openwrt-linux-gcc
# export STAGING_DIR=../../../../workdir/b4d7885/staging_dir
# tp-link 841
# export CC=/home/stephan/freifunk/firmware/workdir/5625f5b.lowmem/staging_dir/toolchain-mips_24kc_gcc-7.3.0_musl/bin/mips-openwrt-linux-gcc
# export STAGING_DIR=../../../../workdir/5625f5b.lowmem/staging_dir

REVISION =	"$(shell git show --abbrev-commit | sed -n '1{s/.* //p}')"
DATE=		"$(shell git show --abbrev-commit | sed -n '3{s/Date:[ ]\+\(.*\) +.*/\1/p}' )"
SOURCE_MD5=	$(shell md5sum *.[ch] linux/*.[cp] posix/*.[cp] Makefile | md5sum | cut -d' ' -f1)
REVISION_VERSION ="\" [md5:$(SOURCE_MD5)]\""

# Recommended defines and approximate binary sizes with gcc-x86
# -static
# -pedantic -Wall -W -Wno-unused-parameter -O1 -g3 -std=gnu99
# -pg  # "-pg" with openWrt toolchain results in "gcrt1.o: No such file" ?!
#

# -DDEBUG_MALLOC  						+ ~0k
# -DMEMORY_USAGE 						+ ~1k
# -DPROFILE_DATA	(some realtime profiling)		+ ~3k

# optional defines (you may disable these features if you dont need it):
# -DNODEBUGALL							- ~13k
# -DLESS_OPTIONS                                                - ~7K
#
# -DNOTUNNEL  		(only affects this node)		- ~23k

# experimental or advanced defines (please dont touch):
# -DNOPARANOIA		(makes bug-hunting impossible)		- ~2k

#CFLAGS += -DDISABLE_NETWORK_ID_CHECK

CFLAGS += -DREVISION_VERSION=$(REVISION_VERSION)

CFLAGS += -pedantic -Wall -W -Wno-unused-parameter -Wmaybe-uninitialized -std=gnu99 -I./
# for release
CFLAGS += -Os -g0

# for debugging (coredumps) / valgrind
#CFLAGS += -Og -g3 -ggdb


#CFLAGS += -DDEBUG_MALLOC -DMEMORY_USAGE
#CFLAGS += -DNODEBUGALL

#LDFLAGS =
# -static
# -pg

SRC_C= objlist.c batman.c originator.c schedule.c plugin.c allocate.c avl.c profile.c control.c metrics.c posix/posix.c posix/tunnel.c linux/route.c
SRC_H= objlist.h batman.h originator.h schedule.h plugin.h allocate.h avl.h profile.h control.h metrics.h os.h
OBJS=  $(SRC_C:.c=.o)

BINARY_NAME=	bmxd

all:
	$(MAKE) $(BINARY_NAME)

$(BINARY_NAME):	$(OBJS) Makefile
	$(CC)  $(OBJS) -o $@  $(LDFLAGS)

%.o:	%.c %.h Makefile $(SRC_H)
	$(CC) $(CFLAGS) -c $< -o $@

%.o:	%.c Makefile $(SRC_H)
	$(CC) $(CFLAGS) -c $< -o $@


strip:	all
	strip $(BINARY_NAME)

clean:
	rm -f $(BINARY_NAME) *.o posix/*.o linux/*.o
