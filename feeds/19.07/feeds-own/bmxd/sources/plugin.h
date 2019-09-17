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

#define PLUGIN_VERSION_01 0x01
#define BMX_LIB_UCI_CONFIG "bmx_uci_config.so"

#define ARG_PLUGIN "plugin"

extern struct list_head_first cb_fd_list;



enum {
 PLUGIN_CB_CONF,
 PLUGIN_CB_ORIG_CREATE,
 PLUGIN_CB_ORIG_FLUSH,
 PLUGIN_CB_ORIG_DESTROY,
 PLUGIN_CB_TERM,
 PLUGIN_CB_SIZE
};

struct plugin_v1 {
	uint32_t plugin_version;
	uint32_t plugin_size;
	char	*plugin_name;
	int32_t (*cb_init) ( void );
	void    (*cb_cleanup) ( void );

	//some more advanced (rarely called) callbacks hooks
	void (*cb_plugin_handler[PLUGIN_CB_SIZE]) (void*);
	
	//some other attributes

};



struct plugin_node {
	struct list_head list;
	int32_t	version;
	void *plugin;
	struct plugin_v1 *plugin_v1;
	void *dlhandle;
	char *dlname;
};


struct cb_ogm_node {
	struct list_head list; 
	int32_t cb_type;
	int32_t (*cb_ogm_handler) ( struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router );
};


struct cb_fd_node {
	struct list_head list; 
	int32_t fd;
	void (*cb_fd_handler) (int32_t fd);
};


struct cb_packet_node {
	struct list_head list; 
	int32_t packet_type;
	void (*cb_packet_handler) (struct msg_buff *mb);
};


struct cb_node {
	struct list_head list; 
	int32_t cb_type;
	void (*cb_handler) ( void );
};



struct cb_snd_ext {
	int32_t (*cb_snd_ext_handler) ( unsigned char* ext_buff );
};


// cb_fd_handler is called when fd received data
// called function may remove itself
int32_t set_fd_hook( int32_t fd, void (*cb_fd_handler) (int32_t fd), int8_t del );

int32_t set_packet_hook( int32_t packet_type, void (*cb_packet_handler) (struct msg_buff *mb), int8_t del );

#define CB_OGM_ACCEPT 0
#define CB_OGM_REJECT -1

/*
enum cb_ogm_t {
	CB_OGM_ACCEPT,
 	CB_OGM_REJECT
};
*/

// only one cb_ogm_hook per plugin
int32_t set_ogm_hook( int32_t (*cb_ogm_handler) ( struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router ), int8_t del );

int32_t set_snd_ext_hook( uint16_t ext_type, int32_t (*cb_snd_ext_handler) ( unsigned char* ext_buff ), int8_t del );



//for registering data hooks:

enum {
 PLUGIN_DATA_ORIG,
 PLUGIN_DATA_SIZE
};

extern int32_t plugin_data_registries[PLUGIN_DATA_SIZE];


int32_t reg_plugin_data( uint8_t data_type );

#ifdef WITHUNUSED
void **get_plugin_data( void *data, uint8_t data_type, int32_t registry );
#endif




/**************************************
 *to be used by batman sceleton...
 */
void init_plugin( void );
void cleanup_plugin( void );


//void cb_config_hooks( void );
void cb_plugin_hooks( void* data, int32_t cb_id );

//returns number of called packet hooks for this packet_type
uint32_t cb_packet_hooks( int32_t packet_type, struct msg_buff *mb );

//return value FAILURE means that ogm or extension header is inacceptible and must be dropped !
int32_t cb_ogm_hooks( struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router );

int32_t cb_snd_ext_hook( uint16_t ext_type, unsigned char* ext_buff );

// use void change_selects( void ) to trigger cb_fd_handler() 


