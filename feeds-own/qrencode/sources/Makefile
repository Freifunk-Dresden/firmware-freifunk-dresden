#whiterussian makefile, the soures are copied to the whiterussian project (not symlinked)
#http://megaui.net/fukuchi/works/qrencode/index.en.html
#made by stephan (me)



#compiler flags for WRT
CFLAGS=		-Wall -O1 -DHAVE_CONFIG_H
INCLUDE=	-I$(STAGING_DIR)/usr/include
LDFLAGS=	-L$(STAGING_DIR)/usr/lib -lpng12 -lz

#compiler flags for i368
#CC =		gcc
#CFLAGS=		-Wall -O1 -DHAVE_CONFIG_H
#INCLUDE=	-I/usr/include/libpng12
#LDFLAGS=	-L/usr/lib/i386-linux-gnu -lpng12 -lz

STRIP=		strip
BINARY_NAME=	qrencode
SRC_C=		*.c

all:	$(BINARY_NAME)

$(BINARY_NAME):	$(SRC_C) Makefile
	$(CC) $(CFLAGS) $(INCLUDE) -o $@ $(SRC_C) $(LDFLAGS)
	$(STRIP) $(BINARY_NAME)

clean:
		rm -f $(BINARY_NAME) *.o
