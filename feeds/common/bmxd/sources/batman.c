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
#include <time.h>

#include "batman.h"
#include "os.h"
#include "originator.h"
#include "metrics.h"
#include "plugin.h"
#include "schedule.h"

//#include "avl.h"

uint32_t My_pid = 0;

uint8_t ext_attribute[EXT_TYPE_MAX + 1] =
		{
				EXT_ATTR_KEEP,								// EXT_TYPE_64B_GW
// hna is removed, but this is still used by older firmware versions in pakets
				0,														// _removed_EXT_TYPE_64B_HNA
				0,														// EXT_TYPE_64B_PIP
				EXT_ATTR_KEEP,								// EXT_TYPE_64B_SRV
				EXT_ATTR_KEEP,								// EXT_TYPE_64B_KEEP_RESERVED4
				0,														// EXT_TYPE_64B_DROP_RESERVED5
				EXT_ATTR_TLV | EXT_ATTR_KEEP, // EXT_TYPE_TLV_KEEP_LOUNGE_REQ
				EXT_ATTR_TLV,									// EXT_TYPE_TLV_DROP_RESERVED7
				EXT_ATTR_KEEP,								// EXT_TYPE_64B_KEEP_RESERVED8
				0,														// EXT_TYPE_64B_DROP_RESERVED9
				EXT_ATTR_TLV | EXT_ATTR_KEEP, // EXT_TYPE_TLV_KEEP_RESERVED10
				EXT_ATTR_TLV,									// EXT_TYPE_TLV_DROP_RESERVED11
				EXT_ATTR_KEEP,								// EXT_TYPE_64B_KEEP_RESERVED12
				0,														// EXT_TYPE_64B_DROP_RESERVED13
				EXT_ATTR_TLV | EXT_ATTR_KEEP, // EXT_TYPE_TLV_KEEP_RESERVED14
				EXT_ATTR_TLV									// EXT_TYPE_TLV_DROP_RESERVED15
};

int32_t Gateway_class = 0;

//uint8_t Link_flags = 0;

batman_time_t batman_time = 0;
batman_time_t batman_time_sec = 0;

uint8_t on_the_fly = NO;

uint32_t s_curr_avg_cpu_load = 0;

void cb_watchdog(void *arg)
{
	FILE *fp = fopen("/tmp/state/bmxd.watchdog","w");
	if(fp)
	{
  	fprintf(fp, "%lu\n", (unsigned long)time(NULL) );
	  fclose(fp);
	}
	//register function AGAIN that updates unix time stamp to be used as watchdog
	register_task(30000, cb_watchdog, NULL);
}

void batman(void)
{
	struct list_head *list_pos;
	struct batman_if *batman_if;
	batman_time_t regular_timeout, statistic_timeout;

	batman_time_t s_last_cpu_time = 0, s_curr_cpu_time = 0;

	regular_timeout = statistic_timeout = batman_time;

	on_the_fly = YES;

	prof_start(PROF_all);

  //stephan: register function that updates unix time stamp to be used as watchdog
	cb_watchdog(NULL);

	while (!is_aborted())
	{
		prof_stop(PROF_all);
		prof_start(PROF_all);

		uint32_t wait = whats_next();

		if (wait)
			wait4Event(MIN(wait, MAX_SELECT_TIMEOUT_MS));

		// The regular tasks...
		if (LESS_U32(regular_timeout + 1000, batman_time))
		{
			purge_orig(batman_time, NULL);

			close_ctrl_node(CTRL_CLEANUP, 0);

			list_for_each(list_pos, &dbgl_clients[DBGL_ALL])
			{
				struct ctrl_node *cn = (list_entry(list_pos, struct dbgl_node, list))->cn;

				dbg_printf(cn, "------------------ DEBUG ------------------ \n");

				debug_send_list(cn);

				check_apply_parent_option(ADD, OPT_APPLY, 0, get_option(0, 0, ARG_STATUS), 0, cn);
				check_apply_parent_option(ADD, OPT_APPLY, 0, get_option(0, 0, ARG_LINKS), 0, cn);
				check_apply_parent_option(ADD, OPT_APPLY, 0, get_option(0, 0, ARG_ORIGINATORS), 0, cn);
				check_apply_parent_option(ADD, OPT_APPLY, 0, get_option(0, 0, ARG_GATEWAYS), 0, cn);
				dbg_printf(cn, "--------------- END DEBUG ---------------\n");
			}

			/* preparing the next debug_timeout */
			regular_timeout = batman_time;
		}

		if (LESS_U32(statistic_timeout + 5000, batman_time))
		{
			// check for corrupted memory..
			checkIntegrity();

			// check for changed kernel konfigurations...
			check_kernel_config(NULL);

			// check for changed interface konfigurations...
			list_for_each(list_pos, &if_list)
			{
				batman_if = list_entry(list_pos, struct batman_if, list);

				if (batman_if->if_active)
					check_kernel_config(batman_if);
			}

			/* generating cpu load statistics... */
			s_curr_cpu_time = (uint32_t)clock();

			s_curr_avg_cpu_load = ((s_curr_cpu_time - s_last_cpu_time) / (batman_time_t)(batman_time - statistic_timeout));

			s_last_cpu_time = s_curr_cpu_time;

			statistic_timeout = batman_time;
		}
	}

	prof_stop(PROF_all);
}

/*some static plugins*/
