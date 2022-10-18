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

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <linux/sockios.h>
#include <linux/if.h> /* ifr_if, ifr_tun */
#include <linux/rtnetlink.h>

#include "batman.h"
#include "os.h"
#include "originator.h"
#include "metrics.h"
#include "plugin.h"
#include "schedule.h"

int32_t my_ogi; /* orginator message interval in miliseconds */
int32_t ogi_pwrsave;

static int32_t pref_udpd_size = DEF_UDPD_SIZE;

//static int32_t aggr_p_ogi;
static int32_t aggr_interval;

#ifndef NOPARANOIA
#define DEF_SIM_PARA NO
static int32_t sim_paranoia = DEF_SIM_PARA;
#endif

static LIST_ENTRY send_list;
static LIST_ENTRY task_list;

static int32_t receive_max_sock = 0;
static fd_set receive_wait_set;

static uint16_t changed_readfds = 1;

static int ifevent_sk = -1;

static struct ext_packet my_pip_extension_packet;

void change_selects(void)
{
	changed_readfds++;
}

static void check_selects(void)
{
	if (changed_readfds == 0)
		return;

	dbgf_all(DBGT_INFO, "%d select fds changed... ", changed_readfds);

	changed_readfds = 0;

	FD_ZERO(&receive_wait_set);
	receive_max_sock = 0;

	receive_max_sock = ifevent_sk;
	FD_SET(ifevent_sk, &receive_wait_set);

	if (receive_max_sock < unix_sock)
		receive_max_sock = unix_sock;

	FD_SET(unix_sock, &receive_wait_set);

	OLForEach(cn, struct ctrl_node, ctrl_list)
	{
		if (cn->fd > 0 && cn->fd != STDOUT_FILENO)
		{
			receive_max_sock = MAX(receive_max_sock, cn->fd);

			FD_SET(cn->fd, &receive_wait_set);
		}
	}

	OLForEach(bif, struct batman_if, if_list)
	{
		if (bif->if_active && bif->if_linklayer != VAL_DEV_LL_LO)
		{
			receive_max_sock = MAX(receive_max_sock, bif->if_unicast_sock);

			FD_SET(bif->if_unicast_sock, &receive_wait_set);

			receive_max_sock = MAX(receive_max_sock, bif->if_netwbrc_sock);

			FD_SET(bif->if_netwbrc_sock, &receive_wait_set);

			if (bif->if_fullbrc_sock > 0)
			{
				receive_max_sock = MAX(receive_max_sock, bif->if_fullbrc_sock);

				FD_SET(bif->if_fullbrc_sock, &receive_wait_set);
			}
		}
	}

}

void register_task(uint32_t timeout, void (*task)(void *), void *data)
{

	//TODO: allocating and freeing tn and tn->data may be much faster when done by registerig function..
	struct task_node *tn = debugMalloc(sizeof(struct task_node), 109);
	memset(tn, 0, sizeof(struct task_node));

	tn->expire = batman_time + timeout;
	tn->task = task;
	tn->data = data;

	int inserted = 0;
	OLForEach(tmp_tn, struct task_node, task_list)
	{

		if ( tmp_tn->expire > tn->expire )
		{
			OLInsertTailList((PLIST_ENTRY)tmp_tn, (PLIST_ENTRY)tn);
			inserted = 1;
			break;
		}
	}

	if (!inserted)
		OLInsertTailList(&task_list, (PLIST_ENTRY)tn);
}

void remove_task(void (*task)(void *), void *data)
{
	OLForEach(tn, struct task_node, task_list)
	{

		if (tn->task == task && tn->data == data)
		{
			LIST_ENTRY *prev = OLGetPrev(tn);
			OLRemoveEntry(tn);

			if (tn->data)
			{
				debugFree(tn->data, 1109);
			}
			debugFree(tn, 1109);
			tn = (struct task_node *)prev;
		}
	}
}

uint32_t whats_next(void)
{

	paranoia(-500175, sim_paranoia);

	OLForEach(tn, struct task_node, task_list)
	{
		if (tn->expire <= batman_time)
		{
			OLRemoveEntry(tn);

			(*(tn->task))(tn->data);

			if (tn->data)
			{
				debugFree(tn->data, 1109);
			}
			debugFree(tn, 1109);

			return 0;
		}
		else
		{
			return tn->expire - batman_time;
		}
	}

	return MAX_SELECT_TIMEOUT_MS;
}

static void send_aggregated_ogms(void)
{
	prof_start(PROF_send_aggregated_ogms);

	uint8_t iftype;

	/* send all the aggregated packets (which fit into max packet size) */

	/* broadcast via lan interfaces first */
	for (iftype = VAL_DEV_LL_LAN; iftype <= VAL_DEV_LL_WLAN; iftype++)
	{
		OLForEach(bif, struct batman_if, if_list)
		{

			dbgf_all(DBGT_INFO, "dev: %s, linklayer %d iftype %d len %d min_len %d...",
							 bif->dev, bif->if_linklayer, iftype, bif->aggregation_len,
							 (int32_t)sizeof(struct bat_header));

			if (bif->if_linklayer == iftype &&
					bif->aggregation_len > (int32_t)sizeof(struct bat_header))
			{
				struct bat_header *bat_hdr = (struct bat_header *)bif->aggregation_out;
				bat_hdr->version = COMPAT_VERSION;
				bat_hdr->networkId_high = gNetworkId >> 8;
				bat_hdr->networkId_low  = gNetworkId & 0xff;
				bat_hdr->size = (bif->aggregation_len) / 4;

				if (bif->aggregation_len > MAX_UDPD_SIZE || (bif->aggregation_len) % 4 != 0)
				{
					dbg(DBGL_SYS, DBGT_ERR, "trying to send strange packet length %d oktets",
							bif->aggregation_len);

					cleanup_all(-500016);
				}

				if (send_udp_packet(bif->aggregation_out, bif->aggregation_len,
														&bif->if_netwbrc_addr, bif->if_unicast_sock) < 0)
				{
					dbg_mute(60, DBGL_SYS, DBGT_ERR,
									 "send_aggregated_ogms() cant send via dev %s %s fd %d",
									 bif->dev, bif->if_ip_str, bif->if_unicast_sock);
				}

				bif->aggregation_len = sizeof(struct bat_header);
			}
		}
	}

	prof_stop(PROF_send_aggregated_ogms);
	return;
}

void debug_send_list(struct ctrl_node *cn)
{
	//char str[ADDR_STR_LEN];

	dbg_printf(cn, "Outstanding OGM for sending: \n");

	OLForEach(send_node, struct send_node, send_list)
	{
		struct bat_packet_ogm *ogm = send_node->ogm;

		dbg_printf(cn, "%-15s   (seqno %5d  ttl %3d)  at %llu (if_seqno=%d) to iff %s\n",
							 ipStr(ogm->orig), ntohs(ogm->ogm_seqno), ogm->ogm_ttl, (unsigned long long)send_node->send_time, send_node->if_outgoing->if_seqno, send_node->if_outgoing->dev);
	}

	dbg_printf(cn, "\n");
	return;
}

static int open_ifevent_netlink_sk(void)
{
	struct sockaddr_nl sa;
	int32_t unix_opts;
	memset(&sa, 0, sizeof(sa));
	sa.nl_family = AF_NETLINK;
	sa.nl_groups |= RTMGRP_IPV4_IFADDR;
	sa.nl_groups |= RTMGRP_LINK; // (this can result in select storms with buggy wlan devices

	if ((ifevent_sk = socket(AF_NETLINK, SOCK_RAW, NETLINK_ROUTE)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't create af_netlink socket for reacting on if up/down events: %s",
				strerror(errno));
		ifevent_sk = 0;
		return -1;
	}

	unix_opts = fcntl(ifevent_sk, F_GETFL, 0);
	fcntl(ifevent_sk, F_SETFL, unix_opts | O_NONBLOCK);

	if ((bind(ifevent_sk, (struct sockaddr *)&sa, sizeof(sa))) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't bind af_netlink socket for reacting on if up/down events: %s",
				strerror(errno));
		ifevent_sk = 0;
		return -1;
	}

	change_selects();

	return ifevent_sk;
}

static void close_ifevent_netlink_sk(void)
{
	if (ifevent_sk > 0)
		close(ifevent_sk);

	ifevent_sk = 0;
}

static void recv_ifevent_netlink_sk(void)
{
	char buf[4096]; //test this with a very small value !!
	struct iovec iov = {buf, sizeof(buf)};
	struct sockaddr_nl sa;
	struct msghdr msg = {(void *)&sa, sizeof(sa), &iov, 1, NULL, 0, 0};

	while (recvmsg(ifevent_sk, &msg, 0) > 0)
		;

	//so fare I just want to consume the pending message...
}

void remove_outstanding_ogms(struct batman_if *bif)
{

	if (!bif)
		return;

	OLForEach(send_node, struct send_node, send_list)
	{
		if (send_node->if_outgoing == bif)
		{
			LIST_ENTRY *prev = OLGetPrev(send_node);
			OLRemoveEntry(send_node);
			debugFree(send_node, 1502);
			send_node = (struct send_node *)prev;
		}
	}
}

static void aggregate_outstanding_ogms(void *unused)
{
	prof_start(PROF_send_outstanding_ogms);

	uint8_t directlink, unidirectional, cloned, ttl, if_singlehomed;
	int16_t aggregated_size = sizeof(struct bat_header);

	int dbg_if_out = 0;
#define MAX_DBG_IF_SIZE 200
	static char dbg_if_str[MAX_DBG_IF_SIZE];

	// ensuring that aggreg_interval is really an upper boundary
	register_task(aggr_interval - 1 - rand_num(aggr_interval / 10), aggregate_outstanding_ogms, NULL);

	OLForEach(send_node, struct send_node, send_list)
	{
		if ( send_node->send_time > batman_time )
			break; // for now we are done,

		if (aggregated_size > (int32_t)sizeof(struct bat_header) &&
				aggregated_size + send_node->ogm_buff_len > pref_udpd_size)
		{
			dbgf_all(DBGT_INFO, "max aggregated size %d", aggregated_size);
			send_aggregated_ogms();
			aggregated_size = sizeof(struct bat_header);
		}

		send_node->iteration++;

		uint8_t send_node_done = YES;

		if ((aggregated_size + send_node->ogm_buff_len > MAX_UDPD_SIZE) ||
				(aggregated_size + send_node->ogm_buff_len > pref_udpd_size && send_node->own_if))
		{
			if (aggregated_size <= (int32_t)sizeof(struct bat_header))
			{
				dbg_mute(30, DBGL_SYS, DBGT_ERR,
								 "Drop OGM, single packet (own=%d) to large to fit legal packet size"
								 "scheduled %llu, agg_size %d, next_len %d, pref_udpd_size %d  !!",
								 send_node->own_if, (unsigned long long)send_node->send_time,
								 aggregated_size, send_node->ogm_buff_len, pref_udpd_size);
			}
		}
		else
		{
			if (send_node->send_bucket == 0)
			{
				send_node->send_bucket = ((int32_t)(rand_num(100)));
			}

			// keep care to not aggregate more packets than would fit into max packet size
			aggregated_size += send_node->ogm_buff_len;

			directlink = (send_node->ogm->flags & DIRECTLINK_FLAG) > 0;
			unidirectional = (send_node->ogm->flags & UNIDIRECTIONAL_FLAG) > 0;
			cloned = (send_node->ogm->flags & CLONED_FLAG) > 0;

			ttl = send_node->ogm->ogm_ttl;
			if_singlehomed = ((send_node->own_if && send_node->if_outgoing->if_singlehomed) ? 1 : 0);

			//can't forward packet with IDF: outgoing iface not specified
			paranoia(-500015, (directlink && !send_node->if_outgoing));

			if (!send_node->if_outgoing->if_active)
			{
				dbg_if_out += snprintf((dbg_if_str + dbg_if_out), (MAX_DBG_IF_SIZE - dbg_if_out), " (down)");
			}
			/* stephan:
 OGM kommt entweder von aussen oder von localen interfaces.
 Wenn eine OGM von aussen kommt und nicht die eigene OGM (die zurueck kommt), dann wird am anfang
 die node-strucktur (die diese node representiert) als unidirekt markiert. Bedeutet, dass noch kein direkter link
 zwischen diesem und den anderen node erkannt worden ist.
 Dann wird diese OGM mit (unidirectflag) genau ueber das gleiche interface zurueck geschickt.
 Hinweis: diese selbe OGM von aussen kann auch noch ueber ein anderes interface empfangen werden.
 Auch dann wird diese zweite OGM nur ueber das zweite interface zurueck geschickt mit dem unidirectlflag.

 Die andere node erkennt dann an diesem unidirect flag und dass es sich um seine eignene node ist und
 antwortet im nachsten OGM mit dem direct-link-flag. das wird hier in der node-strucktur (die diese andere
 represendiert) gespeichert (unidirectflag wird geloescht).

 Alle anderen OGM die dann von diesem node ueber irgendein inteface kommen, werden als "normale"
 OGM an alle anderen interfaces verteilt.
 Das macht der else-zweig der nachfolgenden if-anweiseung. die aktuelle OGM, welche zurueck an
 die sender-node (via primary ip erkannt) uber das gleich interface geschickt wird, wo die OGM
 emfangen wird, wird dann in einer loop durch alle anderen interfaces ebenfalls an das interface gehängt.

 jedes interface hat einen eingenen aggregations-buffer, in der die ogms gesammelt werden, die ueber die interface
 verschickt werden sollen.

 singlehomed bedeutet nur, dass der node nur ein interface hat.
 ist das nicht gesetzt, so werden OGMs an alle interfaces angehängt und dann später versendet.

 im original wird nur eine "grosse" OGM erzeugt (mit gateway,...) und �beralle alle interfaces mit
 TTL 50 verschickt. "kleine" OGM enthalten nur die ip des interfaces und als einzige erweiterung
 die ip und seqno der grossen OGM. diese werden mit ttl=1 verschickt, so dass diese ip von den
 non-prim interfaces nicht im netz gestreut werden.
 Nur die grosse ogm travelt durch das netz.

 Das setzt aber voraus, dass die non-prim interfaces alles verschiedene IPs zum primaren
 interface haben, da die ogm
 bei der metrik berechnung von der primary ogm unterschieden werden.

*/
			/* rebroadcast only to allow neighbor to detect bidirectional link */
			if (send_node->if_outgoing->if_active &&
					send_node->iteration <= 1 &&
					directlink &&
					!cloned &&
					(unidirectional || ttl == 0))
			{
				dbg_if_out += snprintf((dbg_if_str + dbg_if_out), (MAX_DBG_IF_SIZE - dbg_if_out),
															 " %-12s  (NBD)", send_node->if_outgoing->dev);

				if ((send_node->send_bucket + 100) < send_node->if_outgoing->if_send_clones)
					send_node_done = NO;

				//TODO: send only pure bat_packet_ogm, no extension headers.
				memcpy(send_node->if_outgoing->aggregation_out +
									 send_node->if_outgoing->aggregation_len,
							 send_node->ogm, send_node->ogm_buff_len);

				send_node->if_outgoing->aggregation_len += send_node->ogm_buff_len;

				/* (re-) broadcast to propagate existence of path to OG*/
			}
			else if (!unidirectional && ttl > 0)
			{
				struct bat_packet_ogm *ogm;

				OLForEach(bif, struct batman_if, if_list)
				{

					if (!bif->if_active)
						continue;

					if ((send_node->send_bucket >= bif->if_send_clones) ||
							(if_singlehomed && send_node->if_outgoing != bif))
						continue;

					if (
							// power-save mode enabled:
							ogi_pwrsave > my_ogi
							&&  batman_time > ( bif->if_last_link_activity + COMMON_OBSERVATION_WINDOW)
							&&	( // not yet time for a neighbor-discovery hardbeat?:
									send_node->own_if == 0 ||
									send_node->if_outgoing != bif ||
									batman_time <= bif->if_next_pwrsave_hardbeat)
						 )
						 { continue; }

					if ((send_node->send_bucket + 100) < bif->if_send_clones)
						send_node_done = NO;

					ogm = (struct bat_packet_ogm *)(bif->aggregation_out + bif->aggregation_len);

					memcpy(ogm, send_node->ogm, send_node->ogm_buff_len);

					if (send_node->iteration > 1)
						ogm->flags |= CLONED_FLAG;

					if ((directlink) && (send_node->if_outgoing == bif))
						ogm->flags |= DIRECTLINK_FLAG;
					else
						ogm->flags &= ~DIRECTLINK_FLAG;

					bif->aggregation_len += send_node->ogm_buff_len;

					dbg_if_out += snprintf((dbg_if_str + dbg_if_out),
																 (MAX_DBG_IF_SIZE - dbg_if_out), " %-12s", bif->dev);

					if (if_singlehomed && send_node->if_outgoing == bif)
						dbg_if_out += snprintf((dbg_if_str + dbg_if_out),
																	 (MAX_DBG_IF_SIZE - dbg_if_out), "  (npIF)");
				}
			}

			send_node->send_bucket += 100;

			dbgf_all(DBGT_INFO,
							 "OG %-16s, seqno %5d, TTL %2d, DirectF %d, UniF %d, CloneF %d "
							 "iter %d len %3d max agg_size %3d IFs %s",
							 ipStr(send_node->ogm->orig),
							 ntohs(send_node->ogm->ogm_seqno),
							 ttl, directlink, unidirectional, cloned, send_node->iteration,
							 send_node->ogm_buff_len, aggregated_size, dbg_if_str);

			*dbg_if_str = '\0';
			dbg_if_out = 0;
		}

		// trigger next seqno now where the first one of the current seqno has been send
		if (send_node->own_if && send_node->iteration == 1)
		{
			send_node->if_outgoing->if_seqno++;
			send_node->if_outgoing->send_own = 1;
		}

		// remove all the finished packets from send_list
		if (send_node_done)
		{
			LIST_ENTRY *prev = OLGetPrev(send_node);
			OLRemoveEntry(send_node);
			debugFree(send_node, 1502);
			send_node = (struct send_node *)prev;
		}
	}

	if (aggregated_size > (int32_t)sizeof(struct bat_header))
	{
		send_aggregated_ogms();

		dbgf_all(DBGT_INFO, "max aggregated size %d", aggregated_size);
	}

	OLForEach(bif, struct batman_if, if_list)
	{
		if (bif->aggregation_len != sizeof(struct bat_header))
		{
			dbgf(DBGL_SYS, DBGT_ERR,
					 "finished with dev %s and packet_out_len %d > %d",
					 bif->dev, bif->aggregation_len, (int)sizeof(struct bat_header));
		}

		// if own OGMs need to be send, schedule next one now
		if (bif->send_own)
		{
			schedule_own_ogm(bif);

			if ( batman_time > bif->if_next_pwrsave_hardbeat )
			{
				bif->if_next_pwrsave_hardbeat = batman_time + ((uint32_t)(ogi_pwrsave));
			}

			bif->send_own = 0;
		}

		// this timestamp may become invalid after U32 wrap-around
		if ( batman_time > (bif->if_last_link_activity + (2 * COMMON_OBSERVATION_WINDOW)) )
		{	bif->if_last_link_activity = batman_time - COMMON_OBSERVATION_WINDOW; }
	}

	prof_stop(PROF_send_outstanding_ogms);

	return;
}

void schedule_rcvd_ogm(uint16_t oCtx, uint16_t neigh_id, struct msg_buff *mb)
{
	prof_start(PROF_schedule_rcvd_ogm);

	uint8_t with_unidirectional_flag = 0;
	uint8_t directlink = 0;

	/* is single hop (direct) neighbour */
	if (oCtx & IS_DIRECT_NEIGH)
	{
		directlink = 1;

		/* it is our best route towards him */
		if ((oCtx & IS_ACCEPTED) && (oCtx & IS_BEST_NEIGH_AND_NOT_BROADCASTED))
		{
			if (oCtx & IS_ASOCIAL)
			{
				dbgf_all(DBGT_INFO, "re-brc (accepted) neighb OGM with direct link and unidirect flag");
				with_unidirectional_flag = 1;
			}
			else
			{ // mark direct link on incoming interface
				dbgf_all(DBGT_INFO, "rebroadcast neighbour (accepted) packet with direct link flag");
			}

			/* if an unidirectional direct neighbour sends us a packet or
		 * if a bidirectional neighbour sends us a packet who is not our best link to him:
		 * retransmit it with unidirectional flag to tell him that we get his packets       */
		}
		else if (!(oCtx & HAS_CLONED_FLAG))
		{
			dbgf_all(DBGT_INFO, "re-brc (answer back) neighb OGM with direct link and unidirect flag");
			with_unidirectional_flag = 1;
		}
		else
		{
			dbgf_all(DBGT_INFO, "drop OGM: no reason to re-brc!");
			prof_stop(PROF_schedule_rcvd_ogm);
			return;
		}
	}
	else if (oCtx & IS_ASOCIAL)
	{
		dbgf_all(DBGT_INFO, "drop OGM, asocial devices re-brc almost nothing :-(");
		prof_stop(PROF_schedule_rcvd_ogm);
		return;

		/* multihop originator */
	}
	else if ((oCtx & IS_ACCEPTED) && (oCtx & IS_BEST_NEIGH_AND_NOT_BROADCASTED))
	{
		dbgf_all(DBGT_INFO, "re-brc accepted OGM");
	}
	else
	{
		dbgf_all(DBGT_INFO, "drop multihop OGM, not accepted or not via best link !");
		prof_stop(PROF_schedule_rcvd_ogm);
		return;
	}

	if (!(((mb->ogm)->ogm_ttl == 1 && directlink) || (mb->ogm)->ogm_ttl > 1))
	{
		dbgf_all(DBGT_INFO, "ttl exceeded");
		prof_stop(PROF_schedule_rcvd_ogm);
		return;
	}

	uint16_t i, snd_ext_total_len = 0;

	for (i = 0; i <= EXT_TYPE_MAX; i++)
		snd_ext_total_len += mb->snd_ext_len[i];

	struct send_node *sn = debugMalloc(sizeof(struct send_node) + sizeof(struct bat_packet_ogm) + snd_ext_total_len, 504);
	memset(sn, 0, sizeof(struct send_node));

	sn->ogm_buff_len = sizeof(struct bat_packet_ogm) + snd_ext_total_len;
	sn->ogm = (struct bat_packet_ogm *)sn->_attached_ogm_buff;

	memcpy(sn->ogm, mb->ogm, sizeof(struct bat_packet_ogm));

	/* primary-interface-extension messages do not need to be rebroadcastes */
	/* other extension messages only if not unidirectional and ttl > 1 */

	uint16_t p = sizeof(struct bat_packet_ogm);

	for (i = 0; (snd_ext_total_len && i <= EXT_TYPE_MAX); i++)
	{
		if (mb->snd_ext_len[i])
		{
			memcpy(&(((unsigned char *)(sn->ogm))[p]),
						 (unsigned char *)(mb->snd_ext_array[i]),
						 mb->snd_ext_len[i]);

			p += mb->snd_ext_len[i];
		}
	}

	if (p != sn->ogm_buff_len)
	{
		dbgf(DBGL_SYS, DBGT_ERR, "incorrect msg lengths %d != %d", p, sn->ogm_buff_len);
	}

	sn->ogm->ogm_ttl--;
	sn->ogm->prev_hop_id = neigh_id;
	sn->ogm->bat_size = (sn->ogm_buff_len) >> 2;

	sn->send_time = batman_time;
	sn->own_if = 0;

	sn->if_outgoing = mb->iif;

	sn->ogm->flags = 0x00;

	if (with_unidirectional_flag)
		sn->ogm->flags |= UNIDIRECTIONAL_FLAG;

	if (directlink)
		sn->ogm->flags |= DIRECTLINK_FLAG;

	if (oCtx & HAS_CLONED_FLAG)
		sn->ogm->flags |= CLONED_FLAG;

	/* change sequence number to network order */
	sn->ogm->ogm_seqno = htons(sn->ogm->ogm_seqno);

	// we send the ogm back as answer with direct link, unidirect, to tell neighbour that we are direct connected
	dbgf_all(DBGT_INFO, "prepare send re-brc OGM TTL %d DirectF %d UniF %d ", sn->ogm->ogm_ttl, directlink, with_unidirectional_flag );

	int inserted = 0;
	OLForEach(send_packet_tmp, struct send_node, send_list)
	{

		if ( send_packet_tmp->send_time > sn->send_time )
		{
			OLInsertTailList((PLIST_ENTRY)send_packet_tmp, (PLIST_ENTRY)sn);
			inserted = 1;
			break;
		}
	}

	if (!inserted)
	{
		OLInsertTailList(&send_list, (PLIST_ENTRY)sn);
	}

	prof_stop(PROF_schedule_rcvd_ogm);
}

static void strip_packet(struct msg_buff *mb, unsigned char *pos, int32_t udp_len)
{
	prof_start(PROF_strip_packet);

	uint16_t left_p, ext_type, done_p, ext_p;
	unsigned char *ext_a;

	while (udp_len >= (int32_t)sizeof(struct bat_packet_common) &&
				 udp_len >= ((struct bat_packet_common *)pos)->bat_size << 2)
	{
		if (((struct bat_packet_common *)pos)->bat_type == BAT_TYPE_OGM)
		{
			((struct bat_packet_ogm *)pos)->ogm_seqno =
					ntohs(((struct bat_packet_ogm *)pos)->ogm_seqno);

			mb->ogm = (struct bat_packet_ogm *)pos;

			/* process optional extension messages */

			left_p = udp_len - sizeof(struct bat_packet_ogm);
			done_p = 0;

			memset(mb->rcv_ext_len, 0, sizeof(mb->rcv_ext_len));
			memset(mb->snd_ext_len, 0, sizeof(mb->snd_ext_len));

			ext_type = 0;

			ext_a = (pos + sizeof(struct bat_packet_ogm) + done_p);
			ext_p = 0;

			while (done_p < left_p &&
						 done_p < ((((struct bat_packet_common *)pos)->bat_size) << 2) &&
						 ((struct ext_packet *)(ext_a))->EXT_FIELD_MSG == YES &&
						 ext_type <= EXT_TYPE_MAX)
			{
				while ((ext_p + done_p) < left_p &&
							 ((struct ext_packet *)(ext_a + ext_p))->EXT_FIELD_MSG == YES)
				{
					if (((struct ext_packet *)(ext_a + ext_p))->EXT_FIELD_TYPE == ext_type)
					{
						if (ext_attribute[ext_type] & EXT_ATTR_TLV)
							ext_p += 4 * ((struct ext_packet *)(ext_a + ext_p))->EXT_FIELD_LEN_4B;

						else
							ext_p += sizeof(struct ext_packet);
					}
					else if (((struct ext_packet *)(ext_a + ext_p))->EXT_FIELD_TYPE > ext_type)
					{
						break;
					}
					else
					{
						dbg_mute(75, DBGL_SYS, DBGT_ERR,
										 "Drop packet! Rcvd incompatible extension message order: "
										 "via NB %s  OG? %s  size? %i, ext_type %d",
										 mb->neigh_str, ipStr(mb->ogm->orig),
										 udp_len, ((struct ext_packet *)(ext_a + ext_p))->EXT_FIELD_TYPE);

						prof_stop(PROF_strip_packet);
						return;
					}
				}

				done_p = done_p + ext_p;

				if (ext_p)
				{
					mb->rcv_ext_array[ext_type] = (struct ext_packet *)ext_a;
					mb->rcv_ext_len[ext_type] = ext_p;

					if (ext_attribute[ext_type] & EXT_ATTR_KEEP)
					{
						mb->snd_ext_array[ext_type] = (struct ext_packet *)ext_a;
						mb->snd_ext_len[ext_type] = ext_p;
					}
				}

				ext_a = pos + sizeof(struct bat_packet_ogm) + done_p;
				ext_p = 0;
				ext_type++;
			}

			if ((int32_t)(sizeof(struct bat_packet_ogm) + done_p) !=
					((((struct bat_packet_common *)pos)->bat_size) << 2))
			{
				udp_len = udp_len - ((((struct bat_packet_common *)pos)->bat_size) << 2);
				pos = pos + ((((struct bat_packet_common *)pos)->bat_size) << 2);

				dbg_mute(60, DBGL_SYS, DBGT_ERR,
								 "Drop packet! Rcvd corrupted packet size via NB %s: "
								 "processed bytes: %d , indicated bytes %d, flags. %X, remaining bytes %d",
								 mb->neigh_str,
								 (int)(sizeof(struct bat_packet_ogm) + done_p),
								 ((((struct bat_packet_common *)pos)->bat_size) << 2),
								 ((struct bat_packet_ogm *)pos)->flags, udp_len);

				prof_stop(PROF_strip_packet);
				return;
			}

			dbgf_all(DBGT_INFO,
							 "rcvd OGM: flags. %X, remaining bytes %d", (mb->ogm)->flags, udp_len);

			process_ogm(mb);
		}
		else
		{
			dbg_mute(47, DBGL_CHANGES, DBGT_WARN,
								"Drop single unkown bat_type via NB %s, bat_type %X, size %i,  "
								"OG? %s, remaining len %d. Maybe you need an update",
								mb->neigh_str,
								((struct bat_packet_common *)pos)->bat_type,
								(((struct bat_packet_common *)pos)->bat_size) << 2,
								ipStr(((struct bat_packet_ogm *)pos)->orig), udp_len);
		}

		/* prepare for next ogm and attached extension messages */
		udp_len = udp_len - ((((struct bat_packet_common *)pos)->bat_size) << 2);
		pos = pos + ((((struct bat_packet_common *)pos)->bat_size) << 2);

	} //while

	prof_stop(PROF_strip_packet);
}

static void process_packet(struct msg_buff *mb, unsigned char *pos, uint32_t rcvd_neighbor)
{
	prof_start(PROF_process_packet);

	int32_t check_len, check_done, udp_len;
	unsigned char *check_pos;

	if (mb->total_length < (int32_t)(sizeof(struct bat_header) + sizeof(struct bat_packet_common)))
	{
		dbg_mute(35, DBGL_SYS, DBGT_ERR, "Invalid packet length from %s, len %d",
						 ipStr(rcvd_neighbor), mb->total_length);

		prof_stop(PROF_process_packet);
		return;
	}

	// immediately drop my own packets
	if (rcvd_neighbor == mb->iif->if_addr)
	{
		dbgf_all(DBGT_INFO, "Drop packet: received my own broadcast iif %s", mb->iif->dev);

		prof_stop(PROF_process_packet);
		return;
	}

	addr_to_str(rcvd_neighbor, mb->neigh_str);

	//SE: add network ID, but enable/disable check
	mb->networkId =   (((struct bat_header *)pos)->networkId_high) << 8
	                | (((struct bat_header *)pos)->networkId_low) ;

	// immediately drop invalid packets...
	// we acceppt longer packets than specified by pos->size to allow padding for equal packet sizes
	if (((((struct bat_header *)pos)->size) << 2) < (int32_t)(sizeof(struct bat_header) + sizeof(struct bat_packet_common)) ||
			(((struct bat_header *)pos)->version) != COMPAT_VERSION ||
			((((struct bat_header *)pos)->size) << 2) > mb->total_length)
	{
		if (mb->total_length >= (int32_t)(sizeof(struct bat_header) /*+ sizeof(struct bat_packet_common) */))
		{
			dbg_mute(60, DBGL_SYS, DBGT_WARN,
							 "Drop packet: rcvd incompatible batman packet via NB %s "
							 "(version %i, networkId %u, size %i), "
							 "rcvd udp_len %d  My version is %d",
							 mb->neigh_str,
							 ((struct bat_header *)pos)->version,
							 mb->networkId,
							 ((struct bat_header *)pos)->size,
							 mb->total_length, COMPAT_VERSION);
		}
		else
		{
			dbg_mute(40, DBGL_SYS, DBGT_ERR, "Rcvd to small packet via NB %s, rcvd udp_len %i",
							 mb->neigh_str, mb->total_length);
		}

		prof_stop(PROF_process_packet);
		return;
	}

	mb->neigh = rcvd_neighbor;


	dbgf_all(DBGT_INFO, "version %i, "
											"networkId %u, size %i, rcvd udp_len %d via NB %s %s %s",
					 ((struct bat_header *)pos)->version,
					 mb->networkId,
					 ((struct bat_header *)pos)->size,
					 mb->total_length, mb->neigh_str, mb->iif->dev, mb->unicast ? "UNICAST" : "BRC");

	#ifndef DISABLE_NETWORK_ID_CHECK
		//se: check networkId against our
		if ( mb->networkId != gNetworkId)
		{
			dbgf_all(DBGT_INFO, "Drop packet: invalid networkId %u iif %s", mb->iif->dev);

			prof_stop(PROF_process_packet);
			return;
		}
	#endif

	check_len = udp_len = ((((struct bat_header *)pos)->size) << 2) - sizeof(struct bat_header);
	check_pos = pos = pos + sizeof(struct bat_header);

	// immediately drop non-plausibile packets...
	check_done = 0;

	while (check_done < check_len)
	{
		if ((((struct bat_packet_common *)check_pos)->ext_msg) == 1 ||
				(((struct bat_packet_common *)check_pos)->bat_size) == 0 ||
				((((struct bat_packet_common *)check_pos)->bat_size) << 2) > check_len - check_done)
		{
			char orig_str[16];
			if ((((struct bat_packet_common *)check_pos)->ext_msg) == 0 &&
					((((struct bat_packet_common *)check_pos)->bat_size) << 2) >=
							(int32_t)sizeof(struct bat_packet_ogm) &&
					check_len >= (int32_t)sizeof(struct bat_packet_ogm))

				addr_to_str(((struct bat_packet_ogm *)check_pos)->orig, orig_str);

			else
				addr_to_str(0, orig_str);

			dbg_mute(70, DBGL_SYS, DBGT_ERR,
							 "Drop jumbo packet: rcvd incorrect size or order via NB %s, Originator? %s: "
							 "ext_msg %d, reserved %X, OGM size field %d aggregated OGM size %i, via IF: %s",
							 mb->neigh_str, orig_str,
							 ((struct bat_packet_common *)check_pos)->ext_msg,
							 ((struct bat_packet_common *)check_pos)->reserved1,
							 ((((struct bat_packet_common *)check_pos)->bat_size)),
							 check_len, mb->iif->dev);

			prof_stop(PROF_process_packet);
			return;
		}

		check_done = check_done + ((((struct bat_packet_common *)check_pos)->bat_size) << 2);
		check_pos = check_pos + ((((struct bat_packet_common *)check_pos)->bat_size) << 2);
	}

	if (check_len != check_done)
	{
		dbg_mute(40, DBGL_SYS, DBGT_ERR,
						 "Drop jumbo packet via %s: End of packet does not match indicated size",
						 mb->neigh_str);

		prof_stop(PROF_process_packet);
		return;
	}

	mb->iif->if_last_link_activity = batman_time;

	strip_packet(mb, pos, udp_len);

	prof_stop(PROF_process_packet);
}

void wait4Event(uint32_t timeout)
{
	prof_start(PROF_wait4Event);

	static unsigned char packet_in[2001];
	static struct msg_buff msg_buff;
	struct msg_buff *mb = &msg_buff;

	batman_time_t last_get_time_result = 0;

	struct sockaddr_in addr;
	static uint32_t addr_len = sizeof(struct sockaddr_in);

	batman_time_t return_time = batman_time + timeout;
	struct timeval tv;
	int selected;
	fd_set tmp_wait_set;

loop4Event:

	prof_stop(PROF_wait4Event_5);

	while ( return_time > batman_time )
	{
		prof_start(PROF_wait4Event_select);

		check_selects();

		memcpy(&tmp_wait_set, &receive_wait_set, sizeof(fd_set));

		tv.tv_sec = (return_time - batman_time) / 1000;
		tv.tv_usec = ((return_time - batman_time) % 1000) * 1000;

		selected = select(receive_max_sock + 1, &tmp_wait_set, NULL, NULL, &tv);

		update_batman_time(&(mb->tv_stamp));

		//omit debugging here since event could be a closed -d4 ctrl socket
		//which should be removed before debugging
		//dbgf_all( DBGT_INFO, "timeout %d", timeout );

		prof_stop(PROF_wait4Event_select);

		if (batman_time < last_get_time_result)
		{
			last_get_time_result = batman_time;
			dbg(DBGL_SYS, DBGT_WARN, "detected Timeoverlap...");

			goto wait4Event_end;
		}

		last_get_time_result = batman_time;

		if (selected < 0)
		{
			dbg(DBGL_SYS, DBGT_WARN, //happens when receiving SIGHUP
					"can't select! Waiting a moment! errno: %s", strerror(errno));

			bat_wait(0, 1);
			update_batman_time(NULL);

			goto wait4Event_end;
		}

		if (selected == 0)
		{
			//Often select returns just a few milliseconds before being scheduled
			if ( return_time < (batman_time + 10) )
			{
				//cheating time :-)
				batman_time = return_time;

				goto wait4Event_end;
			}

			dbg_mute(50, DBGL_CHANGES, DBGT_WARN,
							 "select() returned %d without reason!! return_time %llu, curr_time %llu",
							 selected, return_time, batman_time);

			goto loop4Event;
		}

		// check for changed interface status...
		if (FD_ISSET(ifevent_sk, &tmp_wait_set))
		{
			dbg_mute(40, DBGL_CHANGES, DBGT_INFO,
							 "select() indicated changed interface status! Going to check interfaces!");

			recv_ifevent_netlink_sk();

			//do NOT delay checking of interfaces to not miss ifdown/up of interfaces !!
			check_interfaces();

			goto wait4Event_end;
		}

		// check for received packets...
		OLForEach(bif, struct batman_if, if_list)
		{
			mb->iif = bif;

			if (mb->iif->if_linklayer == VAL_DEV_LL_LO)
				continue;

			if (FD_ISSET(mb->iif->if_netwbrc_sock, &tmp_wait_set))
			{
				mb->unicast = NO;

				errno = 0;
				mb->total_length = recvfrom(mb->iif->if_netwbrc_sock, packet_in,
																		sizeof(packet_in) - 1, 0,
																		(struct sockaddr *)&addr, &addr_len);

				if (mb->total_length < 0 && (errno == EWOULDBLOCK || errno == EAGAIN))
				{
					dbgf(DBGL_SYS, DBGT_WARN,
							 "sock returned %d errno %d: %s",
							 mb->total_length, errno, strerror(errno));

					continue;
				}

				ioctl(mb->iif->if_netwbrc_sock, SIOCGSTAMP, &(mb->tv_stamp));

				process_packet(mb, packet_in, addr.sin_addr.s_addr);

				if (--selected == 0)
					goto loop4Event;
			}

			if (FD_ISSET(mb->iif->if_fullbrc_sock, &tmp_wait_set))
			{
				mb->unicast = NO;

				errno = 0;
				mb->total_length = recvfrom(mb->iif->if_fullbrc_sock, packet_in,
																		sizeof(packet_in) - 1, 0,
																		(struct sockaddr *)&addr, &addr_len);

				if (mb->total_length < 0 && (errno == EWOULDBLOCK || errno == EAGAIN))
				{
					dbgf(DBGL_SYS, DBGT_WARN,
							 "sock returned %d errno %d: %s",
							 mb->total_length, errno, strerror(errno));

					continue;
				}

				ioctl(mb->iif->if_fullbrc_sock, SIOCGSTAMP, &(mb->tv_stamp));

				process_packet(mb, packet_in, addr.sin_addr.s_addr);

				if (--selected == 0)
					goto loop4Event;
			}

			if (FD_ISSET(mb->iif->if_unicast_sock, &tmp_wait_set))
			{
				mb->unicast = YES;

				struct msghdr msghdr;
				struct iovec iovec;
				char buf[4096];
				struct cmsghdr *cp;
				struct timeval *tv_stamp = NULL;

				iovec.iov_base = packet_in;
				iovec.iov_len = sizeof(packet_in) - 1;

				msghdr.msg_name = (struct sockaddr *)&addr;
				msghdr.msg_namelen = addr_len;
				msghdr.msg_iov = &iovec;
				msghdr.msg_iovlen = 1;
				msghdr.msg_control = buf;
				msghdr.msg_controllen = sizeof(buf);
				msghdr.msg_flags = 0;

				errno = 0;

				mb->total_length = recvmsg(mb->iif->if_unicast_sock, &msghdr, MSG_DONTWAIT);

				if (mb->total_length < 0 && (errno == EWOULDBLOCK || errno == EAGAIN))
				{
					dbgf(DBGL_SYS, DBGT_WARN,
							 "sock returned %d errno %d: %s",
							 mb->total_length, errno, strerror(errno));
					continue;
				}

#ifdef SO_TIMESTAMP
				for (cp = CMSG_FIRSTHDR(&msghdr); cp; cp = CMSG_NXTHDR(&msghdr, cp))
				{
					if (cp->cmsg_type == SO_TIMESTAMP &&
							cp->cmsg_level == SOL_SOCKET &&
							cp->cmsg_len >= CMSG_LEN(sizeof(struct timeval)))
					{
						tv_stamp = (struct timeval *)CMSG_DATA(cp);
						break;
					}
				}
#endif
				if (tv_stamp == NULL)
				{
					ioctl(mb->iif->if_unicast_sock, SIOCGSTAMP, &(mb->tv_stamp));
				}
				else
				{
					timercpy(tv_stamp, &(mb->tv_stamp));
				}

				process_packet(mb, packet_in, addr.sin_addr.s_addr);

				if (--selected == 0)
					goto loop4Event;
				//goto wait4Event_end;
			}
		}

		prof_start(PROF_wait4Event_5);

		// check for new control clients...
		if (FD_ISSET(unix_sock, &tmp_wait_set))
		{
			dbgf_all(DBGT_INFO, "new control client...");

			accept_ctrl_node();

			if (--selected == 0)
				goto loop4Event;

			//goto wait4Event_end;
		}

	loop4ActiveClients:
		// check for all connected control clients...
		OLForEach(client, struct ctrl_node, ctrl_list)
		{
			if (FD_ISSET(client->fd, &tmp_wait_set))
			{
				FD_CLR(client->fd, &tmp_wait_set);

				//omit debugging here since event could be a closed -d4 ctrl socket
				//which should be removed before debugging
				//dbgf_all( DBGT_INFO, "got msg from control client");

				handle_ctrl_node(client);

				--selected;

				// return straight because client might be removed and list might have changed.
				goto loop4ActiveClients;
			}
		}

		if (selected)
			dbg(DBGL_CHANGES, DBGT_WARN,
					"select() returned with  %d unhandled event(s)!! return_time %llu, curr_time %llu",
					selected, return_time, batman_time);

		break;
	}

wait4Event_end:

	dbgf_all(DBGT_INFO, "end of function");

	prof_stop(PROF_wait4Event);
	prof_stop(PROF_wait4Event_5);
	return;
}

void schedule_own_ogm(struct batman_if *bif)
{
	prof_start(PROF_schedule_own_ogm);

	int sn_size = sizeof(struct send_node) +
								((bif == primary_if) ? MAX_UDPD_SIZE + 1 : sizeof(struct bat_packet_ogm) + sizeof(struct ext_packet));

	struct send_node *sn = (struct send_node *)debugMalloc(sn_size, 209);

	memset(sn, 0, sizeof(struct send_node) + sizeof(struct bat_packet_ogm));

	sn->ogm = (struct bat_packet_ogm *)sn->_attached_ogm_buff;

	sn->ogm->ext_msg = NO;
	sn->ogm->bat_type = BAT_TYPE_OGM;
	sn->ogm->ogx_flag = NO;
	sn->ogm->ogm_ttl = bif->if_ttl;
	sn->ogm->ogm_pws = my_pws;
	sn->ogm->orig = bif->if_addr;
	//sn->ogm->ogm_path_lounge = Signal_lounge;

	sn->send_time = bif->if_seqno_schedule + my_ogi;

	if (   sn->send_time < batman_time
			|| sn->send_time > (batman_time + my_ogi)
		 )
	{
		dbg_mute(50, DBGL_SYS, DBGT_WARN,
						 "strange own OGM schedule, rescheduling IF %10s SQN %d from %llu to %llu. "
						 "Maybe we just woke up from power-save mode, --%s too small, --%s to big or too much --%s",
						 bif->dev, bif->if_seqno, (unsigned long long)sn->send_time, (unsigned long long)batman_time + my_ogi,
						 ARG_OGI, ARG_AGGR_IVAL, ARG_WL_CLONES);

		sn->send_time = batman_time + my_ogi; // - (my_ogi/(2*aggr_p_ogi));
	}

	bif->if_seqno_schedule = sn->send_time;

	dbgf_all(DBGT_INFO, "for %s seqno %u at %llu", bif->dev, bif->if_seqno, (unsigned long long)sn->send_time);

	sn->if_outgoing = bif;
	sn->own_if = 1;

	uint32_t ogm_len = sizeof(struct bat_packet_ogm);

	/* only primary interfaces send usual extension messages */
	if (bif == primary_if)
	{
		uint16_t t;
		for (t = 0; t <= EXT_TYPE_MAX; t++)
		{
			int32_t what_len = 0;

			if ((what_len = cb_snd_ext_hook(t, (unsigned char *)sn->ogm + ogm_len)) == FAILURE)
				cleanup_all(-500040 - t);

			if (ogm_len + what_len > (uint32_t)pref_udpd_size)
			{
				dbg(DBGL_SYS, DBGT_ERR,
						"%s=%d  exceeded by needed ogm + extension header length (%d+%d) "
						"due to additional extension header 0x%X"
						"you may increase %s or specify less tpye-0x%X extension headers",
						ARG_UDPD_SIZE, pref_udpd_size, ogm_len, what_len, t, ARG_UDPD_SIZE, t);

				cleanup_all(-500192);
				//break;
			}

			ogm_len += what_len;
		}

		/* all non-primary interfaces send primary-interface extension message */
	}
	else if (primary_if)
	{
		my_pip_extension_packet.EXT_PIP_FIELD_ADDR = primary_addr;
		my_pip_extension_packet.EXT_PIP_FIELD_PIPSEQNO = htons(primary_if->if_seqno);

		memcpy((unsigned char *)sn->ogm + ogm_len, &my_pip_extension_packet, sizeof(struct ext_packet));
		ogm_len += sizeof(struct ext_packet);
	}

	sn->ogm_buff_len = ogm_len;

	sn->ogm->ogm_seqno = htons(bif->if_seqno);
	sn->ogm->bat_size = ogm_len / 4;
	sn->ogm->flags = 0;

	sn->ogm->ogm_misc = MIN(s_curr_avg_cpu_load, 255);

	dbgf_all(DBGT_INFO, "prepare send own OGM");

	int inserted = 0;
	OLForEach(send_packet_tmp, struct send_node, send_list)
	{

		if ( send_packet_tmp->send_time > sn->send_time )
		{
			OLInsertTailList((PLIST_ENTRY)send_packet_tmp, (PLIST_ENTRY)sn);
			inserted = 1;
			break;
		}
	}

	if (!inserted)
	{
		OLInsertTailList(&send_list, (PLIST_ENTRY)sn);
	}

	OLForEach(ln, struct link_node, link_list)
	{
		struct link_node_dev *lndev = get_lndev(ln, bif, NO /*create*/);

		if (lndev)
		{
			update_lounged_metric(0, local_rtq_lounge,
														bif->if_seqno - OUT_SEQNO_OFFSET, bif->if_seqno - OUT_SEQNO_OFFSET,
														&lndev->rtq_sqr, local_lws);
		}
	}

	prof_stop(PROF_schedule_own_ogm);
}

static struct opt_type schedule_options[] =
		{
				//        ord parent long_name          shrt Attributes				*ival		min		max		default		*func,*syntax,*help

				{ODI, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				 0, "\nScheduling options:"},

				{ODI, 5, 0, ARG_OGI, 'o', A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &my_ogi, MIN_OGI, MAX_OGI, DEF_OGI, 0,
				 ARG_VALUE_FORM, "set interval in ms with which new originator message (OGM) are send"},

				{ODI, 5, 0, ARG_OGI_PWRSAVE, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &ogi_pwrsave, MIN_OGI, MAX_OGI, MIN_OGI, 0,
				 ARG_VALUE_FORM, "enable power-saving feature by setting increased OGI when no other nodes are in range"},

				{ODI, 5, 0, ARG_AGGR_IVAL, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &aggr_interval, MIN_AGGR_IVAL, MAX_AGGR_IVAL, DEF_AGGR_IVAL, 0,
				 ARG_VALUE_FORM, "set aggregation interval (SHOULD be smaller than the half of your and others OGM interval)"},

				{ODI, 5, 0, ARG_UDPD_SIZE, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &pref_udpd_size, MIN_UDPD_SIZE, MAX_UDPD_SIZE, DEF_UDPD_SIZE, 0,
				 ARG_VALUE_FORM, "set preferred udp-data size for send packets"}

#ifndef LESS_OPTIONS
#ifndef NOPARANOIA
				,
				{ODI, 5, 0, "simulate_cleanup", 0, A_PS1, A_ADM, A_DYI, A_ARG, A_ANY, &sim_paranoia, NO, YES, DEF_SIM_PARA, 0,
				 ARG_VALUE_FORM, "simulate paranoia and cleanup_all for testing"}
#endif
#endif

};

void init_schedule(void)
{
	OLInitializeListHead(&send_list);
	OLInitializeListHead(&task_list);
	memset(&my_pip_extension_packet, 0, sizeof(struct ext_packet));
	my_pip_extension_packet.EXT_FIELD_MSG = YES;
	my_pip_extension_packet.EXT_FIELD_TYPE = EXT_TYPE_64B_PIP;

	if (open_ifevent_netlink_sk() < 0)
		cleanup_all(-500150);

	register_options_array(schedule_options, sizeof(schedule_options));
}

void start_schedule(void)
{
	register_task(50 + rand_num(100), aggregate_outstanding_ogms, NULL);
}

void cleanup_schedule(void)
{
	while (!OLIsListEmpty(&send_list))
	{
		PLIST_ENTRY entry = OLRemoveHeadList(&send_list);
		debugFree(entry, 1106);
	}

	while (!OLIsListEmpty(&task_list))
	{
		struct task_node *tn = (struct task_node *)OLRemoveHeadList(&task_list);

		if (tn->data)
		{
			debugFree(tn->data, 1109);
		}
		debugFree(tn, 1109);
	}

	close_ifevent_netlink_sk();
}
