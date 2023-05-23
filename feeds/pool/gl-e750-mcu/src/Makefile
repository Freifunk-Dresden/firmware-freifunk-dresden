#LDFLAGS += libglmodem-util.a libglsdk.a -L/usr/lib/ -ljson-c -luci -lubox -lubus -ldl -lpthread  -L/usr/lib/lua/ -liwinfo -luuid  -lblobmsg_json libglmodem-util.a -lcurl -I include
LDFLAGS += libglmodem-util.a libglsdk.a -L/usr/lib/ -ljson-c -luci -lubox -lubus -ldl -lpthread  -L/usr/lib/lua/ -liwinfo -luuid  -lblobmsg_json libglmodem-util.a -I include
CFLAGS += -I include

BINARY_NAME=e750-mcu
all : ${BINARY_NAME} libraries

${BINARY_NAME} :
	$(CC) $(CFLAGS)  app.c curl.c uart_posix.c -o ${BINARY_NAME} $(LDFLAGS)
	$(STRIP) ${BINARY_NAME}

libraries:
	$(CC) $(CFLAGS) -Wall api.c -shared -fPIC -o libglmcu.so $(LDFLAGS)

clean:
	rm -fr $(PROC) ${BINARY_NAME}
