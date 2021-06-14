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
#include "schedule.h"

LIST_ENTRY cb_fd_list;
static LIST_ENTRY cb_packet_list;
static LIST_ENTRY cb_ogm_list;
static LIST_ENTRY plugin_list;

struct cb_snd_ext snd_ext_hooks[EXT_TYPE_MAX + 1];

int32_t plugin_data_registries[PLUGIN_DATA_SIZE];

void cb_plugin_hooks(void *data, int32_t cb_id)
{
	struct plugin_node *prev_pn = NULL;

	OLForEach(pn, struct plugin_node, plugin_list)
	{
		if (prev_pn && prev_pn->plugin_v1 && prev_pn->plugin_v1->cb_plugin_handler[cb_id])
			(*(prev_pn->plugin_v1->cb_plugin_handler[cb_id]))(data);

		prev_pn = pn;
	}

	if (prev_pn && prev_pn->plugin_v1 && prev_pn->plugin_v1->cb_plugin_handler[cb_id])
		(*(prev_pn->plugin_v1->cb_plugin_handler[cb_id]))(data);
}

static int32_t add_del_thread_hook(int32_t cb_type, void (*cb_handler)(void), int8_t del, PLIST_ENTRY cb_list)
{

	if (!cb_type || !cb_handler)
	{
		cleanup_all(-500143);
		//dbgf( DBGL_SYS, DBGT_ERR, "cb_type or cb_handler == 0");
		//return FAILURE;
	}

	OLForEach(cbn, struct cb_node, *cb_list)
	{
		if (cb_type == cbn->cb_type && cb_handler == cbn->cb_handler)
		{
			if (del)
			{
				OLRemoveEntry(cbn);
				debugFree(cbn, 1315);
				return SUCCESS;
			}
			else
			{
				cleanup_all(-500144);
				//dbgf( DBGL_SYS, DBGT_ERR, "cb_hook for cb_type %d and cb_handler already registered", cb_type );
				//return FAILURE;
			}
		}
	}

	if (del)
	{
		cleanup_all(-500145);
		//dbgf( DBGL_SYS, DBGT_ERR, "cb_type %d and handler not registered", cb_type );
		return FAILURE;
	}
	else
	{
		struct cb_node *cbn;
		cbn = debugMalloc(sizeof(struct cb_node), 315);
		memset(cbn, 0, sizeof(struct cb_node));
		OLInitializeListHead(&cbn->list);

		cbn->cb_type = cb_type;
		cbn->cb_handler = cb_handler;
		OLInsertTailList(cb_list, &cbn->list);

		return SUCCESS;
	}
}

int32_t set_fd_hook(int32_t fd, void (*cb_fd_handler)(int32_t fd), int8_t del)
{
	int32_t ret = add_del_thread_hook(fd, (void (*)(void))cb_fd_handler, del, &cb_fd_list);

	change_selects();
	return ret;
}

int32_t set_packet_hook(int32_t packet_type, void (*cb_packet_handler)(struct msg_buff *mb), int8_t del)
{
	return add_del_thread_hook(packet_type, (void (*)(void))cb_packet_handler, del, &cb_packet_list);
}

//notify interested plugins of rcvd packet...
// THIS MAY CRASH when one plugin unregisteres two packet_hooks while being called with cb_packet_handler()
// TODO: find solution to prevent this ???
uint32_t cb_packet_hooks(int32_t packet_type, struct msg_buff *mb)
{
	struct cb_packet_node *prev_cpn = NULL;
	int calls = 0;

	OLForEach(cpn, struct cb_packet_node, cb_packet_list)
	{
		if (prev_cpn && prev_cpn->packet_type == packet_type)
		{
			(*(prev_cpn->cb_packet_handler))(mb);

			calls++;
		}

		prev_cpn = cpn;
	}

	if (prev_cpn && prev_cpn->packet_type == packet_type)
		(*(prev_cpn->cb_packet_handler))(mb);

	return calls;
}

int32_t set_ogm_hook(int32_t (*cb_ogm_handler)(struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router), int8_t del)
{
	return add_del_thread_hook(1, (void (*)(void))cb_ogm_handler, del, &cb_ogm_list);
}

int32_t cb_ogm_hooks(struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router)
{
	prof_start(PROF_cb_ogm_hooks);

	struct cb_ogm_node *prev_con = NULL;

	OLForEach(con, struct cb_ogm_node, cb_ogm_list)
	{
		if (prev_con)
		{
			if (((*(prev_con->cb_ogm_handler))(mb, oCtx, old_router)) == CB_OGM_REJECT)
			{
				prof_stop(PROF_cb_ogm_hooks);
				return CB_OGM_REJECT;
			}
		}

		prev_con = con;
	}

	if (prev_con)
	{
		if (((*(prev_con->cb_ogm_handler))(mb, oCtx, old_router)) == FAILURE)
		{
			prof_stop(PROF_cb_ogm_hooks);
			return CB_OGM_REJECT;
		}
	}

	prof_stop(PROF_cb_ogm_hooks);
	return CB_OGM_ACCEPT;
}

int32_t set_snd_ext_hook(uint16_t ext_type, int32_t (*cb_snd_ext_handler)(unsigned char *ext_buff), int8_t del)
{
	static uint8_t initialized = NO;

	if (!initialized)
	{
		memset(&snd_ext_hooks[0], 0, sizeof(snd_ext_hooks));
		initialized = YES;
	}

	if (ext_type > EXT_TYPE_MAX)
		return FAILURE;

	if (del && snd_ext_hooks[ext_type].cb_snd_ext_handler == cb_snd_ext_handler)
	{
		snd_ext_hooks[ext_type].cb_snd_ext_handler = NULL;
		return SUCCESS;
	}
	else if (!del && snd_ext_hooks[ext_type].cb_snd_ext_handler == NULL)
	{
		snd_ext_hooks[ext_type].cb_snd_ext_handler = cb_snd_ext_handler;
		return SUCCESS;
	}

	return FAILURE;
}

int32_t cb_snd_ext_hook(uint16_t ext_type, unsigned char *ext_buff)
{
	if (snd_ext_hooks[ext_type].cb_snd_ext_handler)
		return ((*(snd_ext_hooks[ext_type].cb_snd_ext_handler))(ext_buff));

	else
		return SUCCESS;
}

int32_t reg_plugin_data(uint8_t data_type)
{
	static int initialized = NO;

	if (!initialized)
	{
		memset(plugin_data_registries, 0, sizeof(plugin_data_registries));
		initialized = YES;
	}

	if (on_the_fly || data_type >= PLUGIN_DATA_SIZE)
		return FAILURE;

	// do NOT return the incremented value!
	plugin_data_registries[data_type]++;

	return (plugin_data_registries[data_type] - 1);
}

static int is_plugin_active(void *plugin)
{
	OLForEach(pn, struct plugin_node, plugin_list)
	{
		if (pn->plugin == plugin)
			return YES;
	}

	return NO;
}

static int activate_plugin(void *p, int32_t version, void *dlhandle, const char *dl_name)
{
	if (p == NULL || version != PLUGIN_VERSION_01)
		return FAILURE;

 // check if already present in list
	if (is_plugin_active(p))
		return FAILURE;

	if (version == PLUGIN_VERSION_01)
	{
		struct plugin_v1 *pv1 = (struct plugin_v1 *)p;

		if (pv1->plugin_size != sizeof(struct plugin_v1))
		{
			dbgf(DBGL_SYS, DBGT_ERR, "requested to register plugin with unexpected size !");
			return FAILURE;
		}

		if (pv1->cb_init == NULL || ((*(pv1->cb_init))()) == FAILURE)
		{
			dbg(DBGL_SYS, DBGT_ERR, "could not init plugin");
			return FAILURE;
		}

		struct plugin_node *pn = debugMalloc(sizeof(struct plugin_node), 312);
		memset(pn, 0, sizeof(struct plugin_node));
		OLInitializeListHead(&pn->list);

		pn->version = PLUGIN_VERSION_01;
		pn->plugin_v1 = pv1;
		pn->plugin = p;
		pn->dlhandle = dlhandle;

		OLInsertTailList(&plugin_list, &pn->list);

		dbgf_all(DBGT_INFO, "%s SUCCESS", pn->plugin_v1->plugin_name);

		if (dl_name)
		{
			pn->dlname = debugMalloc(strlen(dl_name) + 1, 316);
			strcpy(pn->dlname, dl_name);
		}

		return SUCCESS;
	}

	return FAILURE;
}

static void deactivate_plugin(void *p)
{
	// when removing entries, I can modify lndev (because OLForEach() is a macro)
	OLForEach(pn, struct plugin_node, plugin_list)
	{
		if (pn->plugin == p)
		{
			PLIST_ENTRY prev = OLGetPrev(pn);

			OLRemoveEntry(pn);

			if (pn->version != PLUGIN_VERSION_01)
				cleanup_all(-500098);

			dbg(DBGL_CHANGES, DBGT_INFO, "deactivating plugin %s", pn->plugin_v1->plugin_name);

			if (pn->plugin_v1->cb_cleanup)
				(*(pn->plugin_v1->cb_cleanup))();

			if (pn->dlname)
				debugFree(pn->dlname, 1316);

			debugFree(pn, 1312);
			pn = (struct plugin_node *)prev;
		}
	}
}

void init_plugin(void)
{

	OLInitializeListHead(&cb_fd_list);
	OLInitializeListHead(&cb_packet_list);
	OLInitializeListHead(&cb_ogm_list);
	OLInitializeListHead(&plugin_list);

	set_snd_ext_hook(0, NULL, YES);		 //ensure correct initialization of extension hooks
	reg_plugin_data(PLUGIN_DATA_SIZE); // ensure correct initialization of plugin_data

	struct plugin_v1 *pv1;

	pv1 = NULL;

#ifndef NOTUNNEL
	if ((pv1 = tun_get_plugin_v1()) != NULL)
		activate_plugin(pv1, PLUGIN_VERSION_01, NULL, NULL);
#endif
}

void cleanup_plugin(void)
{
	struct plugin_node *pn;

	while (!OLIsListEmpty(&plugin_list))
	{
		pn = (struct plugin_node *)OLGetNext(&plugin_list);
		deactivate_plugin(pn->plugin);
	}
}
