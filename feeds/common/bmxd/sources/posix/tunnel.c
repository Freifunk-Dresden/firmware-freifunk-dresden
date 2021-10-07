/*
 * Copyright (C) 2006 BATMAN contributors:
 * Marek Lindner, Axel Neumann
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

#ifndef NOTUNNEL

#include <errno.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <linux/ip.h>
#include <linux/udp.h>
#include <arpa/inet.h>
#include <linux/if_tun.h> /* TUNSETPERSIST, ... */
#include <linux/if.h>			/* ifr_if, ifr_tun */
#include <fcntl.h>				/* open(), O_RDWR */
#include <asm/types.h>
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>

#include "batman.h"
#include "os.h"
#include "originator.h"
#include "plugin.h"
#include "schedule.h"


#define ARG_GW_HYSTERESIS "gateway_hysteresis"
#define MIN_GW_HYSTERE 1
#define MAX_GW_HYSTERE PROBE_RANGE / PROBE_TO100
#define DEF_GW_HYSTERE 2
static int32_t gw_hysteresis;

#define ARG_GW_COMMUNITY "community"
#define MIN_GW_COMMUNITY	0
#define MAX_GW_COMMUNITY	1
#define DEF_GW_COMMUNITY	0
static int32_t communityGateway;

#define DEF_GWTUN_NETW_PREFIX "169.254.0.0" /* 0x0000FEA9 */
static uint32_t gw_tunnel_prefix;

//damit ich per options 10.200er network angeben kann und
//wenn bmxd als gateway arbeitet die ip auch gesetzt wird
#define MIN_GWTUN_NETW_MASK 16

#define MAX_GWTUN_NETW_MASK 30
//change default from 22 to 20 to have 2^ (32-20) clients: 1023 -> 4095 clients
#define DEF_GWTUN_NETW_MASK 20
static uint32_t gw_tunnel_netmask;

/* "-r" is the command line switch for the routing class,
 * 0 set no default route
 * 1 use fast internet connection
 * 2 use stable internet connection
 * 3 use use best statistic (olsr style)
 * this option is used to set the routing behaviour
 */

#define MIN_RT_CLASS 0
#define MAX_RT_CLASS 3
static int32_t routing_class = 0;

static uint32_t pref_gateway = 0;

#define BATMAN_TUN_PREFIX "bat"
#define MAX_BATMAN_TUN_INDEX 20

#define TUNNEL_DATA 0x01
#define TUNNEL_IP_REQUEST 0x02
#define TUNNEL_IP_INVALID 0x03
#define TUNNEL_IP_REPLY 0x06

#define GW_STATE_UNKNOWN 0x01
#define GW_STATE_VERIFIED 0x02

#define ONE_MINUTE 60000

#define GW_STATE_UNKNOWN_TIMEOUT (1 * ONE_MINUTE)
#define GW_STATE_VERIFIED_TIMEOUT (5 * ONE_MINUTE)

#define IP_LEASE_TIMEOUT (1 * ONE_MINUTE)

#define MAX_TUNNEL_IP_REQUESTS 60 //12

//SE: timeout wurde von 1000 auf 5000 erhoeht. dieser wert wird als Schutz vor ueberflutung
//mit tunnel ip requets definert und ist die minimale zeit zwischen neuen tunnel ip requests.
//das ist notwendig wenn die erste anfrage gestellt wird, da ein reply vom gateway server langer
//dauern kann und bis dahin die aktuelle lease time und lease dauer noch 0 ist.
//bei ganz viel nutzern (schnorrstrasse dresden), die gleichzeitig eine anfrage mache, fuert das
//zu ganz vielen anfragen.
#define TUNNEL_IP_REQUEST_TIMEOUT 5000 // msec

#define DEF_TUN_PERSIST 1

static int32_t Tun_persist = DEF_TUN_PERSIST;

static int32_t my_gw_port = 0;
static uint32_t my_gw_addr = 0;

static int32_t tun_orig_registry = FAILURE;

static LIST_ENTRY gw_list;

#define TP_VERS(v) (((v) >> 4) & 0xf)
#define TP_TYPE(v) ((v)&0xf)

struct tun_packet
{
	unsigned char start; //[7:4]version; [3:0]type
	union
	{
		unsigned char ip_packet[MAX_MTU];
		struct iphdr iphdr;
	} u;
} __attribute__((packed)); // use "packed" structure to avoid compiler padding bytes inserted

// MAX_MTU is used for ip_packet buffer size in struct tun_packet
// 1 byte for struct tun_packet::start
#define TX_DP_SIZE (1 + MAX_MTU)

struct gwc_args
{
	batman_time_t gw_state_stamp;
	uint8_t gw_state;
	uint8_t prev_gw_state;
	uint32_t orig;
	struct gw_node *gw_node;			 // pointer to gw node
	struct sockaddr_in gw_addr;		 // gateway ip
	char gw_str[ADDR_STR_LEN];		 // string of gateway ip
	struct sockaddr_in my_addr;		 // primary_ip
	uint32_t my_tun_addr;					 // ip used for bat0 tunnel interface
	char my_tun_str[ADDR_STR_LEN]; // string of my_tun_addr
	int32_t mtu_min;
	uint8_t tunnel_type;
	int32_t udp_sock;
	int32_t tun_fd;
	int32_t tun_ifi;
	char tun_dev[IFNAMSIZ]; // was tun_if
};

struct gws_args
{
	int8_t netmask;
	int32_t port;
	int32_t owt;
	int mtu_min;
	uint32_t my_tun_ip;
	uint32_t my_tun_netmask;
	uint32_t my_tun_ip_h;
	uint32_t my_tun_suffix_mask_h;
	struct sockaddr_in client_addr;
	int32_t sock;
	int32_t tun_fd;
	int32_t tun_ifi;
	char tun_dev[IFNAMSIZ];
};

// field accessor and flags for gateway announcement extension packets
#define EXT_GW_FIELD_GWTYPES ext_related
#define EXT_GW_FIELD_GWFLAGS def8
#define EXT_GW_FIELD_GWPORT d16.def16
#define EXT_GW_FIELD_GWADDR d32.def32

// the flags for gw extension messsage gwtypes:
#define COMMUNITY_GATEWAY 0x01			// this is used by community servers that provide a default
																		// gateway from one to ALL other communities.
																		// The server then can route traffic not found within current
																		// communitiy (not found in bat_route table) to the selected
																		// gw.
																		// such gateways are always preverred over gateways that do not
																		// have this flag set (a router that provides a fall back GW).
																		// such a router, does not signal this flag (via command line)
#define ONE_WAY_TUNNEL_FLAG 0x02

struct tun_orig_data
{
	int16_t tun_array_len;
	struct ext_packet tun_array[];
};

static uint16_t my_gw_ext_array_len = 0;
static struct ext_packet my_gw_extension_packet; //currently only one gw_extension_packet considered
static struct ext_packet *my_gw_ext_array = &my_gw_extension_packet;

static struct gw_node *curr_gateway = NULL;

static struct gws_args *gws_args = NULL;
static struct gwc_args *gwc_args = NULL;

static struct tun_packet tp;

static int32_t batman_tun_index = 0;

static void gwc_cleanup(struct gw_node *curr_gateway);

/* Probe for tun interface availability */
static int8_t probe_tun(void)
{
	int32_t fd;

	if ((fd = open("/dev/net/tun", O_RDWR)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "could not open '/dev/net/tun' ! Is the tun kernel module loaded ?");
		return FAILURE;
	}

	close(fd);

	return SUCCESS;
}

static void del_dev_tun(int32_t fd, char *tun_name, uint32_t tun_ip, char const *whose)
{
	if (Tun_persist && ioctl(fd, TUNSETPERSIST, 0) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't delete tun device: %s", strerror(errno));
		return;
	}

	dbgf(DBGL_SYS, DBGT_INFO, "closing %s tunnel %s  ip %s", whose, tun_name, ipStr(tun_ip));

	close(fd);

	return;
}

//stephan: begin
void call_script(char *pCmd)
{
	#define SCRIPT_CMD_SIZE 256
	static char cmd[SCRIPT_CMD_SIZE];			//mache es static, da ich nicht weiss, wie gross die stacksize ist
	static char old_cmd[25]; //mache es static, da ich nicht weiss, wie gross die stacksize ist

	if (gw_scirpt_name && strcmp(pCmd, old_cmd))
	{
		snprintf(cmd, SCRIPT_CMD_SIZE, "%s %s", gw_scirpt_name, pCmd);
		cmd[SCRIPT_CMD_SIZE-1] = '\0';
		UNUSED_RETVAL(system(cmd));
		strcpy(old_cmd, pCmd);
	}
}
//stephan: end

static int32_t add_dev_tun(uint32_t tun_addr, char *tun_dev, size_t tun_dev_size, int32_t *ifi, int mtu_min)
{
	int32_t tmp_fd = -1;
	int32_t fd = -1;
	int32_t sock_opts;
	struct ifreq ifr_tun, ifr_if;
	struct sockaddr_in addr;
	int req = 0;

	/* set up tunnel device */
	memset(&ifr_if, 0, sizeof(ifr_if));

	if ((fd = open("/dev/net/tun", O_RDWR)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't open tun device (/dev/net/tun): %s", strerror(errno));
		return FAILURE;
	}

	batman_tun_index = 0;
	uint8_t name_tun_success = NO;

	while (batman_tun_index < MAX_BATMAN_TUN_INDEX && !name_tun_success)
	{
		memset(&ifr_tun, 0, sizeof(ifr_tun));
		ifr_tun.ifr_flags = IFF_TUN | IFF_NO_PI;
		sprintf(ifr_tun.ifr_name, "%s%d", BATMAN_TUN_PREFIX, batman_tun_index++);

		if ((ioctl(fd, TUNSETIFF, (void *)&ifr_tun)) < 0)
		{
			dbg(DBGL_CHANGES, DBGT_WARN, "Tried to name tunnel to %s ... busy", ifr_tun.ifr_name);
		}
		else
		{
			name_tun_success = YES;
			dbg(DBGL_CHANGES, DBGT_INFO, "Tried to name tunnel to %s ... success", ifr_tun.ifr_name);
		}
	}

	if (!name_tun_success)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't set tun device (TUNSETIFF): %s", strerror(errno));
		dbg(DBGL_SYS, DBGT_ERR, "Giving up !");
		close(fd);
		return FAILURE;
	}

	if (Tun_persist && ioctl(fd, TUNSETPERSIST, 1) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't set tun device (TUNSETPERSIST): %s", strerror(errno));
		close(fd);
		return FAILURE;
	}

	if ((tmp_fd = socket(AF_INET, SOCK_DGRAM, 0)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't create tun device (udp socket): %s", strerror(errno));
		goto add_dev_tun_error;
	}

	/* set ip of this end point of tunnel */
	memset(&addr, 0, sizeof(addr));
	addr.sin_addr.s_addr = tun_addr;
	addr.sin_family = AF_INET;
	memcpy(&ifr_tun.ifr_addr, &addr, sizeof(struct sockaddr));

	if (ioctl(tmp_fd, (req = SIOCSIFADDR), &ifr_tun) < 0)
		goto add_dev_tun_error;

	if (ioctl(tmp_fd, (req = SIOCGIFINDEX), &ifr_tun) < 0)
		goto add_dev_tun_error;

	*ifi = ifr_tun.ifr_ifindex;

	if (ioctl(tmp_fd, (req = SIOCGIFFLAGS), &ifr_tun) < 0)
		goto add_dev_tun_error;

	ifr_tun.ifr_flags |= IFF_UP;
	ifr_tun.ifr_flags |= IFF_RUNNING;

	if (ioctl(tmp_fd, (req = SIOCSIFFLAGS), &ifr_tun) < 0)
		goto add_dev_tun_error;

	/* set MTU of tun interface: real MTU - 29 */
	if (mtu_min < 100)
	{
		dbg(DBGL_SYS, DBGT_ERR, "MTU min smaller than 100 -> can't reduce MTU anymore");
		req = 0;
		goto add_dev_tun_error;
	}
	else
	{
		ifr_tun.ifr_mtu = mtu_min - 29;

		if (ioctl(tmp_fd, (req = SIOCSIFMTU), &ifr_tun) < 0)
		{
			dbg(DBGL_SYS, DBGT_ERR, "can't set SIOCSIFMTU for device %s: %s",
					ifr_tun.ifr_name, strerror(errno));

			goto add_dev_tun_error;
		}
	}

	/* make tun socket non blocking */
	sock_opts = fcntl(fd, F_GETFL, 0);
	fcntl(fd, F_SETFL, sock_opts | O_NONBLOCK);

	strncpy(tun_dev, ifr_tun.ifr_name, tun_dev_size - 1);
	close(tmp_fd);

	return fd;

add_dev_tun_error:

	if (req)
		dbg(DBGL_SYS, DBGT_ERR, "can't ioctl %d tun device %s: %s", req, tun_dev, strerror(errno));

	if (fd > -1)
		del_dev_tun(fd, tun_dev, tun_addr, __func__);

	if (tmp_fd > -1)
		close(tmp_fd);

	return FAILURE;
}

static int8_t set_tun_addr(int32_t fd, uint32_t tun_addr, char *tun_dev)
{
	struct sockaddr_in addr;
	struct ifreq ifr_tun;

	memset(&ifr_tun, 0, sizeof(ifr_tun));
	memset(&addr, 0, sizeof(addr));

	addr.sin_addr.s_addr = tun_addr;
	addr.sin_family = AF_INET;
	memcpy(&ifr_tun.ifr_addr, &addr, sizeof(struct sockaddr));

	strncpy(ifr_tun.ifr_name, tun_dev, IFNAMSIZ - 1);

	if (ioctl(fd, SIOCSIFADDR, &ifr_tun) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't set tun address (SIOCSIFADDR): %s", strerror(errno));
		return -1;
	}

	return 1;
}

/* returns the up and downspeeds in kbit, calculated from the class */
static void get_gw_speeds(unsigned char class, int *down, int *up)
{
	char sbit = (class & 0x80) >> 7;
	char dpart = (class & 0x78) >> 3;
	char upart = (class & 0x07);

	*down = 32 * (sbit + 2) * (1 << dpart);
	*up = ((upart + 1) * (*down)) / 8;
}

/* calculates the gateway class from kbit */
static unsigned char get_gw_class(int down, int up)
{
	int mdown = 0, tdown, tup, difference = 0x0FFFFFFF;
	unsigned char class = 0, sbit, part;

	/* test all downspeeds */
	for (sbit = 0; sbit < 2; sbit++)
	{
		for (part = 0; part < 16; part++)
		{
			tdown = 32 * (sbit + 2) * (1 << part);

			if (abs(tdown - down) < difference)
			{
				class = (sbit << 7) + (part << 3);
				difference = abs(tdown - down);
				mdown = tdown;
			}
		}
	}

	/* test all upspeeds */
	difference = 0x0FFFFFFF;

	for (part = 0; part < 8; part++)
	{
		tup = ((part + 1) * (mdown)) / 8;

		if (abs(tup - up) < difference)
		{
			class = (class & 0xF8) | part;
			difference = abs(tup - up);
		}
	}

	return class;
}

static void update_gw_list(struct orig_node *orig_node, int16_t gw_array_len, struct ext_packet *gw_array)
{
	struct gw_node *gw_node;
	int download_speed, upload_speed;
	struct tun_orig_data *tuno = orig_node->plugin_data[tun_orig_registry];

	OLForEach(gw_node, struct gw_node, gw_list)
	{
		if (gw_node->orig_node == orig_node)
		{
			dbg(DBGL_CHANGES, DBGT_INFO,
					"Gateway class of originator %s changed from %i -> %i, community %d->%d, port %d, addr %s",
					orig_node->orig_str,
					tuno ? tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS : 0,
					gw_array ? gw_array[0].EXT_GW_FIELD_GWFLAGS : 0,
					tuno ? tuno->tun_array[0].EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY: 0,
					gw_array ? gw_array[0].EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY : 0,

					tuno ? ntohs(tuno->tun_array[0].EXT_GW_FIELD_GWPORT) : 0,
					ipStr(tuno ? tuno->tun_array[0].EXT_GW_FIELD_GWADDR : 0));

			if (tuno)
			{
				debugFree(orig_node->plugin_data[tun_orig_registry], 1123);

				tuno = NULL;
				orig_node->plugin_data[tun_orig_registry] = NULL;

				if (!gw_array)
				{
					OLRemoveEntry(gw_node);
					debugFree(gw_node, 1103);
					dbg(DBGL_CHANGES, DBGT_INFO, "Gateway %s removed from gateway list", orig_node->orig_str);
				}
			}

			if (!tuno && gw_array)
			{
				tuno = debugMalloc(sizeof(struct tun_orig_data) + gw_array_len * sizeof(struct ext_packet), 123);

				orig_node->plugin_data[tun_orig_registry] = tuno;

				memcpy(tuno->tun_array, gw_array, gw_array_len * sizeof(struct ext_packet));

				tuno->tun_array_len = gw_array_len;
			}

			if (gw_node == curr_gateway)
			{
				gwc_cleanup(curr_gateway);
				curr_gateway = NULL;
			}

			return;
		}
	}

	if (gw_array && !tuno)
	{
		get_gw_speeds(gw_array->EXT_GW_FIELD_GWFLAGS, &download_speed, &upload_speed);

		dbg(DBGL_CHANGES, DBGT_INFO, "found new gateway %s, announced by %s -> community: %i, class: %i - %i%s/%i%s",
				ipStr(gw_array->EXT_GW_FIELD_GWADDR),
				orig_node->orig_str,
				gw_array->EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY,
				gw_array->EXT_GW_FIELD_GWFLAGS,
				(download_speed > 2048 ? download_speed / 1024 : download_speed),
				(download_speed > 2048 ? "MBit" : "KBit"),
				(upload_speed > 2048 ? upload_speed / 1024 : upload_speed),
				(upload_speed > 2048 ? "MBit" : "KBit")	);

		gw_node = debugMalloc(sizeof(struct gw_node), 103);
		memset(gw_node, 0, sizeof(struct gw_node));
		OLInitializeListHead(&gw_node->list);

		gw_node->orig_node = orig_node;

		tuno = debugMalloc(sizeof(struct tun_orig_data) + gw_array_len * sizeof(struct ext_packet), 123);

		orig_node->plugin_data[tun_orig_registry] = tuno;

		memcpy(tuno->tun_array, gw_array, gw_array_len * sizeof(struct ext_packet));

		tuno->tun_array_len = gw_array_len;

		gw_node->unavail_factor = 0;
		gw_node->last_failure = batman_time;

		OLInsertTailList(&gw_list, &gw_node->list);

		return;
	}

	cleanup_all(-500018);
}

static int32_t cb_tun_ogm_hook(struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router)
{
	struct orig_node *on = mb->orig_node;
	struct tun_orig_data *tuno = on->plugin_data[tun_orig_registry];

	/* may be GW announcements changed */
	uint16_t gw_array_len = mb->rcv_ext_len[EXT_TYPE_64B_GW] / sizeof(struct ext_packet);
	struct ext_packet *gw_array = gw_array_len ? mb->rcv_ext_array[EXT_TYPE_64B_GW] : NULL;

	if (tuno && !gw_array)
	{
		// remove cached gw_msg
		update_gw_list(on, 0, NULL);
	}
	else if (!tuno && gw_array)
	{
		// memorize new gw_msg
		update_gw_list(on, gw_array_len, gw_array);
	}
	else if (tuno && gw_array &&
					 (tuno->tun_array_len != gw_array_len || memcmp(tuno->tun_array, gw_array, gw_array_len * sizeof(struct ext_packet))))
	{
		// update existing gw_msg
		update_gw_list(on, gw_array_len, gw_array);
	}

	/* restart gateway selection if routing class 3 and we have more packets than curr_gateway */
	if (curr_gateway &&
			on->router &&
			routing_class == 3 &&
			tuno &&
			tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS &&
			curr_gateway->orig_node != on &&
			((pref_gateway == on->orig) ||
			 (pref_gateway != curr_gateway->orig_node->orig &&
				curr_gateway->orig_node->router->longtm_sqr.wa_val + (gw_hysteresis * PROBE_TO100) <= on->router->longtm_sqr.wa_val)))
	{
		dbg(DBGL_CHANGES, DBGT_INFO, "Restart gateway selection. %s gw found! "
																 "%d OGMs from new GW %s (compared to %d from old GW %s)",
				pref_gateway == on->orig ? "Preferred" : "Better",
				on->router->longtm_sqr.wa_val,
				on->orig_str,
				pref_gateway != on->orig ? curr_gateway->orig_node->router->longtm_sqr.wa_val : 255,
				pref_gateway != on->orig ? curr_gateway->orig_node->orig_str : "???");


		gwc_cleanup(curr_gateway);
		curr_gateway = NULL;
	}

	return CB_OGM_ACCEPT;
}

static void gwc_recv_tun(int32_t fd_in)
{
	uint16_t r = 0;
	int32_t tp_data_len, tp_len;

	if (gwc_args == NULL)
	{
		dbgf(DBGL_SYS, DBGT_ERR, "called while curr_gateway_changed  %s",
				 gwc_args ? "with invalid gwc_args..." : "");

		gwc_cleanup(NULL);
		return;
	}

	// read data from bat0 interface and send version+type+u.ip_packet as udp packet
	while (r++ < 30 && (tp_data_len = read(gwc_args->tun_fd, tp.u.ip_packet, sizeof(tp.u.ip_packet) /*TBD: why -2 here? */)) > 0)
	{
		tp_len = tp_data_len + sizeof(tp.start);

		if (tp_data_len < (int32_t)sizeof(struct iphdr) || tp.u.iphdr.version != 4)
		{
			dbgf(DBGL_SYS, DBGT_ERR, "Received Invalid packet type via tunnel !");
			continue;
		}

		tp.start = (COMPAT_VERSION << 4) | TUNNEL_DATA; //version|type

		if (gwc_args->my_tun_addr == 0)
		{
			gwc_args->gw_node->last_failure = batman_time;
			gwc_args->gw_node->unavail_factor++;

			dbgf(DBGL_SYS, DBGT_ERR, "No vitual IP! Ignoring this GW for %d secs",
					 (gwc_args->gw_node->unavail_factor * gwc_args->gw_node->unavail_factor * GW_UNAVAIL_TIMEOUT) / 1000);

			gwc_cleanup(curr_gateway);
			curr_gateway = NULL;
			return;
		}

		if (gwc_args->tunnel_type & ONE_WAY_TUNNEL_FLAG)
		{
			if (sendto(gwc_args->udp_sock, (unsigned char *)&tp.start, tp_len, 0,
								 (struct sockaddr *)&gwc_args->gw_addr, sizeof(struct sockaddr_in)) < 0)
			{
				dbg_mute(30, DBGL_SYS, DBGT_ERR, "can't send data to gateway: %s", strerror(errno));

				gwc_cleanup(curr_gateway);
				curr_gateway = NULL;
				return;
			}

			// dbgf_all( DBGT_INFO "Send data to gateway %s, len %d", gw_str, tp_len );
		}
		else /*if ( gwc_args->last_invalidip_warning == 0 ||
		            (gwc_args->last_invalidip_warning + WARNING_PERIOD) < batman_time) )*/
		{
//sollte hier niemals herkommen, da es nur einen ONE-WAY tunnel gibt
//kann nur sein, wenn ein anderer client einen anderen tunnel signalisiert,
//was aber nicht mehr sein durfte (alte firmware)

			//gwc_args->last_invalidip_warning = batman_time;
			dbg_mute(60, DBGL_CHANGES, DBGT_ERR,
							 "Gateway client - Invalid outgoing src IP: %s (should be %s) or dst IP %s ! Dropping packet",
							 ipStr(tp.u.iphdr.saddr), gwc_args->my_tun_str, gwc_args->gw_str);

			if (tp.u.iphdr.saddr == gwc_args->gw_addr.sin_addr.s_addr)
			{
				gwc_cleanup(curr_gateway);
				return;
			}
		}
	}
}

static void gwc_cleanup(struct gw_node *curr_gateway)
{
	if (gwc_args)
	{
		dbgf(DBGL_CHANGES, DBGT_WARN, "aborted: %s, curr_gateway_changed", (is_aborted() ? "YES" : "NO"));

		update_interface_rules(IF_RULE_CLR_TUNNEL);

		if (gwc_args->my_tun_addr)
		{
			// delete default route (in table bat_default)
			add_del_route(0, 0, 0, 0, gwc_args->tun_ifi, gwc_args->tun_dev, RT_TABLE_TUNNEL, RTN_UNICAST, DEL, TRACK_TUNNEL);

			//delete community default route in bat_route (RT_TABLE_HOST)
			if(curr_gateway && curr_gateway->orig_node)
			{
// route for community: eine default route anlegen, mit dem knoten, ueber das das gw erreichbar ist.
// nicht die gw ip verwendent, sonder die des nachesten hops zum gw. damit musste es dann irgendwann
// beim gw ankommen. dieser muss in seinen rules dann sehen, dass die ip in einem anderen netz liegt
// (bgp) und routen.

// NOTE: I have to check for prefix/netmask. if user did not pass in this
		// then no route will be added.
		// The community route should only forward community pakets.
		// Later when ICVPN is used for other communiiies, bmxd or routing rules
		// must be extended
				if(gNetworkPrefix && gNetworkNetmask)
				{
					add_del_route(gNetworkPrefix, gNetworkNetmask,
										curr_gateway->orig_node->router->key.addr, 0,
										curr_gateway->orig_node->router->key.iif ? curr_gateway->orig_node->router->key.iif->if_index : 0,
										curr_gateway->orig_node->router->key.iif ? curr_gateway->orig_node->router->key.iif->dev : NULL,
										RT_TABLE_HOSTS, RTN_UNICAST, DEL, TRACK_OTHER_HOST);
				}
			}
			call_script("del");
		}

		if (gwc_args->tun_fd)
		{
			del_dev_tun(gwc_args->tun_fd, gwc_args->tun_dev, gwc_args->my_tun_addr, __func__);
			set_fd_hook(gwc_args->tun_fd, gwc_recv_tun, YES /*delete*/);
		}

		if (gwc_args->udp_sock)
		{
			close(gwc_args->udp_sock);
		}

		// critical syntax: may be used for nameserver updates
		dbg(DBGL_CHANGES, DBGT_INFO, "GWT: GW-client tunnel closed ");

		debugFree(gwc_args, 1207);
		gwc_args = NULL;
	}
}

static int8_t gwc_init(void)
{
	dbgf(DBGL_CHANGES, DBGT_INFO, " ");

	if (probe_tun() == FAILURE)
		goto gwc_init_failure;

	if (gwc_args || gws_args)
	{
		dbgf(DBGL_SYS, DBGT_ERR, "gateway client or server already running !");
		goto gwc_init_failure;
	}

	if (!curr_gateway || !curr_gateway->orig_node || !curr_gateway->orig_node->plugin_data[tun_orig_registry])
	{
		dbgf(DBGL_SYS, DBGT_ERR, "curr_gateway invalid!");
		goto gwc_init_failure;
	}

	struct orig_node *on = curr_gateway->orig_node;
	struct tun_orig_data *tuno = on->plugin_data[tun_orig_registry];

	memset(&tp, 0, sizeof(tp));

	gwc_args = debugMalloc(sizeof(struct gwc_args), 207);
	memset(gwc_args, 0, sizeof(struct gwc_args));

	gwc_args->gw_state_stamp = 0;
	gwc_args->gw_state = GW_STATE_UNKNOWN;
	gwc_args->prev_gw_state = GW_STATE_UNKNOWN;

	gwc_args->gw_node = curr_gateway;
	gwc_args->orig = on->orig;
	addr_to_str(on->orig, gwc_args->gw_str);

	gwc_args->gw_addr.sin_family = AF_INET;
	// the cached gw_msg stores the network byte order, so no need to transform
	gwc_args->gw_addr.sin_port = tuno->tun_array[0].EXT_GW_FIELD_GWPORT;
	gwc_args->gw_addr.sin_addr.s_addr = tuno->tun_array[0].EXT_GW_FIELD_GWADDR;

	gwc_args->my_addr.sin_family = AF_INET;
	// the cached gw_msg stores the network byte order, so no need to transform
	gwc_args->my_addr.sin_port = tuno->tun_array[0].EXT_GW_FIELD_GWPORT;
	gwc_args->my_addr.sin_addr.s_addr = primary_addr;

	gwc_args->mtu_min = Mtu_min;

	gwc_args->tunnel_type = ONE_WAY_TUNNEL_FLAG;

	update_interface_rules(IF_RULE_SET_TUNNEL);

	/* connect to server (establish udp tunnel) */
	if ((gwc_args->udp_sock = socket(PF_INET, SOCK_DGRAM, 0)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't create udp socket: %s", strerror(errno));
		goto gwc_init_failure;
	}

	if (bind(gwc_args->udp_sock, (struct sockaddr *)&gwc_args->my_addr, sizeof(struct sockaddr_in)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't bind tunnel socket: %s", strerror(errno));
		goto gwc_init_failure;
	}

	/* make udp socket non blocking */
	int32_t sock_opts;
	if ((sock_opts = fcntl(gwc_args->udp_sock, F_GETFL, 0)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't get opts of tunnel socket: %s", strerror(errno));
		goto gwc_init_failure;
	}

	if (fcntl(gwc_args->udp_sock, F_SETFL, sock_opts | O_NONBLOCK) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't set opts of tunnel socket: %s", strerror(errno));
		goto gwc_init_failure;
	}

	curr_gateway->last_failure = batman_time;

	if ((gwc_args->tun_fd = add_dev_tun(0, gwc_args->tun_dev, sizeof(gwc_args->tun_dev), &gwc_args->tun_ifi, gwc_args->mtu_min)) == FAILURE)
	{
		curr_gateway->unavail_factor++;

		dbgf(DBGL_CHANGES, DBGT_WARN, "could not add tun device, ignoring this GW for %d secs",
				 (curr_gateway->unavail_factor * curr_gateway->unavail_factor * GW_UNAVAIL_TIMEOUT) / 1000);

		goto gwc_init_failure;
	}

	if (set_fd_hook(gwc_args->tun_fd, gwc_recv_tun, NO /*no delete*/) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't register gwc_recv_tun hook");
		goto gwc_init_failure;
	}

	if (gwc_args->tunnel_type & ONE_WAY_TUNNEL_FLAG)
	{
		if (set_tun_addr(gwc_args->udp_sock, gwc_args->my_addr.sin_addr.s_addr, gwc_args->tun_dev) < 0)
		{
			dbgf(DBGL_CHANGES, DBGT_WARN, "could not set tun ip, ignoring this GW for %d secs",
					 (curr_gateway->unavail_factor * curr_gateway->unavail_factor * GW_UNAVAIL_TIMEOUT) / 1000);

			goto gwc_init_failure;
		}

		curr_gateway->unavail_factor = 0;

		gwc_args->my_tun_addr = gwc_args->my_addr.sin_addr.s_addr;
		addr_to_str(gwc_args->my_tun_addr, gwc_args->my_tun_str);

		// add default route to bat_default
		add_del_route(0, 0, 0, 0, gwc_args->tun_ifi, gwc_args->tun_dev, RT_TABLE_TUNNEL, RTN_UNICAST, ADD, TRACK_TUNNEL);

		//SE: create default route to the next hop that also the gateway is using.
		// if all routers have this default route, the packets that are not found in sub-community are traveling
		// to the gateway. This then is responsible to forward it via (e.g.: BGP) to other sub-community and
		// return it back to origin node (initially sent the request)
		// NOTE: I have to check for prefix/netmask. if user did not pass in this
		// then no route will be added.
		// The community route should only forward community pakets of the complete 10.200.er network..
		// Later when ICVPN is used for other communiiies, bmxd or routing rules
		// must be extended
		if(gNetworkPrefix && gNetworkNetmask)
		{
			add_del_route(gNetworkPrefix, gNetworkNetmask,
								curr_gateway->orig_node->router->key.addr, primary_addr,
								curr_gateway->orig_node->router->key.iif ? curr_gateway->orig_node->router->key.iif->if_index : 0,
								curr_gateway->orig_node->router->key.iif ? curr_gateway->orig_node->router->key.iif->dev : NULL,
								RT_TABLE_HOSTS, RTN_UNICAST, ADD, TRACK_OTHER_HOST);
		}

		call_script(gwc_args->gw_str);

		// critical syntax: may be used for nameserver updates
		dbg(DBGL_CHANGES, DBGT_INFO, "GWT: GW-client tunnel init succeeded - type: 1WT  dev: %s  IP: %s  MTU: %d",
				gwc_args->tun_dev, ipStr(gwc_args->my_addr.sin_addr.s_addr), gwc_args->mtu_min);
	}

	return SUCCESS;

gwc_init_failure:

	// critical syntax: may be used for nameserver updates
	dbg(DBGL_CHANGES, DBGT_INFO, "GWT: GW-client tunnel init failed");

	gwc_cleanup(curr_gateway);
	curr_gateway = NULL;

	return FAILURE;
}

// is udp packet from GW-Client
static void gws_recv_udp(int32_t fd_in)
{
	struct sockaddr_in addr;
	static uint32_t addr_len = sizeof(struct sockaddr_in);
	int32_t tp_data_len, tp_len;

	if (gws_args == NULL)
	{
		dbgf(DBGL_SYS, DBGT_ERR, "called with gws_args = NULL");
		return;
	}

	// receive udp package (type+version+u.ip_packet) and
	while ((tp_len = recvfrom(gws_args->sock, (unsigned char *)&tp.start, TX_DP_SIZE, 0, (struct sockaddr *)&addr, &addr_len)) > 0)
	{
		if (tp_len < (int32_t)sizeof(tp.start))
		{
			dbgf(DBGL_SYS, DBGT_ERR, "Invalid packet size (%d) via tunnel, from %s",
					 tp_len, ipStr(addr.sin_addr.s_addr));
			continue;
		}

		if (TP_VERS(tp.start) != COMPAT_VERSION)
		{
			dbgf(DBGL_SYS, DBGT_ERR, "Invalid compat version (%d) via tunnel, from %s",
					 TP_VERS(tp.start), ipStr(addr.sin_addr.s_addr));
			continue;
		}

		tp_data_len = tp_len - sizeof(tp.start);

		if (TP_TYPE(tp.start) == TUNNEL_DATA)
		{
			if (!(tp_data_len >= (int32_t)sizeof(struct iphdr) && tp.u.iphdr.version == 4))
			{
				dbgf(DBGL_SYS, DBGT_ERR, "Invalid packet type via tunnel");
				continue;
			}

			if (gws_args->owt &&
					((tp.u.iphdr.saddr & gws_args->my_tun_netmask) != gws_args->my_tun_ip || tp.u.iphdr.saddr == addr.sin_addr.s_addr))
			{
				if (write(gws_args->tun_fd, tp.u.ip_packet, tp_data_len) < 0)
					dbg(DBGL_SYS, DBGT_ERR, "can't write packet: %s", strerror(errno));

				continue;
			}
		}
		else
		{
			dbgf(DBGL_SYS, DBGT_ERR, "received unknown packet type %d from %s",
					 TP_VERS(tp.start), ipStr(addr.sin_addr.s_addr));
		}
	}
}

static void gws_cleanup(void)
{
	my_gw_ext_array_len = 0;
	memset(my_gw_ext_array, 0, sizeof(struct ext_packet));

	if (gws_args)
	{
		if (gws_args->tun_ifi)
			add_del_route(gws_args->my_tun_ip, gws_args->netmask,
										0, 0, gws_args->tun_ifi, gws_args->tun_dev, 254, RTN_UNICAST, DEL, TRACK_TUNNEL);

		if (gws_args->tun_fd)
		{
			del_dev_tun(gws_args->tun_fd, gws_args->tun_dev, gws_args->my_tun_ip, __func__);
		}

		if (gws_args->sock)
		{
			close(gws_args->sock);
			set_fd_hook(gws_args->sock, gws_recv_udp, YES /*delete*/);
		}

		// critical syntax: may be used for nameserver updates
		dbg(DBGL_CHANGES, DBGT_INFO, "GWT: GW-server tunnel closed - dev: %s  IP: %s/%d  MTU: %d",
				gws_args->tun_dev, ipStr(gws_args->my_tun_ip), gws_args->netmask, gws_args->mtu_min);

		debugFree(gws_args, 1223);
		gws_args = NULL;

		call_script("del");
	}
}

static int32_t gws_init(void)
{
	//char str[16], str2[16];

	if (probe_tun() == FAILURE)
		goto gws_init_failure;

	if (gwc_args || gws_args)
	{
		dbg(DBGL_SYS, DBGT_ERR, "gateway client or server already running !");
		goto gws_init_failure;
	}

	memset(&tp, 0, sizeof(tp));

	/* TODO: This needs a better security concept...
	if ( my_gw_port == 0 ) */
	my_gw_port = base_port + 1;

	/* TODO: This needs a better security concept...
	if ( my_gw_addr == 0 ) */
	my_gw_addr = primary_addr;

	gws_args = debugMalloc(sizeof(struct gws_args), 223);
	memset(gws_args, 0, sizeof(struct gws_args));

	gws_args->netmask = gw_tunnel_netmask;
	gws_args->port = my_gw_port;
	gws_args->owt = 1; //one-way-tunnel
	gws_args->mtu_min = Mtu_min;
	gws_args->my_tun_ip = gw_tunnel_prefix;
	gws_args->my_tun_netmask = htonl(0xFFFFFFFF << (32 - (gws_args->netmask)));
	gws_args->my_tun_ip_h = ntohl(gw_tunnel_prefix);
	gws_args->my_tun_suffix_mask_h = ntohl(~gws_args->my_tun_netmask);

	//addr_to_str( gws_args->my_tun_ip, str );
	//addr_to_str( gws_args->my_tun_netmask, str2 );

	gws_args->client_addr.sin_family = AF_INET;
	gws_args->client_addr.sin_port = htons(gws_args->port);

	if ((gws_args->sock = socket(PF_INET, SOCK_DGRAM, 0)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't create tunnel socket: %s", strerror(errno));
		goto gws_init_failure;
	}

	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(struct sockaddr_in));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(my_gw_port);
	addr.sin_addr.s_addr = primary_addr;

	if (bind(gws_args->sock, (struct sockaddr *)&addr, sizeof(struct sockaddr_in)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't bind tunnel socket: %s", strerror(errno));
		goto gws_init_failure;
	}

	/* make udp socket non blocking */
	int32_t sock_opts;
	if ((sock_opts = fcntl(gws_args->sock, F_GETFL, 0)) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't get opts of tunnel socket: %s", strerror(errno));
		goto gws_init_failure;
	}

	if (fcntl(gws_args->sock, F_SETFL, sock_opts | O_NONBLOCK) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't set opts of tunnel socket: %s", strerror(errno));
		goto gws_init_failure;
	}

	if (set_fd_hook(gws_args->sock, gws_recv_udp, NO /*no delete*/) < 0)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't register gws_recv_udp hook");
		goto gws_init_failure;
	}

	if ((gws_args->tun_fd = add_dev_tun(gws_args->my_tun_ip, gws_args->tun_dev, sizeof(gws_args->tun_dev),
																			&gws_args->tun_ifi, gws_args->mtu_min)) == FAILURE)
	{
		dbg(DBGL_SYS, DBGT_ERR, "can't add tun device");
		goto gws_init_failure;
	}

	add_del_route(gws_args->my_tun_ip, gws_args->netmask,
								0, 0, gws_args->tun_ifi, gws_args->tun_dev, 254, RTN_UNICAST, ADD, TRACK_TUNNEL);

	memset(my_gw_ext_array, 0, sizeof(struct ext_packet));

	my_gw_ext_array->EXT_FIELD_MSG = YES;
	my_gw_ext_array->EXT_FIELD_TYPE = EXT_TYPE_64B_GW;

	my_gw_ext_array->EXT_GW_FIELD_GWFLAGS = Gateway_class;

	my_gw_ext_array->EXT_GW_FIELD_GWTYPES = 0;
	if (Gateway_class) 	{my_gw_ext_array->EXT_GW_FIELD_GWTYPES |= ONE_WAY_TUNNEL_FLAG;}
  if (communityGateway) 	{my_gw_ext_array->EXT_GW_FIELD_GWTYPES |= COMMUNITY_GATEWAY;}

	my_gw_ext_array->EXT_GW_FIELD_GWPORT = htons(my_gw_port);
	my_gw_ext_array->EXT_GW_FIELD_GWADDR = my_gw_addr;

	my_gw_ext_array_len = 1;

	// critical syntax: may be used for nameserver updates
	dbg(DBGL_CHANGES, DBGT_INFO, "GWT: GW-server tunnel init succeeded - dev: %s  IP: %s/%d  MTU: %d",
			gws_args->tun_dev, ipStr(gws_args->my_tun_ip), gws_args->netmask, gws_args->mtu_min);

	call_script("gateway");

	return SUCCESS;

gws_init_failure:

	// critical syntax: may be used for nameserver updates
	dbg(DBGL_CHANGES, DBGT_INFO, "GWT: GW-server tunnel init failed");

	gws_cleanup();

	return FAILURE;
}

static void cb_tun_conf_changed(void *unused)
{
	static int32_t prev_routing_class = 0;
	static int32_t prev_gateway_class = 0;
	static uint32_t prev_primary_ip = 0;
	static int32_t prev_mtu_min = 0;
	static struct gw_node *prev_curr_gateway = NULL;

	if (prev_primary_ip != primary_addr ||
			prev_mtu_min != Mtu_min ||
			prev_curr_gateway != curr_gateway ||
			(prev_routing_class ? 1 : 0) != (routing_class ? 1 : 0) ||
			prev_gateway_class != Gateway_class ||
			(curr_gateway && !gwc_args))
	{
		if (gws_args)
			gws_cleanup();

		if (gwc_args)
			gwc_cleanup(curr_gateway);

		if (primary_addr)
		{
			if (routing_class && curr_gateway)
			{
				gwc_init();
			}
			else if (Gateway_class)
			{
				gws_init();
			}
		}

		prev_primary_ip = primary_addr;
		prev_mtu_min = Mtu_min;
		prev_curr_gateway = curr_gateway;
		prev_routing_class = routing_class;
		prev_gateway_class = Gateway_class;
	}

	return;
}

static void cb_tun_orig_flush(void *data)
{
	struct orig_node *on = data;

	if (on->plugin_data[tun_orig_registry])
		update_gw_list(on, 0, NULL);
}

static void cb_choose_gw(void *unused)
{
	struct gw_node *tmp_curr_gw = NULL;
	/* TBD: check the calculations of this variables for overflows */
	uint8_t max_gw_class = 0;
	uint32_t best_wa_val = 0;
	uint32_t max_gw_factor = 0, tmp_gw_factor = 0;
	int download_speed, upload_speed;

	register_task(1000, cb_choose_gw, NULL);

	if (routing_class == 0 || curr_gateway ||
			((routing_class == 1 || routing_class == 2) &&
			 (batman_time_sec < (COMMON_OBSERVATION_WINDOW / 1000))))
	{
		return;
	}

	// first run i==0 means, that community flag is checked. if
	// no gw was found with such flag, all gw without this flag are checked
	tmp_curr_gw = NULL;
	for( int i = 0; !tmp_curr_gw && i < 2; i++)
	{
		OLForEach(gw_node, struct gw_node, gw_list)
		{
			if (gw_node->unavail_factor > MAX_GW_UNAVAIL_FACTOR)
			{
				gw_node->unavail_factor = MAX_GW_UNAVAIL_FACTOR;
			}

			/* ignore this gateway if recent connection attempts were unsuccessful */
			if (     ((gw_node->unavail_factor * gw_node->unavail_factor * GW_UNAVAIL_TIMEOUT) + gw_node->last_failure)
						>  batman_time
				)
			{
				continue;
			}

			struct orig_node *on = gw_node->orig_node;
			struct tun_orig_data *tuno = on->plugin_data[tun_orig_registry];

			if (!on->router || !tuno)
			{
				continue;
			}

			// check for community flag
			if( i == 0 && ! (tuno->tun_array[0].EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY))
			{ // ignore gw for first run that not have a flag
				continue;
			}

			switch (routing_class)
			{
			case 1: /* fast connection */
				get_gw_speeds(tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS, &download_speed, &upload_speed);

				// is this voodoo ???
				tmp_gw_factor = (((on->router->longtm_sqr.wa_val / PROBE_TO100) *
													(on->router->longtm_sqr.wa_val / PROBE_TO100))) *
												(download_speed / 64);

				if (tmp_gw_factor > max_gw_factor ||
						(tmp_gw_factor == max_gw_factor &&
						on->router->longtm_sqr.wa_val > best_wa_val))
					tmp_curr_gw = gw_node;

				break;

			case 2: /* stable connection (use best statistic) */
				if (on->router->longtm_sqr.wa_val > best_wa_val)
					tmp_curr_gw = gw_node;
				break;

			default: /* fast-switch (use best statistic but change as soon as a better gateway appears) */
				if (on->router->longtm_sqr.wa_val > best_wa_val)
					tmp_curr_gw = gw_node;
				break;
			}

			if (tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS > max_gw_class)
				max_gw_class = tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS;

			best_wa_val = MAX(best_wa_val, on->router->longtm_sqr.wa_val);

			if (tmp_gw_factor > max_gw_factor)
				max_gw_factor = tmp_gw_factor;

			if ((pref_gateway != 0) && (pref_gateway == on->orig))
			{
				tmp_curr_gw = gw_node;

				dbg(DBGL_SYS, DBGT_INFO,
						"Preferred gateway found: %s (gw_flags: %i, packet_count: %i, ws: %i, gw_product: %i)",
						on->orig_str, tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS,
						on->router->longtm_sqr.wa_val / PROBE_TO100, on->pws, tmp_gw_factor);

				break;
			}
		} //for gw list
	} //for: try first gateway community

	if (curr_gateway != tmp_curr_gw)
	{
		if (curr_gateway != NULL)
			dbg(DBGL_CHANGES, DBGT_INFO, "removing old default route");

		/* may be the last gateway is now gone */
		if (tmp_curr_gw != NULL)
		{
			dbg(DBGL_SYS, DBGT_INFO, "using new default tunnel to GW %s (gw_flags: %i, packet_count: %i, gw_product: %i)",
					tmp_curr_gw->orig_node->orig_str, max_gw_class, best_wa_val / PROBE_TO100, max_gw_factor);
		}

		gwc_cleanup(curr_gateway);
		curr_gateway = tmp_curr_gw;

		cb_plugin_hooks(NULL, PLUGIN_CB_CONF);
	}
}

static int32_t cb_send_my_tun_ext(unsigned char *ext_buff)
{
	memcpy(ext_buff, (unsigned char *)my_gw_ext_array, my_gw_ext_array_len * sizeof(struct ext_packet));

	return my_gw_ext_array_len * sizeof(struct ext_packet);
}

static int32_t opt_gateways(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	uint16_t batman_count = 0;

	int download_speed, upload_speed;

	if (cmd != OPT_APPLY)
		return SUCCESS;

	if (OLIsListEmpty(&gw_list))
	{
		dbg_printf(cn, "No gateways in range ...  preferred gateway: %s \n", ipStr(pref_gateway));
	}
	else
	{
		dbg_printf(cn, "%12s     %15s   #   Community      preferred gateway: %s \n", "Originator", "bestNextHop", ipStr(pref_gateway));

		OLForEach(gw_node, struct gw_node, gw_list)
		{
			struct orig_node *on = gw_node->orig_node;
			struct tun_orig_data *tuno = on->plugin_data[tun_orig_registry];

			if (!tuno || on->router == NULL)
				continue;

			get_gw_speeds(tuno->tun_array[0].EXT_GW_FIELD_GWFLAGS, &download_speed, &upload_speed);

			dbg_printf(cn, "%s %-15s %15s %3i, %i, %i%s/%i%s, reliability: %i\n",
								 (gwc_args && curr_gateway == gw_node) ? "=>" : "  ",
								 ipStr(on->orig), ipStr(on->router->key.addr),
								 gw_node->orig_node->router->longtm_sqr.wa_val / PROBE_TO100,
								 tuno->tun_array[0].EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY ? 1 : 0,
								 download_speed > 2048 ? download_speed / 1024 : download_speed,
								 download_speed > 2048 ? "MBit" : "KBit",
								 upload_speed > 2048 ? upload_speed / 1024 : upload_speed,
								 upload_speed > 2048 ? "MBit" : "KBit",
								 gw_node->unavail_factor );

			batman_count++;
		}

		if (batman_count == 0)
			dbg(DBGL_GATEWAYS, DBGT_NONE, "No gateways in range...");

		dbg_printf(cn, "\n");
	}

	return SUCCESS;
}

static int32_t opt_gwtun_netw(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	uint32_t ip = 0;
	int32_t mask = 0;

	if (cmd == OPT_REGISTER)
	{
		inet_pton(AF_INET, DEF_GWTUN_NETW_PREFIX, &gw_tunnel_prefix);
		gw_tunnel_netmask = DEF_GWTUN_NETW_MASK;
	}
	else if (cmd == OPT_CHECK || cmd == OPT_APPLY)
	{
		if (str2netw(patch->p_val, &ip, '/', cn, &mask, 32) == FAILURE ||
				mask < MIN_GWTUN_NETW_MASK || mask > MAX_GWTUN_NETW_MASK)
			return FAILURE;

		if (ip != validate_net_mask(ip, mask, cmd == OPT_CHECK ? cn : 0))
			return FAILURE;

		if (cmd == OPT_APPLY)
		{
			gw_tunnel_prefix = ip;
			gw_tunnel_netmask = mask;
		}
	}

	return SUCCESS;
}

static int32_t opt_rt_class(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	if (cmd == OPT_APPLY)
	{
		if (/* Gateway_class  && */ routing_class)
			check_apply_parent_option(DEL, OPT_APPLY, _save, get_option(0, 0, ARG_GW_CLASS), 0, cn);
	}

	return SUCCESS;
}

static int32_t opt_rt_pref(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	uint32_t test_ip;

	if (cmd == OPT_CHECK || cmd == OPT_APPLY)
	{
		if (patch->p_diff == DEL)
			test_ip = 0;

		else if (str2netw(patch->p_val, &test_ip, '/', cn, NULL, 0) == FAILURE)
			return FAILURE;

		if (cmd == OPT_APPLY)
		{
			pref_gateway = test_ip;

			/* use routing class 3 if none specified */
			/*
			if ( pref_gateway && !routing_class && !Gateway_class )
				check_apply_parent_option( ADD, OPT_APPLY, _save, get_option(0,0,ARG_RT_CLASS), "3", cn );
*/
		}
	}

	return SUCCESS;
}

static int32_t opt_gw_class(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	char gwarg[30];
	int32_t download_speed = 0, upload_speed = 0, gateway_class;
	char *slashp = NULL;

	if (cmd == OPT_CHECK || cmd == OPT_APPLY || cmd == OPT_ADJUST)
	{
		if (patch->p_diff == DEL)
		{
			download_speed = 0;
		}
		else
		{
			if (wordlen(patch->p_val) <= 0 || wordlen(patch->p_val) > 29)
				return FAILURE;

			snprintf(gwarg, wordlen(patch->p_val) + 1, "%s", patch->p_val);

			if ((slashp = strchr(gwarg, '/')) != NULL)
				*slashp = '\0';

			errno = 0;
			download_speed = strtol(gwarg, NULL, 10);

			if ((errno == ERANGE) || (errno != 0 && download_speed == 0))
				return FAILURE;

			if (wordlen(gwarg) > 4 && strncasecmp(gwarg + wordlen(gwarg) - 4, "mbit", 4) == 0)
				download_speed *= 1024;

			if (slashp)
			{
				errno = 0;
				upload_speed = strtol(slashp + 1, NULL, 10);

				if ((errno == ERANGE) || (errno != 0 && upload_speed == 0))
					return FAILURE;

				slashp++;

				if (strlen(slashp) > 4 && strncasecmp(slashp + wordlen(slashp) - 4, "mbit", 4) == 0)
					upload_speed *= 1024;
			}

			if ((download_speed > 0) && (upload_speed == 0))
				upload_speed = download_speed / 5;
		}

		if (download_speed > 0)
		{
			gateway_class = get_gw_class(download_speed, upload_speed);
			get_gw_speeds(gateway_class, &download_speed, &upload_speed);
		}
		else
		{
			gateway_class = download_speed = upload_speed = 0;
		}

		sprintf(gwarg, "%u%s/%u%s",
						(download_speed > 2048 ? download_speed / 1024 : download_speed),
						(download_speed > 2048 ? "MBit" : "KBit"),
						(upload_speed > 2048 ? upload_speed / 1024 : upload_speed),
						(upload_speed > 2048 ? "MBit" : "KBit"));

		if (cmd == OPT_ADJUST)
		{
			set_opt_parent_val(patch, gwarg);
		}
		else if (cmd == OPT_APPLY)
		{
			Gateway_class = gateway_class;

			if (gateway_class /*&&  routing_class*/)
				check_apply_parent_option(DEL, OPT_APPLY, _save, get_option(0, 0, ARG_RT_CLASS), 0, cn);

			dbg(DBGL_SYS, DBGT_INFO, "gateway class: %i -> propagating: %s", gateway_class, gwarg);
		}
	}

	return SUCCESS;
}

static struct opt_type tunnel_options[] = {
		//        ord parent long_name          shrt Attributes				*ival		min		max		default		*func,*syntax,*help
		{ODI, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		 "\nGateway (GW) and tunnel options:"},

		{ODI, 5, 0, ARG_RT_CLASS, 'r', A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &routing_class, 0, 3, 0, opt_rt_class,
		 ARG_VALUE_FORM, "control GW-client functionality:\n"
										 "	0 -> no tunnel, no default route (default)\n"
										 "	1 -> permanently select fastest GW according to GW announcment (deprecated)\n"
										 "	2 -> permanently select most stable GW accoridng to measurement \n"
										 "	3 -> dynamically switch to most stable GW"},

		{ODI, 5, 0, ARG_GW_HYSTERESIS, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &gw_hysteresis, MIN_GW_HYSTERE, MAX_GW_HYSTERE, DEF_GW_HYSTERE, 0,
		 ARG_VALUE_FORM, "set number of additional rcvd OGMs before changing to more stable GW (only relevant for -r3 GW-clients)"},

		{ODI, 5, 0, "preferred_gateway", 'p', A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, 0, 0, 0, 0, opt_rt_pref,
		 ARG_ADDR_FORM, "permanently select specified GW if available"},

		{ODI, 5, 0, ARG_GW_COMMUNITY, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &communityGateway, MIN_GW_COMMUNITY, MAX_GW_COMMUNITY, DEF_GW_COMMUNITY, 0,
		 ARG_VALUE_FORM, "gateway is a community gw that can route default traffic to other communities"},

		{ODI, 5, 0, ARG_GW_CLASS, 'g', A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, 0, 0, 0, 0, opt_gw_class,
		 ARG_VALUE_FORM "[/VAL]", "set GW up- & down-link class (e.g. 5mbit/1024kbit)"},

		{ODI, 4, 0, ARG_GWTUN_NETW, 0, A_PS1, A_ADM, A_INI, A_CFA, A_ANY, 0, 0, 0, 0, opt_gwtun_netw,
		 ARG_PREFIX_FORM, "set network used by gateway nodes\n"},

#ifndef LESS_OPTIONS
		{ODI, 5, 0, "tun_persist", 0, A_PS1, A_ADM, A_INI, A_CFA, A_ANY, &Tun_persist, 0, 1, DEF_TUN_PERSIST, 0,
		 ARG_VALUE_FORM, "disable/enable ioctl TUNSETPERSIST for GW tunnels (disabling was required for openVZ emulation)"},
#endif

		{ODI, 5, 0, ARG_GATEWAYS, 0, A_PS0, A_USR, A_DYN, A_ARG, A_END, 0, 0, 0, 0, opt_gateways, 0,
		 "show currently available gateways\n"}};

static void tun_cleanup(void)
{
	set_snd_ext_hook(EXT_TYPE_64B_GW, cb_send_my_tun_ext, DEL);

	set_ogm_hook(cb_tun_ogm_hook, DEL);

	if (gws_args)
		gws_cleanup();

	if (gwc_args)
		gwc_cleanup(NULL);
}

static int32_t tun_init(void)
{
	register_options_array(tunnel_options, sizeof(tunnel_options));

	if ((tun_orig_registry = reg_plugin_data(PLUGIN_DATA_ORIG)) < 0)
		return FAILURE;

	set_ogm_hook(cb_tun_ogm_hook, ADD);

	set_snd_ext_hook(EXT_TYPE_64B_GW, cb_send_my_tun_ext, ADD);

	register_task(1000, cb_choose_gw, NULL);

	cb_tun_conf_changed(NULL);

	return SUCCESS;
}

struct plugin_v1 *tun_get_plugin_v1(void)
{
	static struct plugin_v1 tun_plugin_v1;
	memset(&tun_plugin_v1, 0, sizeof(struct plugin_v1));

	tun_plugin_v1.plugin_version = PLUGIN_VERSION_01;
	tun_plugin_v1.plugin_size = sizeof(struct plugin_v1);
	tun_plugin_v1.plugin_name = "bmx_tunnel_plugin";
	tun_plugin_v1.cb_init = tun_init;
	tun_plugin_v1.cb_cleanup = tun_cleanup;

	tun_plugin_v1.cb_plugin_handler[PLUGIN_CB_CONF] = cb_tun_conf_changed;
	tun_plugin_v1.cb_plugin_handler[PLUGIN_CB_ORIG_FLUSH] = cb_tun_orig_flush;
	tun_plugin_v1.cb_plugin_handler[PLUGIN_CB_ORIG_DESTROY] = cb_tun_orig_flush;

	return &tun_plugin_v1;
}

void init_tunnel(void)
{
	OLInitializeListHead(&gw_list);
}

#endif
