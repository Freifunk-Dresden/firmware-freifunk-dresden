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


static LIST_ENTRY plugin_list;

struct cb_snd_ext snd_ext_hooks[EXT_TYPE_MAX + 1];

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
	OLInitializeListHead(&plugin_list);

	set_snd_ext_hook(0, NULL, YES);		 //ensure correct initialization of extension hooks

	struct plugin_v1 *pv1;

	pv1 = NULL;

	if ((pv1 = tun_get_plugin_v1()) != NULL)
		activate_plugin(pv1, PLUGIN_VERSION_01, NULL, NULL);
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
