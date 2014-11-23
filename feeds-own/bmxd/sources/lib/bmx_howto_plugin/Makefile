
CFLAGS +=	-fpic -pedantic -Wall -W -Wno-unused-parameter -Os -g3 -std=gnu99 -I../../
LDFLAGS +=	-shared
#-Wl,-soname,bmxd_config 

PLUGIN_NAME =   bmx_howto_plugin
PLUGIN_VER =    1

SRC_C = howto_plugin.c
SRC_H = howto_plugin.h
OBJS= $(SRC_C:.c=.o)

PLUGIN_FULLNAME = $(PLUGIN_NAME).so.$(PLUGIN_VER)
PLUGIN_SHORTNAME = $(PLUGIN_NAME).so

LIBDIR = /usr/lib

all:	$(PLUGIN_FULLNAME) Makefile


$(PLUGIN_FULLNAME):	$(OBJS) Makefile
	$(CC) $(LDFLAGS) $(EXTRA_LDFLAGS) $(OBJS) -o $(PLUGIN_FULLNAME)

%.o:	%.c %.h Makefile
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) -c $< -o $@


clean:
	rm -f *.o *.so.$(PLUGIN_VER)
	

install:	all
		mkdir -p $(LIBDIR)
		install -D -m 755 $(PLUGIN_FULLNAME) $(LIBDIR)/$(PLUGIN_FULLNAME); /sbin/ldconfig -n $(LIBDIR); ln -f -s $(LIBDIR)/$(PLUGIN_FULLNAME) $(LIBDIR)/$(PLUGIN_SHORTNAME)


strip:		all
		strip $(PLUGIN_FULLNAME)
