

# Compilation directives
CFLAGS= -O2 -Wall -fPIC -W -Waggregate-return -Wcast-align -Wmissing-prototypes -Wnested-externs -Wshadow -Wwrite-strings -Wpointer-arith -pedantic

SRCS= rings.c
OBJS= rings.o

all: rings.so

rings.so: $(OBJS)
	export MACOSX_DEPLOYMENT_TARGET="10.3"; $(CC) $(CFLAGS) -shared -o rings.so $(OBJS)

clean:
	rm -f rings.so $(OBJS)
