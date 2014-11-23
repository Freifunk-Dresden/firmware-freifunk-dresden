/*
 * Copyright (C) 2006 BATMAN contributors:
 * Hans Howto
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

#include "batman.h"
#include "os.h"
#include "plugin.h"
#include "howto_plugin.h"

#define DEF_ARG "0"
#define ARG_HOWTO_VAR "howto_var"
#define ARG_HOWTO_DO  "howto_do"
#define ARG_HOWTO_GET "howto_get"

static int32_t howto_var;


static int32_t opt_howto_do ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	static uint8_t call_counter;
	struct opt_parent *p;
	
	if ( cmd == OPT_REGISTER ) {
		
		call_counter = 0;
	
	} else if ( cmd == OPT_CHECK ) {
		
		if( wordlen( patch->p_val )+1 >= MAX_ARG_SIZE )
			return FAILURE;
		
	} else if ( cmd == OPT_APPLY ) {
		
		call_counter++;
		
		dbgf_cn( cn, DBGL_CHANGES, DBGT_INFO, 
		        "now called for the %d time: going to store: %s", 
		         call_counter, patch->p_val );
		
		dbgf( DBGL_CHANGES, DBGT_INFO, "%s - but currently still stored: %s", 
		      opt_cmd2str[cmd], (p=get_opt_parent_val( opt, 0 )) ? p->p_val : NULL );
		
	} else if ( cmd == OPT_SET_POST ) {
		
		// this block will always be executed 
		// after all options with this order were set and
		// before any option with a higher order is set
		
		dbgf( DBGL_CHANGES, DBGT_INFO, "%s - now stored: %s", 
		      opt_cmd2str[cmd], (p=get_opt_parent_val( opt, 0 )) ? p->p_val : NULL );
		
		
	} else if ( cmd == OPT_POST ) {
		
		//this block will always be executed after all options were set
		
		if ( !on_the_fly ) {
			//due to NOT on_the_fly 
			//this block will only be executed once during init after all options were set
		}
		
	} else if ( cmd == OPT_UNREGISTER ) {
	
	}
	
	return SUCCESS;
}

static int32_t opt_howto_get ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	if ( cmd == OPT_APPLY ) {
		
		int i;
		for ( i=0; i<howto_var; i++ ) {
			dbgf_cn( cn, DBGL_ALL, DBGT_INFO, "printing line %10d", i );
		}
		
	}
	
	return SUCCESS;
}

static struct opt_type howto_plugin_options[]= {
//        ord parent long_name          shrt Attributes				*ival		min		max		default		*func,*syntax,*help
	
	{ODI,5,0,0,			0,   0,0,0,0,0,				0,		0,		0,		0,		0,0,
			"\nDemo-plugin options:"},
		
	{ODI,5,0,ARG_HOWTO_VAR,		0,   A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&howto_var,	0, 		10000,		100, 		0,
			ARG_VALUE_FORM,"set val of howto_plugin plugin" },

	{ODI,5,0,ARG_HOWTO_DO,		0,   A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0, 		0,		0, 		opt_howto_do,
			"<word>","set argument of howto_plugin plugin"},
	
	{ODI,5,0,ARG_HOWTO_GET,		0,   A_PS0,A_ADM,A_DYI,A_ARG,A_ANY,	0,		0, 		0,		0, 		opt_howto_get,
			"<word>","set argument of howto_plugin plugin"}
};


static void howto_plugin_cleanup( void ) {
	
	dbgf( DBGL_CHANGES, DBGT_INFO, "cleanung up plugin %s", HOWTO_PLUGIN );
	
}

static int32_t howto_plugin_init( void ) {
	
	dbgf( DBGL_CHANGES, DBGT_INFO, "init plugin %s", HOWTO_PLUGIN );
	
	register_options_array( howto_plugin_options, sizeof( howto_plugin_options ) );
	
	return SUCCESS;
	
}


struct plugin_v1* get_plugin_v1( void ) {
	
	static struct plugin_v1 howto_plugin_v1;
	
	memset( &howto_plugin_v1, 0, sizeof ( struct plugin_v1 ) );
	
	howto_plugin_v1.plugin_version = PLUGIN_VERSION_01;
	howto_plugin_v1.plugin_size = sizeof ( struct plugin_v1 );
	howto_plugin_v1.plugin_name = HOWTO_PLUGIN;
	howto_plugin_v1.cb_init = howto_plugin_init;
	howto_plugin_v1.cb_cleanup = howto_plugin_cleanup;
	
	return &howto_plugin_v1;
	
}
