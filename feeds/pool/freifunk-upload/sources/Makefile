#whiterussian makefile, the soures are copied to the whiterussian project (not symlinked)
#http://megaui.net/fukuchi/works/qrencode/index.en.html
#made by stephan (me)



STRIP=		strip
BINARY_NAME= 	freifunk-upload	
SRC_C=		*.c

all:	$(BINARY_NAME)

$(BINARY_NAME):	$(SRC_C) Makefile
	$(CC) $(CFLAGS) $(INCLUDE) -o $@ $(SRC_C)
	$(STRIP) $(BINARY_NAME)

clean:
		rm -f $(BINARY_NAME) *.o
