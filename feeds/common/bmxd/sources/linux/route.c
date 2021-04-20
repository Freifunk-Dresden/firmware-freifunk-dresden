/*
 * Copyright (C) 2006 BATMAN contributors:
 * Marek Lindner, Axel Neumann, Thomas Lopatic
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
#include <fcntl.h>
#include <sys/ioctl.h>
#include <stdlib.h>
#include <arpa/inet.h> /* inet_ntop() */
#include <errno.h>
#include <unistd.h>		/* close() */
#include <linux/if.h> /* ifr_if, ifr_tun */
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <sys/ioctl.h>
#include <sys/socket.h>

//from  linux/wireless.h
#define SIOCGIWNAME 0x8B01 /* get name == wireless protocol */

#include "batman.h"
#include "os.h"
#include "originator.h"
#include "plugin.h"
#include "schedule.h"

int32_t base_port = DEF_BASE_PORT;

#define ARG_RT_TABLE "rt_table_offset"
#define DEF_RT_TABLE 64
#define MIN_RT_TABLE 0
#define MAX_RT_TABLE 254
#define RT_TABLE_HOSTS_OFFS 0
#define RT_TABLE_NETS_OFFS 1
#define RT_TABLE_TUNS_OFFS 2
#define RT_TABLE_MAX_OFFS 2
static int32_t Rt_table = DEF_RT_TABLE;

#define ARG_RT_PRIO "prio_rules_offset"
#define MIN_RT_PRIO 3
#define MAX_RT_PRIO 32765
#define DEF_RT_PRIO 6400
#define RT_PRIO_HOSTS (Rt_prio + 0)
#define RT_PRIO_NETWORKS (Rt_prio + 1)
#define RT_PRIO_TUNNEL (Rt_prio + 2)
static int32_t Rt_prio = DEF_RT_PRIO;

#define ARG_PRIO_RULES "prio_rules"
#define ARG_THROW_RULES "throw_rules"
#define ARG_NO_POLICY_RT "no_policy_routing"
#define ARG_PEDANTIC_CLEANUP "pedantic_cleanup"

#define DEF_PRIO_RULES 1
static int32_t prio_rules = DEF_PRIO_RULES;

#define DEF_THROW_RULES 1
static int32_t throw_rules = DEF_THROW_RULES;

#define DEF_PEDANT_CLNUP NO
static int32_t Pedantic_cleanup = DEF_PEDANT_CLNUP;

#define DEF_LO_RULE 1
static int32_t Lo_rule = DEF_LO_RULE;

#define DEF_METRIC 0
static int32_t metric = DEF_METRIC;

static uint8_t touched_systen_config = NO;

static int nl_sk = -1;
static int flush_sk = -1;

static int rt_sock = 0;

static int32_t forward_orig = -1, if_rp_filter_all_orig = -1, if_rp_filter_default_orig = -1, if_send_redirects_all_orig = -1, if_send_redirects_default_orig = -1;

static SIMPEL_LIST(rules_list);
static SIMPEL_LIST(routes_list);
static SIMPEL_LIST(throw_list);

uint8_t if_conf_soft_changed = NO; // temporary enabled to trigger changed interface configuration
uint8_t if_conf_hard_changed = NO; // temporary enabled to trigger changed interface configuration

int Mtu_min = MAX_MTU;

static struct
{
	struct nlmsghdr nlh;
	struct rtmsg rtm;
	char buff[256];
} req;

static void add_rtattr(int rta_type, char *data, int data_len)
{
	struct rtattr *rta = (struct rtattr *)(((char *)&req) + NLMSG_ALIGN(req.nlh.nlmsg_len));

	req.nlh.nlmsg_len = NLMSG_ALIGN(req.nlh.nlmsg_len) + RTA_LENGTH(data_len);

	paranoia(-50173, (NLMSG_ALIGN(req.nlh.nlmsg_len) > sizeof(req)));
	// if this fails then double req buff size !!

	rta->rta_type = rta_type;
	rta->rta_len = RTA_LENGTH(data_len);
	memcpy(RTA_DATA(rta), data, data_len);
}

static char *rt2str(uint8_t t)
{
	if (t == RTN_UNICAST)
		return "RTN_UNICAST";
	else if (t == RTN_THROW)
		return "RTN_THROW  ";

	return "RTN_ILLEGAL";
}

static char *trackt2str(uint8_t t)
{
	if (t == TRACK_NO)
		return "TRACK_NO";
	else if (t == TRACK_STANDARD)
		return "TRACK_STANDARD";
	else if (t == TRACK_MY_NET)
		return "TRACK_MY_NET";
	else if (t == TRACK_OTHER_HOST)
		return "TRACK_OTHER_HOST";
	else if (t == TRACK_TUNNEL)
		return "TRACK_TUNNEL";

	return "TRACK_ILLEGAL";
}

static int open_netlink_socket(void)
{
	int sock = 0;
	if ((sock = socket(AF_NETLINK, SOCK_DGRAM, NETLINK_ROUTE)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't create netlink socket for routing table manipulation: %s",
				strerror(errno));

		return -1;
	}

	if (fcntl(sock, F_SETFL, O_NONBLOCK) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't set netlink socket nonblocking : (%s)", strerror(errno));
		close(sock);
		return -1;
	}

	return sock;
}

static int rt_macro_to_table(int rt_macro)
{
	dbgf_all(DBGT_INFO, "rt_macro %d", rt_macro);

	if (rt_macro == RT_TABLE_HOSTS)
		return Rt_table + RT_TABLE_HOSTS_OFFS;

	else if (rt_macro == RT_TABLE_NETWORKS)
		return Rt_table + RT_TABLE_NETS_OFFS;

	else if (rt_macro == RT_TABLE_TUNNEL)
		return Rt_table + RT_TABLE_TUNS_OFFS;

	else if (rt_macro > MAX_RT_TABLE)
		cleanup_all(-500170);

	else if (rt_macro >= 0)
		return rt_macro;

	cleanup_all(-500171);

	return 0;
}

static int8_t track_rule_and_proceed(uint32_t network, int16_t mask, int16_t rt_table, uint32_t prio, char *iif,
																		 int16_t rule_type, int8_t del, int8_t track_t)
{
	struct list_head *list_pos, *tmp_pos, *first_found_pos = NULL, *first_found_prev = NULL;
	struct list_head *prev_pos = (struct list_head *)&rules_list;
	struct rules_node *first_found_rn = NULL;
	uint32_t found_rns = 0;

	paranoia(-500176, (!del && track_t == TRACK_NO));

	list_for_each_safe(list_pos, tmp_pos, &rules_list)
	{
		struct rules_node *tmp_rn = list_entry(list_pos, struct rules_node, list);

		if (tmp_rn->network == network &&
				tmp_rn->netmask == mask &&
				tmp_rn->rt_table == rt_table &&
				tmp_rn->prio == prio &&
				tmp_rn->iif == iif &&
				tmp_rn->rta_type == rule_type)
		{
			// the kernel-ip-stack does not care about my track_t when adding the same rule twice
			// but found_rns is evaluated for this
			if (!first_found_rn && (tmp_rn->track_t == track_t || track_t == TRACK_NO))
			{
				first_found_rn = tmp_rn;
				first_found_pos = list_pos;
				first_found_prev = prev_pos;
			}

			found_rns++;
		}

		prev_pos = &tmp_rn->list;
	}

	if ((track_t == TRACK_NO) ||
			(del && !first_found_rn) ||
			(del && found_rns != 1) ||
			(!del && found_rns > 0))
	{
		dbg((track_t == TRACK_NO || (del && !first_found_rn)) ? DBGL_SYS : DBGL_CHANGES,
				(track_t == TRACK_NO || (del && !first_found_rn)) ? DBGT_ERR : DBGT_INFO,
				"   %s rule from %s/%d  table %d  prio %d  iif %s  type %d  "
				"%s exists %d tims with at least %d exact match",
				del ? "del" : "add", ipStr(network), mask, rt_table, prio, iif, rule_type,
				trackt2str(track_t), found_rns, (first_found_rn ? 1 : 0));
	}

	if (track_t == TRACK_NO)
		return YES;

	if (del)
	{
		if (first_found_rn)
		{
			list_del(first_found_prev, first_found_pos, &rules_list);
			debugFree(first_found_rn, 1741);

			if (found_rns > 1)
				return NO;
		}
		else
		{
			return NO;
		}
	}
	else
	{
		struct rules_node *tmp_rn = debugMalloc(sizeof(struct rules_node), 741);
		memset(tmp_rn, 0, sizeof(struct rules_node));
		INIT_LIST_HEAD(&tmp_rn->list);

		tmp_rn->network = network;
		tmp_rn->netmask = mask;
		tmp_rn->rt_table = rt_table;
		tmp_rn->prio = prio;
		tmp_rn->iif = iif;
		tmp_rn->rta_type = rule_type;
		tmp_rn->track_t = track_t;

		list_add_tail(&tmp_rn->list, &rules_list);

		if (found_rns > 0)
			return NO;
	}

	return YES;
}

static void add_del_rule(uint32_t network, int16_t mask, int16_t rt_table_macro, uint32_t prio, char *iif,
												 int16_t rta_type, int8_t del, int8_t track_t)
{
	char buf[4096], str1[16];
	struct sockaddr_nl nladdr;
	struct iovec iov = {buf, sizeof(buf)};
	struct msghdr msg;
	struct nlmsghdr *nh;

	uint16_t rt_table = rt_macro_to_table(rt_table_macro);

	inet_ntop(AF_INET, &network, str1, sizeof(str1));

	if (track_rule_and_proceed(network, mask, rt_table, prio, iif, rta_type, del, track_t) == NO)
		return;

	dbg(DBGL_CHANGES, DBGT_INFO, "%s rule from %s/%d  table %d  prio %d  iif %s  type %d",
			del ? "del" : "add", str1, mask, rt_table, prio, iif, rta_type);

	memset(&nladdr, 0, sizeof(struct sockaddr_nl));
	memset(&req, 0, sizeof(req));
	memset(&msg, 0, sizeof(struct msghdr));

	nladdr.nl_family = AF_NETLINK;

	req.nlh.nlmsg_len = NLMSG_LENGTH(sizeof(struct rtmsg));
	req.nlh.nlmsg_pid = My_pid;

	req.rtm.rtm_family = AF_INET;
	req.rtm.rtm_table = rt_table;

	dbgf_all(DBGT_INFO, "%s ip rule pref %d iif %s %d %s/%d  lookup table %d",
					 (del ? "del" : "add"), prio, iif, rta_type, str1, mask, rt_table);

	if (del)
	{
		req.nlh.nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK;
		req.nlh.nlmsg_type = RTM_DELRULE;

		req.rtm.rtm_scope = RT_SCOPE_NOWHERE;
	}
	else
	{
		req.nlh.nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK | NLM_F_CREATE | NLM_F_EXCL;
		req.nlh.nlmsg_type = RTM_NEWRULE;

		req.rtm.rtm_scope = RT_SCOPE_UNIVERSE;
		req.rtm.rtm_protocol = RTPROT_STATIC;
		req.rtm.rtm_type = RTN_UNICAST;
	}

	if (rta_type == RTA_DST)
	{
		req.rtm.rtm_dst_len = mask;
		add_rtattr(rta_type, (char *)&network, sizeof(network));
	}
	else if (rta_type == RTA_SRC)
	{
		req.rtm.rtm_src_len = mask;
		add_rtattr(rta_type, (char *)&network, sizeof(network));
	}

	if (iif)
		add_rtattr(RTA_IIF, iif, strlen(iif) + 1);

	if (prio)
		add_rtattr(RTA_PRIORITY, (char *)&prio, sizeof(prio));

	if (sendto(nl_sk, &req, req.nlh.nlmsg_len, 0, (struct sockaddr *)&nladdr, sizeof(struct sockaddr_nl)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR,
				"can't send message to kernel via netlink socket for routing rule manipulation: %s",
				strerror(errno));
		return;
	}

	while (1)
	{
		msg.msg_name = (void *)&nladdr;
		msg.msg_namelen = sizeof(nladdr);
		msg.msg_iov = &iov;
		msg.msg_iovlen = 1;
		msg.msg_control = NULL;
		msg.msg_controllen = 0;
		msg.msg_flags = 0;

		int32_t len = recvmsg(nl_sk, &msg, 0);

		if (len < 0)
		{
			if (errno == EINTR)
			{
				dbgf(DBGL_SYS, DBGT_WARN, "(EINTR) %s", strerror(errno));
				continue;
			}

			if (errno == EWOULDBLOCK || errno == EAGAIN)
			{
				//dbgf( DBGL_SYS, DBGT_WARN, "(EWOULDBLOCK || EAGAIN) %s", strerror(errno) );
				break;
			}

			dbgf(DBGL_SYS, DBGT_ERR, "%s", strerror(errno));

			continue;
		}

		if (len == 0)
		{
			dbgf(DBGL_SYS, DBGT_ERR, "netlink EOF");
		}

		nh = (struct nlmsghdr *)buf;

		while (NLMSG_OK(nh, (uint32_t)len))
		{
			if (nh->nlmsg_type == NLMSG_DONE)
				return;

			if ((nh->nlmsg_type == NLMSG_ERROR) && (((struct nlmsgerr *)NLMSG_DATA(nh))->error != 0))
			{
				dbg(DBGL_SYS, DBGT_WARN, "can't %s rule %s %s/%i iif %s table %d, prio %d: %s "
																 "(if busy: Help me! Howto avoid this ERROR message?)",
						del ? "delete" : "add",
						(rta_type == RTA_DST ? "to" : (rta_type == RTA_SRC ? "from" : (rta_type == RTA_IIF ? "iif" : "???"))),
						str1, mask, iif, rt_table, prio,
						strerror(-((struct nlmsgerr *)NLMSG_DATA(nh))->error));
			}

			nh = NLMSG_NEXT(nh, len);
		}
	}
}

static void flush_tracked_rules(int8_t track_type)
{
	dbgf_all(DBGT_INFO, "%s", trackt2str(track_type));

	struct list_head *list_pos;
	struct rules_node *rn, *p_rn = NULL;

	list_for_each(list_pos, &rules_list)
	{
		rn = list_entry(list_pos, struct rules_node, list);

		if (p_rn)
			add_del_rule(p_rn->network, p_rn->netmask,
									 p_rn->rt_table, p_rn->prio, p_rn->iif, p_rn->rta_type, DEL, p_rn->track_t);

		if (track_type == rn->track_t || track_type == TRACK_NO)
			p_rn = rn;
		else
			p_rn = NULL;
	}

	if (p_rn)
		add_del_rule(p_rn->network, p_rn->netmask,
								 p_rn->rt_table, p_rn->prio, p_rn->iif, p_rn->rta_type, DEL, p_rn->track_t);
}

static void flush_tracked_routes(int8_t track_type)
{
	dbgf_all(DBGT_INFO, "%s", trackt2str(track_type));

	struct list_head *list_pos;
	struct routes_node *rn, *p_rn = NULL;

	list_for_each(list_pos, &routes_list)
	{
		rn = list_entry(list_pos, struct routes_node, list);

		if (p_rn)
			add_del_route(p_rn->dest, p_rn->netmask, 0, 0, 0, 0,
										p_rn->rt_table, p_rn->rta_type, DEL, p_rn->track_t);

		if (track_type == rn->track_t || track_type == TRACK_NO)
			p_rn = rn;
		else
			p_rn = NULL;
	}

	if (p_rn)
		add_del_route(p_rn->dest, p_rn->netmask, 0, 0, 0, 0,
									p_rn->rt_table, p_rn->rta_type, DEL, p_rn->track_t);
}

static void flush_routes_rules(int8_t is_rule)
{
	dbgf_all(DBGT_INFO, "is_rule %d", is_rule);

	size_t len;
	int rtl;
	char buf[8192];
	struct sockaddr_nl nladdr;
	struct iovec iov = {buf, sizeof(buf)};
	struct msghdr msg;
	struct nlmsghdr *nh;
	struct rtmsg *rtm;
	struct
	{
		struct nlmsghdr nlh;
		struct rtmsg rtm;
	} req;
	struct rtattr *rtap;

	memset(&nladdr, 0, sizeof(struct sockaddr_nl));
	memset(&req, 0, sizeof(req));

	nladdr.nl_family = AF_NETLINK;

	req.nlh.nlmsg_len = NLMSG_LENGTH(sizeof(struct rtmsg));
	req.nlh.nlmsg_pid = My_pid;
	req.nlh.nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
	req.nlh.nlmsg_type = (is_rule ? RTM_GETRULE : RTM_GETROUTE);

	req.rtm.rtm_family = AF_INET;
	req.rtm.rtm_scope = RTN_UNICAST;

	if (sendto(flush_sk, &req, req.nlh.nlmsg_len, 0,
						 (struct sockaddr *)&nladdr, sizeof(struct sockaddr_nl)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR,
				"can't send message to kernel via netlink socket for flushing the routing table: %s",
				strerror(errno));

		cleanup_all(CLEANUP_FAILURE);
	}

	uint8_t nlm_f_multi = NO;

	do
	{
		memset(&msg, 0, sizeof(struct msghdr));
		memset(&nladdr, 0, sizeof(struct sockaddr_nl));

		nladdr.nl_family = AF_NETLINK;

		msg.msg_name = (void *)&nladdr;
		msg.msg_namelen = sizeof(nladdr);
		msg.msg_iov = &iov;
		msg.msg_iovlen = 1;
		msg.msg_control = NULL;

		len = recvmsg(flush_sk, &msg, 0);
		nh = (struct nlmsghdr *)buf;

		dbgf_all(DBGT_INFO, "searching: %s  NLMSG_OK: %d  len: %d",
						 is_rule ? "rules" : "routes", NLMSG_OK(nh, len), (int)len);

		while (NLMSG_OK(nh, len))
		{
			if (nh->nlmsg_flags & NLM_F_MULTI)
				nlm_f_multi = YES;

			if (nh->nlmsg_type == NLMSG_DONE)
			{
				dbgf_all(DBGT_INFO, "found NLMSG_DONE");
				break;
			}

			if ((nh->nlmsg_type == NLMSG_ERROR) && (((struct nlmsgerr *)NLMSG_DATA(nh))->error != 0))
			{
				dbg(DBGL_SYS, DBGT_ERR, "can't flush %s: %s",
						(is_rule ? "routing rules" : "routing table"),
						strerror(-((struct nlmsgerr *)NLMSG_DATA(nh))->error));

				cleanup_all(CLEANUP_FAILURE);
			}

			rtm = (struct rtmsg *)NLMSG_DATA(nh);
			rtap = (struct rtattr *)RTM_RTA(rtm);
			rtl = RTM_PAYLOAD(nh);

			nh = NLMSG_NEXT(nh, len);

			if (/* rtm->rtm_table == 0 || */
					rtm->rtm_table == Rt_table + RT_TABLE_NETS_OFFS ||
					rtm->rtm_table == Rt_table + RT_TABLE_HOSTS_OFFS ||
					rtm->rtm_table == Rt_table + RT_TABLE_TUNS_OFFS)
			{
				int8_t rule_type = RTA_UNSPEC;
				uint32_t dest = 0;
				uint32_t router = 0;
				uint16_t mask = 0;
				int32_t oif = 0;
				int32_t prio = 0;
				char *iif = NULL;

				while (RTA_OK(rtap, rtl))
				{
					dbgf_all(DBGT_INFO, "found rtm_table %d, rta_type %d rta_len %d",
									 rtm->rtm_table, rtap->rta_type, rtap->rta_len);

					switch (rtap->rta_type)
					{
					case RTA_DST:
						dest = *((int32_t *)RTA_DATA(rtap));
						mask = rtm->rtm_dst_len;
						rule_type = RTA_DST;
						break;

					case RTA_SRC:
						dest = *((int32_t *)RTA_DATA(rtap));
						mask = rtm->rtm_src_len;
						rule_type = RTA_SRC;
						break;

					case RTA_GATEWAY:
						router = *((int32_t *)RTA_DATA(rtap));
						break;

					case RTA_OIF:
						oif = *((int32_t *)RTA_DATA(rtap));
						break;

					case RTA_PRIORITY:
						prio = *((uint32_t *)RTA_DATA(rtap));
						break;

					case RTA_IIF:
						iif = ((char *)RTA_DATA(rtap));
						break;

					case 15: // FIXME: RTA_TABLE is not always available - not needed but avoid warning
						break;

					case RTA_PREFSRC: // rta_type 7 - not needed but avoid warning
						break;

					default:
						dbg(DBGL_SYS, DBGT_ERR, "unknown rta type: %i", rtap->rta_type);
						break;
					}

					rtap = RTA_NEXT(rtap, rtl);
				}

				if (is_rule)
				{
					add_del_rule(dest, mask, rtm->rtm_table, prio, iif, rule_type, DEL, TRACK_NO);

//					dbg(DBGL_SYS, DBGT_WARN, "flushing orphan rule type %d dest? %s/%d  table %d  prio %d",
//							rule_type, ipStr(dest), mask, rtm->rtm_table, prio);
				}
				else
				{
					add_del_route(dest, mask, router, 0, oif, "unknown", rtm->rtm_table, rtm->rtm_type, DEL, TRACK_NO);

//					dbg(DBGL_SYS, DBGT_WARN, "flushing orphan route to %s  via %s  type %d  table %d",
//							ipStr(dest), ipStr(router), rtm->rtm_type, rtm->rtm_table);
				}
			}
		}

	} while (!(nlm_f_multi == NO || ((NLMSG_OK(nh, len) && (nh->nlmsg_type == NLMSG_DONE)))));
}

static void check_proc_sys(char *file, int32_t desired, int32_t *backup)
{
	FILE *f;
	int32_t state = 0;
	char filename[MAX_PATH_SIZE];

	sprintf(filename, "/proc/sys/%s", file);

	if ((f = fopen(filename, "r")) == NULL)
	{
		dbgf(DBGL_SYS, DBGT_ERR, "can't open %s for reading! retry later..", filename);

		if (backup)
			cleanup_all(CLEANUP_FAILURE);

		return;
	}

	UNUSED_RETVAL(fscanf(f, "%d", &state));
	fclose(f);

	if (backup)
		*backup = state;

	// other routing protocols are probably not able to handle this therefore
	// it is probably better to leave the routing configuration operational as it is!
	if (!backup && !Pedantic_cleanup && state != desired)
	{
		dbg_mute(50, DBGL_SYS, DBGT_INFO,
						 "NOT restoring %s to NOT mess up other routing protocols. "
						 "Use --%s=1 to enforce proper cleanup",
						 file, ARG_PEDANTIC_CLEANUP);

		return;
	}

	if (state != desired)
	{
		touched_systen_config = YES;

		dbg(DBGL_SYS, DBGT_INFO, "changing %s from %d to %d", filename, state, desired);

		if ((f = fopen(filename, "w")) == NULL)
		{
			dbgf(DBGL_SYS, DBGT_ERR,
					 "can't open %s for writing! retry later...", filename);
			return;
		}

		fprintf(f, "%d", desired ? 1 : 0);
		fclose(f);
	}
}

static void restore_kernel_config(struct batman_if *batman_if)
{
	if (!touched_systen_config)
		return;

	if (batman_if)
	{
		char filename[100];

		if (batman_if->if_rp_filter_orig > -1)
		{
			sprintf(filename, "net/ipv4/conf/%s/rp_filter", batman_if->dev_phy);
			check_proc_sys(filename, batman_if->if_rp_filter_orig, NULL);
		}

		batman_if->if_rp_filter_orig = -1;

		if (batman_if->if_send_redirects_orig > -1)
		{
			sprintf(filename, "net/ipv4/conf/%s/send_redirects", batman_if->dev_phy);
			check_proc_sys(filename, batman_if->if_send_redirects_orig, NULL);
		}

		batman_if->if_send_redirects_orig = -1;
	}
	else
	{
		if (if_rp_filter_all_orig != -1)
			check_proc_sys("net/ipv4/conf/all/rp_filter", if_rp_filter_all_orig, NULL);

		if_rp_filter_all_orig = -1;

		if (if_rp_filter_default_orig != -1)
			check_proc_sys("net/ipv4/conf/default/rp_filter", if_rp_filter_default_orig, NULL);

		if_rp_filter_default_orig = -1;

		if (if_send_redirects_all_orig != -1)
			check_proc_sys("net/ipv4/conf/all/send_redirects", if_send_redirects_all_orig, NULL);

		if_send_redirects_all_orig = -1;

		if (if_send_redirects_default_orig != -1)
			check_proc_sys("net/ipv4/conf/default/send_redirects", if_send_redirects_default_orig, NULL);

		if_send_redirects_default_orig = -1;

		if (forward_orig != -1)
			check_proc_sys("net/ipv4/ip_forward", forward_orig, NULL);

		forward_orig = -1;
	}
}

static int8_t get_if_req(char *dev_name, struct ifreq *int_req, int siocgi_req)
{
	memset(int_req, 0, sizeof(struct ifreq));
	strncpy(int_req->ifr_name, dev_name, IFNAMSIZ - 1);

	if (ioctl(rt_sock, siocgi_req, int_req) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't get SIOCGI %d of interface %s: %s", siocgi_req, dev_name, strerror(errno));
		return FAILURE;
	}

	return SUCCESS;
}

static int8_t if_validate(uint8_t set, struct batman_if *bif, char *dev_name, uint8_t reduced)
{
	struct ifreq int_req;

	if (get_if_req(dev_name, &int_req, SIOCGIFADDR) == FAILURE)
		goto if_validate_failure;

	if (set)
	{
		bif->if_addr = ((struct sockaddr_in *)&int_req.ifr_addr)->sin_addr.s_addr;
		addr_to_str(bif->if_addr, bif->if_ip_str);
	}
	else if (bif->if_addr != ((struct sockaddr_in *)&int_req.ifr_addr)->sin_addr.s_addr)
	{
		dbg(DBGL_SYS, DBGT_WARN, "IP address of %s: changed from %s to %s !",
				dev_name, ipStr(bif->if_addr),
				ipStr(((struct sockaddr_in *)&int_req.ifr_addr)->sin_addr.s_addr));
		goto if_validate_failure;
	}

	if (!bif->if_addr)
	{
		dbg(DBGL_SYS, DBGT_ERR, "invalid IP address: %s %s", dev_name, ipStr(0));
		goto if_validate_failure;
	}

	if (get_if_req(dev_name, &int_req, SIOCGIFNETMASK) == FAILURE)
		goto if_validate_failure;

	if (set)
	{
		bif->if_netaddr = (((struct sockaddr_in *)&int_req.ifr_addr)->sin_addr.s_addr & bif->if_addr);
	}
	else if (bif->if_netaddr != (((struct sockaddr_in *)&int_req.ifr_addr)->sin_addr.s_addr & bif->if_addr))
	{
		dbg(DBGL_SYS, DBGT_WARN, "Net address of interface %s changed", dev_name);
		goto if_validate_failure;
	}

	if (set)
	{
		bif->if_netmask = ((struct sockaddr_in *)&int_req.ifr_addr)->sin_addr.s_addr;
		bif->if_prefix_length = get_set_bits(bif->if_netmask);
	}
	else if (bif->if_netmask != ((struct sockaddr_in *)&int_req.ifr_addr)->sin_addr.s_addr)
	{
		dbg(DBGL_SYS, DBGT_WARN, "Prefix length of interface %s changed from %d to %d",
				dev_name, bif->if_prefix_length,
				get_set_bits(((struct sockaddr_in *)&int_req.ifr_addr)->sin_addr.s_addr));
		goto if_validate_failure;
	}

	if (!bif->if_prefix_length)
	{
		dbg(DBGL_SYS, DBGT_WARN, "Prefix length of IF %s must be > 0", dev_name);
		goto if_validate_failure;
	}

	if (reduced)
		return SUCCESS;

	if (get_if_req(dev_name, &int_req, SIOCGIFINDEX) == FAILURE)
		goto if_validate_failure;

	if (set)
	{
		bif->if_index = int_req.ifr_ifindex;
	}
	else if (bif->if_index != int_req.ifr_ifindex)
	{
		dbg(DBGL_SYS, DBGT_WARN, "Interface index of %s %s: changed from %d to %d !",
				dev_name, ipStr(bif->if_addr),
				bif->if_index, int_req.ifr_ifindex);
	}

	if (get_if_req(dev_name, &int_req, SIOCGIFBRDADDR) == FAILURE)
		goto if_validate_failure;

	if (set)
	{
		bif->if_broad = ((struct sockaddr_in *)&int_req.ifr_broadaddr)->sin_addr.s_addr;
	}
	else if (bif->if_broad != ((struct sockaddr_in *)&int_req.ifr_broadaddr)->sin_addr.s_addr)
	{
		dbg(DBGL_SYS, DBGT_WARN, "Broadcast address of %s changed", dev_name);
		goto if_validate_failure;
	}

	if (!bif->if_broad && bif->if_linklayer != VAL_DEV_LL_LO)
	{
		dbg(DBGL_SYS, DBGT_ERR, "invalid broadcast address: %s %s", dev_name, ipStr(0));
		goto if_validate_failure;
	}

	if (get_if_req(dev_name, &int_req, SIOCGIFMTU) == FAILURE)
		goto if_validate_failure;

	if (set)
	{
		bif->if_mtu = int_req.ifr_mtu;
	}
	else if (bif->if_mtu != int_req.ifr_mtu)
	{
		dbg(DBGL_SYS, DBGT_WARN, "MTU of interface %s changed from %d to %d",
				dev_name, bif->if_mtu, int_req.ifr_mtu);
		goto if_validate_failure;
	}

	return SUCCESS;

if_validate_failure:

	bif->if_addr = 0;
	addr_to_str(0, bif->if_ip_str);
	return FAILURE;
}

static char *get_ip4conf_buffer(struct ifconf *ifc)
{
	/* use netlink, netdevice and rtnetlink (7)
         * to resolve ipv6 addresses. SIOCGIFCONF will only resolv ipv4 addresses !!!
         */

	char *buf;

	int32_t len = 10 * sizeof(struct ifreq); /* initial buffer size guess (10 interfaces) */

	while (1)
	{
		buf = debugMalloc(len, 601);
		memset(buf, 0, len);
		memset(ifc, 0, sizeof(struct ifconf));

		ifc->ifc_len = len;
		ifc->ifc_buf = buf;

		if (ioctl(rt_sock, SIOCGIFCONF, ifc) < 0)
		{
			dbg(DBGL_SYS, DBGT_ERR, "can't add interface rules (SIOCGIFCONF): %s", strerror(errno));
			//close( tmp_fd );
			debugFree(buf, 1601);
			return NULL;
		}
		else
		{
			if (ifc->ifc_len < len)
				break;
		}

		len += 10 * sizeof(struct ifreq);
		debugFree(buf, 1601);
	}

	return buf;
}

static int is_batman_if(char *dev, struct batman_if **bif)
{
	struct list_head *if_pos = NULL;

	list_for_each(if_pos, &if_list)
	{
		(*bif) = list_entry(if_pos, struct batman_if, list);

		if (wordsEqual((*bif)->dev, dev))
			return YES;
	}

	return NO;
}

static int is_interface_up(char *dev)
{
	struct ifreq int_req;

	memset(&int_req, 0, sizeof(struct ifreq));
	strncpy(int_req.ifr_name, dev, IFNAMSIZ - 1);

	if (ioctl(rt_sock, SIOCGIFFLAGS, &int_req) < 0)
		return 0;

	if (!(int_req.ifr_flags & IFF_UP))
		return 0;

	if (ioctl(rt_sock, SIOCGIFADDR, &int_req) < 0)
		return 0;

	return 1;
}

static void if_reconfigure_soft(struct batman_if *bif)
{
	if (!bif->if_active)
	{
		dbg(DBGL_SYS, DBGT_INFO,
				"skipping invalid IF %s ", bif->dev);
	}
	else if (bif->if_linklayer == VAL_DEV_LL_LO)
	{
		dbg(DBGL_SYS, DBGT_INFO,
				"enabled loopback %s %s %s/%d brc %s",
				ARG_DEV, bif->dev, ipStr(bif->if_addr), bif->if_prefix_length, ipStr(bif->if_broad));
	}
	else if (bif->if_linklayer == VAL_DEV_LL_WLAN)
	{
		dbg(DBGL_SYS, DBGT_INFO,
				"enabled wireless %s %s %s/%d brc %s (use %s /l=%d to optimize for ethernet)",
				ARG_DEV, bif->dev, ipStr(bif->if_addr), bif->if_prefix_length, ipStr(bif->if_broad), bif->dev, VAL_DEV_LL_LAN);

		bif->if_send_clones = wl_clones;
	}
	else
	{
		dbg(DBGL_SYS, DBGT_INFO,
				"enabled ethernet %s %s %s/%d brc %s (use %s /l=%d to optimize for wireless)",
				ARG_DEV, bif->dev, ipStr(bif->if_addr), bif->if_prefix_length, ipStr(bif->if_broad), bif->dev, VAL_DEV_LL_WLAN);

		bif->if_send_clones = DEF_LAN_CLONES;
	}

	if (bif == primary_if)
	{
		bif->if_ttl = Ttl;
		bif->if_singlehomed = NO;
	}
	else
	{
		bif->if_ttl = 1;
		bif->if_singlehomed = YES;
	}

	bif->if_ant_diversity = 1;

	if (bif->if_send_clones_conf != -1)
		bif->if_send_clones = bif->if_send_clones_conf;

	if (bif->if_ant_diversity_conf != -1)
		bif->if_ant_diversity = bif->if_ant_diversity_conf;

	if (bif->if_ttl_conf != -1)
		bif->if_ttl = bif->if_ttl_conf;

	if (bif->if_singlehomed_conf != -1)
		bif->if_singlehomed = bif->if_singlehomed_conf;

	bif->if_last_link_activity = batman_time;
	bif->if_next_pwrsave_hardbeat = batman_time;

	bif->if_conf_soft_changed = NO;
}

static int8_t bind_to_iface(int32_t sock, char *dev)
{
	errno = 0;

	if (setsockopt(sock, SOL_SOCKET, SO_BINDTODEVICE, dev, strlen(dev) + 1) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "Cannot bind socket to device %s : %s", dev, strerror(errno));
		return -1;
	}

	return 1;
}

static void if_activate(struct batman_if *bif)
{
	if (if_validate(YES /*set*/, bif, bif->dev, NO /*reduced check*/) == FAILURE)
		goto error;

	if (wordsEqual("lo", bif->dev_phy))
	{
		bif->if_linklayer = VAL_DEV_LL_LO;
	}
	else if (bif->if_linklayer_conf != -1)
	{
		//FIXME: when this parameter is changed only if_reconfigure_soft is called
		bif->if_linklayer = bif->if_linklayer_conf;
	}
	else /* check if interface is a wireless interface */
	{
		struct ifreq int_req;
		memset(&int_req, 0, sizeof(struct ifreq));
		strncpy(int_req.ifr_name, bif->dev_phy, IFNAMSIZ - 1);

		bif->if_linklayer =
				(ioctl(rt_sock, SIOCGIWNAME, &int_req) < 0 ? VAL_DEV_LL_LAN : VAL_DEV_LL_WLAN);
	}

	if (bif->if_linklayer != VAL_DEV_LL_LO && (bif->if_unicast_sock = socket(PF_INET, SOCK_DGRAM, 0)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't create send socket: %s", strerror(errno));
		goto error;
	}

	// the src address and port used for sending:
	bif->if_unicast_addr.sin_addr.s_addr = bif->if_addr;
	bif->if_unicast_addr.sin_family = AF_INET;
	bif->if_unicast_addr.sin_port = htons(base_port);

	// the dst address and port used for sending:
	bif->if_netwbrc_addr.sin_addr.s_addr = bif->if_broad;
	bif->if_netwbrc_addr.sin_family = AF_INET;
	bif->if_netwbrc_addr.sin_port = htons(base_port);

	Mtu_min = MIN(Mtu_min, bif->if_mtu);

	dbgf_all(DBGT_INFO, "searching minimum MTU, so fare: %d, current dev %s, mtu: %d",
					 Mtu_min, bif->dev, bif->if_mtu);

	if (bif->if_linklayer == VAL_DEV_LL_LO)
	{
		if (bif->if_prefix_length != 32 /*||  bif->if_addr != bif->if_broad*/)
			dbg_mute(30, DBGL_SYS, DBGT_WARN, "netmask of loopback interface is %d but SHOULD BE 32",
							 bif->if_prefix_length);
	}
	else
	{
		int set_on = 1, sock_opts;

		if (setsockopt(bif->if_unicast_sock, SOL_SOCKET, SO_BROADCAST, &set_on, sizeof(set_on)) < 0)
		{
			dbg(DBGL_SYS, DBGT_ERR, "can't enable broadcasts on unicast socket: %s", strerror(errno));
			goto error;
		}

		// bind send socket to interface name
		if (bind_to_iface(bif->if_unicast_sock, bif->dev_phy) < 0)
			goto error;

		// bind send socket to address
		if (bind(bif->if_unicast_sock, (struct sockaddr *)&bif->if_unicast_addr, sizeof(struct sockaddr_in)) < 0)
		{
			dbg(DBGL_SYS, DBGT_ERR, "can't bind unicast socket: %s", strerror(errno));
			goto error;
		}

		// make udp send socket non blocking
		sock_opts = fcntl(bif->if_unicast_sock, F_GETFL, 0);
		fcntl(bif->if_unicast_sock, F_SETFL, sock_opts | O_NONBLOCK);

#ifdef SO_TIMESTAMP
		if (setsockopt(bif->if_unicast_sock, SOL_SOCKET, SO_TIMESTAMP, &set_on, sizeof(set_on)))
			dbg(DBGL_SYS, DBGT_WARN,
					"No SO_TIMESTAMP support, despite being defined, falling back to SIOCGSTAMP");
#else
		dbg(DBGL_SYS, DBGT_WARN, "No SO_TIMESTAMP support, falling back to SIOCGSTAMP");
#endif

		// if the dst address used for sending is the full-broadcast address
		// we'll also listen on the network-broadcast address

		struct sockaddr_in if_netwbrc_addr;
		memset(&if_netwbrc_addr, 0, sizeof(struct sockaddr_in));
		if_netwbrc_addr.sin_family = AF_INET;
		if_netwbrc_addr.sin_port = htons(base_port);
		if (bif->if_broad == 0xFFFFFFFF)
			if_netwbrc_addr.sin_addr.s_addr = bif->if_netaddr | ~(bif->if_netmask);
		else
			if_netwbrc_addr.sin_addr.s_addr = bif->if_broad;

		// get netwbrc recv socket
		if ((bif->if_netwbrc_sock = socket(PF_INET, SOCK_DGRAM, 0)) < 0)
		{
			dbg(DBGL_CHANGES, DBGT_ERR, "can't create network-broadcast socket: %s", strerror(errno));
			goto error;
		}

		// bind recv socket to interface name
		if (bind_to_iface(bif->if_netwbrc_sock, bif->dev_phy) < 0)
			goto error;

		// bind recv socket to address
		if (bind(bif->if_netwbrc_sock, (struct sockaddr *)&if_netwbrc_addr, sizeof(struct sockaddr_in)) < 0)
		{
			dbg(DBGL_CHANGES, DBGT_ERR, "can't bind network-broadcast socket: %s", strerror(errno));
			goto error;
		}

		// we'll always listen on the full-broadcast address

		struct sockaddr_in if_fullbrc_addr;
		memset(&if_netwbrc_addr, 0, sizeof(struct sockaddr_in));
		if_fullbrc_addr.sin_addr.s_addr = 0xFFFFFFFF;
		if_fullbrc_addr.sin_family = AF_INET;
		if_fullbrc_addr.sin_port = htons(base_port);

		// get fullbrc recv socket
		if ((bif->if_fullbrc_sock = socket(PF_INET, SOCK_DGRAM, 0)) < 0)
		{
			dbg(DBGL_CHANGES, DBGT_ERR, "can't create full-broadcast socket: %s", strerror(errno));
			goto error;
		}

		// bind recv socket to interface name
		if (bind_to_iface(bif->if_fullbrc_sock, bif->dev_phy) < 0)
			goto error;

		// bind recv socket to address
		if (bind(bif->if_fullbrc_sock, (struct sockaddr *)&if_fullbrc_addr, sizeof(struct sockaddr_in)) < 0)
		{
			dbg(DBGL_CHANGES, DBGT_ERR, "can't bind full-broadcast socket: %s", strerror(errno));
			goto error;
		}
	}

	check_kernel_config(bif);

	if (bif == primary_if)
	{
		primary_addr = bif->if_addr;
	}

	bif->if_conf_hard_changed = NO;

	bif->if_conf_soft_changed = YES;

	bif->if_active = YES;

	//reschedule if_reconfigure_soft( bif ) also called from check_interfaces()
	// but should also be called here
	//	-  before first schedule_own_ogm()
	// -   after if_active=YES
	if_reconfigure_soft(bif);

	if (!bif->if_scheduling)
		schedule_own_ogm(bif);

	bif->if_scheduling = YES;

	//activate selector for active interfaces
	change_selects();

	//trigger plugins interested in changed interface configuration
	cb_plugin_hooks(NULL, PLUGIN_CB_CONF);

	return;

error:

	if_deactivate(bif);
}

static int8_t track_route_and_proceed(uint32_t dest, int16_t mask, uint32_t gw, uint32_t src, int32_t ifi, char *dev,
																			int16_t rt_table, int16_t rta_type, int8_t del, int8_t track_t)
{
	struct list_head *list_pos, *tmp_pos, *prev_pos = (struct list_head *)&routes_list;
	struct list_head *first_found_pos = NULL, *first_found_prev = NULL;
	struct routes_node *first_found_rn = NULL;
	uint32_t found_rns = 0;

	paranoia(-500177, (!del && track_t == TRACK_NO));

	list_for_each_safe(list_pos, tmp_pos, &routes_list)
	{
		struct routes_node *tmp_rn = list_entry(list_pos, struct routes_node, list);

		if (tmp_rn->dest == dest &&
				tmp_rn->netmask == mask &&
				tmp_rn->rt_table == rt_table &&
				tmp_rn->rta_type == rta_type)
		{
			// the kernel-ip-stack does not care about my track_t when adding the same route twice
			// but found_rns is evaluated for this
			if (!first_found_rn && (tmp_rn->track_t == track_t || track_t == TRACK_NO))
			{
				first_found_rn = tmp_rn;
				first_found_pos = list_pos;
				first_found_prev = prev_pos;
			}

			found_rns++;
		}

		prev_pos = &tmp_rn->list;
	}

	// if (track_t == TRACK_NO ||
	// 		(del && !first_found_rn) ||
	// 		(del && found_rns != 1) ||
	// 		(!del && found_rns > 0))
	// {
	// 	dbg((track_t == TRACK_NO || (del && !first_found_rn)) ? DBGL_SYS : DBGL_ALL,
	// 			(track_t == TRACK_NO || (del && !first_found_rn)) ? DBGT_ERR : DBGT_INFO,
	// 			"  %s route to %-15s via %-15s  src %s  dev %s table %d  %s  "
	// 			"%s has %d (%d exact) matches",
	// 			del ? "del" : "add", ipStr(dest), ipStr(gw), ipStr(src), dev, rt_table,
	// 			rt2str(rta_type), trackt2str(track_t), found_rns, (first_found_rn ? 1 : 0));
	// }

	if (track_t == TRACK_NO)
		return YES;

	if (del && !first_found_rn)
	{
		dbgf_all(DBGT_WARN, "removing orphan route");
		return NO;
	}
	else if (del && first_found_rn)
	{
		list_del(first_found_prev, first_found_pos, &routes_list);
		debugFree(first_found_rn, 1742);

		if (found_rns > 1)
			return NO;
	}
	else if (!del)
	{
		struct routes_node *tmp_rn = debugMalloc(sizeof(struct routes_node), 742);
		memset(tmp_rn, 0, sizeof(struct routes_node));
		INIT_LIST_HEAD(&tmp_rn->list);

		tmp_rn->dest = dest;
		tmp_rn->netmask = mask;
		tmp_rn->rt_table = rt_table;
		tmp_rn->rta_type = rta_type;
		tmp_rn->track_t = track_t;

		list_add_tail(&tmp_rn->list, &routes_list);

		if (found_rns > 0)
			return NO;
	}

	return YES;
}

void add_del_route(uint32_t dest, int16_t mask, uint32_t gw, uint32_t src, int32_t ifi, char *dev,
									 int16_t rt_table_macro, int16_t rta_type, int8_t del, int8_t track_t)
{
	uint32_t my_router;
	char buf[4096];
	struct sockaddr_nl nladdr;
	struct iovec iov = {buf, sizeof(buf)};
	struct msghdr msg;
	struct nlmsghdr *nh;

	uint16_t rt_table = rt_macro_to_table(rt_table_macro);

	dest = dest & htonl(0xFFFFFFFF << (32 - mask));

	if ((!throw_rules) && (rta_type == RTN_THROW))
		return;

	if (track_route_and_proceed(dest, mask, gw, src, ifi, dev, rt_table, rta_type, del, track_t) == NO)
		return;

	// if (track_t != TRACK_OTHER_HOST)
	// {
	// 	dbg(DBGL_CHANGES, DBGT_INFO,
	// 			" %s route to %15s/%-2d  table %d  via %-15s  dev %-10s ifi %2d  %s %s",
	// 			del ? "del" : "add",
	// 			ipStr(dest), mask, rt_table, ipStr(gw), dev, ifi, rt2str(rta_type), trackt2str(track_t));
	// }

	if (gw == dest)
		my_router = 0;

	else
		my_router = gw;

	dbgf_all(DBGT_INFO, "%s %s to %s/%i via %s (table %i - %s src %s )",
					 del ? "del" : "add",
					 rt2str(rta_type), ipStr(dest), mask, ipStr(gw), rt_table, dev, ipStr(src));

	memset(&nladdr, 0, sizeof(struct sockaddr_nl));
	memset(&req, 0, sizeof(req));
	memset(&msg, 0, sizeof(struct msghdr));

	nladdr.nl_family = AF_NETLINK;

	req.nlh.nlmsg_len = NLMSG_LENGTH(sizeof(struct rtmsg));
	req.nlh.nlmsg_pid = My_pid;

	req.rtm.rtm_family = AF_INET;
	req.rtm.rtm_table = rt_table;
	req.rtm.rtm_dst_len = mask;

	if (del)
	{
		req.nlh.nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK;
		req.nlh.nlmsg_type = RTM_DELROUTE;
		req.rtm.rtm_scope = RT_SCOPE_NOWHERE;
	}
	else
	{
		req.nlh.nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK | NLM_F_CREATE | NLM_F_EXCL /* | NLM_F_REPLACE*/;
		req.nlh.nlmsg_type = RTM_NEWROUTE;

		if (/* source != 0 && */ rta_type == RTN_UNICAST && my_router == 0)
		{
			req.rtm.rtm_scope = RT_SCOPE_LINK;
		}
		else
		{
			req.rtm.rtm_scope = RT_SCOPE_UNIVERSE;
		}

		req.rtm.rtm_protocol = RTPROT_STATIC; // may be changed to some batman specific value - see <linux/rtnetlink.h>
		req.rtm.rtm_type = (rta_type == RTN_THROW ? RTN_THROW : RTN_UNICAST);
	}

	add_rtattr(RTA_DST, (char *)&dest, sizeof(dest));

	if (rta_type == RTN_UNICAST)
	{
		if (my_router)
			add_rtattr(RTA_GATEWAY, (char *)&my_router, sizeof(my_router));

		if (ifi)
			add_rtattr(RTA_OIF, (char *)&ifi, sizeof(ifi));

		if (src /* && my_router == 0 */)
			add_rtattr(RTA_PREFSRC, (char *)&src, sizeof(src));

		if (metric)
			add_rtattr(RTA_PRIORITY, (char *)&metric, sizeof(metric));
	}

	errno = 0;

	if (sendto(nl_sk, &req, req.nlh.nlmsg_len, 0, (struct sockaddr *)&nladdr, sizeof(struct sockaddr_nl)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR,
				"can't send message to kernel via netlink socket for routing table manipulation: %s",
				strerror(errno));

		return;
	}

	while (1)
	{
		msg.msg_name = (void *)&nladdr;
		msg.msg_namelen = sizeof(nladdr);
		msg.msg_iov = &iov;
		msg.msg_iovlen = 1;
		msg.msg_control = NULL;
		msg.msg_controllen = 0;
		msg.msg_flags = 0;

		errno = 0;
		int32_t len = recvmsg(nl_sk, &msg, 0);

		if (len < 0)
		{
			if (errno == EINTR)
			{
				dbgf(DBGL_SYS, DBGT_WARN, "(EINTR) %s", strerror(errno));

				continue;
			}

			if (errno == EWOULDBLOCK || errno == EAGAIN)
			{
				//dbgf( DBGL_CHANGES, DBGT_WARN, "(EWOULDBLOCK || EAGAIN) %s", strerror(errno) );
				break;
			}

			dbgf(DBGL_SYS, DBGT_ERR, "%s", strerror(errno));

			continue;
		}

		if (!len)
		{
			dbgf(DBGL_SYS, DBGT_ERR, "netlink EOF");
		}

		nh = (struct nlmsghdr *)buf;

		while (NLMSG_OK(nh, (uint32_t)len))
		{
			if (nh->nlmsg_type == NLMSG_DONE)
				return;

			if ((nh->nlmsg_type == NLMSG_ERROR) && (((struct nlmsgerr *)NLMSG_DATA(nh))->error != 0))
			{
				dbg(DBGL_CHANGES, DBGT_WARN, "can't %s %s to %s/%i via %s (table %i): %s",
						del ? "delete" : "add", rt2str(rta_type), ipStr(dest), mask, ipStr(gw), rt_table,
						strerror(-((struct nlmsgerr *)NLMSG_DATA(nh))->error));
			}

			nh = NLMSG_NEXT(nh, len);
		}
	}
}

int update_interface_rules(uint8_t cmd)
{
	static uint8_t setup_tunnel = NO;
	static uint8_t setup_networks = NO;

	static uint64_t checksum = 0;

	uint64_t old_checksum = checksum;
	checksum = 0;

	uint8_t if_count = 1;
	char *buf, *buf_ptr;

	struct ifreq *ifr;
	struct ifconf ifc;

	struct batman_if *batman_if;

	struct list_head *throw_pos;
	struct throw_node *throw_node;
	uint32_t no_netmask;

	if (cmd != IF_RULE_CHK_IPS)
	{
		flush_tracked_routes(TRACK_MY_NET);
		flush_tracked_rules(TRACK_MY_NET);
	}

	if (cmd == IF_RULE_SET_TUNNEL)
	{
		setup_tunnel = YES;
		return SUCCESS; //will be called again when bat0s' IP is set
	}
	else if (cmd == IF_RULE_CLR_TUNNEL)
	{
		setup_tunnel = NO;
		return SUCCESS; //will be called again when bat0s' IP gets removed
	}
	else if (cmd == IF_RULE_SET_NETWORKS)
	{
		setup_networks = YES;
	}
	else if (cmd == IF_RULE_CLR_NETWORKS)
	{
		setup_networks = NO;
	}

	if (!(buf = get_ip4conf_buffer(&ifc)))
		return FAILURE;

	for (buf_ptr = buf; buf_ptr < buf + ifc.ifc_len;)
	{
		struct batman_if bif;
		//                memset( &bif, 0, sizeof(struct batman_if));

		ifr = (struct ifreq *)buf_ptr;

		buf_ptr += sizeof(struct ifreq);

		/* ignore if not IPv4 interface */
		if (ifr->ifr_addr.sa_family != AF_INET)
			continue;

		if (!is_interface_up(ifr->ifr_name))
			continue;

		if (if_validate(YES /*set*/, &bif, ifr->ifr_name, YES /*reduced check only*/) == FAILURE)
			continue;

		size_t i;
		struct key
		{
			uint32_t if_prefix_length;
			uint32_t if_netaddr;
			uint32_t if_addr;
		} key = {bif.if_prefix_length, /*bif.if_index,*/ bif.if_netaddr, bif.if_addr};

		for (i = 0; i < sizeof(struct key); i++)
		{
			checksum += ((unsigned char *)(&key))[i];
			checksum += (checksum << 10);
			checksum ^= (checksum >> 6);
		}

		dbgf_ext(DBGT_INFO, "%15ju  %15ju  %10s %15s %15s %2d ",
						 old_checksum, checksum,
						 //                        ((uint32_t*)&(old_checksum))[0], ((uint32_t*)&(old_checksum))[1],
						 //                        ((uint32_t*)&(checksum))[0], ((uint32_t*)&(checksum))[1],
						 ifr->ifr_name, ipStr(bif.if_addr), ipStr(bif.if_netaddr), bif.if_prefix_length);

		if (cmd == IF_RULE_CHK_IPS)
			continue;

		uint8_t add_this_rule = YES;

		list_for_each(throw_pos, &throw_list)
		{
			throw_node = list_entry(throw_pos, struct throw_node, list);

			no_netmask = htonl(0xFFFFFFFF << (32 - throw_node->netmask));

			if (((throw_node->addr & no_netmask) == (bif.if_netaddr & no_netmask)))
				add_this_rule = NO;
		}

		if (prio_rules && setup_tunnel == YES)
		{
			if (!Lo_rule &&
					(bif.if_netaddr & htonl(0xFF000000)) == (htonl(0x7F000000 /*127.0.0.0*/)))
				add_this_rule = NO;

			if (add_this_rule)
			{
				add_del_rule(bif.if_netaddr, bif.if_prefix_length,
										 RT_TABLE_TUNNEL, RT_PRIO_TUNNEL, 0, RTA_SRC, ADD, TRACK_MY_NET);
				if_count++;
			}

			if (Lo_rule && strncmp(ifr->ifr_name, "lo", IFNAMSIZ - 1) == 0)
			{
				add_del_rule(0, 0, RT_TABLE_TUNNEL, RT_PRIO_TUNNEL, "lo", RTA_IIF, ADD, TRACK_MY_NET);
			}
		}

		if (throw_rules && setup_tunnel == YES)
			add_del_route(bif.if_netaddr, bif.if_prefix_length,
										0, 0, 0, ifr->ifr_name, RT_TABLE_TUNNEL, RTN_THROW, ADD, TRACK_MY_NET);

		if (is_batman_if(ifr->ifr_name, &batman_if))
			continue;

		if (throw_rules && setup_networks == YES)
			add_del_route(bif.if_netaddr, bif.if_prefix_length,
										0, 0, 0, ifr->ifr_name, RT_TABLE_NETWORKS, RTN_THROW, ADD, TRACK_MY_NET);
	}

	debugFree(buf, 1601);

	if (cmd != IF_RULE_CHK_IPS)
	{
		list_for_each(throw_pos, &throw_list)
		{
			throw_node = list_entry(throw_pos, struct throw_node, list);

			add_del_route(throw_node->addr, throw_node->netmask,
										0, 0, 0, "unknown", RT_TABLE_HOSTS, RTN_THROW, ADD, TRACK_MY_NET);
			add_del_route(throw_node->addr, throw_node->netmask,
										0, 0, 0, "unknown", RT_TABLE_NETWORKS, RTN_THROW, ADD, TRACK_MY_NET);
			add_del_route(throw_node->addr, throw_node->netmask,
										0, 0, 0, "unknown", RT_TABLE_TUNNEL, RTN_THROW, ADD, TRACK_MY_NET);
		}
	}

	if (cmd == IF_RULE_CHK_IPS && (checksum != old_checksum))
	{
		dbg(DBGL_CHANGES, DBGT_INFO,
				"systems' IP configuration changed! Going to re-init interface rules...");
		update_interface_rules(IF_RULE_UPD_ALL);
	}

	return SUCCESS;
}

// check for further traps: http://lwn.net/Articles/45386/
void check_kernel_config(struct batman_if *batman_if)
{
	if (batman_if)
	{
		char filename[100];

		sprintf(filename, "net/ipv4/conf/%s/rp_filter", batman_if->dev_phy);
		check_proc_sys(filename, 0, &batman_if->if_rp_filter_orig);

		sprintf(filename, "net/ipv4/conf/%s/send_redirects", batman_if->dev_phy);
		check_proc_sys(filename, 0, &batman_if->if_send_redirects_orig);
	}
	else
	{
		check_proc_sys("net/ipv4/conf/all/rp_filter", 0, &if_rp_filter_all_orig);
		check_proc_sys("net/ipv4/conf/default/rp_filter", 0, &if_rp_filter_default_orig);
		check_proc_sys("net/ipv4/conf/all/send_redirects", 0, &if_send_redirects_all_orig);
		check_proc_sys("net/ipv4/conf/default/send_redirects", 0, &if_send_redirects_default_orig);
		check_proc_sys("net/ipv4/ip_forward", 1, &forward_orig);
	}
}

void if_deactivate(struct batman_if *bif)
{
	dbg_mute(30, DBGL_SYS, DBGT_WARN, "deactivating IF %-10s %-15s", bif->dev, ipStr(bif->if_addr));

	if (bif->if_linklayer != VAL_DEV_LL_LO)
	{
		if (bif->if_unicast_sock != 0)
			close(bif->if_unicast_sock);

		bif->if_unicast_sock = 0;

		if (bif->if_netwbrc_sock != 0)
			close(bif->if_netwbrc_sock);

		bif->if_netwbrc_sock = 0;

		if (bif->if_fullbrc_sock != 0)
			close(bif->if_fullbrc_sock);

		bif->if_fullbrc_sock = 0;
	}

	bif->if_active = 0;

	restore_kernel_config(bif);

	change_selects();

	dbgf_all(DBGT_WARN, "Interface %s deactivated", bif->dev);

	if (bif == primary_if && !is_aborted())
	{
		purge_orig(0, 0);

		dbg_mute(30, DBGL_SYS, DBGT_WARN,
						 "You SHOULD always configure a loopback-alias interface for %s/32 to remain reachable under your primary IP!",
						 ipStr(bif->if_addr));
	}
	else
	{
		purge_orig(0, bif);
	}
}

void check_interfaces()
{
	struct list_head *list_pos;
	uint8_t cb_conf_hooks = NO;

	dbgf_all(DBGT_INFO, " ");

	remove_task(check_interfaces, NULL);

	//Do we need this? There was an interface attribute which change is not catched by ifevent_sk ??
	register_task(5000, check_interfaces, NULL);

	if (list_empty(&if_list))
	{
		dbg(DBGL_SYS, DBGT_ERR, "No interfaces specified");
		cleanup_all(CLEANUP_FAILURE);
	}

	Mtu_min = MAX_MTU;

	list_for_each(list_pos, &if_list)
	{
		struct batman_if *bif = list_entry(list_pos, struct batman_if, list);

		if ((bif->if_active) && (!is_interface_up(bif->dev)))
		{
			dbg(DBGL_SYS, DBGT_WARN,
					"detected inactive but used %sprimary interface: %s ! Deactivating now...",
					(bif == primary_if ? "" : "non-"), bif->dev);

			cb_conf_hooks = YES;
			if_deactivate(bif);
		}
		else if (bif->if_active && is_interface_up(bif->dev))
		{
			/* Interface properties might have changed */

			if (if_conf_hard_changed || bif->if_conf_hard_changed ||
					if_validate(NO /*set*/, bif, bif->dev, NO /*reduced check*/) == FAILURE)
			{
				cb_conf_hooks = YES;
				if_deactivate(bif);
			}
			else
			{
				Mtu_min = MIN(Mtu_min, bif->if_mtu);

				dbgf_all(DBGT_INFO,
								 "researching minimum MTU, so fare: %d, current dev %s, mtu: %d",
								 Mtu_min, bif->dev, bif->if_mtu);
			}
		}

		if (if_conf_soft_changed)
			bif->if_conf_soft_changed = YES; // to be considered in if_activate()->if_reconfigure_soft()

		if ((!bif->if_active) && (is_interface_up(bif->dev)))
		{
			struct list_head *tmp_pos;
			struct batman_if *tmp_bif = NULL;
			list_for_each(tmp_pos, &if_list)
			{
				tmp_bif = list_entry(list_pos, struct batman_if, list);

				if (!wordsEqual(tmp_bif->dev, bif->dev) && tmp_bif->if_active && tmp_bif->if_addr == bif->if_addr)
				{
					dbg_mute(40, DBGL_SYS, DBGT_ERR, "IF %-10s IP %-15s already used for IF %s",
									 bif->dev, bif->if_ip_str, tmp_bif->dev);
					break;
				}
				tmp_bif = NULL;
			}

			if (!tmp_bif)
			{
				if (on_the_fly)
					dbg_mute(50, DBGL_SYS, DBGT_INFO,
									 "detected valid but disabled dev: %s ! Activating now...", bif->dev);

				if_activate(bif);
			}
		}

		if (/*bif->if_active  &&*/ (/*if_conf_soft_changed  ||*/ bif->if_conf_soft_changed))
		{
			if (on_the_fly)
				dbg(DBGL_CHANGES, DBGT_INFO, "%s soft interface configuration changed", bif->dev);

			if_reconfigure_soft(bif);
		}

		if (!on_the_fly && !bif->if_active)
		{
			if (bif == primary_if)
			{
				dbg(DBGL_SYS, DBGT_ERR,
						"at least primary interface %s MUST be operational at startup! "
						"Use loopback (e.g. lo:bmx a.b.c.d/32 ) if nothing else is available!",
						bif->dev);

				cleanup_all(CLEANUP_FAILURE);
			}

			dbg(DBGL_SYS, DBGT_WARN,
					"not using interface %s (retrying later): interface not ready", bif->dev);
		}
	}

	if_conf_soft_changed = NO;
	if_conf_hard_changed = NO;

	if (cb_conf_hooks)
		cb_plugin_hooks(NULL, PLUGIN_CB_CONF);

	if (on_the_fly) // opt_policy_rt() is responsible for this during init
		update_interface_rules(IF_RULE_CHK_IPS);
}

static int32_t opt_policy_rt(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	if (cmd == OPT_APPLY)
	{
		check_apply_parent_option(ADD, OPT_APPLY, _save, get_option(0, 0, ARG_PRIO_RULES), "0", cn);
		check_apply_parent_option(ADD, OPT_APPLY, _save, get_option(0, 0, ARG_THROW_RULES), "0", cn);
	}
	else if (cmd == OPT_SET_POST && !on_the_fly)
	{
		// flush orphan routes must be before flushing rules, otherwise orphan routes are not found !
		flush_routes_rules(0 /* flush routes */);

		/* add rule for hosts and announced interfaces and networks */
		if (prio_rules)
			flush_routes_rules(1 /* flush rules */);
	}
	else if (cmd == OPT_POST && !on_the_fly)
	{
		// add rule for hosts and announced interfaces and networks
		if (prio_rules)
		{
			add_del_rule(0, 0, RT_TABLE_HOSTS, RT_PRIO_HOSTS, 0, RTA_DST, ADD, TRACK_STANDARD);
			add_del_rule(0, 0, RT_TABLE_NETWORKS, RT_PRIO_NETWORKS, 0, RTA_DST, ADD, TRACK_STANDARD);
		}

		// add rules and routes for interfaces
		if (update_interface_rules(IF_RULE_SET_NETWORKS) < 0)
			cleanup_all(CLEANUP_FAILURE);
	}

	return SUCCESS;
}

static int32_t opt_throw(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	uint32_t ip;
	int32_t mask;
	char tmp[30];
	struct throw_node *throw_node = NULL;
	struct list_head *throw_tmp, *throw_pos;

	if (cmd == OPT_ADJUST || cmd == OPT_CHECK || cmd == OPT_APPLY)
	{
		if (patch->p_val[0] >= '0' && patch->p_val[0] <= '9')
		{
			// configure an unnamed throw-rule

			if (str2netw(patch->p_val, &ip, '/', cn, &mask, 32) == FAILURE)
				return FAILURE;

			sprintf(tmp, "%s/%d", ipStr(validate_net_mask(ip, mask, 0)), mask);
			set_opt_parent_val(patch, tmp);
		}
		else
		{
			// configure a named throw-rule

			// just for adjust and check
			if (adj_patched_network(opt, patch, tmp, &ip, &mask, cn) == FAILURE)
				return FAILURE;

			if (patch->p_diff == ADD)
			{
				if (adj_patched_network(opt, patch, tmp, &ip, &mask, cn) == FAILURE)
					return FAILURE;
			}
			else
			{
				// re-configure network and netmask parameters of an already configured and named throw-rule
				if (get_tracked_network(opt, patch, tmp, &ip, &mask, cn) == FAILURE)
					return FAILURE;
			}
		}

		struct list_head *prev_pos = (struct list_head *)&throw_list;
		list_for_each_safe(throw_pos, throw_tmp, &throw_list)
		{
			throw_node = list_entry(throw_pos, struct throw_node, list);
			if (throw_node->addr == ip && throw_node->netmask == mask)
				break;
			prev_pos = &throw_node->list;
			throw_node = NULL;
		}

		if (cmd == OPT_ADJUST)
			return SUCCESS;

		if ((patch->p_diff != ADD && !throw_node) || (patch->p_diff == ADD && throw_node))
		{
			dbg_cn(cn, DBGL_SYS, DBGT_ERR, "%s %s does %s exist!",
						 ARG_THROW, tmp, patch->p_diff == ADD ? "already" : "not");
			return FAILURE;
		}

		if (cmd == OPT_CHECK)
			return SUCCESS;

		if (patch->p_diff == DEL || patch->p_diff == NOP)
		{
			list_del(prev_pos, throw_pos, &throw_list);
			debugFree(throw_pos, 1224);
		}

		if (patch->p_diff == NOP)
		{
			// get new network again
			if (adj_patched_network(opt, patch, tmp, &ip, &mask, cn) == FAILURE)
				return FAILURE;
		}

		if (patch->p_diff == ADD || patch->p_diff == NOP)
		{
			throw_node = debugMalloc(sizeof(struct throw_node), 224);
			memset(throw_node, 0, sizeof(struct throw_node));
			INIT_LIST_HEAD(&throw_node->list);
			list_add_tail(&throw_node->list, &throw_list);

			throw_node->addr = ip;
			throw_node->netmask = mask;
		}

		if (on_the_fly)
		{
			/* add rules and routes for interfaces */
			if (update_interface_rules(IF_RULE_UPD_ALL) < 0)
				cleanup_all(CLEANUP_FAILURE);
		}

		return SUCCESS;
	}
	else if (cmd == OPT_UNREGISTER)
	{
		list_for_each_safe(throw_pos, throw_tmp, &throw_list)
		{
			list_del((struct list_head *)&throw_list, throw_pos, &throw_list);

			debugFree(throw_pos, 1224);
		}
	}

	return SUCCESS;
}

static struct opt_type route_options[] =
		{
				//        ord parent long_name          shrt Attributes				*ival		min		max		default		*func,*syntax,*help

				{ODI, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				 0, "\nSystem and policy-routing options:"},

				{ODI, 4, 0, ARG_BASE_PORT, 0, A_PS1, A_ADM, A_INI, A_CFA, A_ANY, &base_port, MIN_BASE_PORT, MAX_BASE_PORT, DEF_BASE_PORT, 0,
				 ARG_VALUE_FORM, "set udp ports"},

				{ODI, 4, 0, ARG_RT_PRIO, 0, A_PS1, A_ADM, A_INI, A_CFA, A_ANY, &Rt_prio, MIN_RT_PRIO, MAX_RT_PRIO, DEF_RT_PRIO, 0,
				 ARG_VALUE_FORM, "set preferences for iproute2-style rules to rt_table (see: man ip)"},

				{ODI, 4, 0, ARG_RT_TABLE, 0, A_PS1, A_ADM, A_INI, A_CFA, A_ANY, &Rt_table, MIN_RT_TABLE, MAX_RT_TABLE - RT_TABLE_MAX_OFFS, DEF_RT_TABLE, 0,
				 ARG_VALUE_FORM, "set bmx routing-table offset (iproute2 style, see: man ip)"},

#ifndef LESS_OPTIONS
				{ODI, 4, 0, ARG_THROW_RULES, 0, A_PS1, A_ADM, A_INI, A_CFA, A_ANY, &throw_rules, 0, 1, DEF_THROW_RULES, 0,
				 ARG_VALUE_FORM, "disable/enable default throw rules"},

				{ODI, 4, 0, ARG_PRIO_RULES, 0, A_PS1, A_ADM, A_INI, A_CFA, A_ANY, &prio_rules, 0, 1, DEF_PRIO_RULES, 0,
				 ARG_VALUE_FORM, "disable/enable default priority rules"},
#endif
				{ODI, 4, 0, ARG_NO_POLICY_RT, 'n', A_PS0, A_ADM, A_INI, A_ARG, A_ANY, 0, 0, 0, 0, opt_policy_rt,
				 0, "disable policy routing (throw and priority rules)"},

#ifndef LESS_OPTIONS
				{ODI, 4, 0, "metric", 0, A_PS1, A_ADM, A_INI, A_CFA, A_ANY, &metric, 0, OV32, DEF_METRIC, 0,
				 ARG_VALUE_FORM, "set non-zero metric for all bmx routes"},

				{ODI, 4, 0, "lo_rule", 0, A_PS1, A_ADM, A_INI, A_CFA, A_ANY, &Lo_rule, 0, 1, DEF_LO_RULE, 0,
				 ARG_VALUE_FORM, "disable/enable autoconfiguration of lo rule"},
#endif
				{ODI, 5, 0, ARG_THROW, 0, A_PMN, A_ADM, A_DYI, A_CFA, A_ANY, 0, 0, 0, 0, opt_throw,
				 ARG_PREFIX_FORM, "do NOT route packets matching src or dst IP range(s) into gateway tunnel or announced networks"},

				{ODI, 5, ARG_THROW, ARG_NETW, 'n', A_CS1, A_ADM, A_DYI, A_CFA, A_ANY, 0, 0, 0, 0, opt_throw,
				 ARG_NETW_FORM, "specify network of throw rule"},

				{ODI, 5, ARG_THROW, ARG_MASK, 'm', A_CS1, A_ADM, A_DYI, A_CFA, A_ANY, 0, 0, 0, 0, opt_throw,
				 ARG_MASK_FORM, "specify network of throw rule"}

#ifndef LESS_OPTIONS
				,
				{ODI, 5, 0, ARG_PEDANTIC_CLEANUP, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &Pedantic_cleanup, 0, 1, DEF_PEDANT_CLNUP, 0,
				 ARG_VALUE_FORM, "disable/enable pedantic cleanup of system configuration (like ip_forward,..) \n"
												 "	at program termination. Its generally safer to keep this disabled to not mess up \n"
												 "	with other routing protocols"}
#endif

};

void init_route_args(void)
{
	register_options_array(route_options, sizeof(route_options));
}

void init_route(void)
{
	if ((nl_sk = open_netlink_socket()) <= 0)
		cleanup_all(-500067);

	if ((flush_sk = open_netlink_socket()) <= 0)
		cleanup_all(-500067);

	errno = 0;
	if (!rt_sock && (rt_sock = socket(AF_INET, SOCK_DGRAM, 0)) < 0)
	{
		dbgf(DBGL_SYS, DBGT_ERR, "can't create routing socket %s:", strerror(errno));
		cleanup_all(-500021);
	}
}

void cleanup_route(void)
{
	flush_tracked_routes(TRACK_NO);
	flush_tracked_rules(TRACK_NO);

	// if ever started succesfully in daemon mode...
	if (on_the_fly)
	{
		// flush orphan routes (and do warning in case)
		// must be before flushing rules, otherwise orphan routes are not found !
		flush_routes_rules(0 /* flush route */);

		// flush orphan rules (and do warning in case)
		if (prio_rules)
			flush_routes_rules(1 /* flush rule */);
	}

	restore_kernel_config(NULL);

	if (nl_sk > 0)
		close(nl_sk);

	if (flush_sk > 0)
		close(flush_sk);

	if (rt_sock)
		close(rt_sock);

	rt_sock = 0;
}
