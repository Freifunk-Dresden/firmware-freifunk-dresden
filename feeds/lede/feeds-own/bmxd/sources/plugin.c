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

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <dlfcn.h>

#include "batman.h"
#include "os.h"
#include "plugin.h"
#include "hna.h"
#include "schedule.h"

SIMPEL_LIST( cb_fd_list );
static SIMPEL_LIST( cb_packet_list);
static SIMPEL_LIST( cb_ogm_list);
static SIMPEL_LIST( plugin_list );

struct cb_snd_ext snd_ext_hooks[EXT_TYPE_MAX+1];

int32_t plugin_data_registries[PLUGIN_DATA_SIZE];


void cb_plugin_hooks( void* data, int32_t cb_id ) {
	
	struct list_head *list_pos;
	struct plugin_node *pn, *prev_pn = NULL;
	
	list_for_each( list_pos, &plugin_list ) {
		
		pn = list_entry( list_pos, struct plugin_node, list );
		
		if ( prev_pn  &&  prev_pn->plugin_v1  &&  prev_pn->plugin_v1->cb_plugin_handler[cb_id] )
			(*(prev_pn->plugin_v1->cb_plugin_handler[cb_id])) ( data );
		
		prev_pn = pn;
	}
	
	if ( prev_pn  &&  prev_pn->plugin_v1  &&  prev_pn->plugin_v1->cb_plugin_handler[cb_id] )
		(*(prev_pn->plugin_v1->cb_plugin_handler[cb_id])) (data);
	
}



static int32_t add_del_thread_hook( int32_t cb_type, void (*cb_handler) (void), int8_t del, struct list_head *cb_list ) {
	
	struct list_head *list_pos, *tmp_pos, *prev_pos = cb_list;
	struct cb_node *cbn;
		
	if ( !cb_type  ||  !cb_handler ) {
		cleanup_all( -500143 );
		//dbgf( DBGL_SYS, DBGT_ERR, "cb_type or cb_handler == 0");
		//return FAILURE;
	}
	
	list_for_each_safe( list_pos, tmp_pos, cb_list ) {
			
		cbn = list_entry( list_pos, struct cb_node, list );
		
		if ( cb_type == cbn->cb_type  &&  cb_handler == cbn->cb_handler ) {

			if ( del ) {
				
				list_del( prev_pos, list_pos, ((struct list_head_first*)cb_list) );
				debugFree( cbn, 1315 );
				return SUCCESS;
				
			} else {
				cleanup_all( -500144 );
				//dbgf( DBGL_SYS, DBGT_ERR, "cb_hook for cb_type %d and cb_handler already registered", cb_type );
				//return FAILURE;
			}
			
		} else {
			
			prev_pos = &cbn->list;
			
		}
			
	}
	
	if ( del ) {
		
		cleanup_all( -500145 );
		//dbgf( DBGL_SYS, DBGT_ERR, "cb_type %d and handler not registered", cb_type );
		return FAILURE;
	
	} else {
		
		cbn = debugMalloc( sizeof( struct cb_node), 315  );
		memset( cbn, 0, sizeof( struct cb_node) );
		INIT_LIST_HEAD( &cbn->list );
		
		cbn->cb_type = cb_type;
		cbn->cb_handler = cb_handler;
		list_add_tail( &cbn->list, ((struct list_head_first*)cb_list) );
	
		return SUCCESS;
	}
}



int32_t set_fd_hook( int32_t fd, void (*cb_fd_handler) (int32_t fd), int8_t del ) {
	
	int32_t ret = add_del_thread_hook( fd, (void (*) (void)) cb_fd_handler, del, (struct list_head*)&cb_fd_list );
	
	change_selects();
	return ret;
}




int32_t set_packet_hook( int32_t packet_type, void (*cb_packet_handler) (struct msg_buff *mb), int8_t del ) {
	
	return add_del_thread_hook( packet_type, (void (*) (void)) cb_packet_handler, del, (struct list_head*)&cb_packet_list );
}


//notify interested plugins of rcvd packet...
// THIS MAY CRASH when one plugin unregisteres two packet_hooks while being called with cb_packet_handler()
// TODO: find solution to prevent this ???
uint32_t cb_packet_hooks( int32_t packet_type, struct msg_buff *mb ) {
	
	struct list_head *list_pos;
	struct cb_packet_node *cpn, *prev_cpn = NULL;
	int calls = 0;
	
	list_for_each( list_pos, &cb_packet_list ) {
		
		cpn = list_entry( list_pos, struct cb_packet_node, list );
		
		if ( prev_cpn  &&  prev_cpn->packet_type == packet_type ) {
			
			(*(prev_cpn->cb_packet_handler)) (mb);
			
			calls++;
		}
		
		prev_cpn = cpn;
	
	}
	
	if ( prev_cpn  &&  prev_cpn->packet_type == packet_type )
		(*(prev_cpn->cb_packet_handler)) (mb);

	return calls;	
}


int32_t set_ogm_hook( int32_t (*cb_ogm_handler) ( struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router ), int8_t del ) {
	
	return add_del_thread_hook( 1, (void (*) (void)) cb_ogm_handler, del, (struct list_head*)&cb_ogm_list );
}


int32_t cb_ogm_hooks( struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router ) {
	
	prof_start( PROF_cb_ogm_hooks );
	
	struct list_head *list_pos;
	struct cb_ogm_node *con, *prev_con = NULL;
	
	list_for_each( list_pos, &cb_ogm_list ) {
		
		con = list_entry( list_pos, struct cb_ogm_node, list );
		
		if ( prev_con ) {
			
			if ( ((*(prev_con->cb_ogm_handler)) (mb, oCtx, old_router)) == CB_OGM_REJECT ) {
				
				prof_stop( PROF_cb_ogm_hooks );
				return CB_OGM_REJECT;
			}
			
		}
		
		prev_con = con;
	
	}
	
	if ( prev_con ) {
		
		if ( ((*(prev_con->cb_ogm_handler)) (mb, oCtx, old_router)) == FAILURE ) {
			
			prof_stop( PROF_cb_ogm_hooks );
			return CB_OGM_REJECT;
		}
		
	}

	prof_stop( PROF_cb_ogm_hooks );
	return CB_OGM_ACCEPT;	
}



int32_t set_snd_ext_hook( uint16_t ext_type, int32_t (*cb_snd_ext_handler) ( unsigned char* ext_buff ), int8_t del ) {
	
	static uint8_t initialized = NO;
	
	if ( !initialized ) {
		memset( &snd_ext_hooks[0], 0, sizeof( snd_ext_hooks ) );
		initialized = YES;
	}

	if ( ext_type > EXT_TYPE_MAX )
		return FAILURE;
	
	if ( del && snd_ext_hooks[ext_type].cb_snd_ext_handler == cb_snd_ext_handler ) {
		
		snd_ext_hooks[ext_type].cb_snd_ext_handler = NULL;
		return SUCCESS;
	
	} else if ( !del  &&  snd_ext_hooks[ext_type].cb_snd_ext_handler == NULL ) {
		
		snd_ext_hooks[ext_type].cb_snd_ext_handler = cb_snd_ext_handler;
		return SUCCESS;
	}
	
	return FAILURE;
}

int32_t cb_snd_ext_hook( uint16_t ext_type, unsigned char* ext_buff ) {
	
	if ( snd_ext_hooks[ext_type].cb_snd_ext_handler )
		return ((*(snd_ext_hooks[ext_type].cb_snd_ext_handler))( ext_buff ));
	
	else
		return SUCCESS;

}





int32_t reg_plugin_data( uint8_t data_type ) {
	
	static int initialized = NO;
	
	if ( !initialized ) {
		memset( plugin_data_registries, 0, sizeof( plugin_data_registries ) );
		initialized=YES;
	}
	
	if ( on_the_fly || data_type >= PLUGIN_DATA_SIZE )
		return FAILURE;
	
	// do NOT return the incremented value! 
	plugin_data_registries[data_type]++;
	
	return (plugin_data_registries[data_type] - 1);
}

#ifdef WITHUNUSED
void **get_plugin_data( void *data, uint8_t data_type, int32_t registry ) {
	
	if ( data_type >= PLUGIN_DATA_SIZE  ||  registry > plugin_data_registries[data_type] ) {
		cleanup_all( -500145 );
		//dbgf( DBGL_SYS, DBGT_ERR, "requested to deliver data for unknown registry !");
		//return NULL;
	}
		
	if ( data_type == PLUGIN_DATA_ORIG )
		return &(((struct orig_node*)data)->plugin_data[registry]);
	
	return NULL;
}
#endif

static int is_plugin_active( void *plugin ) {
	
	struct list_head *list_pos;
		
	list_for_each( list_pos, &plugin_list ) {
			
		if ( ((struct plugin_node *) (list_entry( list_pos, struct plugin_node, list )))->plugin == plugin )
			return YES;
	
	}
	
	return NO;
}

static int activate_plugin( void *p, int32_t version, void *dlhandle, const char *dl_name ) {
	
	if ( p == NULL || version != PLUGIN_VERSION_01 )
		return FAILURE;
	
	if ( is_plugin_active( p ) )
		return FAILURE;
	
	
	if ( version == PLUGIN_VERSION_01 ) {
		
		struct plugin_v1 *pv1 = (struct plugin_v1*)p;
		
		if ( pv1->plugin_size != sizeof( struct plugin_v1 ) ) {
			dbgf( DBGL_SYS, DBGT_ERR, "requested to register plugin with unexpected size !");
			return FAILURE;
		}
	
		
		if ( pv1->cb_init == NULL  ||  ((*( pv1->cb_init )) ()) == FAILURE ) {
			 
			dbg( DBGL_SYS, DBGT_ERR, "could not init plugin");
			return FAILURE;
		}
	
		struct plugin_node *pn = debugMalloc( sizeof( struct plugin_node), 312);
		memset( pn, 0, sizeof( struct plugin_node) );
		INIT_LIST_HEAD( &pn->list );
		
		pn->version = PLUGIN_VERSION_01;
		pn->plugin_v1 = pv1;
		pn->plugin = p;
		pn->dlhandle = dlhandle;
		
		list_add_tail( &pn->list, &plugin_list );
		
		dbgf_all( DBGT_INFO, "%s SUCCESS", pn->plugin_v1->plugin_name );

		if ( dl_name ) {
			pn->dlname = debugMalloc( strlen(dl_name)+1, 316 );
			strcpy( pn->dlname, dl_name );
		}
		
		return SUCCESS;
		
	}
	
	return FAILURE;
	
}

static void deactivate_plugin( void *p ) {
	
	if ( !is_plugin_active( p ) ) {
		cleanup_all( -500190 );
		//dbg( DBGL_SYS, DBGT_ERR, "deactivate_plugin(): requested to deactivate inactive plugin !");
		//return;
	}
	
	struct list_head *list_pos, *tmp_pos, *prev_pos = (struct list_head*)&plugin_list;
		
	list_for_each_safe( list_pos, tmp_pos, &plugin_list ) {
			
		struct plugin_node *pn = list_entry( list_pos, struct plugin_node, list );
			
		if ( pn->plugin == p ) {
			
			list_del( prev_pos, list_pos, &plugin_list );
			
			if ( pn->version != PLUGIN_VERSION_01 )
				cleanup_all( -500098 );
			
			dbg( DBGL_CHANGES, DBGT_INFO, "deactivating plugin %s", pn->plugin_v1->plugin_name );
			
			if ( pn->plugin_v1->cb_cleanup )
				(*( pn->plugin_v1->cb_cleanup )) ();
			
				
			if ( pn->dlname)
				debugFree( pn->dlname, 1316);
			
			debugFree( pn, 1312);
			
		} else {
			
			prev_pos = &pn->list;
			
		}

	}

}

static int8_t activate_dyn_plugin( const char* name ) {
	
	struct plugin_v1* (*get_plugin_v1) ( void ) = NULL;
	
	void *dlhandle;
	struct plugin_v1 *pv1;
	char dl_path[1000];
	
	char *My_libs = getenv(BMX_ENV_LIB_PATH);
	
	if ( !name )
		return FAILURE;
	
	// dl_open sigfaults on some systems without reason.
	// removing the dl files from BMX_DEF_LIB_PATH is a way to prevent calling dl_open.
	// Therefore we restrict dl search to BMX_DEF_LIB_PATH and BMX_ENV_LIB_PATH and ensure that dl_open 
	// is only called if a file with the requested dl name could be found.
	
	if ( My_libs )
		sprintf( dl_path, "%s/%s", My_libs, name );
	else
		sprintf( dl_path, "%s/%s", BMX_DEF_LIB_PATH, name );
	
	
	dbgf_all( DBGT_INFO, "trying to load dl %s", dl_path );
	
	int dl_tried = 0;

	if ( check_file( dl_path, NO, YES ) == SUCCESS  &&
	     (dl_tried = 1)  &&  (dlhandle = dlopen( dl_path, RTLD_NOW )) )
	{
		
		dbgf_all( DBGT_INFO, "succesfully loaded dynamic library %s", dl_path );
		
	} else {
		
		dbg( dl_tried ? DBGL_SYS : DBGL_CHANGES, dl_tried ? DBGT_ERR : DBGT_WARN,
		     "failed loading dl %s %s (maybe incompatible binary/lib versions?)", 
		     dl_path, dl_tried?dlerror():"" );
		
		return FAILURE;
		
	}
	
	dbgf_all( DBGT_INFO, "survived dlopen()!" );


        typedef struct plugin_v1* (*sdl_init_function_type) ( void );

        union {
                sdl_init_function_type func;
                void * obj;
        } alias;

        alias.obj = dlsym( dlhandle, "get_plugin_v1");

	if ( !( get_plugin_v1 = alias.func )  ) {
		dbgf( DBGL_SYS, DBGT_ERR, "dlsym( %s ) failed: %s", name, dlerror() );
		return FAILURE;
	}

	
	if ( !(pv1 = get_plugin_v1()) ) {

		dbgf( DBGL_SYS, DBGT_ERR, "get_plugin_v1( %s ) failed", name );
		return FAILURE;
		
	}
	
	if ( is_plugin_active( pv1 ) )
		return SUCCESS;
	
	
	if ( activate_plugin( pv1, PLUGIN_VERSION_01, dlhandle, name ) == FAILURE ) {
		
		dbgf( DBGL_SYS, DBGT_ERR, "activate_plugin( %s ) failed", dl_path );
		return FAILURE;
		
	}
	
	dbg( DBGL_CHANGES, DBGT_INFO, 
	     "loading and activating %s dl %s succeeded",
	     My_libs ? "customized" : "default",   dl_path );
	
	return SUCCESS;
}

static int32_t opt_plugin ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	dbgf_all( DBGT_INFO, "%s %d", opt_cmd2str[cmd], _save );
	
	char tmp_name[MAX_PATH_SIZE] = "";
	
	
	if ( cmd == OPT_CHECK ) {
		
		dbgf_all( DBGT_INFO, "about to load dl %s", patch->p_val );
		
		if ( wordlen(patch->p_val)+1 >= MAX_PATH_SIZE  ||  patch->p_val[0] == '/' )
			return FAILURE;
		
		wordCopy( tmp_name, patch->p_val );
		
		if ( get_opt_parent_val( opt, tmp_name ) )
			return SUCCESS;
		
		if ( activate_dyn_plugin( tmp_name ) == FAILURE )
			return FAILURE;
		
	}
	
	return SUCCESS;
}

static struct opt_type plugin_options[]= 
{
//        ord parent long_name          shrt Attributes				*ival		min		max		default		*func,*syntax,*help
	
	//order> config-file order to be loaded by config file, order < ARG_CONNECT oder to appera first in help text
	{ODI,2,0,ARG_PLUGIN,		0,  A_PMN,A_ADM,A_INI,A_CFA,A_ANY,	0,		0, 		0,		0, 		opt_plugin,
			ARG_FILE_FORM,	"load plugin. "ARG_FILE_FORM" must be in LD_LIBRARY_PATH or " BMX_ENV_LIB_PATH 
			"\n	path (e.g. --plugin bmx_howto_plugin.so )\n"}
};


void init_plugin( void ) {

	
	set_snd_ext_hook( 0, NULL, YES ); //ensure correct initialization of extension hooks
	reg_plugin_data( PLUGIN_DATA_SIZE );// ensure correct initialization of plugin_data
	
	struct plugin_v1 *pv1;
	
	pv1=NULL;
	
	// first try loading config plugin, if succesfull, continue loading optinal plugins depending on config
	activate_dyn_plugin( BMX_LIB_UCI_CONFIG );
	
	register_options_array( plugin_options, sizeof( plugin_options ) );
	
#ifndef NOHNA
	if ( (pv1 = hna_get_plugin_v1()) != NULL )
		activate_plugin( pv1, PLUGIN_VERSION_01, NULL, NULL );
#endif

#ifndef	NOVIS
	if ( (pv1 = vis_get_plugin_v1()) != NULL )
		activate_plugin( pv1, PLUGIN_VERSION_01, NULL, NULL );
#endif

#ifndef	NOTUNNEL
	if ( (pv1 = tun_get_plugin_v1()) != NULL )
		activate_plugin( pv1, PLUGIN_VERSION_01, NULL, NULL );
#endif

#ifndef	NOSRV
	if ( (pv1 = srv_get_plugin_v1()) != NULL )
		activate_plugin( pv1, PLUGIN_VERSION_01, NULL, NULL );
#endif

}

void cleanup_plugin( void ) {

	while ( !list_empty( &plugin_list ) )
		deactivate_plugin( ((struct plugin_node*)(list_entry( (&plugin_list)->next, struct plugin_node, list)))->plugin );

}
