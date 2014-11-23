/*
 * Copyright (C) 2006 BATMAN contributors:
 * Axel Neumann
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


#ifndef NOHNA
#include <arpa/inet.h>
#include <string.h>
#include <stdio.h>
#include <asm/types.h>
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>

#include "batman.h"
#include "os.h"
#include "originator.h"
#include "plugin.h"
#include "hna.h"
//#include "avl.h"


static int32_t hna_orig_registry = FAILURE;

static struct ext_type_hna *my_hna_ext_array = NULL;
static uint16_t my_hna_list_enabled = 0;

//static struct avl_tree hna_avl = { sizeof(struct hna_key), NULL};
static AVL_TREE( hna_avl, sizeof(struct hna_key) );

// this function finds (or if it does not exits and create is true it creates) 
// an hna entry for the given hna address, anetmask, and atype 
static struct hna_node *get_hna_node( struct hna_key *hk, uint8_t create ) {
	
        struct avl_node *an = avl_find( &hna_avl, hk );
        struct hna_node *hn = an ? (struct hna_node*) an->key : NULL;
	
	if ( hn ) {
		
		paranoia( -500022, ( memcmp( hk, &hn->key, sizeof( struct hna_key ) ) ) );// found incorrect key
		
		return hn;
	}
	
	if ( !create )
		return NULL;
	
	dbgf_all( DBGT_INFO, "  creating new and empty hna_node: %s/%d, type %d", 
	         ipStr(hk->addr), hk->KEY_FIELD_ANETMASK, hk->KEY_FIELD_ATYPE );
	
	hn = debugMalloc( sizeof(struct hna_node), 401 );
	memset(hn, 0, sizeof(struct hna_node));
	
	hn->key.addr = hk->addr;
	hn->key.KEY_FIELD_ATYPE = hk->KEY_FIELD_ATYPE;
	hn->key.KEY_FIELD_ANETMASK = hk->KEY_FIELD_ANETMASK;
	hn->status = HNA_HASH_NODE_EMPTY;
	
        avl_insert( &hna_avl, hn );
	
	paranoia( -500022, ( memcmp( hk, &hn->key, sizeof( struct hna_key ) ) ) );// found incorrect key
	
	return hn;
}


static int8_t add_del_hna( uint8_t del, struct orig_node *other_orig, struct neigh_node *router,
                    uint32_t ip, uint32_t mask, uint8_t atype ) 
{
	
	if ( atype > A_TYPE_MAX ) // NOT YET supported!
		return SUCCESS;
	
	uint8_t err = !del  &&  other_orig  &&  ( !router || !router->nnkey_addr ||  !router->nnkey_iif );
	
	dbgf( ( err ? DBGL_SYS : DBGL_ALL ), ( err ? DBGT_ERR : DBGT_INFO ),
	     "%s %s %s %s %s/%d %d",
	     del?"DEL":"ADD",
	     other_orig?ipStr(other_orig->orig):"myself",
	     ipStr( router&&router->nnkey_addr ? router->nnkey_addr : 0 ),
	     ( router&&router->nnkey_iif ? router->nnkey_iif->dev : "???" ),
	     ipStr(ip), mask, atype );
	
	paranoia( -500023, err );
	
	struct hna_key key;
	key.addr = ip;
	key.KEY_FIELD_ANETMASK = mask;
	key.KEY_FIELD_ATYPE = atype;

        int16_t rt_table = (atype == A_TYPE_INTERFACE || atype == A_TYPE_NETWORK) ? RT_TABLE_NETWORKS : 0;
	
	struct hna_node *hn = get_hna_node( &key, NO/*create*/);

        
	if ( del ) {
		
		if ( !other_orig  &&  hn  &&  hn->status == HNA_HASH_NODE_MYONE ) {
			
			/* del throw routing entries for own hna */
			add_del_route( ip, mask, 0,0,0, "unknown", RT_TABLE_HOSTS,      RTN_THROW, DEL, TRACK_MY_HNA );
			add_del_route( ip, mask, 0,0,0, "unknown", RT_TABLE_NETWORKS,   RTN_THROW, DEL, TRACK_MY_HNA );
			add_del_route( ip, mask, 0,0,0, "unknown", RT_TABLE_TUNNEL,     RTN_THROW, DEL, TRACK_MY_HNA );
			
			my_hna_list_enabled--;
			
		} else if ( other_orig  &&  hn  &&  hn->status == HNA_HASH_NODE_OTHER   &&  hn->orig == other_orig ) {
			
			add_del_route( ip, mask, 0, primary_addr, 0, 0, rt_table, RTN_UNICAST, DEL, TRACK_OTHER_HNA );
			
		} else {
                        // paranoia( -500181, 1 );
                        if (!hn) {
                                dbgf(DBGL_SYS, DBGT_WARN, "get_hna_node() requested to remove non-existing hna registry");
                        }
                        return FAILURE;
                }

                avl_remove(&hna_avl, hn);
		
		debugFree( hn, 1401 );
		
	} else {
		
		if ( other_orig  &&  !hn ) {
			
			hn = get_hna_node( &key, YES/*create*/);
			hn->status = HNA_HASH_NODE_OTHER;
			hn->orig = other_orig;
			
			// we checked for err = !del  &&  ( !router || !router->addr ||  !router->iif ) at beginning: 
			add_del_route( ip, mask, router->nnkey_addr, primary_addr,
			               router->nnkey_iif->if_index,
			               router->nnkey_iif->dev,
			               rt_table, RTN_UNICAST, ADD, TRACK_OTHER_HNA  );
			
		
		} else if (  other_orig  &&  hn  &&  hn->status == HNA_HASH_NODE_OTHER  &&  hn->orig == other_orig ) {
			
			dbgf( DBGL_SYS, DBGT_WARN, "requested to add already-existing hna registry");
			cleanup_all ( -500092 );
		
		} else if ( !other_orig  &&  !hn ) {
			
			hn = get_hna_node( &key, YES/*create*/);
			hn->status = HNA_HASH_NODE_MYONE;
			hn->orig = NULL;
			
			/* add throw routing entries for own hna */  
			add_del_route( ip, mask, 0,0,0, "unknown", RT_TABLE_HOSTS,      RTN_THROW, ADD, TRACK_MY_HNA );
			add_del_route( ip, mask, 0,0,0, "unknown", RT_TABLE_NETWORKS,   RTN_THROW, ADD, TRACK_MY_HNA );
			add_del_route( ip, mask, 0,0,0, "unknown", RT_TABLE_TUNNEL,     RTN_THROW, ADD, TRACK_MY_HNA );
			
			my_hna_list_enabled++;
			
		} else if ( !other_orig  &&  hn  &&  hn->status == HNA_HASH_NODE_MYONE ) {
			
			dbgf( DBGL_SYS, DBGT_WARN, "requested to add already registered own hna %s/%d", 
			      ipStr(ip), mask );
			
			return FAILURE;
			
		} else {
			
			cleanup_all ( -500091 );
			return FAILURE;
		}
	}
	
	//recalculate my_hna_array
	if ( !other_orig ) { 
		
		if ( my_hna_ext_array != NULL )
			debugFree( my_hna_ext_array, 1115 );
		
		if ( my_hna_list_enabled ) {
			my_hna_ext_array = debugMalloc( my_hna_list_enabled * sizeof(struct ext_type_hna), 115 );
			memset( my_hna_ext_array, 0, my_hna_list_enabled * sizeof(struct ext_type_hna) );
		} else {
			my_hna_ext_array = NULL;
		}
		
		uint16_t array_len = 0;

                struct hna_key hk = {0,{0,0}};
                struct avl_node *an;
                while ((hn = ((an = avl_next(&hna_avl, &hk)) ? an->key : NULL))) {
                        hk = hn->key;
			
			if ( hn->status == HNA_HASH_NODE_MYONE ) {
				
				my_hna_ext_array[array_len].EXT_FIELD_MSG  = YES;
				my_hna_ext_array[array_len].EXT_FIELD_TYPE = EXT_TYPE_64B_HNA;
				
				my_hna_ext_array[array_len].EXT_HNA_FIELD_ADDR    = hn->key.addr;
				my_hna_ext_array[array_len].EXT_HNA_FIELD_NETMASK = hn->key.KEY_FIELD_ANETMASK;
				my_hna_ext_array[array_len].EXT_HNA_FIELD_TYPE    = hn->key.KEY_FIELD_ATYPE;
				
				array_len++;
			}
		}
	}
	
	return SUCCESS;
}



static void update_other_hna( struct orig_node *on, struct neigh_node *router, struct ext_type_hna *array, int16_t len ) {
	
	uint16_t cnt = 0;
	int8_t del = (len == 0 ? DEL : ADD);
	
	struct hna_orig_data *orig_hna = on->plugin_data[hna_orig_registry];
	
	if ( (  orig_hna &&  ( !orig_hna->hna_array_len  ||  !orig_hna->hna_array ) )  ||
	     (  len  &&  ( !array  ||  orig_hna ) )  || 
	     ( !len  &&  (  array  || !orig_hna ) ) ) 
	{
		dbgf( DBGL_SYS, DBGT_ERR,
		     "invalid hna information on %p, hal %d, ha %p, ohna_data %p ohal %d, oha %p!",
                        (void*)on, len, (void*)array, (void*)orig_hna,
		      orig_hna?orig_hna->hna_array_len:0, (void*)(orig_hna?orig_hna->hna_array:0) );
		
		cleanup_all( -500024 );
	}
	
	if ( len > 0 ) {
		
		orig_hna = on->plugin_data[hna_orig_registry] = debugMalloc( sizeof(struct hna_orig_data), 119 );
		
		orig_hna->hna_array = debugMalloc( len * sizeof(struct ext_type_hna), 101 );
		orig_hna->hna_array_len = len;
		
		memcpy( orig_hna->hna_array, array, len * sizeof(struct ext_type_hna) );
	}
	
	while ( cnt < orig_hna->hna_array_len ) {
		
		if ( add_del_hna( del, on, router,
		                  orig_hna->hna_array[cnt].EXT_HNA_FIELD_ADDR, 
		                  orig_hna->hna_array[cnt].EXT_HNA_FIELD_NETMASK,
		                  orig_hna->hna_array[cnt].EXT_HNA_FIELD_TYPE ) == FAILURE ) 
		{
			dbgf( DBGL_CHANGES, DBGT_WARN, 
			     "NOT %s HNA %s/%d type %d ! HNA %s blocked",
			     (del?"removing":"adding"), 
			     ipStr( orig_hna->hna_array[cnt].EXT_HNA_FIELD_ADDR ),
			     orig_hna->hna_array[cnt].EXT_HNA_FIELD_NETMASK,
			     orig_hna->hna_array[cnt].EXT_HNA_FIELD_TYPE, (del?"was":"is") );
		}
		
		cnt++;
	}
	
	if ( len == 0 ) {
		
		debugFree( orig_hna->hna_array, 1101 );
		orig_hna->hna_array_len = 0;
		orig_hna->hna_array = NULL;
		
		debugFree( on->plugin_data[hna_orig_registry], 1119 );
		on->plugin_data[hna_orig_registry] = NULL;
		
	}
}



static int32_t opt_hna ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	uint32_t ip;
	int32_t mask;
	struct hna_node *hhn;
	struct hna_key key;
	char new[30];
	
	if ( cmd == OPT_ADJUST  ||  cmd == OPT_CHECK  ||  cmd == OPT_APPLY ) {
		
		dbgf_all( DBGT_INFO, "diff %d cmd %s  save %d  opt %s  patch %s",
		        patch->p_diff, opt_cmd2str[cmd], _save, opt->long_name, patch->p_val);
		
		
		if ( patch->p_val[0] >= '0'  &&  patch->p_val[0] <= '9' ) {
			
			// the unnamed UHNA
			
			if ( str2netw( patch->p_val, &ip, '/', cn, &mask, 32 ) == FAILURE )
				return FAILURE;
			
			sprintf( new, "%s/%d", ipStr( validate_net_mask( ip, mask, 0 ) ), mask );
			set_opt_parent_val( patch, new );
			
			if ( cmd == OPT_ADJUST )
				return SUCCESS;
			
		} else {
			
			// the named UHNA
			
			if ( adj_patched_network( opt, patch, new, &ip, &mask, cn ) == FAILURE )
				return FAILURE;
	
			if ( cmd == OPT_ADJUST )
				return SUCCESS;
			
			if ( patch->p_diff == NOP ) {
				
				// change network and netmask parameters of an already configured and named HNA
				
				char old[30];
				
				// 1. check if announcing the new HNA would not block,
				if ( check_apply_parent_option( ADD, OPT_CHECK, NO, opt, new, cn ) == FAILURE )
					return FAILURE;
				
				if ( get_tracked_network( opt, patch, old, &ip, &mask, cn ) == FAILURE )
					return FAILURE;
				
				// 3. remove the old HNA and hope to not mess it up...
				if ( cmd == OPT_APPLY  &&
                                        add_del_hna( DEL, NULL, NULL, ip, mask, A_TYPE_NETWORK ) == FAILURE )
					cleanup_all( -500110 );
				
			}
				
			// then continue with the new HNA
			if ( str2netw( new , &ip, '/', cn, &mask, 32 ) == FAILURE )
				return FAILURE;
		}
		
		key.addr = ip;
		key.nt.atype = A_TYPE_NETWORK;
		key.nt.anetmask = mask;
		
		if ( patch->p_diff!=DEL  &&  (hhn = get_hna_node( &key, NO /*create*/)) ) {
			dbg_cn( cn, DBGL_CHANGES, DBGT_ERR, "HNA %s/%d already blocked by %s !", 
			        ipStr( key.addr ), mask,  
			        (hhn->status == HNA_HASH_NODE_OTHER ? ipStr( hhn->orig->orig ) : "myself" ) );
			return FAILURE;
		}
		
		if ( cmd == OPT_APPLY  &&  
		     add_del_hna( (patch->p_diff==DEL ? DEL : ADD), 0,0, key.addr, mask, A_TYPE_NETWORK ) != SUCCESS) 
		{
			dbg_cn( cn, DBGL_CHANGES, DBGT_ERR, "HNA %s/%d failed", ipStr( key.addr ), mask);
			return FAILURE;
		}
		
	
	} else if ( cmd == OPT_UNREGISTER ) {
		
		while( my_hna_list_enabled )
			add_del_hna( YES/*delete*/, NULL,  NULL,
			             my_hna_ext_array[0].EXT_HNA_FIELD_ADDR, 
			             my_hna_ext_array[0].EXT_HNA_FIELD_NETMASK, 
			             my_hna_ext_array[0].EXT_HNA_FIELD_TYPE );
		
	}
	
	return SUCCESS;
}


static int32_t opt_show_hnas ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	int dbg_ogm_out = 0;
	char dbg_ogm_str[MAX_DBG_STR_SIZE + 1];
	uint8_t blocked;
	uint16_t hna_count = 0;
	struct hna_key key;
	struct hna_node *hn;
	struct orig_node *orig_node;
        struct avl_node *an;
	
	if ( cmd == OPT_APPLY ) {
		
		dbg_printf( cn, "Originator      Announced networks HNAs:  network/netmask or interface/IF (B:blocked)...\n");

                uint32_t orig_ip = 0;

                while ((orig_node = (struct orig_node*) ((an = avl_next(&orig_avl, &orig_ip)) ? an->key : NULL))) {

                        orig_ip = orig_node->orig;

                        struct hna_orig_data *orig_hna = orig_node->plugin_data[hna_orig_registry];
			
			if ( !orig_node->router  ||  !orig_hna )
				continue;
			
			
			dbg_ogm_out = snprintf( dbg_ogm_str, MAX_DBG_STR_SIZE, "%-15s", orig_node->orig_str ); 
			
			hna_count = 0;
			
			while ( hna_count < orig_hna->hna_array_len ) {
				
				key.addr               = orig_hna->hna_array[hna_count].EXT_HNA_FIELD_ADDR;
				key.KEY_FIELD_ANETMASK = orig_hna->hna_array[hna_count].EXT_HNA_FIELD_NETMASK;
				key.KEY_FIELD_ATYPE    = orig_hna->hna_array[hna_count].EXT_HNA_FIELD_TYPE;
				
				// check if HNA was blocked
				hn = get_hna_node( &key, NO/*create*/ );
				
				if ( hn  &&  hn->status == HNA_HASH_NODE_OTHER  &&  hn->orig == orig_node )
					blocked = NO;
				else
					blocked = YES;
				
				
				if ( key.KEY_FIELD_ATYPE == A_TYPE_NETWORK )
					dbg_ogm_out = dbg_ogm_out + 
					snprintf( (dbg_ogm_str + dbg_ogm_out), (MAX_DBG_STR_SIZE - dbg_ogm_out), 
					          " %15s/%2d %c ", 
					          ipStr(key.addr), key.KEY_FIELD_ANETMASK, (blocked?'B':' ') );
				
				else if ( key.KEY_FIELD_ATYPE == A_TYPE_INTERFACE )
					dbg_ogm_out = dbg_ogm_out + 
					snprintf( (dbg_ogm_str + dbg_ogm_out), (MAX_DBG_STR_SIZE - dbg_ogm_out), 
					          " %15s/IF %c ", 
					          ipStr(key.addr), (blocked?'B':' ') );
				
				hna_count++;
				
			}
			
			dbg_printf( cn, "%s \n", dbg_ogm_str );
		}
		
		dbg_printf( cn, "\n" );
	}
	return SUCCESS;
}




static struct opt_type hna_options[]= {
//     		ord parent long_name   shrt Attributes				*ival		min		max		default		*function
	
	{ODI,5,0,0,			0,  0,0,0,0,0,				0,		0,		0,		0,		0,
			0,		"\nHost and Network Announcement (HNA) options:"},

	{ODI,5,0,ARG_UHNA,	 	'a',A_PMN,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0,		0,		0,		opt_hna,
			ARG_PREFIX_FORM,"perform host-network announcement (HNA) for defined ip range"},
	
	{ODI,5,ARG_UHNA,ARG_NETW,	'n',A_CS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0,		0,		0,		opt_hna,
			ARG_NETW_FORM, 	"specify network of announcement"},
	
	{ODI,5,ARG_UHNA,ARG_MASK,	'm',A_CS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0,		0,		0,		opt_hna,
			ARG_MASK_FORM, 	"specify network prefix of announcement"},
	
		
	{ODI,5,0,ARG_HNAS,		0,  A_PS0,A_USR,A_DYN,A_ARG,A_ANY,	0,		0, 		0,		0, 		opt_show_hnas,
			0,		"show HNAs of other nodes\n"}
	
};



/*
static struct hna_orig_data* hna_orig_create( struct orig_node *on,  struct ext_type_hna *hna_array, uint16_t hna_array_len ) {
	
	if ( !hna_array  ||  !hna_array_len  ||  hna_orig_registry < 0  ||  (on->plugin_data[hna_orig_registry]) ) {
		
		dbgf( DBGL_SYS, DBGT_ERR, "hna_orig_registry %d  hna_array_len %d",
		     hna_orig_registry, hna_array_len );
		
		return NULL;
	}
	
	on->plugin_data[hna_orig_registry] = 
		debugMalloc( sizeof( struct hna_orig_data ) + hna_array_len * sizeof( struct ext_type_hna ), 119 );
	
	struct hna_orig_data *orig_hna = on->plugin_data[hna_orig_registry];
	
	memcpy( orig_hna->hna_array, hna_array, hna_array_len * sizeof(struct ext_packet) );
	
	dbg( DBGL_CHANGES, DBGT_INFO, "adding hna announcement len %d %d %d" );
	
	orig_hna->hna_array_len = hna_array_len;
	
	return orig_hna;
}
*/


static void cb_hna_orig_destroy( struct orig_node *on ) {
	
	if ( on->plugin_data[hna_orig_registry] )
		update_other_hna( on, 0, NULL, 0 );

}


//stephan: only accept hna if comming from vserver ip ranges.
#if 1
static int ddmesh_ignore_hna(struct orig_node *orig_node)
  { //10.200.0.1-10.200.0.15 (knoten 0-14)
    const char vserver_ip[ADDR_STR_LEN] = "10.200.0.1";
    u_int32_t  vserver_mask = 28;
    u_int32_t  vserver_nip;
    u_int32_t  orig_nip;

        //mask ip to vserver_mask
        orig_nip = orig_node->orig & htonl( 0xFFFFFFFF<<( 32 - vserver_mask ) );

        //get network ip from vserver ip string
        inet_pton(AF_INET, vserver_ip, &vserver_nip);
        vserver_nip = vserver_nip & htonl( 0xFFFFFFFF<<( 32 - vserver_mask ) );

        //compare vserver nip and originator nip
        //allow  hna from vserver
        if(orig_nip == vserver_nip)
                return 0;
	else
        	return 1; //invalid originator
  }
#endif



static int32_t cb_hna_ogm_hook( struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router ) {
	
	uint16_t hna_array_len = mb->rcv_ext_len[EXT_TYPE_64B_HNA] / sizeof( struct ext_packet );
	struct ext_type_hna *hna_array = (struct ext_type_hna*)mb->rcv_ext_array[EXT_TYPE_64B_HNA];
	
	struct orig_node *orig_node = mb->orig_node;
	
	struct hna_orig_data *orig_hna = (struct hna_orig_data*)(orig_node->plugin_data[hna_orig_registry]);
	
	paranoia( -500063, ( orig_hna  &&  ( !orig_hna->hna_array_len  ||  !orig_hna->hna_array ) ) );
	
	/* check for duplicate/blocked hna announcements */
	if ( hna_array_len  &&
	     ( !orig_hna   ||
	       hna_array_len != orig_hna->hna_array_len  || 
	       memcmp( orig_hna->hna_array, hna_array, hna_array_len * sizeof(struct ext_type_hna) ) ) ) 
	{
		
		dbgf_all( DBGT_INFO, "Changed HNA information received (%i HNA networks):", hna_array_len );

//stephan; ignore originator if it uses hna 
#if 1
		if(hna_array_len > 0 && ddmesh_ignore_hna(orig_node))
		{
			dbg_mute( 45, DBGL_SYS, DBGT_WARN, "drop OGM: originator %15s NOT ALLOWED to send HNA", orig_node->orig_str);
			return CB_OGM_REJECT;
		}
#endif
		
		int16_t hna_count = 0;
		
		while ( hna_count < hna_array_len ) {
			
			struct hna_key key;
                        struct hna_node *hn;
			
			key.addr               = ((hna_array)[hna_count]).EXT_HNA_FIELD_ADDR;
			key.KEY_FIELD_ANETMASK = ((hna_array)[hna_count]).EXT_HNA_FIELD_NETMASK;
			key.KEY_FIELD_ATYPE    = ((hna_array)[hna_count]).EXT_HNA_FIELD_TYPE;
			
			if (  key.KEY_FIELD_ANETMASK < 0  ||
			      key.KEY_FIELD_ANETMASK > 32  ||
			      key.addr != ( key.addr & htonl( 0xFFFFFFFF<<(32 - key.KEY_FIELD_ANETMASK ) ) ) ) 
			{
				
				dbg_mute( 45, DBGL_SYS, DBGT_WARN,
                                        "drop OGM: purging originator %15s "
                                        "hna: %s/%i, type %d -> ignoring (invalid netmask or type)",
                                        orig_node->orig_str, ipStr(key.addr),
                                        key.KEY_FIELD_ANETMASK, key.KEY_FIELD_ATYPE);
				
				return CB_OGM_REJECT;
				
			} else if ( (hn = get_hna_node( &key, NO /*create*/ )) &&
                                !(hn->status == HNA_HASH_NODE_OTHER && hn->orig == orig_node) &&
                                (key.KEY_FIELD_ATYPE <= A_TYPE_MAX) ) {

                                dbg_mute(45, DBGL_SYS, DBGT_WARN,
                                        "DAD-alert! ignoring %15s "
                                        "hna: %s/%d type %d is blocked by %s "
                                        "which may be purged in %d secs ( check --%s=%d )!",
                                        orig_node->orig_str,
                                        ipStr(key.addr), key.KEY_FIELD_ANETMASK, key.KEY_FIELD_ATYPE,
                                        (hn->status == HNA_HASH_NODE_OTHER ? hn->orig->orig_str : "myself"),
                                        (hn->status == HNA_HASH_NODE_OTHER ?
                                        (int) (dad_to - (((uint32_t) (batman_time - hn->orig->last_valid_time)) / 1000)) :
                                        -1),
                                        ARG_PURGE_TO, dad_to);

                                if (hn->status == HNA_HASH_NODE_OTHER) {
                                        // if HNA is blocked by other node which has ńot bean heard of for 
                                        // dad-timeout secs, 
                                        // then its' HNAs should be removed before purge-timeout expires
                                        if (LSEQ_U32(dad_to, (((uint32_t) (batman_time - hn->orig->last_valid_time)) / 1000)))
                                                update_other_hna(hn->orig, 0, NULL, 0);
                                }
				
				return CB_OGM_REJECT;
				
			} else {

				dbgf_all( DBGT_INFO, "hna: %s/%i, type %d", ipStr( key.addr ), 
				         key.KEY_FIELD_ANETMASK, key.KEY_FIELD_ATYPE );
				
			}
			
			hna_count++;
		}
	}	
	
	mb->snd_ext_len[EXT_TYPE_64B_HNA] = mb->rcv_ext_len[EXT_TYPE_64B_HNA];
	mb->snd_ext_array[EXT_TYPE_64B_HNA] = mb->rcv_ext_array[EXT_TYPE_64B_HNA];
	
	/* remove old announced network(s) */
	if ( old_router != orig_node->router ) { 
		
		/* remove old announced network(s) */
		if ( orig_hna )
			update_other_hna( orig_node, 0, NULL, 0 );
		
		/* add new announced network(s) */
		if ( orig_node->router  &&  hna_array_len )
			update_other_hna( orig_node, orig_node->router, hna_array, hna_array_len );
		
	/* maybe just HNA changed */
	} else if ( ( hna_array  &&  !orig_hna ) ||
	            ( !hna_array  &&  orig_hna ) ||
	            ( hna_array  &&  orig_hna  &&  hna_array_len != orig_hna->hna_array_len ) ||
	            ( hna_array_len  &&  orig_hna  &&  memcmp( orig_hna->hna_array, hna_array, hna_array_len * sizeof(struct ext_packet) ) ) )
	{
		
		if ( orig_hna )
			update_other_hna( orig_node, 0, NULL, 0 );
		
		if ( orig_node->router  &&  hna_array_len )
			update_other_hna( orig_node, orig_node->router, hna_array, hna_array_len );
		
	}
	
	return CB_OGM_ACCEPT;
	
}


static int32_t send_my_hna_ext( unsigned char* ext_buff ) {
	
	if ( my_hna_list_enabled )
		memcpy( ext_buff, (unsigned char *)my_hna_ext_array, my_hna_list_enabled * sizeof(struct ext_type_hna) );
	
	return my_hna_list_enabled * sizeof(struct ext_packet);
	
}


static void hna_cleanup( void ) {
	
	set_ogm_hook( cb_hna_ogm_hook, DEL );
	
	set_snd_ext_hook( EXT_TYPE_64B_HNA, send_my_hna_ext, DEL );
	
	
}


static int32_t hna_init( void ) {
	
	paranoia( -500061, ( sizeof(struct ext_type_hna) != sizeof(struct ext_packet) ) );
	
	register_options_array( hna_options, sizeof( hna_options ) );
	
	if ( (hna_orig_registry = reg_plugin_data( PLUGIN_DATA_ORIG )) < 0 )
		cleanup_all( -500062 );
	
	set_ogm_hook( cb_hna_ogm_hook, ADD );
	
	set_snd_ext_hook( EXT_TYPE_64B_HNA, send_my_hna_ext, ADD );
	
	return SUCCESS;
	
}



struct plugin_v1 *hna_get_plugin_v1( void ) {
	
	static struct plugin_v1 hna_plugin_v1;
	memset( &hna_plugin_v1, 0, sizeof ( struct plugin_v1 ) );
	
	hna_plugin_v1.plugin_version = PLUGIN_VERSION_01;
	hna_plugin_v1.plugin_name = "bmx_hna_plugin";
	hna_plugin_v1.plugin_size = sizeof ( struct plugin_v1 );
	hna_plugin_v1.cb_init = hna_init;
	hna_plugin_v1.cb_cleanup = hna_cleanup;
	
	hna_plugin_v1.cb_plugin_handler[PLUGIN_CB_ORIG_FLUSH] = (void(*)(void*))cb_hna_orig_destroy;
	hna_plugin_v1.cb_plugin_handler[PLUGIN_CB_ORIG_DESTROY] = (void(*)(void*))cb_hna_orig_destroy;
	return &hna_plugin_v1;
}


#endif //NOHNA

