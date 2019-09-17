/*
 * Copyright (C) 2006 BATMAN contributors:
 * Marek Lindner, Axel Neumann
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
 *
 */

#ifndef	NOTUNNEL

#include <errno.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <linux/ip.h>
#include <linux/udp.h>
#include <arpa/inet.h>
#include <linux/if_tun.h> /* TUNSETPERSIST, ... */
#include <linux/if.h>     /* ifr_if, ifr_tun */
#include <fcntl.h>        /* open(), O_RDWR */
#include <asm/types.h>
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>



#include "batman.h"
#include "os.h"
#include "originator.h"
#include "plugin.h"
#include "schedule.h"

//nach dem umschalten auf ein neues gateway können noch für eine bestehende verbindung
//packete eintreffen.
#define STEPHAN_ALLOW_TUNNEL_PAKETS

#ifdef STEPHAN_ENABLE_TWT
#define ARG_UNRESP_GW_CHK "unresp_gateway_check"
static int32_t unresp_gw_chk;
#endif //#ifdef STEPHAN_ENABLE_TWT

#define ARG_ONE_WAY_TUNNEL "one_way_tunnel"
static int32_t one_way_tunnel;

#ifdef STEPHAN_ENABLE_TWT
#define ARG_TWO_WAY_TUNNEL "two_way_tunnel"
static int32_t two_way_tunnel;
#endif //#ifdef STEPHAN_ENABLE_TWT

#define ARG_GW_HYSTERESIS "gateway_hysteresis"
#define MIN_GW_HYSTERE    1
#define MAX_GW_HYSTERE    PROBE_RANGE/PROBE_TO100
#define DEF_GW_HYSTERE    2
static int32_t gw_hysteresis;


#define DEF_GWTUN_NETW_PREFIX  "169.254.0.0" /* 0x0000FEA9 */
static uint32_t gw_tunnel_prefix;

#ifdef STEPHAN_ENABLE_TWT
    #define MIN_GWTUN_NETW_MASK 20
#else
    #define MIN_GWTUN_NETW_MASK 16  //damit ich per options 10.200er network angeben kann und
                                    //wenn bmxd als gateway arbeitet die ip auch gesetzt wird
#endif //#ifdef STEPHAN_ENABLE_TWT

#define MAX_GWTUN_NETW_MASK 30
//change default from 22 to 20 to have 2^ (32-20) clients: 1023 -> 4095 clients
#define DEF_GWTUN_NETW_MASK 20
static uint32_t gw_tunnel_netmask;

#ifdef STEPHAN_ENABLE_TWT
	#define MIN_TUN_LTIME 60 /*seconds*/
	#define MAX_TUN_LTIME 60000
	#define DEF_TUN_LTIME 600
	#define ARG_TUN_LTIME "tunnel_lease_time"
	static int32_t Tun_leasetime = DEF_TUN_LTIME;
#endif //#ifdef STEPHAN_ENABLE_TWT


/* "-r" is the command line switch for the routing class,
 * 0 set no default route
 * 1 use fast internet connection
 * 2 use stable internet connection
 * 3 use use best statistic (olsr style)
 * this option is used to set the routing behaviour
 */

#define MIN_RT_CLASS 0
#define MAX_RT_CLASS 3
static int32_t routing_class = 0;

static uint32_t pref_gateway = 0;




#define BATMAN_TUN_PREFIX "bat"
#define MAX_BATMAN_TUN_INDEX 20

#define TUNNEL_DATA 0x01
#define TUNNEL_IP_REQUEST 0x02
#define TUNNEL_IP_INVALID 0x03
#define TUNNEL_IP_REPLY 0x06

#define GW_STATE_UNKNOWN  0x01
#define GW_STATE_VERIFIED 0x02

#define ONE_MINUTE                60000

#define GW_STATE_UNKNOWN_TIMEOUT  (1  * ONE_MINUTE)
#define GW_STATE_VERIFIED_TIMEOUT (5  * ONE_MINUTE)

#define IP_LEASE_TIMEOUT          (1 * ONE_MINUTE)

#define MAX_TUNNEL_IP_REQUESTS 60 //12
#define TUNNEL_IP_REQUEST_TIMEOUT 1000 // msec


#define DEF_TUN_PERSIST 1


static int32_t Tun_persist = DEF_TUN_PERSIST;

static int32_t my_gw_port = 0;
static uint32_t my_gw_addr = 0;

static int32_t tun_orig_registry = FAILURE;

static SIMPEL_LIST( gw_list );






#ifdef STEPHAN_ENABLE_TWT
struct tun_request_type {
	uint32_t lease_ip;
	uint16_t lease_lt;
} __attribute__((packed));
#endif //#ifdef STEPHAN_ENABLE_TWT

struct tun_data_type {
	unsigned char ip_packet[MAX_MTU];
} __attribute__((packed));

struct tun_packet_start {
#if __BYTE_ORDER == __LITTLE_ENDIAN
	unsigned int type:4;
	unsigned int version:4;  // should be the first field in the packet in network byte order
#elif __BYTE_ORDER == __BIG_ENDIAN
	unsigned int version:4;
	unsigned int type:4;
#else
# error "Please fix <bits/endian.h>"
#endif
} __attribute__((packed));

struct tun_packet
{
	uint8_t  reserved1;
	uint8_t  reserved2;
	uint8_t  reserved3;

	struct tun_packet_start start;
#define TP_TYPE  start.type
#define TP_VERS  start.version

	union
	{
#ifdef STEPHAN_ENABLE_TWT
		struct tun_request_type trt;
#endif //#ifdef STEPHAN_ENABLE_TWT
		struct tun_data_type tdt;
		struct iphdr iphdr;
	}tt;
#ifdef STEPHAN_ENABLE_TWT
	#define LEASE_IP  tt.trt.lease_ip
	#define LEASE_LT  tt.trt.lease_lt
#endif //#ifdef STEPHAN_ENABLE_TWT
#define IP_PACKET tt.tdt.ip_packet
#define IP_HDR    tt.iphdr
} __attribute__((packed));


#ifdef STEPHAN_ENABLE_TWT
	#define TX_RP_SIZE (sizeof(struct tun_packet_start) + sizeof(struct tun_request_type))
#else //#ifdef STEPHAN_ENABLE_TWT
	#define TX_RP_SIZE (sizeof(struct tun_packet_start))
#endif //#ifdef STEPHAN_ENABLE_TWT
#define TX_DP_SIZE (sizeof(struct tun_packet_start) + sizeof(struct tun_data_type))


struct gwc_args {
    batman_time_t gw_state_stamp;
	uint8_t gw_state;
	uint8_t prev_gw_state;
	uint32_t orig;
	struct gw_node *gw_node;	// pointer to gw node
	struct sockaddr_in gw_addr;	// gateway ip
	char  gw_str[ADDR_STR_LEN];	// string of gateway ip
	struct sockaddr_in my_addr; 	// primary_ip
	uint32_t my_tun_addr;		// ip used for bat0 tunnel interface
	char  my_tun_str[ADDR_STR_LEN];	// string of my_tun_addr
	int32_t mtu_min;
	uint8_t tunnel_type;
	int32_t udp_sock;
	int32_t tun_fd;
	int32_t tun_ifi;
	char tun_dev[IFNAMSIZ];		// was tun_if
#ifdef STEPHAN_ENABLE_TWT
    batman_time_t tun_ip_request_stamp;
    batman_time_t tun_ip_lease_stamp;
    batman_time_t tun_ip_lease_duration;
	uint32_t send_tun_ip_requests;
	uint32_t pref_addr;
#endif //#ifdef STEPHAN_ENABLE_TWT
	//	uint32_t last_invalidip_warning;
};


struct gws_args
{
	int8_t netmask;
	int32_t port;
	int32_t owt;
#ifdef STEPHAN_ENABLE_TWT
	int32_t twt;
	int32_t lease_time;
#endif //#ifdef STEPHAN_ENABLE_TWT
	int mtu_min;
	uint32_t my_tun_ip;
	uint32_t my_tun_netmask;
	uint32_t my_tun_ip_h;
	uint32_t my_tun_suffix_mask_h;
	struct sockaddr_in  client_addr;
#ifdef STEPHAN_ENABLE_TWT
	struct gw_client **gw_client_list;
#endif //#ifdef STEPHAN_ENABLE_TWT
	int32_t sock;
	int32_t tun_fd;
	int32_t tun_ifi;
	char tun_dev[IFNAMSIZ];
};



// field accessor and flags for gateway announcement extension packets
#define EXT_GW_FIELD_GWTYPES ext_related
#define EXT_GW_FIELD_GWFLAGS def8
#define EXT_GW_FIELD_GWPORT  d16.def16
#define EXT_GW_FIELD_GWADDR  d32.def32

// the flags for gw extension messsage gwtypes:
#define TWO_WAY_TUNNEL_FLAG   0x01
#define ONE_WAY_TUNNEL_FLAG   0x02

struct tun_orig_data {

	int16_t  tun_array_len;
	struct ext_packet tun_array[];

};





static uint16_t my_gw_ext_array_len = 0;
static struct ext_packet my_gw_extension_packet; //currently only one gw_extension_packet considered
static struct ext_packet *my_gw_ext_array = &my_gw_extension_packet;


static struct gw_node *curr_gateway = NULL;

static struct gws_args *gws_args = NULL;
static struct gwc_args *gwc_args = NULL;


static struct tun_packet tp;

static int32_t batman_tun_index = 0;

static void gwc_cleanup( void );


/* Probe for tun interface availability */
static int8_t probe_tun( void ) {

	int32_t fd;

	if ( ( fd = open( "/dev/net/tun", O_RDWR ) ) < 0 ) {

		dbg( DBGL_SYS, DBGT_ERR, "could not open '/dev/net/tun' ! Is the tun kernel module loaded ?" );
		return FAILURE;
	}

	close( fd );

	return SUCCESS;
}



static void del_dev_tun( int32_t fd, char* tun_name, uint32_t tun_ip, char const *whose ) {

	if ( Tun_persist  &&  ioctl( fd, TUNSETPERSIST, 0 ) < 0 ) {
	
		dbg( DBGL_SYS, DBGT_ERR, "can't delete tun device: %s", strerror(errno) );
		return;
	}
	
	dbgf( DBGL_SYS, DBGT_INFO, "closing %s tunnel %s  ip %s", whose, tun_name, ipStr(tun_ip) );
	
	close( fd );

	return;
}

//stephan: begin
void call_script(char *pArg1, char *pArg2)
{
 static char cmd[256]; //mache es static, da ich nicht weiss, wie gross die stacksize ist
 static char old_arg1[25]; //mache es static, da ich nicht weiss, wie gross die stacksize ist

	if(strcmp(pArg1, old_arg1))
	{
		sprintf(cmd,"/usr/lib/bmxd/bmxd-gateway.sh %s %s", pArg1, pArg2);
        UNUSED_RETVAL(system(cmd));
		strcpy(old_arg1, pArg1);
	}
}
//stephan: end

static int32_t add_dev_tun(  uint32_t tun_addr, char *tun_dev, size_t tun_dev_size, int32_t *ifi, int mtu_min ) {

	int32_t tmp_fd = -1;
	int32_t fd = -1;
	int32_t sock_opts;
	struct ifreq ifr_tun, ifr_if;
	struct sockaddr_in addr;
	int req = 0;

	/* set up tunnel device */
	memset( &ifr_if, 0, sizeof(ifr_if) );

	if ( ( fd = open( "/dev/net/tun", O_RDWR ) ) < 0 ) {

		dbg( DBGL_SYS, DBGT_ERR, "can't open tun device (/dev/net/tun): %s", strerror(errno) );
		return FAILURE;
	}

	batman_tun_index = 0;
	uint8_t name_tun_success = NO;
	
	while ( batman_tun_index < MAX_BATMAN_TUN_INDEX && !name_tun_success ) {
		
		memset( &ifr_tun, 0, sizeof(ifr_tun) );
		ifr_tun.ifr_flags = IFF_TUN | IFF_NO_PI;
		sprintf( ifr_tun.ifr_name, "%s%d", BATMAN_TUN_PREFIX, batman_tun_index++ );
		
		
		if ( ( ioctl( fd, TUNSETIFF, (void *) &ifr_tun ) ) < 0 ) {
			dbg( DBGL_CHANGES, DBGT_WARN, "Tried to name tunnel to %s ... busy", ifr_tun.ifr_name );
		} else {
			name_tun_success = YES;
			dbg( DBGL_CHANGES, DBGT_INFO, "Tried to name tunnel to %s ... success", ifr_tun.ifr_name );
		}
		
	}
	
	if ( !name_tun_success ) {
		dbg( DBGL_SYS, DBGT_ERR, "can't set tun device (TUNSETIFF): %s", strerror(errno) );
		dbg( DBGL_SYS, DBGT_ERR, "Giving up !" );
		close(fd);
		return FAILURE;
		
	}
	
	if( Tun_persist  &&  ioctl( fd, TUNSETPERSIST, 1 ) < 0 ) {
		dbg( DBGL_SYS, DBGT_ERR, "can't set tun device (TUNSETPERSIST): %s", strerror(errno) );
		close(fd);
		return FAILURE;
	}

	if ( (tmp_fd = socket( AF_INET, SOCK_DGRAM, 0 )) < 0 ) {
		dbg( DBGL_SYS, DBGT_ERR, "can't create tun device (udp socket): %s", strerror(errno) );
		goto add_dev_tun_error;
	}


	/* set ip of this end point of tunnel */
	memset( &addr, 0, sizeof(addr) );
	addr.sin_addr.s_addr = tun_addr;
	addr.sin_family = AF_INET;
	memcpy( &ifr_tun.ifr_addr, &addr, sizeof(struct sockaddr) );


	if ( ioctl( tmp_fd, (req=SIOCSIFADDR), &ifr_tun) < 0 )
		goto add_dev_tun_error;
	

	if ( ioctl( tmp_fd, (req=SIOCGIFINDEX), &ifr_tun ) < 0 )
		goto add_dev_tun_error;

	
	*ifi = ifr_tun.ifr_ifindex;

	if ( ioctl( tmp_fd, (req=SIOCGIFFLAGS), &ifr_tun) < 0 )
		goto add_dev_tun_error;

	
	ifr_tun.ifr_flags |= IFF_UP;
	ifr_tun.ifr_flags |= IFF_RUNNING;

	if ( ioctl( tmp_fd, (req=SIOCSIFFLAGS), &ifr_tun) < 0 )
		goto add_dev_tun_error;


	/* set MTU of tun interface: real MTU - 29 */
	if ( mtu_min < 100 ) {
		dbg( DBGL_SYS, DBGT_ERR, "MTU min smaller than 100 -> can't reduce MTU anymore" );
		req=0;
		goto add_dev_tun_error;

	} else {

		ifr_tun.ifr_mtu = mtu_min - 29;

		if ( ioctl( tmp_fd, (req=SIOCSIFMTU), &ifr_tun ) < 0 ) {

			dbg( DBGL_SYS, DBGT_ERR, "can't set SIOCSIFMTU for device %s: %s", 
				      ifr_tun.ifr_name, strerror(errno) );
			
			goto add_dev_tun_error;
		}
	}


	/* make tun socket non blocking */
	sock_opts = fcntl( fd, F_GETFL, 0 );
	fcntl( fd, F_SETFL, sock_opts | O_NONBLOCK );

	strncpy( tun_dev, ifr_tun.ifr_name, tun_dev_size - 1 );
	close( tmp_fd );

	return fd;
	
add_dev_tun_error:
		
	if ( req )
		dbg( DBGL_SYS, DBGT_ERR, "can't ioctl %d tun device %s: %s", req, tun_dev, strerror(errno) );
	
	if ( fd > -1 )
		del_dev_tun( fd, tun_dev, tun_addr, __func__ );
	
	if ( tmp_fd > -1 )
		close( tmp_fd );
	
	return FAILURE;

}


static int8_t set_tun_addr( int32_t fd, uint32_t tun_addr, char *tun_dev ) {

	struct sockaddr_in addr;
	struct ifreq ifr_tun;


	memset( &ifr_tun, 0, sizeof(ifr_tun) );
	memset( &addr, 0, sizeof(addr) );

	addr.sin_addr.s_addr = tun_addr;
	addr.sin_family = AF_INET;
	memcpy( &ifr_tun.ifr_addr, &addr, sizeof(struct sockaddr) );

	strncpy( ifr_tun.ifr_name, tun_dev, IFNAMSIZ - 1 );

	if ( ioctl( fd, SIOCSIFADDR, &ifr_tun) < 0 ) {

		dbg( DBGL_SYS, DBGT_ERR, "can't set tun address (SIOCSIFADDR): %s", strerror(errno) );
		return -1;

	}

	return 1;
}

/* returns the up and downspeeds in kbit, calculated from the class */
static void get_gw_speeds( unsigned char class, int *down, int *up ) {

	char sbit    = (class&0x80)>>7;
	char dpart   = (class&0x78)>>3;
	char upart   = (class&0x07);

	*down= 32*(sbit+2)*(1<<dpart);
	*up=   ((upart+1)*(*down))/8;
}



/* calculates the gateway class from kbit */
static unsigned char get_gw_class( int down, int up ) {

	int mdown = 0, tdown, tup, difference = 0x0FFFFFFF;
	unsigned char class = 0, sbit, part;


	/* test all downspeeds */
	for ( sbit = 0; sbit < 2; sbit++ ) {

		for ( part = 0; part < 16; part++ ) {

			tdown = 32 * ( sbit + 2 ) * ( 1<<part );

			if ( abs( tdown - down ) < difference ) {

				class = ( sbit<<7 ) + ( part<<3 );
				difference = abs( tdown - down );
				mdown = tdown;

			}
		}
	}

	/* test all upspeeds */
	difference = 0x0FFFFFFF;

	for ( part = 0; part < 8; part++ ) {

		tup = ( ( part+1 ) * ( mdown ) ) / 8;

		if ( abs( tup - up ) < difference ) {

			class = ( class&0xF8 ) | part;
			difference = abs( tup - up );

		}
	}

	return class;
}


static void update_gw_list( struct orig_node *orig_node, int16_t gw_array_len, struct ext_packet *gw_array ) {

	struct list_head *gw_pos, *gw_tmp, *gw_prev = (struct list_head*)&gw_list;
	struct gw_node *gw_node;
	int download_speed, upload_speed
			;
	struct tun_orig_data *tuno = orig_node->plugin_data[ tun_orig_registry ];
	
	list_for_each_safe( gw_pos, gw_tmp, &gw_list ) {

		gw_node = list_entry(gw_pos, struct gw_node, list);

		if ( gw_node->orig_node == orig_node ) {
			
			dbg( DBGL_CHANGES, DBGT_INFO, 
			     "Gateway class of originator %s changed from %i to %i, port %d, addr %s, "
			     "new supported tunnel types %s, %s", 
			     orig_node->orig_str,
			     tuno ? tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS : 0,
			     gw_array ? gw_array[0].EXT_GW_FIELD_GWFLAGS : 0,
			     tuno ? ntohs( tuno->tun_array[0].EXT_GW_FIELD_GWPORT ) : 0 ,
			     ipStr( tuno ? tuno->tun_array[0].EXT_GW_FIELD_GWADDR : 0 ),
			     gw_array ? ((gw_array[0].EXT_GW_FIELD_GWTYPES & TWO_WAY_TUNNEL_FLAG)?"TWT":"-") : "-",
			     gw_array ? ((gw_array[0].EXT_GW_FIELD_GWTYPES & ONE_WAY_TUNNEL_FLAG)?"OWT":"-") : "-" );
			
			if ( tuno ) {
					
				debugFree( orig_node->plugin_data[ tun_orig_registry ], 1123 );
				
				tuno = orig_node->plugin_data[ tun_orig_registry ] = NULL;
				
				if ( !gw_array ) {
					list_del( gw_prev, gw_pos, &gw_list );
					debugFree( gw_node, 1103 );
					dbg( DBGL_CHANGES, DBGT_INFO, "Gateway %s removed from gateway list", orig_node->orig_str );
				}
			} 
			
			if ( !tuno  &&  gw_array )  {

				tuno = debugMalloc( sizeof( struct tun_orig_data ) + gw_array_len * sizeof( struct ext_packet ), 123 );
				
				orig_node->plugin_data[ tun_orig_registry ] = tuno;
				
				memcpy( tuno->tun_array, gw_array, gw_array_len * sizeof( struct ext_packet ) );
				
				tuno->tun_array_len = gw_array_len;
				
			}
			

			if ( gw_node == curr_gateway ) {
				curr_gateway = NULL;
				gwc_cleanup();
			}

			return;

		} else {
			
			gw_prev = &gw_node->list;
			
		}

	}

	if ( gw_array && !tuno ) {
	
		get_gw_speeds( gw_array->EXT_GW_FIELD_GWFLAGS, &download_speed, &upload_speed );
	
		dbg( DBGL_CHANGES, DBGT_INFO, "found new gateway %s, announced by %s -> class: %i - %i%s/%i%s, new supported tunnel types %s, %s", 
				ipStr( gw_array->EXT_GW_FIELD_GWADDR ),
				orig_node->orig_str, 
				gw_array->EXT_GW_FIELD_GWFLAGS, 
				( download_speed > 2048 ? download_speed / 1024 : download_speed ),
				( download_speed > 2048 ? "MBit" : "KBit" ),
				( upload_speed > 2048 ? upload_speed / 1024 : upload_speed ), 
				( upload_speed > 2048 ? "MBit" : "KBit" ), 
				((gw_array->EXT_GW_FIELD_GWTYPES & TWO_WAY_TUNNEL_FLAG)?"TWT":"-"), 
				((gw_array->EXT_GW_FIELD_GWTYPES & ONE_WAY_TUNNEL_FLAG)?"OWT":"-" ) );
	
		gw_node = debugMalloc( sizeof(struct gw_node), 103 );
		memset( gw_node, 0, sizeof(struct gw_node) );
		INIT_LIST_HEAD( &gw_node->list );
	
		gw_node->orig_node = orig_node;
		
		tuno = debugMalloc( sizeof( struct tun_orig_data ) + gw_array_len * sizeof( struct ext_packet ), 123 );
				
		orig_node->plugin_data[ tun_orig_registry ] = tuno;
				
		memcpy( tuno->tun_array, gw_array, gw_array_len * sizeof( struct ext_packet ) );
		
		tuno->tun_array_len = gw_array_len;
		
		gw_node->unavail_factor = 0;
		gw_node->last_failure = batman_time;
	
		list_add_tail( &gw_node->list, &gw_list );
		
		return;
	}
	
	cleanup_all( -500018 );
}



static int32_t cb_tun_ogm_hook( struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router ) {
	
	struct orig_node *on = mb->orig_node;
	struct tun_orig_data *tuno = on->plugin_data[ tun_orig_registry ];
	
	/* may be GW announcements changed */
	uint16_t gw_array_len = mb->rcv_ext_len[EXT_TYPE_64B_GW] / sizeof(struct ext_packet);
	struct ext_packet *gw_array = gw_array_len ? mb->rcv_ext_array[EXT_TYPE_64B_GW] : NULL;
	
	if ( tuno  &&  !gw_array ) {
	
		// remove cached gw_msg
		update_gw_list( on, 0, NULL );
	
	} else if ( !tuno  &&  gw_array ) {
	
		// memorize new gw_msg
		update_gw_list( on, gw_array_len, gw_array  );
		
	} else if ( tuno  &&  gw_array  &&
                (tuno->tun_array_len != gw_array_len || memcmp( tuno->tun_array, gw_array, gw_array_len * sizeof(struct ext_packet)))) {
		
		// update existing gw_msg
		update_gw_list( on, gw_array_len, gw_array  );
	}

	
	/* restart gateway selection if routing class 3 and we have more packets than curr_gateway */
	if (	curr_gateway  &&
                on->router &&
		routing_class == 3  &&
		tuno  &&
		tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS  &&
                ( tuno->tun_array[0].EXT_GW_FIELD_GWTYPES &
                  (
#ifdef STEPHAN_ENABLE_TWT
                      (two_way_tunnel ? TWO_WAY_TUNNEL_FLAG : 0) |
#endif //#ifdef STEPHAN_ENABLE_TWT
                      (one_way_tunnel ? ONE_WAY_TUNNEL_FLAG : 0))) &&
		curr_gateway->orig_node != on  &&
		(	( pref_gateway == on->orig )  ||
			( pref_gateway != curr_gateway->orig_node->orig  &&  
			  curr_gateway->orig_node->router->longtm_sqr.wa_val + (gw_hysteresis*PROBE_TO100)
				<= on->router->longtm_sqr.wa_val  ) ) ) {
		
		dbg( DBGL_CHANGES, DBGT_INFO, "Restart gateway selection. %s gw found! "
		     "%d OGMs from new GW %s (compared to %d from old GW %s)",
		     pref_gateway == on->orig ? "Preferred":"Better",
		     on->router->longtm_sqr.wa_val,
		     on->orig_str, 
		     pref_gateway != on->orig ? curr_gateway->orig_node->router->longtm_sqr.wa_val : 255,
		     pref_gateway != on->orig ? curr_gateway->orig_node->orig_str : "???" );
	
		curr_gateway = NULL;
		gwc_cleanup();
	
	}

	return CB_OGM_ACCEPT;
	
}



#ifdef STEPHAN_ENABLE_TWT
static int32_t gwc_handle_tun_ip_reply( struct tun_packet *tp, uint32_t sender_ip, int32_t rcv_buff_len ) {
	
    dbg( DBGL_SYS, DBGT_INFO, "got IP reply: sender %s ip %s", ipStr(sender_ip), ipStr(gwc_args->gw_addr.sin_addr.s_addr));
	if ( sender_ip == gwc_args->gw_addr.sin_addr.s_addr && rcv_buff_len == TX_RP_SIZE && tp->TP_TYPE == TUNNEL_IP_REPLY ) {

		tp->LEASE_LT = ntohs( tp->LEASE_LT );
		
        dbg( DBGL_SYS, DBGT_INFO, "got IP %s (preferred: IP %s) from gateway: %s for %u seconds",
			      ipStr( tp->LEASE_IP ), ipStr( gwc_args->pref_addr ), gwc_args->gw_str, tp->LEASE_LT );

		if ( tp->LEASE_LT < MIN_TUN_LTIME ) {

            dbg( DBGL_SYS, DBGT_WARN, "unacceptable virtual IP lifetime" );
			goto gwc_handle_tun_ip_reply_failure;
		}

		if ( gwc_args->pref_addr == 0  || gwc_args->pref_addr != tp->LEASE_IP ) {

			if ( gwc_args->pref_addr /*== 0 ?????*/ )
			{
				add_del_route( 0, 0, 0, 0, gwc_args->tun_ifi, gwc_args->tun_dev, RT_TABLE_TUNNEL, RTN_UNICAST, DEL, TRACK_TUNNEL );
				call_script("del", "gwc_handle_tun_ip_reply");
			}
			
			if ( set_tun_addr( gwc_args->udp_sock, tp->LEASE_IP, gwc_args->tun_dev ) < 0 ) {
		
                dbg( DBGL_SYS, DBGT_WARN, "could not assign IP" );
				goto gwc_handle_tun_ip_reply_failure;
			}
	
			/* kernel deletes routes after resetting the interface ip */
			add_del_route( 0, 0, 0, 0, gwc_args->tun_ifi, gwc_args->tun_dev, RT_TABLE_TUNNEL, RTN_UNICAST, ADD, TRACK_TUNNEL );
			call_script(gwc_args->gw_str, "gwc_handle_tun_ip_reply");
			
			// critical syntax: may be used for nameserver updates
            dbg( DBGL_SYS, DBGT_INFO, "GWT: GW-client tunnel init succeeded - type: 2WT  dev: %s  IP: %s  MTU: %d  GWIP: %s",
			     gwc_args->tun_dev, ipStr( tp->LEASE_IP ) , gwc_args->mtu_min,  ipStr( gwc_args->gw_addr.sin_addr.s_addr) );
			
		}

		gwc_args->tun_ip_lease_stamp = batman_time;
		gwc_args->pref_addr = tp->LEASE_IP;
		
		gwc_args->my_tun_addr = tp->LEASE_IP;
		addr_to_str( gwc_args->my_tun_addr, gwc_args->my_tun_str );

		gwc_args->tun_ip_lease_duration = tp->LEASE_LT;
		gwc_args->send_tun_ip_requests = 0;
		
		
		return tp->LEASE_LT;

	} 
		
	dbg( DBGL_SYS, DBGT_ERR, "can't receive ip request: sender IP, packet type, packet size (%i) do not match", rcv_buff_len );

gwc_handle_tun_ip_reply_failure:
		
	gwc_args->gw_node->last_failure = batman_time;
	gwc_args->gw_node->unavail_factor++;
	gwc_args->tun_ip_lease_duration = 0;
	
    dbg( DBGL_SYS, DBGT_INFO, "ignoring this GW for %d secs",
		      ( gwc_args->gw_node->unavail_factor * gwc_args->gw_node->unavail_factor * GW_UNAVAIL_TIMEOUT )/1000 );

	return FAILURE;

}



static void gwc_request_tun_ip( struct tun_packet *tp ) {
	
    dbg( DBGL_SYS, DBGT_INFO, "send ip request to gateway: %s, preferred IP: %s",
		      ipStr(gwc_args->gw_addr.sin_addr.s_addr), ipStr(gwc_args->pref_addr) );
	
	memset( &tp->tt, 0, sizeof(tp->tt) );
	tp->TP_VERS = COMPAT_VERSION;
	tp->TP_TYPE = TUNNEL_IP_REQUEST;
	tp->LEASE_IP = gwc_args->pref_addr;
	
	if ( sendto( gwc_args->udp_sock, &tp->start, TX_RP_SIZE, 0, (struct sockaddr *)&gwc_args->gw_addr, sizeof(struct sockaddr_in) ) < 0 ) {

		dbg( DBGL_SYS, DBGT_ERR, "can't send ip request to gateway: %s", strerror(errno) );
	
	} 

	gwc_args->tun_ip_request_stamp = batman_time;
	gwc_args->send_tun_ip_requests++;

}


static void gwc_maintain_twt( void* unused ) {
	
	if ( !gwc_args ) {
		dbgf_all( DBGT_INFO, "called while curr_gateway_changed or with invalid gwc_args.." );
		
		gwc_cleanup();
		return;
	}
	
	
	// close connection to gateway if the gateway does not respond 
	if ( gwc_args->send_tun_ip_requests >= MAX_TUNNEL_IP_REQUESTS ) {
		
        dbg( DBGL_SYS, DBGT_INFO, "disconnecting from unresponsive gateway (%s) !  Maximum number of tunnel ip requests send",
			      gwc_args->gw_str );

		gwc_args->gw_node->last_failure = batman_time;
		gwc_args->gw_node->unavail_factor++;
		
        dbg( DBGL_SYS, DBGT_INFO, "Ignoring this GW for %d secs",
			      ( gwc_args->gw_node->unavail_factor * gwc_args->gw_node->unavail_factor * GW_UNAVAIL_TIMEOUT )/1000 );

		gwc_cleanup();
		curr_gateway = NULL;
		return;
	}

    //dbgf( DBGL_CHANGES, DBGT_INFO, "tun_ip_request_stamp=%llu,", gwc_args->tun_ip_request_stamp);
    //dbgf( DBGL_CHANGES, DBGT_INFO, "tun_ip_lease_stamp=%llu", gwc_args->tun_ip_request_stamp);
	// obtain virtual IP and refresh leased IP  when 90% of lease_duration has expired
	if ( LESS_U32( (gwc_args->tun_ip_request_stamp + TUNNEL_IP_REQUEST_TIMEOUT), batman_time) &&
	     LESS_U32( (gwc_args->tun_ip_lease_stamp + (((gwc_args->tun_ip_lease_duration * 1000)/10)*9) ), batman_time) ) {
		gwc_request_tun_ip( &tp );
		
	}
	
	
	// drop connection to gateway if the gateway does not respond 
	if ( unresp_gw_chk  &&  gwc_args->gw_state == GW_STATE_UNKNOWN  &&  gwc_args->gw_state_stamp != 0  &&
		     LESS_U32( ( gwc_args->gw_state_stamp + GW_STATE_UNKNOWN_TIMEOUT ), batman_time ) ) {
		
        dbg( DBGL_SYS,  DBGT_INFO, "GW seems to be a blackhole! Use --%s to disable this check!", ARG_UNRESP_GW_CHK );
        dbg( DBGL_SYS, DBGT_INFO, "disconnecting from unresponsive gateway (%s) !", gwc_args->gw_str );

		gwc_args->gw_node->last_failure = batman_time;
		gwc_args->gw_node->unavail_factor++;
		
        dbg( DBGL_SYS, DBGT_INFO, "Ignoring this GW for %d secs",
			      ( gwc_args->gw_node->unavail_factor * gwc_args->gw_node->unavail_factor * GW_UNAVAIL_TIMEOUT )/1000 );
		
		gwc_cleanup();
		curr_gateway = NULL;
		return;
	}
	
	
	
	// change back to unknown state if gateway did not respond in time
	if ( ( gwc_args->gw_state == GW_STATE_VERIFIED ) && LESS_U32( (gwc_args->gw_state_stamp + GW_STATE_VERIFIED_TIMEOUT), batman_time ) ) {

		gwc_args->gw_state = GW_STATE_UNKNOWN;
		gwc_args->gw_state_stamp = 0; // the timer is not started before the next packet is send to the GW
		
		if( gwc_args->prev_gw_state != gwc_args->gw_state ) {
			
			dbg( DBGL_CHANGES, DBGT_INFO, "changed GW state: %d", gwc_args->gw_state );
			gwc_args->prev_gw_state = gwc_args->gw_state;
		}

	}

	register_task( 1000 + rand_num(100), gwc_maintain_twt, NULL );
	
	return;
}
#endif //#ifdef STEPHAN_ENABLE_TWT


static void gwc_recv_tun( int32_t fd_in ) {
	
        uint16_t r=0;
#ifdef STEPHAN_ENABLE_TWT
        uint16_t  = htons( 53 );
#endif //#ifdef STEPHAN_ENABLE_TWT
	int32_t tp_data_len, tp_len;
	struct iphdr *iphdr;
	
	if ( gwc_args == NULL ) {
		dbgf( DBGL_SYS, DBGT_ERR, "called while curr_gateway_changed  %s", 
		     gwc_args ? "with invalid gwc_args..." : "" );
		
		gwc_cleanup();
		return;
	}
	
	
	while ( r++ < 30  &&  ( tp_data_len = read( gwc_args->tun_fd, tp.IP_PACKET, sizeof(tp.IP_PACKET) /*TBD: why -2 here? */ ) ) > 0 ) {
		
		
		tp_len = tp_data_len + sizeof(tp.start);
		
		if ( tp_data_len < (int32_t)sizeof(struct iphdr) || tp.IP_HDR.version != 4 ) {
			
			dbgf( DBGL_SYS, DBGT_ERR, "Received Invalid packet type via tunnel !" );
			continue;
			
		}
		
		tp.TP_VERS = COMPAT_VERSION;
		tp.TP_TYPE = TUNNEL_DATA;

		iphdr = (struct iphdr *)(tp.IP_PACKET);

		if ( gwc_args->my_tun_addr == 0 ) {
			
			gwc_args->gw_node->last_failure = batman_time;
			gwc_args->gw_node->unavail_factor++;
			
			dbgf( DBGL_SYS, DBGT_ERR, "No vitual IP! Ignoring this GW for %d secs",
			     ( gwc_args->gw_node->unavail_factor * gwc_args->gw_node->unavail_factor * GW_UNAVAIL_TIMEOUT )/1000 );
			
			gwc_cleanup();
			curr_gateway = NULL;
			return;
		}
		
		
                if ( (gwc_args->tunnel_type & ONE_WAY_TUNNEL_FLAG)
#ifdef STEPHAN_ENABLE_TWT
                     || (gwc_args->tunnel_type & TWO_WAY_TUNNEL_FLAG  &&
		      gwc_args->tun_ip_lease_duration  &&  
		      iphdr->saddr == gwc_args->my_tun_addr &&  
                      iphdr->saddr != gwc_args->gw_addr.sin_addr.s_addr )
#endif //#ifdef STEPHAN_ENABLE_TWT
                     )
		{
			
			if ( sendto( gwc_args->udp_sock, (unsigned char*) &tp.start, tp_len, 0, 
			             (struct sockaddr *)&gwc_args->gw_addr, sizeof (struct sockaddr_in) ) < 0 ) 
			{
				
				dbg_mute( 30, DBGL_SYS, DBGT_ERR, "can't send data to gateway: %s", strerror(errno) );
				
				gwc_cleanup();
				curr_gateway = NULL;
				return;
				
			}
		
			// dbgf_all( DBGT_INFO "Send data to gateway %s, len %d", gw_str, tp_len );

#ifdef STEPHAN_ENABLE_TWT
			// activate unresponsive GW check only based on TCP and DNS data
			if ( (gwc_args->tunnel_type & TWO_WAY_TUNNEL_FLAG)  &&  
			     unresp_gw_chk  &&  
			     gwc_args->gw_state == GW_STATE_UNKNOWN  &&   
			     gwc_args->gw_state_stamp == 0 ) {

                                if ((tp.IP_HDR.protocol == IPPROTO_TCP) ||
                                       ( (tp.IP_HDR.protocol == IPPROTO_UDP) &&
				      (((struct udphdr *)((uint8_t*)&tp.IP_HDR) + (tp.IP_HDR.ihl*4))->dest == dns_port)  )
				  ) {
					gwc_args->gw_state_stamp = batman_time;
				  }
			}
#endif //#ifdef STEPHAN_ENABLE_TWT


		} else /*if ( gwc_args->last_invalidip_warning == 0 || 
		            LESS_U32((gwc_args->last_invalidip_warning + WARNING_PERIOD), batman_time) )*/ 
		{

			            //gwc_args->last_invalidip_warning = batman_time;
#ifdef STEPHAN_ENABLE_TWT
	
			dbg_mute( 60, DBGL_CHANGES, DBGT_ERR, 
			     "Gateway client - Invalid outgoing src IP: %s (should be %s) or dst IP %s"
                 "IP lifetime %llu ! Dropping packet",
                 ipStr(iphdr->saddr),  gwc_args->my_tun_str, gwc_args->gw_str, (unsigned long long)gwc_args->tun_ip_lease_duration );

#else //STEPHAN_ENABLE_TWT
			dbg_mute( 60, DBGL_CHANGES, DBGT_ERR, 
			     "Gateway client - Invalid outgoing src IP: %s (should be %s) or dst IP %s ! Dropping packet",
                 ipStr(iphdr->saddr),  gwc_args->my_tun_str, gwc_args->gw_str );
#endif //#ifdef STEPHAN_ENABLE_TWT
			
			if ( iphdr->saddr == gwc_args->gw_addr.sin_addr.s_addr ) {
				gwc_cleanup();
				return;
			}
		}
	}
}


#ifdef STEPHAN_ENABLE_TWT

void gwc_recv_udp( int32_t fd_in ) {
	
	int32_t tp_data_len, tp_len;
	struct sockaddr_in sender_addr;

	if ( !gwc_args ) {
		dbgf( DBGL_SYS, DBGT_ERR, "called with invalid gwc_args.." );
		
		gwc_cleanup();
		return;
	}

	
	
	static uint32_t addr_len = sizeof (struct sockaddr_in);

	while ( ( tp_len = recvfrom( gwc_args->udp_sock, (unsigned char*)&tp.start, TX_DP_SIZE, 0, (struct sockaddr *)&sender_addr, &addr_len ) ) > 0 ) {
		
		if ( tp_len < (int32_t)TX_RP_SIZE ) {
			
			dbgf( DBGL_SYS, DBGT_ERR, 
			     "Invalid packet size (%d) via tunnel, from %s !", 
			     tp_len, ipStr( sender_addr.sin_addr.s_addr ) );
			continue;
			
		}

		if ( tp.TP_VERS != COMPAT_VERSION ) {
			
			dbgf( DBGL_SYS, DBGT_ERR, 
			     "Invalid compat version (%d) via tunnel, from %s !", 
			     tp.TP_VERS, ipStr( sender_addr.sin_addr.s_addr )  );
			continue;
			
		}

		tp_data_len = tp_len - sizeof(tp.start);
		

		if ( ( gwc_args->tunnel_type & TWO_WAY_TUNNEL_FLAG ) && 

#ifdef STEPHAN_ALLOW_TUNNEL_PAKETS
         (     tp.TP_TYPE == TUNNEL_DATA
          ||   ( sender_addr.sin_addr.s_addr == gwc_args->gw_addr.sin_addr.s_addr ) ) ) {
#else

		     ( sender_addr.sin_addr.s_addr == gwc_args->gw_addr.sin_addr.s_addr ) ) {
#endif


			// got data from gateway
			if ( tp.TP_TYPE == TUNNEL_DATA ) {

                if (tp_data_len >= (int32_t)sizeof (struct iphdr) && tp.IP_HDR.version == 4) {

                       if ( write( gwc_args->tun_fd, tp.IP_PACKET, tp_data_len ) < 0 ) {
                          dbgf( DBGL_SYS, DBGT_ERR, "can't write packet: %s", strerror(errno) );
                       }

                       if (unresp_gw_chk && tp.IP_HDR.protocol != IPPROTO_ICMP) {
				
						gwc_args->gw_state = GW_STATE_VERIFIED;
						gwc_args->gw_state_stamp = batman_time;
						
						gwc_args->gw_node->last_failure = batman_time;
						gwc_args->gw_node->unavail_factor = 0;

						if( gwc_args->prev_gw_state != gwc_args->gw_state ) {
							
							dbgf( DBGL_CHANGES, DBGT_INFO,
                                                                "changed GW state: from %d to %d, incoming IP protocol: %d",
                                                                gwc_args->prev_gw_state, gwc_args->gw_state,
                                                                tp.IP_HDR.protocol);
							
							gwc_args->prev_gw_state = gwc_args->gw_state;
						}

					}
				
				} else {
					
					dbgf( DBGL_CHANGES, DBGT_INFO, 
					     "only IPv4 packets supported so fare !");
					
				}
				
			} else if ( tp.TP_TYPE == TUNNEL_IP_REPLY ) {
				
				if ( gwc_handle_tun_ip_reply( &tp, sender_addr.sin_addr.s_addr, tp_len) < 0 ) {
					
					gwc_cleanup();
					curr_gateway = NULL;
					return;
				}
				
				
			// gateway told us that we have no valid IP
			} else if ( tp.TP_TYPE == TUNNEL_IP_INVALID ) {

				dbgf( DBGL_CHANGES, DBGT_WARN, "gateway (%s) says: IP (%s) is expired", 
				     gwc_args->gw_str, gwc_args->my_tun_str );

				gwc_request_tun_ip( &tp );

				gwc_args->tun_ip_lease_duration = 0;

			}

		} else {

            dbgf( DBGL_SYS, DBGT_ERR, "%s client: ignoring gateway packet from %s (expected %s! Wrong GW or packet too small (%i)",
				      (gwc_args->tunnel_type & ONE_WAY_TUNNEL_FLAG ? ARG_ONE_WAY_TUNNEL : ARG_TWO_WAY_TUNNEL), 
                       ipStr(sender_addr.sin_addr.s_addr), ipStr(gwc_args->gw_addr.sin_addr.s_addr), tp_len );
			
		}

	}

}
#endif //#ifdef STEPHAN_ENABLE_TWT




static void gwc_cleanup( void ) {

	if ( gwc_args ) {
		
		dbgf( DBGL_CHANGES, DBGT_WARN, "aborted: %s, curr_gateway_changed", (is_aborted()? "YES":"NO") );

#ifdef STEPHAN_ENABLE_TWT
		remove_task( gwc_maintain_twt, NULL );
#endif //#ifdef STEPHAN_ENABLE_TWT
		
		update_interface_rules( IF_RULE_CLR_TUNNEL );
		
		if ( gwc_args->my_tun_addr )
		{
			add_del_route( 0, 0, 0, 0, gwc_args->tun_ifi, gwc_args->tun_dev, RT_TABLE_TUNNEL, RTN_UNICAST, DEL, TRACK_TUNNEL );
			call_script("del", "gwc_cleanup");
		}
			
		if ( gwc_args->tun_fd ) {
			del_dev_tun( gwc_args->tun_fd, gwc_args->tun_dev, gwc_args->my_tun_addr, __func__ );
			set_fd_hook( gwc_args->tun_fd, gwc_recv_tun, YES /*delete*/ );
		}
		
		if ( gwc_args->udp_sock ) {
			close( gwc_args->udp_sock );
#ifdef STEPHAN_ENABLE_TWT
			set_fd_hook( gwc_args->udp_sock, gwc_recv_udp, YES /*delete*/ );
#endif //#ifdef STEPHAN_ENABLE_TWT
		}
		
		// critical syntax: may be used for nameserver updates
		dbg( DBGL_CHANGES, DBGT_INFO, "GWT: GW-client tunnel closed " );
		
		debugFree( gwc_args, 1207 );
		gwc_args = NULL;
	
	}
	
}



static int8_t gwc_init( void ) {
	
	uint8_t which_tunnel_max = 0;

	
	dbgf( DBGL_CHANGES, DBGT_INFO, " ");
	
	if ( probe_tun() == FAILURE )
		goto gwc_init_failure;
	
	if ( gwc_args || gws_args ) {
		dbgf( DBGL_SYS, DBGT_ERR, "gateway client or server already running !");
		goto gwc_init_failure;
	}
	
	if ( !curr_gateway  ||  !curr_gateway->orig_node  ||  !curr_gateway->orig_node->plugin_data[tun_orig_registry] ) {
		dbgf( DBGL_SYS, DBGT_ERR, "curr_gateway invalid!");
		goto gwc_init_failure;
	}
	
	struct orig_node *on = curr_gateway->orig_node;
	struct tun_orig_data *tuno = on->plugin_data[ tun_orig_registry ];
	
        if ( !( tuno->tun_array[0].EXT_GW_FIELD_GWTYPES & (
#ifdef STEPHAN_ENABLE_TWT
                    (two_way_tunnel?TWO_WAY_TUNNEL_FLAG:0)|
#endif //#ifdef STEPHAN_ENABLE_TWT
                    (one_way_tunnel?ONE_WAY_TUNNEL_FLAG:0)) ) ) {
		dbgf( DBGL_SYS, DBGT_ERR, "curr_gateway does not support desired tunnel type!");
		goto gwc_init_failure;
	}

	
	memset( &tp, 0, sizeof( tp ) );

	gwc_args = debugMalloc( sizeof( struct gwc_args ), 207 );
	memset( gwc_args, 0, sizeof(struct gwc_args) );

	gwc_args->gw_state_stamp = 0;
	gwc_args->gw_state = GW_STATE_UNKNOWN;
	gwc_args->prev_gw_state = GW_STATE_UNKNOWN;

	gwc_args->gw_node = curr_gateway;
	gwc_args->orig = on->orig;
	addr_to_str( on->orig, gwc_args->gw_str );

	gwc_args->gw_addr.sin_family = AF_INET;
	// the cached gw_msg stores the network byte order, so no need to transform
	gwc_args->gw_addr.sin_port = tuno->tun_array[0].EXT_GW_FIELD_GWPORT;
	gwc_args->gw_addr.sin_addr.s_addr = tuno->tun_array[0].EXT_GW_FIELD_GWADDR;

	gwc_args->my_addr.sin_family = AF_INET;
	// the cached gw_msg stores the network byte order, so no need to transform 
	gwc_args->my_addr.sin_port = tuno->tun_array[0].EXT_GW_FIELD_GWPORT;
	gwc_args->my_addr.sin_addr.s_addr = primary_addr;

	gwc_args->mtu_min = Mtu_min;
#ifdef STEPHAN_ENABLE_TWT
	if ( /*two_way_tunnel > which_tunnel_max &&*/ (tuno->tun_array[0].EXT_GW_FIELD_GWTYPES & TWO_WAY_TUNNEL_FLAG) ){
		
		gwc_args->tunnel_type = TWO_WAY_TUNNEL_FLAG;
		which_tunnel_max = two_way_tunnel;
		
	}
#endif //#ifdef STEPHAN_ENABLE_TWT
	if (one_way_tunnel > which_tunnel_max && (tuno->tun_array[0].EXT_GW_FIELD_GWTYPES & ONE_WAY_TUNNEL_FLAG) ) {
			
		gwc_args->tunnel_type = ONE_WAY_TUNNEL_FLAG;
		which_tunnel_max = one_way_tunnel;
	
	}
	
	if ( which_tunnel_max == 0 )
		goto gwc_init_failure;
	

	update_interface_rules(  IF_RULE_SET_TUNNEL );

	
	/* connect to server (establish udp tunnel) */
	if ( ( gwc_args->udp_sock = socket( PF_INET, SOCK_DGRAM, 0 ) ) < 0 ) {

		dbg( DBGL_SYS, DBGT_ERR, "can't create udp socket: %s", strerror(errno) );
		goto gwc_init_failure;
	}

	if ( bind( gwc_args->udp_sock, (struct sockaddr *)&gwc_args->my_addr, sizeof(struct sockaddr_in) ) < 0 ) {

		dbg( DBGL_SYS, DBGT_ERR, "can't bind tunnel socket: %s", strerror(errno) );
		goto gwc_init_failure;
	}

	/* make udp socket non blocking */
	int32_t sock_opts;
	if ( (sock_opts = fcntl( gwc_args->udp_sock, F_GETFL, 0 )) < 0 ) {
		dbg( DBGL_SYS, DBGT_ERR, "can't get opts of tunnel socket: %s", strerror(errno) );
		goto gwc_init_failure;
		
	}
	
	if ( fcntl( gwc_args->udp_sock, F_SETFL, sock_opts | O_NONBLOCK ) < 0 ) {
		dbg( DBGL_SYS, DBGT_ERR, "can't set opts of tunnel socket: %s", strerror(errno) );
		goto gwc_init_failure;
	}
#ifdef STEPHAN_ENABLE_TWT
	if ( set_fd_hook( gwc_args->udp_sock, gwc_recv_udp, NO /*no delete*/ ) < 0 ) {
		dbg( DBGL_SYS, DBGT_ERR, "can't register gwc_recv_udp hook" );
		goto gwc_init_failure;
	}
#endif //#ifdef STEPHAN_ENABLE_TWT

	curr_gateway->last_failure = batman_time;
	
	if ( (gwc_args->tun_fd = add_dev_tun( 0, gwc_args->tun_dev, sizeof(gwc_args->tun_dev), &gwc_args->tun_ifi, gwc_args->mtu_min )) == FAILURE ) {
	
		curr_gateway->unavail_factor++;
		
		dbgf( DBGL_CHANGES, DBGT_WARN, "could not add tun device, ignoring this GW for %d secs",
			( curr_gateway->unavail_factor * curr_gateway->unavail_factor * GW_UNAVAIL_TIMEOUT )/1000 );
		
		goto gwc_init_failure;
		
	}
	
	if ( set_fd_hook( gwc_args->tun_fd, gwc_recv_tun, NO /*no delete*/ ) < 0 ) {
		dbg( DBGL_SYS, DBGT_ERR, "can't register gwc_recv_tun hook" );
		goto gwc_init_failure;
	}

			
	if ( gwc_args->tunnel_type & ONE_WAY_TUNNEL_FLAG ) {
	
		if ( set_tun_addr( gwc_args->udp_sock, gwc_args->my_addr.sin_addr.s_addr, gwc_args->tun_dev ) < 0 ) {
			
			dbgf( DBGL_CHANGES, DBGT_WARN, "could not set tun ip, ignoring this GW for %d secs",
				      ( curr_gateway->unavail_factor * curr_gateway->unavail_factor * GW_UNAVAIL_TIMEOUT )/1000 );
		
			goto gwc_init_failure;
			
		}

		curr_gateway->unavail_factor = 0;
		
		gwc_args->my_tun_addr = gwc_args->my_addr.sin_addr.s_addr;
		addr_to_str( gwc_args->my_tun_addr, gwc_args->my_tun_str );

		add_del_route( 0, 0, 0, 0, gwc_args->tun_ifi, gwc_args->tun_dev, RT_TABLE_TUNNEL, RTN_UNICAST, ADD, TRACK_TUNNEL );
		call_script(gwc_args->gw_str, "gwc_init");

		// critical syntax: may be used for nameserver updates
		dbg( DBGL_CHANGES, DBGT_INFO, "GWT: GW-client tunnel init succeeded - type: 1WT  dev: %s  IP: %s  MTU: %d", 
		     gwc_args->tun_dev, ipStr( gwc_args->my_addr.sin_addr.s_addr ) , gwc_args->mtu_min  );
		
		
        }
#ifdef STEPHAN_ENABLE_TWT
        else /*if ( gwc_args->tunnel_type & TWO_WAY_TUNNEL_FLAG )*/ {
		
		register_task( 0, gwc_maintain_twt, NULL );
		
	}
#endif //#ifdef STEPHAN_ENABLE_TWT
	
	return SUCCESS;
	
gwc_init_failure:
	
	// critical syntax: may be used for nameserver updates
	dbg( DBGL_CHANGES, DBGT_INFO, "GWT: GW-client tunnel init failed" );
	
	gwc_cleanup();
	curr_gateway = NULL;
	
	return FAILURE;

}





#ifdef STEPHAN_ENABLE_TWT

static void gws_cleanup_leased_tun_ips( uint32_t lt, struct gw_client **gw_client_list, uint32_t my_tun_ip, uint32_t my_tun_netmask ) {
	
	uint32_t i, i_max;
	
	i_max = ntohl( ~my_tun_netmask );

	for ( i = 0; i < i_max; i++ ) {

		if ( gw_client_list[i] != NULL ) {

			if ( LSEQ_U32( ( gw_client_list[i]->last_keep_alive + (lt * 1000) ), batman_time ) || lt == 0 ) {

				dbgf( DBGL_CHANGES, DBGT_INFO, "TunIP %s of client: %s timed out", 
					      ipStr((my_tun_ip & my_tun_netmask) | ntohl(i)) , ipStr(gw_client_list[i]->addr) );

				debugFree( gw_client_list[i], 1216 );
				gw_client_list[i] = NULL;

			}

		}

	}

}



static uint8_t gws_get_ip_addr(uint32_t client_addr, uint32_t *pref_addr, struct gw_client **gw_client_list, uint32_t my_tun_ip, uint32_t my_tun_netmask ) {

	uint32_t first_free = 0, i, i_max, i_pref, i_random, cycle, i_begin, i_end;
	
	i_max = ntohl( ~my_tun_netmask );
	
	if ( (*pref_addr & my_tun_netmask) != (my_tun_ip & my_tun_netmask) )
		*pref_addr = 0;
	
	i_pref = ntohl( *pref_addr ) & ntohl( ~my_tun_netmask );
	
	if ( i_pref >= i_max )
		i_pref = 0;
	
	// try to renew virtual IP lifetime
	if ( i_pref > 0 && gw_client_list[i_pref] != NULL && gw_client_list[i_pref]->addr == client_addr ) {
		
		gw_client_list[i_pref]->last_keep_alive = batman_time;
		return YES;
		
	// client asks for a virtual IP which has already been leased to somebody else
	} else if ( i_pref > 0 && gw_client_list[i_pref] != NULL && gw_client_list[i_pref]->addr != client_addr ) {
		
		*pref_addr = 0;
		i_pref = 0;
		
	}
	
	// try to give clients always the same virtual IP
	i_random = (ntohl(client_addr) % (i_max-1)) + 1;
	
	for ( cycle = 0; cycle <= 1; cycle ++ ) {
	
		if( cycle == 0 ) {
			i_begin = i_random;
			i_end = i_max;
		} else {
			i_begin = 1;
			i_end = i_random;
		}
		
		for ( i = i_begin; i < i_end; i++ ) {
		
			if ( gw_client_list[i] != NULL && gw_client_list[i]->addr == client_addr ) {
		
				// take this one! Why give this client another one than last time?.
				gw_client_list[i]->last_keep_alive = batman_time;
				*pref_addr = (my_tun_ip & my_tun_netmask) | htonl( i );
				return YES;
		
			} else if ( first_free == 0 && gw_client_list[i] == NULL ) {
		
				// remember the first randomly-found free virtual IP
				first_free = i;
		
			}
		}
	}
	
	// give client its preferred virtual IP
	if ( i_pref > 0 && gw_client_list[i_pref] == NULL ) {
		
		gw_client_list[i_pref] = debugMalloc( sizeof(struct gw_client), 208 );
		memset( gw_client_list[i_pref], 0, sizeof(struct gw_client) );
		gw_client_list[i_pref]->addr = client_addr;
		gw_client_list[i_pref]->last_keep_alive = batman_time;
		*pref_addr = (my_tun_ip & my_tun_netmask) | htonl( i_pref );
		return YES;
	}
	
	if ( first_free == 0 ) {

		dbg( DBGL_SYS, DBGT_ERR, "can't get IP for client: maximum number of clients reached" );
		*pref_addr = 0;
		return NO;

	}

	gw_client_list[first_free] = debugMalloc( sizeof(struct gw_client), 208 );
	memset( gw_client_list[first_free], 0, sizeof(struct gw_client) );
	gw_client_list[first_free]->addr = client_addr;
	gw_client_list[first_free]->last_keep_alive = batman_time;
	*pref_addr = (my_tun_ip & my_tun_netmask) | htonl( first_free );
	
	return YES;

}


static void gws_garbage_collector( void* unused ) {

	if ( gws_args == NULL )
		return;

	// close unresponsive client connections (free unused IPs)
	gws_cleanup_leased_tun_ips( gws_args->lease_time, gws_args->gw_client_list, gws_args->my_tun_ip, gws_args->my_tun_netmask );

	register_task( 5000 + rand_num( 100 ), gws_garbage_collector, NULL );
}

#endif //#ifdef STEPHAN_ENABLE_TWT

// is udp packet from GW-Client
static void gws_recv_udp( int32_t fd_in ) {
	
	struct sockaddr_in addr;
	static uint32_t addr_len = sizeof( struct sockaddr_in );
	int32_t tp_data_len, tp_len;

	if ( gws_args == NULL ) {
		dbgf( DBGL_SYS, DBGT_ERR, "called with gws_args = NULL");
		return;
	}
	
	while ( ( tp_len = recvfrom( gws_args->sock, (unsigned char*)&tp.start, TX_DP_SIZE, 0, (struct sockaddr *)&addr, &addr_len ) ) > 0 ) {
		
		if ( tp_len < (int32_t)TX_RP_SIZE ) {
			
			dbgf( DBGL_SYS, DBGT_ERR, "Invalid packet size (%d) via tunnel, from %s", 
				      tp_len, ipStr(addr.sin_addr.s_addr) );
			continue;
			
		}

		if ( tp.TP_VERS != COMPAT_VERSION ) {
			
			dbgf( DBGL_SYS, DBGT_ERR, "Invalid compat version (%d) via tunnel, from %s", 
				      tp.TP_VERS, ipStr(addr.sin_addr.s_addr) );
			continue;
			
		}

		tp_data_len = tp_len - sizeof(tp.start);
	
		if ( tp.TP_TYPE == TUNNEL_DATA ) {
			
			if ( !(tp_data_len >= (int32_t)sizeof(struct iphdr) && tp.IP_HDR.version == 4 ) ) {
	
				dbgf( DBGL_SYS, DBGT_ERR, "Invalid packet type via tunnel" );
				continue;
	
			}
			
			struct iphdr *iphdr = (struct iphdr *)(tp.IP_PACKET);
			
			
			if ( gws_args->owt &&
				( (iphdr->saddr & gws_args->my_tun_netmask) != gws_args->my_tun_ip || iphdr->saddr == addr.sin_addr.s_addr ) ) {
				
				if ( write( gws_args->tun_fd, tp.IP_PACKET, tp_data_len ) < 0 )  
					dbg( DBGL_SYS, DBGT_ERR, "can't write packet: %s", strerror(errno) );
				
				continue;

			}
			
#ifdef STEPHAN_ENABLE_TWT
			if ( gws_args->twt ) {
			
				uint32_t iph_addr_suffix_h = ntohl( iphdr->saddr ) & ntohl( ~gws_args->my_tun_netmask );

				/* check if client IP is known */
				if ( !((iphdr->saddr & gws_args->my_tun_netmask) == gws_args->my_tun_ip &&
								    iph_addr_suffix_h > 0 &&
								    iph_addr_suffix_h < gws_args->my_tun_suffix_mask_h &&
								    gws_args->gw_client_list[ iph_addr_suffix_h ] != NULL &&
								    gws_args->gw_client_list[ iph_addr_suffix_h ]->addr == addr.sin_addr.s_addr) ) {
						
					memset( &tp.tt.trt, 0, sizeof(tp.tt.trt));
					tp.TP_VERS = COMPAT_VERSION;
					tp.TP_TYPE = TUNNEL_IP_INVALID;
					
					dbg( DBGL_SYS, DBGT_ERR, "got packet from unknown client: %s (virtual ip %s)", 
							ipStr(addr.sin_addr.s_addr), ipStr(iphdr->saddr) ); 
					
					if ( sendto( gws_args->sock, (unsigned char*)&tp.start, TX_RP_SIZE, 0, (struct sockaddr *)&addr, sizeof(struct sockaddr_in) ) < 0 )
						dbg( DBGL_SYS, DBGT_ERR, "can't send invalid ip information to client (%s): %s", 
							ipStr(addr.sin_addr.s_addr), strerror(errno) );

					continue;

				}
											
				if ( write( gws_args->tun_fd, tp.IP_PACKET, tp_data_len ) < 0 )  
					dbg( DBGL_SYS, DBGT_ERR, "can't write packet: %s", strerror(errno) );  
				
			}
#endif //#ifdef STEPHAN_ENABLE_TWT
		
                }

#ifdef STEPHAN_ENABLE_TWT
                else if ( tp.TP_TYPE == TUNNEL_IP_REQUEST && gws_args->twt ) {
			
			if ( gws_get_ip_addr( addr.sin_addr.s_addr, &tp.LEASE_IP, gws_args->gw_client_list, gws_args->my_tun_ip, gws_args->my_tun_netmask ) )
				tp.LEASE_LT = htons( gws_args->lease_time );
			else
				tp.LEASE_LT = 0;
			
			tp.TP_VERS = COMPAT_VERSION;

			tp.TP_TYPE = TUNNEL_IP_REPLY;
			
			if ( sendto( gws_args->sock, &tp.start, TX_RP_SIZE, 0, (struct sockaddr *)&addr, sizeof(struct sockaddr_in) ) < 0 ) {

				dbg( DBGL_SYS, DBGT_ERR, "can't send requested ip to client (%s): %s", 
					      ipStr(addr.sin_addr.s_addr), strerror(errno) );

			} else {

				dbgf( DBGL_CHANGES, DBGT_INFO, "assigned %s to client: %s", 
					      ipStr(tp.LEASE_IP), ipStr(addr.sin_addr.s_addr) );
			}
                }
#endif //#ifdef STEPHAN_ENABLE_TWT
                else {
			
			dbgf( DBGL_SYS, DBGT_ERR, "received unknown packet type %d from %s", 
				      tp.TP_VERS, ipStr(addr.sin_addr.s_addr) );

		}
	}
}

#ifdef STEPHAN_ENABLE_TWT
// /dev/tunX activity 
static void gws_recv_tun( int32_t fd_in ) {
	
	int32_t tp_data_len, tp_len;
	
	if ( gws_args == NULL ) {
		dbgf( DBGL_SYS, DBGT_ERR, "called with gw_args = NULL");
		return;
	}
	
	while ( ( tp_data_len = read( gws_args->tun_fd, tp.IP_PACKET, sizeof(tp.IP_PACKET) ) ) > 0 ) {
		
		tp_len = tp_data_len + sizeof(tp.start);
		
		if ( !(gws_args->twt) || tp_data_len < (int32_t)sizeof(struct iphdr) || tp.IP_HDR.version != 4 ) {
		
			dbgf( DBGL_SYS, DBGT_ERR, "Invalid packet type for client tunnel" );
			continue;
		
		}
				
		struct iphdr *iphdr = (struct iphdr *)(tp.IP_PACKET);
				
		uint32_t iph_addr_suffix_h = ntohl( iphdr->daddr ) & ntohl( ~gws_args->my_tun_netmask );

		/* check whether client IP is known */
		if ( !((iphdr->daddr & gws_args->my_tun_netmask) == gws_args->my_tun_ip &&
				      iph_addr_suffix_h > 0 &&
				      iph_addr_suffix_h < gws_args->my_tun_suffix_mask_h &&
				      gws_args->gw_client_list[ iph_addr_suffix_h ] != NULL ) ) {
						
			dbgf( DBGL_SYS, DBGT_ERR, "got packet for unknown virtual ip %s", ipStr(iphdr->daddr)); 
					
			continue;
		}
		
		gws_args->client_addr.sin_addr.s_addr = gws_args->gw_client_list[ iph_addr_suffix_h ]->addr;

		tp.TP_VERS = COMPAT_VERSION;
		
		tp.TP_TYPE = TUNNEL_DATA;

		if ( sendto( gws_args->sock, &tp.start, tp_len, 0, (struct sockaddr *)&(gws_args->client_addr), sizeof(struct sockaddr_in) ) < 0 ) {
			
			dbgf( DBGL_SYS, DBGT_ERR, "can't send data to client (%s): %s", 
				      ipStr(gws_args->gw_client_list[ iph_addr_suffix_h ]->addr), strerror(errno) );
		}

	}
	
	return;
}

#endif //#ifdef STEPHAN_ENABLE_TWT

static void gws_cleanup( void ) {
		
	my_gw_ext_array_len = 0;
	memset( my_gw_ext_array, 0, sizeof(struct ext_packet) );
	
	if ( gws_args ) {

#ifdef STEPHAN_ENABLE_TWT
		remove_task( gws_garbage_collector, NULL );
#endif //#ifdef STEPHAN_ENABLE_TWT

		if ( gws_args->tun_ifi )
			add_del_route( gws_args->my_tun_ip, gws_args->netmask, 
			               0, 0, gws_args->tun_ifi, gws_args->tun_dev, 254, RTN_UNICAST, DEL, TRACK_TUNNEL );
			
		if ( gws_args->tun_fd ) {
			del_dev_tun( gws_args->tun_fd, gws_args->tun_dev, gws_args->my_tun_ip, __func__ );
#ifdef STEPHAN_ENABLE_TWT
			set_fd_hook( gws_args->tun_fd, gws_recv_tun, YES /*delete*/ );
#endif //#ifdef STEPHAN_ENABLE_TWT
		}
		
		if ( gws_args->sock ) {
			close( gws_args->sock );
			set_fd_hook( gws_args->sock, gws_recv_udp, YES /*delete*/ );
		}
#ifdef STEPHAN_ENABLE_TWT
		if( gws_args->gw_client_list ) {
			
			gws_cleanup_leased_tun_ips( 0, gws_args->gw_client_list, gws_args->my_tun_ip, gws_args->my_tun_netmask );
			debugFree( gws_args->gw_client_list, 1210 );
			
		}
#endif //STEPHAN_ENABLE_TWT

		// critical syntax: may be used for nameserver updates
		dbg( DBGL_CHANGES, DBGT_INFO, "GWT: GW-server tunnel closed - dev: %s  IP: %s/%d  MTU: %d", 
		     gws_args->tun_dev, ipStr( gws_args->my_tun_ip ), gws_args->netmask , gws_args->mtu_min  );
		
		debugFree( gws_args, 1223 );
		gws_args = NULL;
	
        call_script("del", "gws_cleanup");
	}

}


static int32_t gws_init( void ) {
	
	//char str[16], str2[16];
	
	if ( probe_tun() == FAILURE )
		goto gws_init_failure;

	if ( gwc_args || gws_args ) {
		dbg( DBGL_SYS, DBGT_ERR, "gateway client or server already running !");
		goto gws_init_failure;
	}
	
	memset( &tp, 0, sizeof( tp ) );
	
	/* TODO: This needs a better security concept...
	if ( my_gw_port == 0 ) */
	my_gw_port = base_port + 1;
	
	/* TODO: This needs a better security concept...
	if ( my_gw_addr == 0 ) */
	my_gw_addr = primary_addr;

	gws_args = debugMalloc( sizeof( struct gws_args ), 223 );
	memset( gws_args, 0, sizeof( struct gws_args ) );

	gws_args->netmask = gw_tunnel_netmask;
	gws_args->port = my_gw_port;
	gws_args->owt = one_way_tunnel;
#ifdef STEPHAN_ENABLE_TWT
	gws_args->twt = two_way_tunnel;
	gws_args->lease_time = Tun_leasetime;
#endif //#ifdef STEPHAN_ENABLE_TWT
	gws_args->mtu_min = Mtu_min;
	gws_args->my_tun_ip = gw_tunnel_prefix;
	gws_args->my_tun_netmask = htonl( 0xFFFFFFFF<<(32-(gws_args->netmask)) );
	gws_args->my_tun_ip_h = ntohl( gw_tunnel_prefix );
	gws_args->my_tun_suffix_mask_h = ntohl( ~gws_args->my_tun_netmask );
	
	//addr_to_str( gws_args->my_tun_ip, str );
	//addr_to_str( gws_args->my_tun_netmask, str2 );
	
	
	gws_args->client_addr.sin_family = AF_INET;
	gws_args->client_addr.sin_port = htons(gws_args->port);
	
#ifdef STEPHAN_ENABLE_TWT
	if( (gws_args->gw_client_list = debugMalloc( (0xFFFFFFFF>>gw_tunnel_netmask) * sizeof( struct gw_client* ), 210 ) ) == NULL ) {
	
		dbgf( DBGL_SYS, DBGT_ERR, "could not allocate memory for gw_client_list");
		goto gws_init_failure;
	}
	
	memset( gws_args->gw_client_list, 0, (0xFFFFFFFF>>gw_tunnel_netmask) * sizeof( struct gw_client* ) );
#endif //#ifdef STEPHAN_ENABLE_TWT
	if ( (gws_args->sock = socket( PF_INET, SOCK_DGRAM, 0 )) < 0 ) {

		dbg( DBGL_SYS, DBGT_ERR, "can't create tunnel socket: %s", strerror(errno) );
		goto gws_init_failure;

	}

	struct sockaddr_in addr;
	memset( &addr, 0, sizeof( struct sockaddr_in ) );
	addr.sin_family = AF_INET;
	addr.sin_port = htons( my_gw_port );
	addr.sin_addr.s_addr = primary_addr;
	
	if ( bind( gws_args->sock, (struct sockaddr *)&addr, sizeof(struct sockaddr_in) ) < 0 ) {

		dbg( DBGL_SYS, DBGT_ERR, "can't bind tunnel socket: %s", strerror(errno) );
		goto gws_init_failure;

	}
	
	/* make udp socket non blocking */
	int32_t sock_opts;
	if ( (sock_opts = fcntl( gws_args->sock, F_GETFL, 0 )) < 0 ) {
		dbg( DBGL_SYS, DBGT_ERR, "can't get opts of tunnel socket: %s", strerror(errno) );
		goto gws_init_failure;
		
	}
	
	if ( fcntl( gws_args->sock, F_SETFL, sock_opts | O_NONBLOCK ) < 0 ) {
		dbg( DBGL_SYS, DBGT_ERR, "can't set opts of tunnel socket: %s", strerror(errno) );
		goto gws_init_failure;
	}
	
	if ( set_fd_hook( gws_args->sock, gws_recv_udp, NO /*no delete*/ ) < 0 ) {
		dbg( DBGL_SYS, DBGT_ERR, "can't register gws_recv_udp hook" );
		goto gws_init_failure;
	}
	
	if ( (gws_args->tun_fd = add_dev_tun( gws_args->my_tun_ip, gws_args->tun_dev, sizeof(gws_args->tun_dev), 
	                                      &gws_args->tun_ifi, gws_args->mtu_min )) == FAILURE ) {
		dbg( DBGL_SYS, DBGT_ERR, "can't add tun device" );
		goto gws_init_failure;
	}
#ifdef STEPHAN_ENABLE_TWT
	if ( set_fd_hook( gws_args->tun_fd, gws_recv_tun, NO /*no delete*/ ) < 0 ) {
		dbg( DBGL_SYS, DBGT_ERR, "can't register gws_recv_tun hook" );
		goto gws_init_failure;
	}
#endif //#ifdef STEPHAN_ENABLE_TWT
	add_del_route( gws_args->my_tun_ip, gws_args->netmask, 
	               0, 0, gws_args->tun_ifi, gws_args->tun_dev, 254, RTN_UNICAST, ADD, TRACK_TUNNEL );

#ifdef STEPHAN_ENABLE_TWT
	register_task( 5000, gws_garbage_collector, NULL );
#endif //#ifdef STEPHAN_ENABLE_TWT

	memset( my_gw_ext_array, 0, sizeof(struct ext_packet) );
		
	my_gw_ext_array->EXT_FIELD_MSG  = YES;
	my_gw_ext_array->EXT_FIELD_TYPE = EXT_TYPE_64B_GW;
	
        my_gw_ext_array->EXT_GW_FIELD_GWFLAGS = ( (
#ifdef STEPHAN_ENABLE_TWT
                                                      two_way_tunnel ||
#endif //#ifdef STEPHAN_ENABLE_TWT
                                                      one_way_tunnel ) ? Gateway_class : 0 );
        my_gw_ext_array->EXT_GW_FIELD_GWTYPES = ( Gateway_class ? (
#ifdef STEPHAN_ENABLE_TWT
                                                                      (two_way_tunnel?TWO_WAY_TUNNEL_FLAG:0) |
#endif //#ifdef STEPHAN_ENABLE_TWT
                                                                      (one_way_tunnel?ONE_WAY_TUNNEL_FLAG:0) ) : 0);
	
	my_gw_ext_array->EXT_GW_FIELD_GWPORT = htons( my_gw_port );
	my_gw_ext_array->EXT_GW_FIELD_GWADDR = my_gw_addr;
	
	my_gw_ext_array_len = 1;

	// critical syntax: may be used for nameserver updates
	dbg( DBGL_CHANGES, DBGT_INFO, "GWT: GW-server tunnel init succeeded - dev: %s  IP: %s/%d  MTU: %d", 
	     gws_args->tun_dev, ipStr( gws_args->my_tun_ip ), gws_args->netmask , gws_args->mtu_min  );
	
    call_script("gateway","gws_init");

	return SUCCESS;
	
gws_init_failure:
	
	// critical syntax: may be used for nameserver updates
	dbg( DBGL_CHANGES, DBGT_INFO, "GWT: GW-server tunnel init failed" );
	
	gws_cleanup();
		
	return FAILURE;
	
}




static void cb_tun_conf_changed( void *unused ) {
	
	static int32_t prev_routing_class = 0;
	static int32_t prev_one_way_tunnel = 0;
#ifdef STEPHAN_ENABLE_TWT
	static int32_t prev_two_way_tunnel = 0;
#endif //#ifdef STEPHAN_ENABLE_TWT
	static int32_t prev_gateway_class = 0;
//	static uint32_t prev_pref_gateway = 0;
	static uint32_t prev_primary_ip = 0;
	static int32_t prev_mtu_min = 0;
	static struct gw_node *prev_curr_gateway = NULL;
	
	if ( prev_one_way_tunnel    != one_way_tunnel        ||
#ifdef STEPHAN_ENABLE_TWT
	     prev_two_way_tunnel    != two_way_tunnel        ||
#endif //#ifdef STEPHAN_ENABLE_TWT
	     prev_primary_ip        != primary_addr   ||
	     prev_mtu_min           != Mtu_min               ||
	     prev_curr_gateway      != curr_gateway          || 
	     (prev_routing_class?1:0) != (routing_class?1:0) ||
	     prev_gateway_class	    != Gateway_class         ||
	     (curr_gateway  &&  !gwc_args)
	   ) {

		if ( gws_args )
			gws_cleanup();
	
		if ( gwc_args )
			gwc_cleanup();
		
                if ( primary_addr  &&  (one_way_tunnel
#ifdef STEPHAN_ENABLE_TWT
                                        || two_way_tunnel
#endif //#ifdef STEPHAN_ENABLE_TWT
                                        ) ) {
		
			if ( routing_class  &&  curr_gateway ) {
			
				gwc_init();
			
			} else if ( Gateway_class  ) {
			
				gws_init();
			
			}
			
		}
	
		prev_one_way_tunnel = one_way_tunnel;
#ifdef STEPHAN_ENABLE_TWT
		prev_two_way_tunnel = two_way_tunnel;
#endif //#ifdef STEPHAN_ENABLE_TWT
//		prev_pref_gateway   = pref_gateway;
		prev_primary_ip     = primary_addr;
		prev_mtu_min        = Mtu_min;
		prev_curr_gateway   = curr_gateway;
		prev_routing_class  = routing_class;
		prev_gateway_class  = Gateway_class;
	
	}
	
	return;
}

static void cb_tun_orig_flush( void *data ) {
	
	struct orig_node *on = data;
	
	if ( on->plugin_data[ tun_orig_registry ] )
		update_gw_list( on, 0, NULL );
	
}


static void cb_choose_gw( void* unused ) {

	struct list_head *pos;
	struct gw_node *gw_node, *tmp_curr_gw = NULL;
	/* TBD: check the calculations of this variables for overflows */
	uint8_t max_gw_class = 0;
	uint32_t best_wa_val = 0;  
	uint32_t max_gw_factor = 0, tmp_gw_factor = 0;  
	int download_speed, upload_speed; 
	
	register_task( 1000, cb_choose_gw, NULL );

	if ( routing_class == 0  ||  curr_gateway ||
	     ((routing_class == 1 || routing_class == 2 ) && 
	      ( batman_time_sec < (COMMON_OBSERVATION_WINDOW/1000)  )) ) {

		return;
	}
	
	
	list_for_each( pos, &gw_list ) {

		gw_node = list_entry( pos, struct gw_node, list );

		if( gw_node->unavail_factor > MAX_GW_UNAVAIL_FACTOR )
			gw_node->unavail_factor = MAX_GW_UNAVAIL_FACTOR;

		/* ignore this gateway if recent connection attempts were unsuccessful */
		if ( GREAT_U32( ((gw_node->unavail_factor * gw_node->unavail_factor * GW_UNAVAIL_TIMEOUT) + gw_node->last_failure), batman_time ) )
			continue;
	
		struct orig_node *on = gw_node->orig_node;
		struct tun_orig_data *tuno = on->plugin_data[ tun_orig_registry ];

		if ( !on->router  ||  !tuno )
			continue;

                if ( !( tuno->tun_array[0].EXT_GW_FIELD_GWTYPES & (
#ifdef STEPHAN_ENABLE_TWT
                            (two_way_tunnel?TWO_WAY_TUNNEL_FLAG:0) |
#endif //#ifdef STEPHAN_ENABLE_TWT
                            (one_way_tunnel?ONE_WAY_TUNNEL_FLAG:0) ) ) )
			continue;
	
		switch ( routing_class ) {

			case 1:   /* fast connection */
				get_gw_speeds( tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS, &download_speed, &upload_speed );

		// is this voodoo ???
			tmp_gw_factor = ( ( ( on->router->longtm_sqr.wa_val/PROBE_TO100 ) *
			                    ( on->router->longtm_sqr.wa_val/PROBE_TO100 ) ) ) *
						( download_speed / 64 ) ;
		
				if ( tmp_gw_factor > max_gw_factor || 
				     ( tmp_gw_factor == max_gw_factor  && 
				       on->router->longtm_sqr.wa_val > best_wa_val ) )
					tmp_curr_gw = gw_node;
		
				break;

				case 2:   /* stable connection (use best statistic) */
				     if ( on->router->longtm_sqr.wa_val > best_wa_val )
					     tmp_curr_gw = gw_node;
					break;

					default:  /* fast-switch (use best statistic but change as soon as a better gateway appears) */
				     if ( on->router->longtm_sqr.wa_val > best_wa_val )
							tmp_curr_gw = gw_node;
						break;

		}

		if ( tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS > max_gw_class )
			max_gw_class = tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS;

		best_wa_val = MAX( best_wa_val, on->router->longtm_sqr.wa_val );
		
		
		if ( tmp_gw_factor > max_gw_factor )
			max_gw_factor = tmp_gw_factor;

		if ( ( pref_gateway != 0 ) && ( pref_gateway == on->orig ) ) {

			tmp_curr_gw = gw_node;

	
			dbg( DBGL_SYS, DBGT_INFO, 
			     "Preferred gateway found: %s (gw_flags: %i, packet_count: %i, ws: %i, gw_product: %i)", 
			     on->orig_str, tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS, 
			     on->router->longtm_sqr.wa_val/PROBE_TO100, on->pws, tmp_gw_factor );
	
			break;

		}

	}
	
	
	if ( curr_gateway != tmp_curr_gw ) {

		if ( curr_gateway != NULL )
			dbg( DBGL_CHANGES, DBGT_INFO, "removing old default route" );

		/* may be the last gateway is now gone */
		if ( tmp_curr_gw != NULL ) {

			dbg( DBGL_SYS, DBGT_INFO, "using new default tunnel to GW %s (gw_flags: %i, packet_count: %i, gw_product: %i)",
			     tmp_curr_gw->orig_node->orig_str, max_gw_class, best_wa_val/PROBE_TO100, max_gw_factor );

		}

		curr_gateway = tmp_curr_gw;
		gwc_cleanup();

		cb_plugin_hooks( NULL, PLUGIN_CB_CONF );

	}
	
	
}


static int32_t cb_send_my_tun_ext( unsigned char* ext_buff ) {
	
	memcpy( ext_buff, (unsigned char *)my_gw_ext_array, my_gw_ext_array_len * sizeof(struct ext_packet) );
	
	return my_gw_ext_array_len * sizeof(struct ext_packet);

}



static int32_t opt_gateways ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	uint16_t batman_count = 0;

	struct list_head *orig_pos;
	struct gw_node *gw_node;
	int download_speed, upload_speed;

	if ( cmd != OPT_APPLY )
		return SUCCESS;
	
	if ( list_empty( &gw_list ) ) {

		dbg_printf( cn, "No gateways in range ...  preferred gateway: %s \n", ipStr(pref_gateway) );

	} else {

		dbg_printf( cn, "%12s     %15s   #         preferred gateway: %s \n", "Originator", "bestNextHop", ipStr(pref_gateway) );  

		list_for_each( orig_pos, &gw_list ) {

			gw_node = list_entry( orig_pos, struct gw_node, list );
			
			struct orig_node *on = gw_node->orig_node;
			struct tun_orig_data *tuno = on->plugin_data[ tun_orig_registry ];

			if ( !tuno || on->router == NULL )
				continue;

			get_gw_speeds( tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS, &download_speed, &upload_speed );
			
			dbg_printf( cn, "%s %-15s %15s %3i, %i%s/%i%s, reliability: %i, tunnel %s, %s \n",
				(gwc_args && curr_gateway == gw_node) ? "=>" : "  ",
				ipStr(on->orig) , ipStr(on->router->nnkey_addr),
			        gw_node->orig_node->router->longtm_sqr.wa_val/PROBE_TO100,
				download_speed > 2048 ? download_speed / 1024 : download_speed,
				download_speed > 2048 ? "MBit" : "KBit",
				upload_speed > 2048 ? upload_speed / 1024 : upload_speed,
				upload_speed > 2048 ? "MBit" : "KBit",
				gw_node->unavail_factor,
				(tuno->tun_array[0].EXT_GW_FIELD_GWTYPES & TWO_WAY_TUNNEL_FLAG)?"2WT":"-",
				(tuno->tun_array[0].EXT_GW_FIELD_GWTYPES & ONE_WAY_TUNNEL_FLAG)?"1WT":"-" );
			
			batman_count++;

		}

		if ( batman_count == 0 )
			dbg( DBGL_GATEWAYS, DBGT_NONE, "No gateways in range..." );
		
		dbg_printf( cn, "\n" );
	}


	return SUCCESS;
}


static int32_t opt_gwtun_netw ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	uint32_t ip = 0;
	int32_t mask = 0;
	
	if ( cmd == OPT_REGISTER ) {
		
		inet_pton( AF_INET, DEF_GWTUN_NETW_PREFIX, &gw_tunnel_prefix );
		gw_tunnel_netmask = DEF_GWTUN_NETW_MASK;
		
	} else if ( cmd == OPT_CHECK  || cmd == OPT_APPLY ) {
		
		if ( str2netw( patch->p_val, &ip, '/', cn, &mask, 32 ) == FAILURE || 
		     mask < MIN_GWTUN_NETW_MASK || mask > MAX_GWTUN_NETW_MASK )
			return FAILURE;
		
		if ( ip != validate_net_mask( ip, mask, cmd==OPT_CHECK?cn:0 ) )
			return FAILURE;
		
		if ( cmd == OPT_APPLY ) {
			gw_tunnel_prefix = ip;
			gw_tunnel_netmask = mask;
		}

	}
	
	return SUCCESS;
}


static int32_t opt_rt_class ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	if ( cmd == OPT_APPLY ) {
		
		if ( /* Gateway_class  && */ routing_class )
			check_apply_parent_option( DEL, OPT_APPLY, _save, get_option(0,0,ARG_GW_CLASS), 0, cn );
	
	}
	
	return SUCCESS;
}


static int32_t opt_rt_pref ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	uint32_t test_ip;
	
	if ( cmd == OPT_CHECK  ||  cmd == OPT_APPLY ) {
		
		if ( patch->p_diff == DEL )
			test_ip = 0;
		
		else if ( str2netw( patch->p_val, &test_ip, '/', cn, NULL, 0 ) == FAILURE  )
			return FAILURE;
		
		
		if (  cmd == OPT_APPLY ) {

			pref_gateway = test_ip;
		
			/* use routing class 3 if none specified */
/*
			if ( pref_gateway && !routing_class && !Gateway_class )
				check_apply_parent_option( ADD, OPT_APPLY, _save, get_option(0,0,ARG_RT_CLASS), "3", cn );
*/
			
		}
		
	}
	
	return SUCCESS;
}
	
static int32_t opt_gw_class ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	char gwarg[30];
	int32_t download_speed = 0, upload_speed = 0, gateway_class;
	char *slashp = NULL;
	
 	if ( cmd == OPT_CHECK  ||  cmd == OPT_APPLY  ||  cmd == OPT_ADJUST ) {
		
		if ( patch->p_diff == DEL ) {
			
			download_speed = 0;
		
		} else {
		
			if ( wordlen( patch->p_val ) <= 0 || wordlen( patch->p_val ) > 29 )
				return FAILURE;
		
			snprintf( gwarg, wordlen(patch->p_val)+1, "%s", patch->p_val );
		
			if ( ( slashp = strchr( gwarg, '/' ) ) != NULL )
				*slashp = '\0';
		
			errno = 0;
			download_speed = strtol( gwarg, NULL, 10 );
				
			if ( ( errno == ERANGE ) || ( errno != 0 && download_speed == 0 ) )
				return FAILURE;
		
			if ( wordlen( gwarg ) > 4  &&  strncasecmp( gwarg + wordlen( gwarg ) - 4, "mbit", 4 ) == 0 )
				download_speed *= 1024;
	
			if ( slashp ) {
		
				errno = 0;
				upload_speed = strtol( slashp + 1, NULL, 10 );
		
				if ( ( errno == ERANGE ) || ( errno != 0 && upload_speed == 0 ) )
					return FAILURE;
		
				slashp++;
				
				if ( strlen( slashp ) > 4  &&  strncasecmp( slashp + wordlen( slashp ) - 4, "mbit", 4 ) == 0 )
					upload_speed *= 1024;
		
			}
	
			if ( ( download_speed > 0 ) && ( upload_speed == 0 ) )
				upload_speed = download_speed / 5;
		
		}
	
		if ( download_speed > 0 ) {
			
			gateway_class = get_gw_class( download_speed, upload_speed );
			get_gw_speeds( gateway_class, &download_speed, &upload_speed );
			
		} else {
			
			gateway_class = download_speed = upload_speed = 0;
		}
		
        sprintf( gwarg, "%u%s/%u%s",
		         ( download_speed > 2048 ? download_speed / 1024 : download_speed ), 
		         ( download_speed > 2048 ? "MBit" : "KBit" ), 
		         ( upload_speed > 2048 ? upload_speed / 1024 : upload_speed ), 
		         ( upload_speed > 2048 ? "MBit" : "KBit" ) );
		
		
		if ( cmd == OPT_ADJUST ) {
			
			set_opt_parent_val( patch, gwarg );
		
		
		} else if ( cmd == OPT_APPLY ) {
		
			Gateway_class = gateway_class;
			
			if ( gateway_class  /*&&  routing_class*/ )
				check_apply_parent_option( DEL, OPT_APPLY, _save, get_option(0,0,ARG_RT_CLASS), 0, cn );
	
			dbg( DBGL_SYS, DBGT_INFO, "gateway class: %i -> propagating: %s", gateway_class, gwarg );
		}
	
	}
	
	return SUCCESS;
	
}





static struct opt_type tunnel_options[]= {
//        ord parent long_name          shrt Attributes				*ival		min		max		default		*func,*syntax,*help
	{ODI,5,0,0,			0,  0,0,0,0,0,				0,		0,		0,		0,		0,0,
			"\nGateway (GW) and tunnel options:"},
 
	{ODI,5,0,ARG_RT_CLASS,	 	'r',A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&routing_class,	0,		3,		0, 		opt_rt_class,
			ARG_VALUE_FORM,"control GW-client functionality:\n"
			"	0 -> no tunnel, no default route (default)\n"
			"	1 -> permanently select fastest GW according to GW announcment (deprecated)\n"
			"	2 -> permanently select most stable GW accoridng to measurement \n"
			"	3 -> dynamically switch to most stable GW"},
 
	{ODI,5,0,ARG_GW_HYSTERESIS, 	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&gw_hysteresis,	MIN_GW_HYSTERE,	MIN_GW_HYSTERE,	DEF_GW_HYSTERE,	0,
			ARG_VALUE_FORM,"set number of additional rcvd OGMs before changing to more stable GW (only relevant for -r3 GW-clients)"},
	
	{ODI,5,0,"preferred_gateway",	'p',A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0,		0,		0, 		opt_rt_pref,
			ARG_ADDR_FORM,"permanently select specified GW if available"},
 
	{ODI,5,0,ARG_GW_CLASS,	 	'g',A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0,		0,		0, 		opt_gw_class,
			ARG_VALUE_FORM"[/VAL]","set GW up- & down-link class (e.g. 5mbit/1024kbit)"},
 
	{ODI,5,0,ARG_ONE_WAY_TUNNEL, 	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&one_way_tunnel,0, 		4,		1, 		0,
			ARG_VALUE_FORM,"set preference for one-way-tunnel (OWT) mode over other tunnel modes:\n"
			"	For GW nodes: 0 disables OWT mode, a larger value enables this mode.\n"
			"	For GW-client nodes: 0 disables OWT mode, a larger value sets the preference for this mode."},
 #ifdef STEPHAN_ENABLE_TWT
	{ODI,5,0,ARG_TWO_WAY_TUNNEL, 	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&two_way_tunnel,0, 		4,		2, 		0,
			ARG_VALUE_FORM,"set preference for two-way-tunnel (TWT) mode over other tunnel modes:\n"
			"	For GW nodes: 0 disables TWT mode, a larger value enables this mode.\n"
			"	For GW-client nodes: 0 disables TWT mode, a larger value sets the preference for this mode."},

 
	{ODI,5,0,ARG_UNRESP_GW_CHK,	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&unresp_gw_chk,	0, 		1,		1, 		0,
			ARG_VALUE_FORM,"disable/enable unresponsive GW check (only relevant for GW clients in TWT mode)"},

#ifndef LESS_OPTIONS
	{ODI,5,0,ARG_TUN_LTIME, 	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&Tun_leasetime, MIN_TUN_LTIME, MAX_TUN_LTIME,	DEF_TUN_LTIME, 0,
			ARG_VALUE_FORM,"set leasetime in seconds of virtual two-way-tunnel IPs"},
#endif
#endif //#ifdef STEPHAN_ENABLE_TWT

	{ODI,4,0,ARG_GWTUN_NETW,	0,  A_PS1,A_ADM,A_INI,A_CFA,A_ANY,	0,		0, 		0,		0, 		opt_gwtun_netw,
                        ARG_PREFIX_FORM,"set network used by gateway nodes\n"},

#ifndef LESS_OPTIONS
	{ODI,5,0,"tun_persist", 	0,  A_PS1,A_ADM,A_INI,A_CFA,A_ANY,	&Tun_persist, 	0,		1,		DEF_TUN_PERSIST,0,
			ARG_VALUE_FORM,"disable/enable ioctl TUNSETPERSIST for GW tunnels (disabling was required for openVZ emulation)" },
#endif
 
	{ODI,5,0,ARG_GATEWAYS,		0,  A_PS0,A_USR,A_DYN,A_ARG,A_END,	0,		0, 		0,		0, 		opt_gateways,0,
			"show currently available gateways\n"}
};


static void tun_cleanup( void ) {
	
	set_snd_ext_hook( EXT_TYPE_64B_GW, cb_send_my_tun_ext, DEL );
	
	set_ogm_hook( cb_tun_ogm_hook, DEL );
	
	if ( gws_args )
		gws_cleanup();
	
	if ( gwc_args )
		gwc_cleanup();
		
}


static int32_t tun_init( void ) {
	
	register_options_array( tunnel_options, sizeof( tunnel_options ) );
	
	if ( ( tun_orig_registry = reg_plugin_data( PLUGIN_DATA_ORIG ) ) < 0 )
		return FAILURE;
	
	set_ogm_hook( cb_tun_ogm_hook, ADD );
	
	set_snd_ext_hook( EXT_TYPE_64B_GW, cb_send_my_tun_ext, ADD );
	
	register_task( 1000, cb_choose_gw, NULL );
	
	cb_tun_conf_changed( NULL );
	
	return SUCCESS;
	
}



struct plugin_v1 *tun_get_plugin_v1( void ) {
	
	static struct plugin_v1 tun_plugin_v1;
	memset( &tun_plugin_v1, 0, sizeof ( struct plugin_v1 ) );
	
	tun_plugin_v1.plugin_version = PLUGIN_VERSION_01;
	tun_plugin_v1.plugin_size = sizeof ( struct plugin_v1 );
	tun_plugin_v1.plugin_name = "bmx_tunnel_plugin";
	tun_plugin_v1.cb_init = tun_init;
	tun_plugin_v1.cb_cleanup = tun_cleanup;
	
	tun_plugin_v1.cb_plugin_handler[PLUGIN_CB_CONF] = cb_tun_conf_changed;
	tun_plugin_v1.cb_plugin_handler[PLUGIN_CB_ORIG_FLUSH] = cb_tun_orig_flush;
	tun_plugin_v1.cb_plugin_handler[PLUGIN_CB_ORIG_DESTROY] = cb_tun_orig_flush;
	
	return &tun_plugin_v1;
	
}


#endif

