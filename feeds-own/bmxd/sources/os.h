/*
 * Copyright (C) 2006 BATMAN contributors:
 * Thomas Lopatic, Marek Lindner, Axel Neumann
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

#ifndef _BATMAN_OS_H
#define _BATMAN_OS_H


# define timercpy(d, a) (d)->tv_sec = (a)->tv_sec; (d)->tv_usec = (a)->tv_usec; 


/* posix.c */

enum {
	CLEANUP_SUCCESS,
	CLEANUP_FAILURE,
	CLEANUP_MY_SIGSEV,
	CLEANUP_RETURN
};

void bat_wait( uint32_t sec, uint32_t msec );

#ifndef NOTRAILER
void print_animation( void );
#endif

int8_t send_udp_packet( unsigned char *packet_buff, int32_t packet_buff_len, struct sockaddr_in *dst, int32_t send_sock );

void cleanup_all( int status );

/*
 * PARANOIA ERROR CODES:
 * Negative numbers are used as SIGSEV error codes !
 * Currently used numbers are
 * for core programs:		-500000 ... -500198
 */
#ifdef NOPARANOIA
#define paranoia( ... )
#else
#define paranoia( code , problem ); do { if ( problem ) { cleanup_all( code ); } }while(0)
#endif



void update_batman_time( struct timeval *precise_tv );

char *get_human_uptime( uint32_t reference );

#ifndef NODEPRECATED
void fake_start_time( int32_t fake );
#endif


int32_t rand_num( uint32_t limit );


int8_t is_aborted();
//void handler( int32_t sig );
//void restore_and_exit( uint8_t is_sigsegv );

uint8_t get_set_bits( uint32_t v );




/* route.c */

#define DEV_LO "lo"
#define DEV_UNKNOWN "unknown"

#define	MIN_MASK	1
#define	MAX_MASK	32
#define ARG_MASK	"netmask"
#define ARG_NETW	"network"

extern int32_t base_port;
#define ARG_BASE_PORT "base_port"
#define DEF_BASE_PORT 4305
#define MIN_BASE_PORT 1025
#define MAX_BASE_PORT 60000




/***
 *
 * Things you should leave as is unless your know what you are doing !
 *
 * RT_TABLE_HOSTS	routing table for routes towards originators
 * RT_TABLE_NETWORKS	routing table for announced networks
 * RT_TABLE_TUNNEL	routing table for the tunnel towards the internet gateway
 * RT_PRIO_DEFAULT	standard priority for routing rules
 * RT_PRIO_UNREACH	standard priority for unreachable rules
 * RT_PRIO_TUNNEL	standard priority for tunnel routing rules
 *
 ***/

#define RT_TABLE_HOSTS      -1
#define RT_TABLE_NETWORKS   -2
#define RT_TABLE_TUNNEL     -3



extern uint8_t if_conf_soft_changed; // temporary enabled to trigger changed interface configuration
extern uint8_t if_conf_hard_changed; // temporary enabled to trigger changed interface configuration

extern int Mtu_min;


struct routes_node {
	struct list_head list;
	uint32_t dest;
	uint16_t netmask;
	uint16_t rt_table;
	int16_t rta_type;
	int8_t track_t;
};


struct rules_node {
	struct list_head list;
	uint32_t prio;
	char *iif;
	uint32_t network;
	int16_t netmask;
	int16_t rt_table;
	int16_t rta_type;
	int8_t track_t;
};



//track types:
enum {
	TRACK_NO,
	TRACK_STANDARD,    //basic rules to interfaces, host, and networks routing tables
	TRACK_MY_HNA,
	TRACK_MY_NET,
	TRACK_OTHER_HOST,
	TRACK_OTHER_HNA, 
	TRACK_TUNNEL
};

void add_del_route( uint32_t dest, int16_t mask, uint32_t gw, uint32_t src, int32_t ifi, char *dev,
                    int16_t rt_table_macro, int16_t rta_type, int8_t del, int8_t track_t );

/***
 *
 * rule types: 0 = RTA_SRC, 1 = RTA_DST, 2 = RTA_IIF
#define RTA_SRC 0
#define RTA_DST 1
#define RTA_IIF 2
 *
 ***/
 
// void add_del_rule( uint32_t network, uint8_t netmask, int16_t rt_macro, uint32_t prio, char *iif, int8_t rule_type, int8_t del, int8_t track_t );

enum {
 IF_RULE_SET_TUNNEL,
 IF_RULE_CLR_TUNNEL,
 IF_RULE_SET_NETWORKS,
 IF_RULE_CLR_NETWORKS,
 IF_RULE_UPD_ALL,
 IF_RULE_CHK_IPS
};

int update_interface_rules( uint8_t cmd );


void check_kernel_config( struct batman_if *batman_if );

//int8_t bind_to_iface( int32_t sock, char *dev );

//int is_interface_up(char *dev);
void if_deactivate ( struct batman_if *batman_if );
void check_interfaces ();

void init_route( void );
void init_route_args( void );
void cleanup_route( void );


/* hna.c */

#define ARG_HNAS "hnas"


/* tunnel.c */

extern int32_t Gateway_class;
#define ARG_GWTUN_NETW "gateway_tunnel_network"
#define ARG_GATEWAYS "gateways"

#define ARG_RT_CLASS "routing_class"
#define ARG_GW_CLASS "gateway_class"

#ifndef	NOTUNNEL
struct plugin_v1 *tun_get_plugin_v1( void );
#endif

#endif
