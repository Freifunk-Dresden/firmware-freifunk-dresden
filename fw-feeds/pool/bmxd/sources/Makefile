



SOURCE_MD5=	$(shell md5sum *.[ch] Makefile | md5sum | cut -d' ' -f1)
REVISION_VERSION ="\" [md5:$(SOURCE_MD5)]\""

# if bmxd is compiled by openwrt, I have to use their CFLAGS for the targets
# especially floating point ABI stuff
CFLAGS := $(TARGET_CFLAGS)

# Recommended defines and approximate binary sizes with gcc-x86
# -static
# -pedantic -Wall -W -Wno-unused-parameter -O1 -g3 -std=gnu99
# -pg  # "-pg" with openWrt toolchain results in "gcrt1.o: No such file" ?!
#
#
# -DDEBUG_MALLOC  						+ ~0k
# -DMEMORY_USAGE 						+ ~1k
# -DPROFILE_DATA	(some realtime profiling)		+ ~3k
#
# optional defines (you may disable these features if you dont need it):
# -DNODEBUGALL							- ~13k
# -DLESS_OPTIONS                                                - ~7K
#
#
# experimental or advanced defines (please dont touch):
# -DNOPARANOIA		(makes bug-hunting impossible)		- ~2k
#
#CFLAGS += -DDEBUG_MALLOC -DMEMORY_USAGE
#CFLAGS += -DNODEBUGALL

# network id is a addtional feature that inserts and checks a network id (number)
# to ignore packets when this ID does not match
# default: feature is active
#CFLAGS += -DDISABLE_NETWORK_ID_CHECK

CFLAGS += -DREVISION_VERSION=$(REVISION_VERSION)

CFLAGS += -pedantic -Wall -W -Wno-unused-parameter -Wmaybe-uninitialized -std=gnu99 -I./
# for release
CFLAGS += -Os -g0

# for debugging (coredumps) / valgrind
#CFLAGS += -Og -g3 -ggdb

#LDFLAGS =
# -static
# -pg

SRC_C= objlist.c batman.c originator.c schedule.c plugin.c allocate.c avl.c profile.c control.c metrics.c posix.c tunnel.c route.c
SRC_H= objlist.h batman.h originator.h schedule.h plugin.h allocate.h avl.h profile.h control.h metrics.h tunnel.h os.h
OBJS=  $(SRC_C:.c=.o)

BINARY_NAME=bmxd

all:
	$(MAKE) $(BINARY_NAME)

$(BINARY_NAME):	$(OBJS) Makefile
	$(CC)  $(OBJS) -o $(BINARY_NAME)  $(LDFLAGS)

%.o:	%.c %.h Makefile $(SRC_H)
	$(CC) $(CFLAGS) -c $< -o $@

%.o:	%.c Makefile $(SRC_H)
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(BINARY_NAME) *.o
