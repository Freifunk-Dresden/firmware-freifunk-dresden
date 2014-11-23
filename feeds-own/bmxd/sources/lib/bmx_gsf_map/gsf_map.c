/*
 * Copyright (C) 2006 BATMAN contributors:
 * Axel Neumann, Agusti Moll
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
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>
#include <unistd.h>
#include <fcntl.h>


#include "batman.h"
#include "os.h"
#include "originator.h"
#include "plugin.h"
#include "metrics.h"
//#include "schedule.h"
//#include "avl.h"


#define GSF_MAP_MYNAME 		"gsf_map_name"
#define GSF_MAP_LONGITUDE	"gsf_map_longitude"
#define GSF_MAP_LATITUDE	"gsf_map_latitude"
#define GSF_MAP_HW		"gsf_map_hw"
#define GSF_MAP_EMAIL		"gsf_map_email"
#define GSF_MAP_COMMENT		"gsf_map_comment"
#define GSF_MAP_LOCAL_JSON	"gsf_map_local"
#define GSF_MAP_WORLD_JSON	"gsf_map_world"


#define DEF_GSF_MAP_MYNAME 	"anonymous"
#define DEF_GSF_MAP_LONGITUDE	"0"
#define DEF_GSF_MAP_LATITUDE	"0"
#define DEF_GSF_MAP_HW		"undefined"
#define DEF_GSF_MAP_EMAIL	"anonymous@mesh.bmx"
#define DEF_GSF_MAP_COMMENT	"no-comment"

#define GSF_HELP_WORD "<WORD>"

static int32_t opt_gsf_map_local ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	if ( cmd == OPT_APPLY  &&  cn ) {
	
		struct list_head *lndev_pos;
		struct orig_node *orig_node;
		
		int rq, tq, rtq;
		int count=0;
		int count_neigh=0;
		
		struct link_node *ln;
		struct list_head *link_pos;
		
		struct opt_parent *p;
		char *gsf_map_name      = (p=get_opt_parent_val( get_option( 0,0,GSF_MAP_MYNAME),    0)) ? p->p_val : DEF_GSF_MAP_MYNAME;
		char *gsf_map_longitude = (p=get_opt_parent_val( get_option( 0,0,GSF_MAP_LONGITUDE), 0)) ? p->p_val : DEF_GSF_MAP_LONGITUDE;
		char *gsf_map_latitude  = (p=get_opt_parent_val( get_option( 0,0,GSF_MAP_LATITUDE),  0)) ? p->p_val : DEF_GSF_MAP_LATITUDE;
		char *gsf_map_hw	= (p=get_opt_parent_val( get_option( 0,0,GSF_MAP_HW),        0)) ? p->p_val : DEF_GSF_MAP_HW;
		char *gsf_map_email     = (p=get_opt_parent_val( get_option( 0,0,GSF_MAP_EMAIL),     0)) ? p->p_val : DEF_GSF_MAP_EMAIL;
		//char *gsf_map_comment   = (p=get_opt_parent_val( get_option( 0,0,GSF_MAP_COMMENT),   0)) ? p->p_val : DEF_GSF_MAP_COMMENT;
		
		dbg_printf( cn, 
		         //uncomment following line to get the node back
		         //"\nnode = {\n"
		            "'%s' : {\n"
		            "  'name' : '%s', 'long' : %s, 'lat' : %s, 'hw' : '%s', 'email' : '%s' , 'links' : {\n",
		            ipStr(primary_addr),
		            gsf_map_name, gsf_map_longitude, gsf_map_latitude, gsf_map_hw, gsf_map_email );
		
		list_for_each( link_pos, &link_list ) {
			
			ln = list_entry(link_pos, struct link_node, list);
			
			orig_node = ln->orig_node;
			
			if ( !orig_node->router  ||  !orig_node->primary_orig_node )
				continue;
			
			struct orig_node *onn = get_orig_node( orig_node->router->nnkey_addr, NO/*create*/ );
			
			if ( !onn  ||  !onn->last_valid_time  ||  !onn->router )
				continue;
			
			list_for_each( lndev_pos, &ln->lndev_list ) {
				
				struct link_node_dev *lndev = list_entry( lndev_pos, struct link_node_dev, list );
				
				if ( count++ )
					dbg_printf( cn, ",\n");
				
				rq = lndev->rq_sqr.wa_val;
				tq = tq_rate( orig_node, lndev->bif, PROBE_RANGE );
				rtq = lndev->rtq_sqr.wa_val;
				
				dbg_printf( cn, "    '%i' : {\n"
				            "      'ip' : '%s', 'pq' : %3i, 'lseq' : %5i, 'lvld' : %4i, "
				            "'outIP' : '%s', 'dev' : '%s', 'via' : '%s',"
				            "'rtq' : %3i, 'rq' : %3i, 'tq' : %3i} ",
				            count_neigh++,
				            orig_node->primary_orig_node->orig_str,
				            orig_node->router->longtm_sqr.wa_val/PROBE_TO100,
				            orig_node->last_valid_sqn,
				            ( batman_time - orig_node->last_valid_time)/1000,
				            lndev->bif->if_ip_str,
				            lndev->bif->dev, 
				            orig_node->orig_str,
				            rtq/PROBE_TO100, rq/PROBE_TO100, tq/PROBE_TO100 ); 
				
			}
		}
		dbg_printf( cn,
		         //",\n      '' : {}"
		            "\n    }\n  }\n\n"
		         //uncomment following line to get final closing bracket back
		         //"}\n\n" 
		          );
		
	}
	
	return SUCCESS;
}


static int32_t opt_gsf_map_global ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	if ( cmd == OPT_APPLY  &&  cn ) {
	
	struct orig_node *orig_node;
        struct avl_node *an;
	uint32_t count=0;

	dbg_printf( cn, "\nall_nodes = {\n" "  '%s' : {\n", ipStr(primary_addr) );

        uint32_t orig_ip = 0;

        while ((orig_node = (struct orig_node*) ((an=avl_next(&orig_avl, &orig_ip)) ? an->key : NULL ))) {

                orig_ip = orig_node->orig;


		if ( orig_node->router == NULL )
			continue;

		if ( orig_node->primary_orig_node != orig_node )
			continue;

		struct orig_node *onn = get_orig_node( orig_node->router->nnkey_addr, NO );

		if ( !onn  ||  !onn->last_valid_time  ||  !onn->router  ||  !onn->primary_orig_node )
			continue;


		if ( count++ )
			dbg_printf( cn, ",\n");

		dbg_printf( cn, "    '%s' : {\n", orig_node->orig_str );

		dbg_printf( cn, 
				"      "
				"'dev' : '%s', 'via' : '%s', 'viaPub' : '%s', 'pq' : %i, 'ut' : '%s', "
				"'lseq' : %i, 'lvld' : %i, 'pwd' : %i, 'ogi' : %i, 'hop' : %i, 'chng' : %i }",
				orig_node->router->nnkey_iif->dev,
				ipStr( orig_node->router->nnkey_addr ),
				ipStr( onn->primary_orig_node->orig ),
		        	orig_node->router->longtm_sqr.wa_val/PROBE_TO100,
				get_human_uptime( orig_node->first_valid_sec ),
				orig_node->last_valid_sqn,
				( batman_time - orig_node->last_valid_time)/1000,
				orig_node->pws,
				WAVG( orig_node->ogi_wavg, OGI_WAVG_EXP ),
				(Ttl+1 - orig_node->last_path_ttl),
				orig_node->rt_changes
				); 

	}
	dbg_printf( cn,
			//",\n      '' : {}"
			"\n  }\n}\n\n" );

	}

	return SUCCESS;
}


static int32_t opt_gsf_map_args ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	if ( cmd == OPT_CHECK  ||  cmd == OPT_APPLY ) {
		
		char tmp_arg[MAX_ARG_SIZE]="0";
		
		if( wordlen( patch->p_val ) + 1 >= MAX_ARG_SIZE ) {
			dbg_cn( cn, DBGL_SYS, DBGT_ERR, "opt_gsf_map_args(): arguments: %s to long", patch->p_val );
			return FAILURE;
		}
		
		wordCopy( tmp_arg, patch->p_val );
		
		if( strpbrk( tmp_arg, "*'\"#\\/~?^°,;|<>()[]{}$%&=`´" ) ) {
			dbg_cn( cn, DBGL_SYS, DBGT_ERR, 
			        "opt_gsf_map_args(): argument: %s contains illegal symbols", tmp_arg );
			return FAILURE;
		
		}
		
		if ( patch->p_diff == ADD ) {
			
			if ( !strcmp( opt->long_name, GSF_MAP_LONGITUDE )  ||  
			     !strcmp( opt->long_name, GSF_MAP_LATITUDE ) ) 
			{
				
				char **endptr = NULL;
				errno = 0;
				
				if ( strtod( tmp_arg, endptr ) == 0  ||  errno )
					return FAILURE;
			
			}
		}
	}
	
	return SUCCESS;
}



static struct opt_type gsf_map_options[]= {
//        ord parent long_name          shrt Attributes				*ival		min		max		default		*func,*syntax,*help
	
	{ODI,5,0,0,			0,   0,0,0,0,0,				0,		0,		0,		0,		0,
			0,		"\nGraciaSenseFils (GSF) Map options:"},
		
	{ODI,5,0,GSF_MAP_MYNAME,	0,   A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0, 		0,		0, 		opt_gsf_map_args,
			GSF_HELP_WORD,	"set gsf-map name"},
		
	{ODI,5,0,GSF_MAP_LONGITUDE,	0,   A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0, 		0,		0, 		opt_gsf_map_args,
			GSF_HELP_WORD, 	"set gsf-map longitude" },
		
	{ODI,5,0,GSF_MAP_LATITUDE,	0,   A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0, 		0,		0, 		opt_gsf_map_args,
			GSF_HELP_WORD, "set gsf-map latitude" },
		
	{ODI,5,0,GSF_MAP_HW,		0,   A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0, 		0,		0, 		opt_gsf_map_args,
			GSF_HELP_WORD, "set gsf-map hw" },
		
	{ODI,5,0,GSF_MAP_EMAIL,		0,   A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0, 		0,		0, 		opt_gsf_map_args,
			GSF_HELP_WORD, "set gsf-map email" },
		
	{ODI,5,0,GSF_MAP_COMMENT,	0,   A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0, 		0,		0, 		opt_gsf_map_args,
			GSF_HELP_WORD, "set gsf-map comment (use _ between several words)" },
		
	{ODI,5,0,GSF_MAP_LOCAL_JSON,	0,   A_PS0,A_USR,A_DYI,A_ARG,A_ANY,	0,		0, 		0,		0, 		opt_gsf_map_local,
			0,		"show myself and local neighborhood in JSON format" },
	
	{ODI,5,0,GSF_MAP_WORLD_JSON,	0,   A_PS0,A_USR,A_DYI,A_ARG,A_ANY,	0,		0, 		0,		0, 		opt_gsf_map_global,
			0,		"show all my reachable nodes in JSON format" },
	
};


static void gsf_map_cleanup( void ) {
	
	//	remove_options_array( gsf_map_options );
	
}

static int32_t gsf_map_init( void ) {
	
	register_options_array( gsf_map_options, sizeof( gsf_map_options ) );
	
	return SUCCESS;
	
}


struct plugin_v1* get_plugin_v1( void ) {
	
	static struct plugin_v1 gsf_map_plugin_v1;
	
	memset( &gsf_map_plugin_v1, 0, sizeof ( struct plugin_v1 ) );
	
	gsf_map_plugin_v1.plugin_version = PLUGIN_VERSION_01;
	gsf_map_plugin_v1.plugin_size = sizeof ( struct plugin_v1 );
	gsf_map_plugin_v1.plugin_name = "bmx_gsf_map_plugin";
	gsf_map_plugin_v1.cb_init = gsf_map_init;
	gsf_map_plugin_v1.cb_cleanup = gsf_map_cleanup;
	
	return &gsf_map_plugin_v1;
	
}
