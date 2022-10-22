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

enum
{
	PLUGIN_CB_CONF,
	PLUGIN_CB_ORIG_FLUSH,
	PLUGIN_CB_SIZE  // used as number of callbacks per plugin
};

struct cb_ogm_node
{
	LIST_ENTRY list;
	int32_t cb_type;
	int32_t (*cb_ogm_handler)(struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router);
};

struct cb_fd_node
{
	LIST_ENTRY list;
	int32_t fd;
	void (*cb_fd_handler)(int32_t fd);
};

struct cb_packet_node
{
	LIST_ENTRY list;
	int32_t packet_type;
	void (*cb_packet_handler)(struct msg_buff *mb);
};

struct cb_node
{
	LIST_ENTRY list;
	int32_t cb_type;
	void (*cb_handler)(void);
};

struct cb_snd_ext
{
	int32_t (*cb_snd_ext_handler)(unsigned char *ext_buff);
};

#define CB_OGM_ACCEPT 0
#define CB_OGM_REJECT -1


int32_t set_snd_ext_hook(uint16_t ext_type, int32_t (*cb_snd_ext_handler)(unsigned char *ext_buff), int8_t del);

/**************************************
 *to be used by batman sceleton...
 */
void init_plugin(void);

int32_t cb_snd_ext_hook(uint16_t ext_type, unsigned char *ext_buff);

// use void change_selects( void ) to trigger cb_fd_handler()
