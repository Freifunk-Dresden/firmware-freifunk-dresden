#
# Copyright (C) 2006 BATMAN contributors
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of version 2 of the GNU General Public
# License as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA
#

REVISION =	"$(shell git show --abbrev-commit | sed -n '1{s/.* //p}')"
DATE=		"$(shell git show --abbrev-commit | sed -n '3{s/Date:[ ]\+\(.*\) +.*/\1/p}' )"
SOURCE_MD5=	$(shell md5sum *.[ch] linux/*.[cp] posix/*.[cp] Makefile | md5sum | cut -d' ' -f1)
REVISION_VERSION ="\" [md5:$(SOURCE_MD5)]\""


CFLAGS += -pedantic -Wall -W -Wno-unused-parameter -Wmaybe-uninitialized -std=gnu99 -I./
# for release
CFLAGS += -Os -g0
# for debugging (coredumps)
#CFLAGS += -Og -g3 -ggdb

CFLAGS += -DREVISION_VERSION=$(REVISION_VERSION)
#CFLAGS += -DDEBUG_MALLOC -DMEMORY_USAGE

#EXTRA_CFLAGS += -DTESTDEBUG
#EXTRA_CFLAGS += -DNODEBUGALL

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
# -DEXTDEBUG		(this eats your cpu)			+ ~0k
# -DTESTDEBUG		(testing syntax of __VA_ARGS__ dbg...() macros)

# to create coredumps on pc /var/crash) disable SIGSEGV handling
#EXTRA_CFLAGS += -DSTEPHAN_ENABLE_SEGMENTATION_FAULT_HANDLING

#LDFLAGS +=	-Wl,-export-dynamic -ldl -g3
LDFLAGS +=	-g3
# -static
# -pg

SRC_C= batman.c originator.c schedule.c plugin.c list-batman.c allocate.c avl.c profile.c control.c metrics.c posix/posix.c posix/tunnel.c linux/route.c
SRC_H= batman.h originator.h schedule.h plugin.h list-batman.h allocate.h avl.h profile.h control.h metrics.h os.h
OBJS=  $(SRC_C:.c=.o)

SBINDIR =       $(INSTALL_PREFIX)/usr/sbin
BINARY_NAME=	bmxd

all:
	$(MAKE) $(BINARY_NAME)
	# further make targets: help, libs, build_all, strip[_libs|_all], install[_libs|_all], clean[_libs|_all]

libs:	all
	$(MAKE) -C lib all



$(BINARY_NAME):	$(OBJS) Makefile
	$(CC)  $(OBJS) -o $@  $(LDFLAGS) $(EXTRA_LDFLAGS)

%.o:	%.c %.h Makefile $(SRC_H)
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) -c $< -o $@

%.o:	%.c Makefile $(SRC_H)
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) -c $< -o $@


strip:	all
	strip $(BINARY_NAME)

strip_libs: all libs
	$(MAKE) -C lib strip




install:	all
	mkdir -p $(SBINDIR)
	install -m 0755 $(BINARY_NAME) $(SBINDIR)

install_libs:
	$(MAKE) -C lib install



clean:
	rm -f $(BINARY_NAME) *.o posix/*.o linux/*.o

clean_libs:
	$(MAKE) -C lib clean


clean_all: clean clean_libs
build_all: all libs
strip_all: strip strip_libs
install_all: install install_libs


help:
	# further make targets:
	# help					show this help
	# all					compile  bmxd core only
	# libs			 		compile  bmx plugins
	# build_all				compile  bmxd and plugins
	# strip / strip_libs / strip_all	strip    bmxd / plugins / all
	# install / install_libs / install_all	install  bmxd / plugins / all
	# clean / clean_libs / clean_all	clean    bmxd / libs / all
