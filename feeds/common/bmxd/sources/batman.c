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

#ifndef NOVIS

static struct vis_if *vis_if = NULL;

static unsigned char *vis_packet = NULL;
static uint16_t vis_packet_size = 0;
static int32_t vis_port = DEF_VIS_PORT;

static void send_vis_packet(void *unused)
{
	struct vis_if *vis = vis_if;
	struct list_head *list_pos;
	struct batman_if *batman_if;
	struct link_node *link_node;
	struct list_head *link_pos;
	struct list_head *lndev_pos;

	if (!vis || !vis->sock)
		return;

	if (vis_packet)
	{
		debugFree(vis_packet, 1102);
		vis_packet = NULL;
		vis_packet_size = 0;
	}

	vis_packet_size = sizeof(struct vis_packet);
	vis_packet = debugMalloc(vis_packet_size, 104);

	((struct vis_packet *)vis_packet)->sender_ip = primary_addr;
	((struct vis_packet *)vis_packet)->version = VIS_COMPAT_VERSION;
	((struct vis_packet *)vis_packet)->gw_class = Gateway_class;
	((struct vis_packet *)vis_packet)->seq_range = (PROBE_RANGE / PROBE_TO100);

	dbgf_all(DBGT_INFO, "sender_ip=%s version=%d gw_class=%d seq_range=%d",
					 ipStr(primary_addr), VIS_COMPAT_VERSION, Gateway_class, (PROBE_RANGE / PROBE_TO100));

	/* iterate link list */
	list_for_each(link_pos, &link_list)
	{
		link_node = list_entry(link_pos, struct link_node, list);

		if (link_node->orig_node->router == NULL)
			continue;

		uint32_t q_max = 0;
		struct vis_data *vis_data = NULL;

		list_for_each(lndev_pos, &link_node->lndev_list)
		{
			struct link_node_dev *lndev = list_entry(lndev_pos, struct link_node_dev, list);

			if (!lndev->rq_sqr.wa_val)
				continue;

			if (!vis_data)
			{
				vis_packet_size += sizeof(struct vis_data);

				vis_packet = debugRealloc(vis_packet, vis_packet_size, 105);

				vis_data = (struct vis_data *)(vis_packet + vis_packet_size - sizeof(struct vis_data));
			}

			if (vis_data && lndev->rq_sqr.wa_val > q_max)
			{
				vis_data->ip = link_node->orig_node->orig;
				vis_data->data = lndev->rq_sqr.wa_val / PROBE_TO100;
				vis_data->type = DATA_TYPE_NEIGH;

				dbgf_all(DBGT_INFO, "link to NB=%s lq=%d (dev=%s)",
								 ipStr(link_node->orig_node->orig), lndev->rq_sqr.wa_val, lndev->bif->dev);
			}

			q_max = MAX(lndev->rq_sqr.wa_val, q_max);
		}
	}

	/* secondary interfaces */

	list_for_each(list_pos, &if_list)
	{
		batman_if = list_entry(list_pos, struct batman_if, list);

		if (((struct vis_packet *)vis_packet)->sender_ip == batman_if->if_addr)
			continue;

		if (!batman_if->if_active)
			continue;

		vis_packet_size += sizeof(struct vis_data);

		vis_packet = debugRealloc(vis_packet, vis_packet_size, 106);

		struct vis_data *vis_data = (struct vis_data *)(vis_packet + vis_packet_size - sizeof(struct vis_data));

		vis_data->ip = batman_if->if_addr;

		vis_data->data = 0;
		vis_data->type = DATA_TYPE_SEC_IF;

		dbgf_all(DBGT_INFO, "interface %s (dev=%s)", ipStr(batman_if->if_addr), batman_if->dev);
	}

	if (vis_packet_size == sizeof(struct vis_packet))
	{
		debugFree(vis_packet, 1107);
		vis_packet = NULL;
		vis_packet_size = 0;
	}

	if (vis_packet != NULL)
		send_udp_packet(vis_packet, vis_packet_size, &vis->addr, vis->sock);

	register_task(10000, send_vis_packet, NULL);
}

static int32_t opt_vis(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	uint32_t vis_ip = 0;

	if (cmd == OPT_CHECK || cmd == OPT_APPLY)
	{
		if (patch->p_diff == DEL)
			vis_ip = 0;

		else if (str2netw(patch->p_val, &vis_ip, '/', cn, NULL, 0) == FAILURE)
			return FAILURE;
	}

	if (cmd == OPT_APPLY && vis_ip)
	{
		remove_task(send_vis_packet, NULL);

		if (vis_if && vis_if->sock)
			close(vis_if->sock);

		if (!vis_if)
			vis_if = debugMalloc(sizeof(struct vis_if), 731);

		memset(vis_if, 0, sizeof(struct vis_if));

		vis_if->addr.sin_family = AF_INET;
		vis_if->addr.sin_port = htons(vis_port);
		vis_if->addr.sin_addr.s_addr = vis_ip;
		vis_if->sock = socket(PF_INET, SOCK_DGRAM, 0);

		register_task(1000, send_vis_packet, NULL);
	}

	if ((cmd == OPT_APPLY && !vis_ip) || cmd == OPT_UNREGISTER)
	{
		remove_task(send_vis_packet, NULL);

		if (vis_if)
		{
			if (vis_if->sock)
				close(vis_if->sock);

			debugFree(vis_if, 1731);
			vis_if = NULL;
		}

		if (vis_packet)
		{
			debugFree(vis_packet, 1108);
			vis_packet = NULL;
		}
	}

	return SUCCESS;
}

static struct opt_type vis_options[] = {
		//           		ord parent long_name   shrt Attributes			*ival		min		max		default		*function
		{ODI, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		 "\nVisualization options:"},

		{ODI, 5, 0, "vis_server", 's', A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, 0, 0, 0, 0, opt_vis,
		 ARG_ADDR_FORM, "set IP of visualization server"}

};

static void vis_cleanup(void)
{
}

static int32_t vis_init(void)
{
	register_options_array(vis_options, sizeof(vis_options));

	return SUCCESS;
}

struct plugin_v1 *vis_get_plugin_v1(void)
{
	static struct plugin_v1 vis_plugin_v1;
	memset(&vis_plugin_v1, 0, sizeof(struct plugin_v1));

	vis_plugin_v1.plugin_version = PLUGIN_VERSION_01;
	vis_plugin_v1.plugin_size = sizeof(struct plugin_v1);
	vis_plugin_v1.plugin_name = "bmx_vis_plugin";
	vis_plugin_v1.cb_init = vis_init;
	vis_plugin_v1.cb_cleanup = vis_cleanup;

	return &vis_plugin_v1;
}

#endif /*NOVIS*/
