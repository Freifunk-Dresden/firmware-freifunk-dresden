/*
 * Copyright (C) 2006 B.A.T.M.A.N. contributors:
 * Thomas Lopatic, Corinna 'Elektra' Aichele, Axel Neumann,
 * Felix Fietkau, Marek Lindner
 *
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



#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <unistd.h>

#include "batman.h"
#include "os.h"
#include "originator.h"
#include "metrics.h"
#include "plugin.h"
#include "schedule.h"
//#include "avl.h"






uint32_t My_pid = 0;


uint8_t ext_attribute[EXT_TYPE_MAX+1] = 
{ 
	EXT_ATTR_KEEP, 			// EXT_TYPE_64B_GW
	0, 				// EXT_TYPE_64B_HNA
	0, 				// EXT_TYPE_64B_PIP
	EXT_ATTR_KEEP, 			// EXT_TYPE_64B_SRV
	EXT_ATTR_KEEP, 			// EXT_TYPE_64B_KEEP_RESERVED4
	0, 				// EXT_TYPE_64B_DROP_RESERVED5
	EXT_ATTR_TLV|EXT_ATTR_KEEP, 	// EXT_TYPE_TLV_KEEP_LOUNGE_REQ
	EXT_ATTR_TLV, 			// EXT_TYPE_TLV_DROP_RESERVED7
	EXT_ATTR_KEEP, 			// EXT_TYPE_64B_KEEP_RESERVED8
	0, 				// EXT_TYPE_64B_DROP_RESERVED9
	EXT_ATTR_TLV|EXT_ATTR_KEEP, 	// EXT_TYPE_TLV_KEEP_RESERVED10
	EXT_ATTR_TLV, 			// EXT_TYPE_TLV_DROP_RESERVED11
	EXT_ATTR_KEEP, 			// EXT_TYPE_64B_KEEP_RESERVED12
	0, 				// EXT_TYPE_64B_DROP_RESERVED13
	EXT_ATTR_TLV|EXT_ATTR_KEEP, 	// EXT_TYPE_TLV_KEEP_RESERVED14
	EXT_ATTR_TLV 			// EXT_TYPE_TLV_DROP_RESERVED15
};


int32_t Gateway_class = 0;

//uint8_t Link_flags = 0;

uint32_t batman_time = 0;
uint32_t batman_time_sec = 0;

uint8_t on_the_fly = NO;

uint32_t s_curr_avg_cpu_load = 0;

void batman( void ) {

	struct list_head *list_pos;
	struct batman_if *batman_if;
	uint32_t regular_timeout, statistic_timeout;

	uint32_t s_last_cpu_time = 0, s_curr_cpu_time = 0;
	
	regular_timeout = statistic_timeout = batman_time;
	
	on_the_fly = YES;

	prof_start( PROF_all );
	
	while ( !is_aborted() ) {
		
		prof_stop( PROF_all );
		prof_start( PROF_all );

		uint32_t wait = whats_next( );
		
		if ( wait )
			wait4Event( MIN( wait, MAX_SELECT_TIMEOUT_MS ) );
		
		// The regular tasks...
		if ( LESS_U32( regular_timeout + 1000,  batman_time ) ) {
	
			purge_orig( batman_time, NULL );
			
			close_ctrl_node( CTRL_CLEANUP, 0 );
			
			list_for_each( list_pos, &dbgl_clients[DBGL_ALL] ) {
				
				struct ctrl_node *cn = (list_entry( list_pos, struct dbgl_node, list ))->cn;
				
				dbg_printf( cn, "------------------ DEBUG ------------------ \n" );
				
				debug_send_list( cn );
				
				check_apply_parent_option( ADD, OPT_APPLY, 0, get_option( 0, 0, ARG_STATUS ), 0, cn );
				check_apply_parent_option( ADD, OPT_APPLY, 0, get_option( 0, 0, ARG_LINKS ), 0, cn );
				check_apply_parent_option( ADD, OPT_APPLY, 0, get_option( 0, 0, ARG_ORIGINATORS ), 0, cn );
				check_apply_parent_option( ADD, OPT_APPLY, 0, get_option( 0, 0, ARG_HNAS ), 0, cn );
				check_apply_parent_option( ADD, OPT_APPLY, 0, get_option( 0, 0, ARG_GATEWAYS ), 0, cn );
				check_apply_parent_option( ADD, OPT_APPLY, 0, get_option( 0, 0, ARG_SERVICES ), 0, cn );
				
				dbg_printf( cn, "--------------- END DEBUG ---------------\n" );
				
			}
			
			/* preparing the next debug_timeout */
			regular_timeout = batman_time;
		}
		
			
		if ( LESS_U32( statistic_timeout + 5000, batman_time ) ) {
		
			// check for corrupted memory..
			checkIntegrity();
			
			// check for changed kernel konfigurations...
			check_kernel_config( NULL );
			
			// check for changed interface konfigurations...
			list_for_each( list_pos, &if_list ) {
				
				batman_if = list_entry( list_pos, struct batman_if, list );

				if ( batman_if->if_active )
					check_kernel_config( batman_if );
				
			}
			
			/* generating cpu load statistics... */
			s_curr_cpu_time = (uint32_t)clock();
			
			s_curr_avg_cpu_load = ( (s_curr_cpu_time - s_last_cpu_time) / (uint32_t)(batman_time - statistic_timeout) );
			
			s_last_cpu_time = s_curr_cpu_time;
		
			statistic_timeout = batman_time;
		}
			
			
		
	}

	prof_stop( PROF_all );
}



/*some static plugins*/

#ifndef NOVIS 

static struct vis_if *vis_if = NULL;

static unsigned char *vis_packet = NULL;
static uint16_t vis_packet_size = 0;
static int32_t vis_port = DEF_VIS_PORT;

static void send_vis_packet( void *unused ) {
	
	struct vis_if *vis = vis_if;
	struct list_head *list_pos;
	struct batman_if *batman_if;
	//struct hna_node *hna_node;
	
	struct link_node *link_node;
	struct list_head *link_pos;

	struct list_head  *lndev_pos;
	
	if( !vis  ||  !vis->sock )
		return;
	
	if ( vis_packet ) {
		debugFree( vis_packet, 1102 );
		vis_packet = NULL;
		vis_packet_size = 0;
	}

	vis_packet_size = sizeof(struct vis_packet);
	vis_packet = debugMalloc( vis_packet_size, 104 );
	
	((struct vis_packet *)vis_packet)->sender_ip = primary_addr;
	((struct vis_packet *)vis_packet)->version = VIS_COMPAT_VERSION;
	((struct vis_packet *)vis_packet)->gw_class = Gateway_class;
	((struct vis_packet *)vis_packet)->seq_range = (PROBE_RANGE/PROBE_TO100);

        dbgf_all(DBGT_INFO, "sender_ip=%s version=%d gw_class=%d seq_range=%d",
                ipStr(primary_addr), VIS_COMPAT_VERSION, Gateway_class, (PROBE_RANGE/PROBE_TO100));
	
	/* iterate link list */
	list_for_each( link_pos, &link_list ) {

		link_node = list_entry(link_pos, struct link_node, list);
		
		if ( link_node->orig_node->router == NULL )
			continue;
		
		uint32_t q_max = 0;
                struct vis_data *vis_data = NULL;
		
		list_for_each( lndev_pos, &link_node->lndev_list ) {
		
			struct link_node_dev *lndev = list_entry( lndev_pos, struct link_node_dev, list );

                        if (!lndev->rq_sqr.wa_val)
                                continue;

			if ( !vis_data ) {

				vis_packet_size += sizeof(struct vis_data);
		
				vis_packet = debugRealloc( vis_packet, vis_packet_size, 105 );
		
				vis_data = (struct vis_data *)
					(vis_packet + vis_packet_size - sizeof(struct vis_data));
		
                        }

                        if (vis_data && lndev->rq_sqr.wa_val > q_max) {

				vis_data->ip = link_node->orig_node->orig;
				vis_data->data = lndev->rq_sqr.wa_val/PROBE_TO100;
				vis_data->type = DATA_TYPE_NEIGH;

                                dbgf_all(DBGT_INFO, "link to NB=%s lq=%d (dev=%s)",
                                        ipStr(link_node->orig_node->orig), lndev->rq_sqr.wa_val, lndev->bif->dev);

			}

                        q_max = MAX(lndev->rq_sqr.wa_val, q_max);

		}
	}

	
	/* secondary interfaces */

	list_for_each( list_pos, &if_list ) {
	
		batman_if = list_entry( list_pos, struct batman_if, list );
	
		if ( ((struct vis_packet *)vis_packet)->sender_ip == batman_if->if_addr )
			continue;

                if (!batman_if->if_active)
			continue;

		vis_packet_size += sizeof(struct vis_data);
	
		vis_packet = debugRealloc( vis_packet, vis_packet_size, 106 );

                struct vis_data *vis_data = (struct vis_data *) (vis_packet + vis_packet_size - sizeof (struct vis_data));
	
		vis_data->ip = batman_if->if_addr;
	
		vis_data->data = 0;
		vis_data->type = DATA_TYPE_SEC_IF;

                dbgf_all(DBGT_INFO, "interface %s (dev=%s)", ipStr(batman_if->if_addr), batman_if->dev);
	
	}

	/*
#ifndef NOHNA 
	// hna announcements
	struct hash_it_t *hashit = NULL;
	
	// for all hna_hash_nodes... 
	while ( (hashit = hash_iterate( hna_hash, hashit )) ) {
		
		struct hna_hash_node *hhn = hashit->bucket->data;
		
		if ( hhn->status == HNA_HASH_NODE_MYONE ) {
			
			vis_packet_size += sizeof(struct vis_data);
			
			vis_packet = debugRealloc( vis_packet, vis_packet_size, 107 );
			
			vis_data = (struct vis_data *)(vis_packet + vis_packet_size - sizeof(struct vis_data));
			
			vis_data->ip = hhn->key.addr;
			vis_data->data = hhn->key.KEY_FIELD_ANETMASK;
			vis_data->type = DATA_TYPE_HNA;
		}
	}
#endif 
	*/
	
	if ( vis_packet_size == sizeof(struct vis_packet) ) {

		debugFree( vis_packet, 1107 );
		vis_packet = NULL;
		vis_packet_size = 0;

	}

	if ( vis_packet != NULL )
		send_udp_packet( vis_packet, vis_packet_size, &vis->addr, vis->sock );

	
	register_task( 10000, send_vis_packet, NULL );
	
}

static int32_t opt_vis ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	uint32_t vis_ip = 0;
	
	if ( cmd == OPT_CHECK  ||  cmd == OPT_APPLY ) {
		
		if ( patch->p_diff == DEL )
			vis_ip = 0;
		
		else if ( str2netw( patch->p_val, &vis_ip, '/', cn, NULL, 0 ) == FAILURE  )
			return FAILURE;
	}
		
	if ( cmd == OPT_APPLY  &&  vis_ip ) {
		
		remove_task( send_vis_packet, NULL );

		if ( vis_if  &&  vis_if->sock )
			close( vis_if->sock );
		
		if ( !vis_if )
			vis_if = debugMalloc( sizeof( struct vis_if ), 731 );

		memset( vis_if, 0, sizeof( struct vis_if ) );

		vis_if->addr.sin_family = AF_INET;
		vis_if->addr.sin_port = htons( vis_port );
		vis_if->addr.sin_addr.s_addr = vis_ip;
		vis_if->sock = socket( PF_INET, SOCK_DGRAM, 0 );

		register_task( 1000, send_vis_packet, NULL );
	}
	
	
	if ( ( cmd == OPT_APPLY  &&  !vis_ip ) || cmd == OPT_UNREGISTER ) {

		remove_task( send_vis_packet, NULL );

		if ( vis_if ) {
	
			if ( vis_if->sock )
				close( vis_if->sock );
	
			debugFree( vis_if, 1731 );
			vis_if = NULL;
		
		}	
		
		if ( vis_packet ) {
			
			debugFree( vis_packet, 1108 );
			vis_packet = NULL;
		}
		
	}
	
	return SUCCESS;
}


static struct opt_type vis_options[]= {
//           		ord parent long_name   shrt Attributes			*ival		min		max		default		*function
	{ODI,5,0,0,			0,  0,0,0,0,0,				0,		0,		0,		0,		0,0,
			"\nVisualization options:"},
 
	{ODI,5,0,"vis_server",		's',A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0,		0,		0, 		opt_vis,
			ARG_ADDR_FORM,"set IP of visualization server"}

};



static void vis_cleanup( void ) {
}


static int32_t vis_init( void ) {
	
	register_options_array( vis_options, sizeof( vis_options ) );
	
	return SUCCESS;
	
}



struct plugin_v1 *vis_get_plugin_v1( void ) {
	
	static struct plugin_v1 vis_plugin_v1;
	memset( &vis_plugin_v1, 0, sizeof ( struct plugin_v1 ) );
	
	vis_plugin_v1.plugin_version = PLUGIN_VERSION_01;
	vis_plugin_v1.plugin_size = sizeof ( struct plugin_v1 );
	vis_plugin_v1.plugin_name = "bmx_vis_plugin";
	vis_plugin_v1.cb_init = vis_init;
	vis_plugin_v1.cb_cleanup = vis_cleanup;
	
	return &vis_plugin_v1;
}


#endif /*NOVIS*/



#ifndef NOSRV

static SIMPEL_LIST( my_srv_list );

static struct ext_packet *my_srv_ext_array = NULL;
static uint16_t my_srv_list_enabled = 0;

static int32_t srv_orig_registry = FAILURE;

static void update_own_srv( uint8_t purge ) {
	struct list_head *list_pos, *srv_tmp;
	struct srv_node *srv_node;
	
	if ( purge ) { 
				
		list_for_each_safe( list_pos, srv_tmp, &my_srv_list ) {

			srv_node = list_entry( list_pos, struct srv_node, list );
			
			list_del( (struct list_head*)&my_srv_list, list_pos, &my_srv_list );
			
			debugFree( srv_node, 1222 );

			
		}
		
		my_srv_list_enabled=0;
	}

	if ( my_srv_ext_array != NULL )
		debugFree( my_srv_ext_array, 1125 );
	
	my_srv_ext_array = NULL;
		
	uint16_t array_len = 0;
	
	
	if ( ! purge  &&  !( list_empty( &my_srv_list ) )  ) {
		
		my_srv_ext_array = debugMalloc( my_srv_list_enabled * sizeof(struct ext_packet), 125 );
		memset( my_srv_ext_array, 0, my_srv_list_enabled * sizeof(struct ext_packet) );

		list_for_each( list_pos, &my_srv_list ) {

			srv_node = list_entry( list_pos, struct srv_node, list );

			my_srv_ext_array[array_len].EXT_FIELD_MSG  = YES;
			my_srv_ext_array[array_len].EXT_FIELD_TYPE = EXT_TYPE_64B_SRV;

			my_srv_ext_array[array_len].EXT_SRV_FIELD_ADDR  = srv_node->srv_addr;
			my_srv_ext_array[array_len].EXT_SRV_FIELD_PORT  = htons( srv_node->srv_port );
			my_srv_ext_array[array_len].EXT_SRV_FIELD_SEQNO = srv_node->srv_seqno;
			
			array_len++;
		}
	
	}

}


static int32_t opt_srv ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {

	uint32_t ip=0;
	int32_t port=0;
	
	if ( cmd == OPT_CHECK  ||  cmd == OPT_APPLY ) {
	
		if ( str2netw( patch->p_val, &ip, ':', cn, &port, 65535 ) == FAILURE )
			return FAILURE;
		
		if ( cmd == OPT_APPLY  &&  ip ) {
			
			struct srv_node *srv_node=NULL;
			struct list_head *srv_pos, *srv_tmp, *srv_prev = (struct list_head *)&my_srv_list;
			
			list_for_each_safe( srv_pos, srv_tmp, &my_srv_list ) {
			
				srv_node = list_entry( srv_pos, struct srv_node, list );

				if ( srv_node->srv_addr == ip  &&  srv_node->srv_port == port )
					break;
			
				srv_prev = &srv_node->list;
				srv_node = NULL;
			
			}
			
			if ( patch->p_diff == DEL  &&  srv_node ) {
				
				list_del( srv_prev, srv_pos, &my_srv_list );
				debugFree( srv_pos, 1222 );
				my_srv_list_enabled--;
				
			} else if ( patch->p_diff == ADD  &&  !srv_node ) {
				
				srv_node = debugMalloc( sizeof(struct srv_node), 222 );
				memset( srv_node, 0, sizeof(struct srv_node) );
				INIT_LIST_HEAD( &srv_node->list );
				
				srv_node->srv_addr = ip;
				srv_node->srv_port = port;
				
				list_add_tail( &srv_node->list, &my_srv_list );
				my_srv_list_enabled++;
				
			}
			
			struct opt_child *c;
			
			if ( (c=get_opt_child( get_option(opt,0,ARG_SRV_SQN), patch )) ) {
				
				if ( !srv_node )
					return FAILURE;
				
				if ( c->c_val )
					srv_node->srv_seqno = strtol( c->c_val, NULL, 10 );
				else
					srv_node->srv_seqno = 0;
				
			}
			
			update_own_srv( NO /*purge*/ );
		}
		
		return SUCCESS;

	
		
	} else if ( cmd == OPT_UNREGISTER ) {
		
		update_own_srv( YES /*purge*/ );
		
	}

	return SUCCESS;

}	

static int32_t opt_srvs ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	int dbg_ogm_out = 0;
	static char dbg_ogm_str[MAX_DBG_STR_SIZE + 1]; // TBD: must be checked for overflow when 
        struct orig_node *on;
        struct avl_node *an;
	uint16_t srv_count = 0;

	if ( cmd != OPT_APPLY )
		return SUCCESS;
	
	dbg_printf( cn, "Originator      Announced services ip:port:seqno ...\n");

        uint32_t orig_ip = 0;

        while ((on = (struct orig_node*) ((an = avl_next(&orig_avl, &orig_ip)) ? an->key : NULL))) {

                orig_ip = on->orig;

		if ( on->router == NULL  ||  srv_orig_registry < 0  ||  on->plugin_data[srv_orig_registry] == NULL )
			continue;

		struct srv_orig_data *orig_srv = (struct srv_orig_data*)(on->plugin_data[srv_orig_registry]);
		
		dbg_ogm_out = snprintf( dbg_ogm_str, MAX_DBG_STR_SIZE, "%-15s", on->orig_str ); 
				
		srv_count = 0;
			
		while ( srv_count < orig_srv->srv_array_len ) {

			dbg_ogm_out = dbg_ogm_out + 
				snprintf( (dbg_ogm_str + dbg_ogm_out), (MAX_DBG_STR_SIZE - dbg_ogm_out), 
				          " %15s:%d:%d", 
				          ipStr(orig_srv->srv_array[srv_count].EXT_SRV_FIELD_ADDR),
				          ntohs( orig_srv->srv_array[srv_count].EXT_SRV_FIELD_PORT ), 
				          orig_srv->srv_array[srv_count].EXT_SRV_FIELD_SEQNO );

			srv_count++;

		}

		dbg_printf( cn, "%s \n", dbg_ogm_str );

	}
	
	dbg_printf( cn, "\n" );
	return SUCCESS;
}

static struct opt_type srv_options[]= {
//     		ord parent long_name   shrt Attributes				*ival		min		max		default		*function
	{ODI,5,0,0,			0,  0,0,0,0,0,				0,		0,		0,		0,		0,0,
			"\nService announcement options:"},

	{ODI,5,0,ARG_SRV, 		0,  A_PMN,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0,		0,		0,		opt_srv,
			ARG_ADDR_FORM":PORT","announce the given IP, port [0-65535] as an available service to other nodes"},
		
	{ODI,5,ARG_SRV,ARG_SRV_SQN, 	'q',A_CS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0,		255,		0,		opt_srv,
			"SEQNO",	"set seqno [0-255] of announced service"},
	
	{ODI,5,0,ARG_SERVICES,		0,  A_PS0,A_USR,A_DYN,A_ARG,A_ANY,	0,		0, 		0,		0, 		opt_srvs,0,
			"show services announced by other nodes\n"}

};



static int32_t send_my_srv_ext( unsigned char* ext_buff ) {
	
	if ( my_srv_list_enabled)
                memcpy(ext_buff, (unsigned char *) my_srv_ext_array, my_srv_list_enabled * sizeof (struct ext_packet));
	
	return my_srv_list_enabled * sizeof(struct ext_packet);

}

static struct srv_orig_data* srv_orig_create( struct orig_node *on,  struct ext_packet *srv_array, uint16_t srv_array_len ) {
	
	paranoia( -500142, ( !srv_array  ||  !srv_array_len  ||  srv_orig_registry < 0  ||  (on->plugin_data[srv_orig_registry]) ) );
	
	
	on->plugin_data[srv_orig_registry] = 
		debugMalloc( sizeof( struct srv_orig_data ) + srv_array_len * sizeof( struct ext_packet ), 121 );
	
	struct srv_orig_data *orig_srv = on->plugin_data[srv_orig_registry];
	
	memcpy( orig_srv->srv_array, srv_array, srv_array_len * sizeof(struct ext_packet) );
	dbg( DBGL_CHANGES, DBGT_INFO, "adding service announcement len %d", srv_array_len );
	
	orig_srv->srv_array_len = srv_array_len;
	
	return orig_srv;
	
}

static void cb_srv_orig_destroy( struct orig_node *on ) {
	
	if ( on->plugin_data[srv_orig_registry] ) {
		
		debugFree( on->plugin_data[srv_orig_registry], 1121 );
		on->plugin_data[srv_orig_registry] = NULL;
		
		dbg( DBGL_CHANGES, DBGT_INFO, "removing service announcement");
		
	}
	
}



static int32_t cb_srv_ogm_hook( struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router ) {
	
	struct orig_node *orig_node = mb->orig_node;
	
	struct srv_orig_data *orig_srv = mb->orig_node->plugin_data[ srv_orig_registry ];
	
	/* may be service announcements changed */
	uint16_t srv_array_len = mb->rcv_ext_len[EXT_TYPE_64B_SRV] / sizeof(struct ext_packet);
	struct ext_packet *srv_array = mb->rcv_ext_array[EXT_TYPE_64B_SRV];
	
	if ( !srv_array_len && !orig_srv )
		return CB_OGM_ACCEPT;
	
	
	if ( ( (srv_array_len?1:0) != (orig_srv?1:0) )  ||  
	     ( srv_array_len != orig_srv->srv_array_len ) || 
	     ( srv_array_len > 0  &&  
	       memcmp( srv_array, orig_srv->srv_array, srv_array_len * sizeof(struct ext_packet) ) )  ) 
	{

		dbg( DBGL_CHANGES, DBGT_INFO, "announced services changed" );
	
		if ( orig_srv )
			cb_srv_orig_destroy( orig_node );

		if ( srv_array_len > 0  &&  srv_array )
			srv_orig_create( orig_node, srv_array, srv_array_len );

	}

	return CB_OGM_ACCEPT;
	
}

static void srv_cleanup( void ) {
	
	set_ogm_hook( cb_srv_ogm_hook, DEL );
	set_snd_ext_hook( EXT_TYPE_64B_SRV, send_my_srv_ext, DEL );
}


static int32_t srv_init( void ) {
	
	register_options_array( srv_options, sizeof( srv_options ) );
	
	if ( (srv_orig_registry = reg_plugin_data( PLUGIN_DATA_ORIG )) < 0 )
		return FAILURE;
	
	set_ogm_hook( cb_srv_ogm_hook, ADD );
	
	set_snd_ext_hook( EXT_TYPE_64B_SRV, send_my_srv_ext, ADD );
	
	return SUCCESS;
}




struct plugin_v1 *srv_get_plugin_v1( void ) {
	
	static struct plugin_v1 srv_plugin_v1;
	memset( &srv_plugin_v1, 0, sizeof ( struct plugin_v1 ) );
	
	srv_plugin_v1.plugin_version = PLUGIN_VERSION_01;
	srv_plugin_v1.plugin_name = "bmx_srv_plugin";
	srv_plugin_v1.plugin_size = sizeof ( struct plugin_v1 );
	srv_plugin_v1.cb_init = srv_init;
	srv_plugin_v1.cb_cleanup = srv_cleanup;
	
	srv_plugin_v1.cb_plugin_handler[PLUGIN_CB_ORIG_FLUSH] = (void(*)(void*))cb_srv_orig_destroy;
	srv_plugin_v1.cb_plugin_handler[PLUGIN_CB_ORIG_DESTROY] = (void(*)(void*))cb_srv_orig_destroy;
	return &srv_plugin_v1;
}


#endif /*NOSRV*/

