/*
 * Copyright (c) 2012-2013  Axel Neumann
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of version 2 of the GNU General Public
 * License as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301, USA
 */

/*

BGP/Quagga plugin inspired by:
http://olsr.org/git/?p=olsrd.git;a=tree;f=lib/quagga;h=031772d0be26605f97bc08b10694c8429252921f;hb=04ab230c75111be01b86c419c54f48dc6f6daa2e
http://www.mail-archive.com/b.a.t.m.a.n@lists.open-mesh.org/msg00529.html
https://dev.openwrt.org/browser/packages/net/quagga/patches/120-quagga_manet.patch
https://github.com/zioproto/quagga-manet/commits/olsrpatch-0.99.21
http://www.nongnu.org/quagga/zhh.html
 */


#define ARG_REDIST        "redistribute"
#define HLP_REDIST        "arbitrary but unique name for redistributed network(s) depending on sub criterias"

#define ZEBRA_VERSION2 2


///////////////////////////////////////////////////////////////////////////////
// from quagga/config.h
#define ZEBRA_SERV_PATH "/var/run/quagga/zserv.api" // "/var/run/quagga/zserv.api"



///////////////////////////////////////////////////////////////////////////////
// from quagga/lib/route_types.h (BMX6 patched: quagga/lib/route_types.txt):

/* Zebra route types. */
#define ZEBRA_ROUTE_SYSTEM               0
#define ZEBRA_ROUTE_KERNEL               1
#define ZEBRA_ROUTE_CONNECT              2
#define ZEBRA_ROUTE_STATIC               3
#define ZEBRA_ROUTE_RIP                  4
#define ZEBRA_ROUTE_RIPNG                5
#define ZEBRA_ROUTE_OSPF                 6
#define ZEBRA_ROUTE_OSPF6                7
#define ZEBRA_ROUTE_ISIS                 8
#define ZEBRA_ROUTE_BGP                  9
#define ZEBRA_ROUTE_HSLS                 10
#define ZEBRA_ROUTE_OLSR                 11
#define ZEBRA_ROUTE_BATMAN               12
#define ZEBRA_ROUTE_BMX6                 13
#define ZEBRA_ROUTE_BABEL                14
#define ZEBRA_ROUTE_MAX                  15


/* BMX6 route's types: look at hna.h. */






///////////////////////////////////////////////////////////////////////////////
// from quagga/lib/zebra.h:


/* Marker value used in new Zserv, in the byte location corresponding
 * the command value in the old zserv header. To allow old and new
 * Zserv headers to be distinguished from each other.
 */
#define ZEBRA_HEADER_MARKER              255

/* default zebra TCP port for zclient */
#define ZEBRA_PORT			2600





/* Zebra message types. */
#define ZEBRA_INTERFACE_ADD                1
#define ZEBRA_INTERFACE_DELETE             2
#define ZEBRA_INTERFACE_ADDRESS_ADD        3
#define ZEBRA_INTERFACE_ADDRESS_DELETE     4
#define ZEBRA_INTERFACE_UP                 5
#define ZEBRA_INTERFACE_DOWN               6
#define ZEBRA_IPV4_ROUTE_ADD               7
#define ZEBRA_IPV4_ROUTE_DELETE            8
#define ZEBRA_IPV6_ROUTE_ADD               9
#define ZEBRA_IPV6_ROUTE_DELETE           10
#define ZEBRA_REDISTRIBUTE_ADD            11
#define ZEBRA_REDISTRIBUTE_DELETE         12
#define ZEBRA_REDISTRIBUTE_DEFAULT_ADD    13
#define ZEBRA_REDISTRIBUTE_DEFAULT_DELETE 14
#define ZEBRA_IPV4_NEXTHOP_LOOKUP         15
#define ZEBRA_IPV6_NEXTHOP_LOOKUP         16
#define ZEBRA_IPV4_IMPORT_LOOKUP          17
#define ZEBRA_IPV6_IMPORT_LOOKUP          18
#define ZEBRA_INTERFACE_RENAME            19
#define ZEBRA_ROUTER_ID_ADD               20
#define ZEBRA_ROUTER_ID_DELETE            21
#define ZEBRA_ROUTER_ID_UPDATE            22
#define ZEBRA_HELLO                       23
#define ZEBRA_MESSAGE_MAX                 24

/* Subsequent Address Family Identifier. */
#define SAFI_UNICAST              1
#define SAFI_MULTICAST            2
#define SAFI_RESERVED_3           3
#define SAFI_MPLS_VPN             4
#define SAFI_MAX                  5


/* Zebra's family types. */
#define ZEBRA_FAMILY_IPV4                1
#define ZEBRA_FAMILY_IPV6                2
#define ZEBRA_FAMILY_MAX                 3

/* Error codes of zebra. */
#define ZEBRA_ERR_NOERROR                0
#define ZEBRA_ERR_RTEXIST               -1
#define ZEBRA_ERR_RTUNREACH             -2
#define ZEBRA_ERR_EPERM                 -3
#define ZEBRA_ERR_RTNOEXIST             -4
#define ZEBRA_ERR_KERNEL                -5

/* Zebra message flags */
#define ZEBRA_FLAG_INTERNAL           0x01
#define ZEBRA_FLAG_SELFROUTE          0x02
#define ZEBRA_FLAG_BLACKHOLE          0x04
#define ZEBRA_FLAG_IBGP               0x08
#define ZEBRA_FLAG_SELECTED           0x10
#define ZEBRA_FLAG_CHANGED            0x20
#define ZEBRA_FLAG_STATIC             0x40
#define ZEBRA_FLAG_REJECT             0x80

/* Zebra nexthop flags. */
#define ZEBRA_NEXTHOP_IFINDEX            1
#define ZEBRA_NEXTHOP_IFNAME             2
#define ZEBRA_NEXTHOP_IPV4               3
#define ZEBRA_NEXTHOP_IPV4_IFINDEX       4
#define ZEBRA_NEXTHOP_IPV4_IFNAME        5
#define ZEBRA_NEXTHOP_IPV6               6
#define ZEBRA_NEXTHOP_IPV6_IFINDEX       7
#define ZEBRA_NEXTHOP_IPV6_IFNAME        8
#define ZEBRA_NEXTHOP_BLACKHOLE          9


///////////////////////////////////////////////////////////////////////////////
// from quagga/lib/zclient.h:
// see also: quagga/lib/zclient.c: zapi_ipv4_route()
//           quagga/zebra/zserv.c: zread_ipv4_add()
//           olsrd-0.6.3/lib/quagga/src/quagga.c: zerba_addroute()

/* Zebra API message flag. */
#define ZAPI_MESSAGE_NEXTHOP  0x01
#define ZAPI_MESSAGE_IFINDEX  0x02
#define ZAPI_MESSAGE_DISTANCE 0x04
#define ZAPI_MESSAGE_METRIC   0x08

/* Zserv protocol message header */
struct zapiV2_header {
        uint16_t length;
        uint8_t marker; // always set to 255 in new zserv.
        uint8_t version;
        uint16_t command;
} __attribute__((packed));





///////////////////////////////////////////////////////////////////////////////


#define ZSOCK_RECONNECT_TO 1000


struct zebra_cfg {
        char unix_path[MAX_PATH_SIZE];
        int32_t port;
        IPX_T ipX;
        int32_t socket;
        char *zread_buff;
        uint16_t zread_buff_len;
        uint16_t zread_len;
        uint32_t bmx6_redist_bits_new;
        uint32_t bmx6_redist_bits_old;

        //...
};

struct zsock_write_node {
	struct list_node list;
	char *zpacket;
        uint16_t send;
};

struct zdata {
	struct list_node list;
//	char *zpacket;
        struct zapiV2_header* hdr;
        uint16_t len;
        uint16_t cmd;
};


#define ARG_ZAPI_DIR "zebraPath"



