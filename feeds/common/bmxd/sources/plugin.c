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


struct cb_snd_ext snd_ext_hooks[EXT_TYPE_MAX + 1];

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

void init_plugin(void)
{
	set_snd_ext_hook(0, NULL, YES);		 //ensure correct initialization of extension hooks
}
