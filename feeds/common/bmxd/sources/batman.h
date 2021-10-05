/*
 * Copyright (C) 2006 B.A.T.M.A.N. contributors:
 * Thomas Lopatic, Corinna 'Elektra' Aichele, Axel Neumann, Marek Lindner
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

#ifndef _BATMAN_BATMAN_H
#define _BATMAN_BATMAN_H

#include <stdint.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <linux/if.h>

#include "objlist.h"
#include "control.h"
#include "allocate.h"
#include "profile.h"
#include "avl.h"
#include "objlist.h"

/***
 *
 * Things you should enable via your make file:
 *
 * DEBUG_MALLOC   enables malloc() / free() wrapper functions to detect memory leaks / buffer overflows / etc
 * MEMORY_USAGE   allows you to monitor the internal memory usage (needs DEBUG_MALLOC to work)
 * PROFILE_DATA   allows you to monitor the cpu usage for each function
 *
 ***/

/**
 * Some often used variable acronyms:
 * mb			struct msg_buff*	contians metainformation about received packet
 * iif / oif / bif	struct batman_if*	incoming-/outgoing-/batman- interface
 * ln			struct link_node*
 * tn			struct task_node*
 * cdn			struct struct cb_fd_node*
 * pn			struct plugin_node*
 * ogm			struct bat_packet_ogm*
 *
 */

/**
 * Global Variables and definitions
 */

#define SOURCE_VERSION "1.0-freifunk-dresden"

#define COMPAT_VERSION 10

#define ADDR_STR_LEN 16

#define MAX_DBG_STR_SIZE 1500
#define OUT_SEQNO_OFFSET 1

enum NoYes
{
	NO,
	YES
};

enum ADGSN
{
	ADD,
	DEL,
	GET,
	SET,
	NOP
};

#define SUCCESS 0
#define FAILURE -1

#define ILLEGAL_STATE "Illegal program state. This should not happen!"

#ifndef REVISION_VERSION
#define REVISION_VERSION "0"
#endif

/*
 * No configuration files or fancy command line switches yet
 * To experiment with B.A.T.M.A.N. settings change them here
 * and recompile the code
 * Here is the stuff you may want to play with:
 */

#define MAX_GW_UNAVAIL_FACTOR 10 /* 10 */
#define GW_UNAVAIL_TIMEOUT 10000

#define COMMON_OBSERVATION_WINDOW (DEF_OGI * DEF_PWS)

#define MAX_SELECT_TIMEOUT_MS 400 /* MUST be smaller than (1000/2) to fit into max tv_usec */

//#define TYPE_OF_WORD unsigned long /* you should choose something big, if you don't want to waste cpu */
//#define WORD_BIT_SIZE ( sizeof(TYPE_OF_WORD) * 8 )

#define UNUSED_RETVAL(x) do { if(x){} } while(0)

#define OV32 2147483647

#define MAX(a, b) ((a > b) ? (a) : (b))
#define MIN(a, b) ((a < b) ? (a) : (b))
/*
#define MAX_SQ( a, b ) ( (GREAT_SQ( (a), (b) )) ? (a) : (b) )
*/

#define WARNING_PERIOD 20000

#define MAX_PATH_SIZE 300
#define MAX_ARG_SIZE 200

/* DEF_UDPD_SIZE should not be increased before all bmxds' of a mesh support this option!
   Otherwise OGMs + extension headers exceeding this size
   could not be send by nodes with the old MAX_PACKET_SIZE = 256 */
#define MIN_UDPD_SIZE 24
#define DEF_UDPD_SIZE 256
#define MAX_UDPD_SIZE (255 << 2) //the maximum packet size which could be defined with the bat_header->size field
#define ARG_UDPD_SIZE "udp_data_size"

#define MAX_MTU 1500

#define ARG_DEBUG "debug"
#define ARG_NO_FORK "no_fork"
#define ARG_QUIT "quit"

#define ARG_CONNECT "connect"
#define ARG_RUN_DIR "runtime_dir"
#define DEF_RUN_DIR "/var/run/bmx"

extern uint32_t My_pid;

#define SOME_ADDITIONAL_SIZE 0 /*100*/
#define IEEE80211_HDR_SIZE 24
#define LLC_HDR_SIZE 8
#define IP_HDR_SIZE 20
#define UDP_HDR_SIZE 8

#define UDP_OVERHEAD (SOME_ADDITIONAL_SIZE + IEEE80211_HDR_SIZE + LLC_HDR_SIZE + IP_HDR_SIZE + UDP_HDR_SIZE)

#define ARG_HELP "help"
#define ARG_VERBOSE_HELP "verbose_help"

#define ARG_VERSION "version"
#define ARG_TRAILER "trailer"

#define ARG_TEST "test"
#define ARG_SHOW_CHANGED "options"

#define ARG_GW_SCRIPT "script"
extern char * gw_scirpt_name;

#define ARG_DEV "dev"
#define ARG_DEV_TTL "ttl"
#define ARG_DEV_CLONE "clone"
#define ARG_DEV_LL "linklayer"
#define ARG_DEV_HIDE "hide"

#define VAL_DEV_LL_LO 0
#define VAL_DEV_LL_LAN 1
#define VAL_DEV_LL_WLAN 2

#define ARG_ORIGINATORS "originators"
#define ARG_STATUS "status"
#define ARG_LINKS "links"
#define ARG_ROUTES "routes"
#define ARG_INTERFACES "interfaces"

#define ARG_NETA "neta"
#define ARG_NETB "netb"

#define ARG_THROW "throw"

#define HAS_UNIDIRECT_FLAG 0x00000001
#define HAS_DIRECTLINK_FLAG 0x00000002
#define HAS_CLONED_FLAG 0x00000004
#define IS_DIRECT_NEIGH 0x00000008
#define IS_DIRECT_UNDUPL_NEIGH 0x00000010
#define IS_MY_ADDR 0x00000020
#define IS_MY_ORIG 0x00000040
#define IS_BROADCAST 0x00000080
#define IS_VALID 0x00000100
#define IS_NEW 0x00000200
#define IS_BIDIRECTIONAL 0x00000400
#define IS_ACCEPTABLE 0x00000800
#define IS_ACCEPTED 0x00001000
#define IS_BEST_NEIGH_AND_NOT_BROADCASTED 0x00002000
#define IS_ASOCIAL 0x00004000

//#define BATMAN_TIME_START 4294367 //2147183 //5min vor overflow
extern batman_time_t batman_time; //milli seconds
extern batman_time_t batman_time_sec;

extern uint8_t on_the_fly;

extern uint32_t s_curr_avg_cpu_load;

#define SQ_TYPE uint16_t

/**
 * Packet and Message formats
 */

/* the bat_packet_ogm flags: */
#define UNIDIRECTIONAL_FLAG 0x01 /* set when re-broadcasting a received OGM via a curretnly not bi-directional link and only together with IDF */
#define DIRECTLINK_FLAG 0x02		 /* set when re-broadcasting a received OGM with identical OG IP and NB IP on the interface link as received */
#define CLONED_FLAG 0x04				 /* set when (re-)broadcasting a OGM not-for-the-first time or re-broadcasting a OGM with this flag */

struct bat_header
{
	uint8_t version;
  uint8_t networkId_high; //SE: big-endian; replace unused fields with network ID (16bit, is suffient)
	uint8_t networkId_low;  //SE: big-endian; replace unused fields with network ID (16bit, is suffient)
	uint8_t size; // the relevant data size in 4 oktets blocks of the packet (including the bat_header)
} __attribute__((packed));

#define BAT_TYPE_OGM 0x00 // originator message

struct bat_packet_common
{
#if __BYTE_ORDER == __LITTLE_ENDIAN
	unsigned int reserved1 : 4;
	unsigned int bat_type : 3;
	unsigned int ext_msg : 1;
#elif __BYTE_ORDER == __BIG_ENDIAN
	unsigned int ext_msg : 1;
	unsigned int bat_type : 3;
	unsigned int reserved1 : 4;
#else
#error "Please fix <bits/endian.h>"
#endif

	// the size of this pat_packet_xyz msg and appended extenson headers
	// in 4 oktet bocks (including this bat_size and the prevailing oktet)
	uint8_t bat_size;

	uint16_t reserved2;

} __attribute__((packed));

struct bat_packet_ogm
{
#if __BYTE_ORDER == __LITTLE_ENDIAN
	unsigned int flags : 3;		 /* UNIDIRECTIONAL_FLAG, DIRECTLINK_FLAG, CLONED_FLAG, OGI_FLAG... */
	unsigned int ogx_flag : 1; // reserved
	unsigned int bat_type : 3;
	unsigned int ext_msg : 1;
#elif __BYTE_ORDER == __BIG_ENDIAN
	unsigned int ext_msg : 1;
	unsigned int bat_type : 3;
	unsigned int ogx_flag : 1;
	unsigned int flags : 3;
#else
#error "Please fix <bits/endian.h>"
#endif
	uint8_t bat_size;

	uint8_t ogm_pws;	// in 1 bit steps
	uint8_t ogm_misc; // still used for CPU
	//uint8_t ogm_path_lounge;

	uint8_t ogm_ttl;
	uint8_t prev_hop_id;
	SQ_TYPE ogm_seqno;

	uint32_t orig;  //ip address of node that sent the ogm

} __attribute__((packed));

#define EXT_TYPE_MIN 0
#define EXT_TYPE_64B_GW 0
#define EXT_TYPE_64B_PIP 2

/*Stephan:
Die extensions werden am ende einer OGM angeh�ngt. bmxd prueft ob diese
behalten werden wenn eine OGM empfangen wird (also weiter gesendet
(EXT_ATTR_KEEP) oder rausgeschmissen wird).
Dazu gibt es das globale array ext_attribute[]
Das passiert in schedule.c::strip_packet() zeile 760ff

"EXT_DDMESH_FIELD_ID"

Devel-info:
suche nach, als anhaltspunkt:
 	memset(&my_pip_extension_packet, 0, sizeof(struct ext_packet));
	my_pip_extension_packet.EXT_FIELD_MSG = YES;
	my_pip_extension_packet.EXT_FIELD_TYPE = EXT_TYPE_64B_PIP;

*/
//stephan create new extension (we can use maximal 15)
#ifdef ENABLE_DDMESH
	#define EXT_TYPE_64B_DDMESH 3		//struct ext_packet has has
#endif //ENABLE_DDMESH

//SE: die namen der defines spielen nur die konfigurierent attribute
//    aus dem globalen array "ext_attribute[]" wider.
//
#define EXT_TYPE_64B_KEEP_RESERVED4 4
#define EXT_TYPE_64B_DROP_RESERVED5 5
#define EXT_TYPE_TLV_KEEP_RESERVED6 6
#define EXT_TYPE_TLV_DROP_RESERVED7 7
#define EXT_TYPE_64B_KEEP_RESERVED8 8
#define EXT_TYPE_64B_DROP_RESERVED9 9
#define EXT_TYPE_TLV_KEEP_RESERVED10 10
#define EXT_TYPE_TLV_DROP_RESERVED11 11
#define EXT_TYPE_TLV_KEEP_RESERVED12 10
#define EXT_TYPE_TLV_DROP_RESERVED13 11
#define EXT_TYPE_TLV_KEEP_RESERVED14 14
#define EXT_TYPE_TLV_DROP_RESERVED15 15
#define EXT_TYPE_MAX 15


#define EXT_ATTR_TLV 0x01	 /* extension message is TLV type */
#define EXT_ATTR_KEEP 0x02 /* re-propagate extension message (even if unknown) */

extern uint8_t ext_attribute[EXT_TYPE_MAX + 1];

struct ext_packet
{
#define EXT_FIELD_RELATED ext_related
#define EXT_FIELD_TYPE ext_type
#define EXT_FIELD_MSG ext_msg

#define EXT_FIELD_LEN_4B def8 /* the size of this TLV extension header in 4 oktet blocks (including this first 4 oktets) */
#define MIN_TLV_LEN_1B 4			/* the minimum size in bytes (1 octet) of a TLV extension message */

// field accessor for primary interface announcement extension packets
#define EXT_PIP_FIELD_RES1 def8
#define EXT_PIP_FIELD_PIPSEQNO d16.def16
#define EXT_PIP_FIELD_ADDR d32.def32

// stephan
#ifdef ENABLE_DDMESH
	#define EXT_DDMESH_FIELD_8  def8
	#define EXT_DDMESH_FIELD_16 d16.def16
	#define EXT_DDMESH_FIELD_32 d32.def32
#endif 	//ENABLE_DDMESH

#if __BYTE_ORDER == __LITTLE_ENDIAN
	unsigned int ext_related : 2; // may be used by the related message type
	unsigned int ext_type : 5;		// identifies the extension message type and thereby size and content
	unsigned int ext_msg : 1;			// MUST be set to one for extension messages
#elif __BYTE_ORDER == __BIG_ENDIAN
	unsigned int ext_msg : 1;
	unsigned int ext_type : 5;
	unsigned int ext_related : 2;
#else
#error "Please fix <bits/endian.h>"
#endif

	uint8_t def8;

	union
	{
		uint16_t def16;
		uint8_t dat8[2];
	} d16;

	union
	{
		uint32_t def32;
		uint8_t dat8[4];
		uint32_t dat32[1];
	} d32;

} __attribute__((packed));

/**
 * The most important data structures
 */

struct msg_buff
{
	//filled by process_packet()
	struct timeval tv_stamp;
	struct batman_if *iif;
	uint32_t neigh;
	char neigh_str[ADDR_STR_LEN];
	int16_t total_length;
	uint8_t unicast;

  uint16_t networkId;

	//filled by strip_packet()
	struct bat_packet_ogm *ogm;

	struct ext_packet *rcv_ext_array[EXT_TYPE_MAX + 1];
	uint16_t rcv_ext_len[EXT_TYPE_MAX + 1];

	struct ext_packet *snd_ext_array[EXT_TYPE_MAX + 1];
	uint16_t snd_ext_len[EXT_TYPE_MAX + 1];

	char orig_str[ADDR_STR_LEN];

	//filled by process_ogm()

	struct orig_node *orig_node;
	//struct orig_node *orig_node_neigh;
};

struct send_node /* structure for send_list maintaining packets to be (re-)broadcasted */
{
  LIST_ENTRY entry;
	batman_time_t send_time;
	int16_t send_bucket;
	uint8_t iteration;
	uint8_t own_if;
	int32_t ogm_buff_len;
	struct batman_if *if_outgoing;
	struct bat_packet_ogm *ogm;

	// the following ogm_buff array MUST be aligned with bit-range of the OS (64bit for 64-bit OS)
	// having a pointer right before ensures this alignment.
	unsigned char _attached_ogm_buff[]; // this is to access attached ogm data (only if allocated) !!!
};

struct task_node
{
  LIST_ENTRY entry;
	batman_time_t expire;
	void (*task)(void *fpara); // pointer to the function to be executed
	void *data;								 //NULL or pointer to data to be given to function. Data will be freed after functio is called.
};

struct batman_if
{
  LIST_ENTRY entry;
	char dev[IFNAMSIZ + 1];
	char dev_phy[IFNAMSIZ + 1];
	char if_ip_str[ADDR_STR_LEN];

	uint8_t if_active;
	uint8_t if_scheduling;

	uint16_t if_prefix_length;

	int32_t if_index;
	uint32_t if_netaddr;
	uint32_t if_addr;
	uint32_t if_broad;

	uint32_t if_netmask;

	int32_t if_rp_filter_orig;
	int32_t if_send_redirects_orig;

	struct sockaddr_in if_unicast_addr;
	struct sockaddr_in if_netwbrc_addr;

	int32_t if_unicast_sock;
	int32_t if_netwbrc_sock;
	int32_t if_fullbrc_sock;

	SQ_TYPE if_seqno;
	batman_time_t if_seqno_schedule;
	batman_time_t if_last_link_activity;
	batman_time_t if_next_pwrsave_hardbeat;

	/*
	struct send_node own_send_struct;
	struct bat_packet_ogm *own_ogm_out;
	 */

	// having a pointer right before the following array ensures 32/64 bit alignment.
	unsigned char *aggregation_out;
	unsigned char aggregation_out_buff[MAX_UDPD_SIZE + 1];

	int16_t aggregation_len;

	int8_t send_own;

	int8_t if_conf_soft_changed;

	int8_t if_conf_hard_changed;

	int8_t if_linklayer_conf;
	int8_t if_linklayer;

	int16_t if_ttl_conf;
	int16_t if_ttl;

	int16_t if_send_clones_conf;
	int16_t if_send_clones;

	int8_t if_singlehomed_conf;
	int8_t if_singlehomed;
	int if_mtu;
};

struct orig_node /* structure for orig_list maintaining nodes of mesh */
{
	uint32_t orig; /* avl key / this must be the first four bytes! otherwise avl or hash functionality do not work */

	struct neigh_node *router; /* the neighbor which is the currently best_next_hop */

	char orig_str[ADDR_STR_LEN];

  LIST_ENTRY neigh_list_head;
	struct avl_tree neigh_avl;

	batman_time_t last_aware;			 /* when last valid ogm via  this node was received */
	batman_time_t last_valid_time; /* when last valid ogm from this node was received */

	uint32_t first_valid_sec; /* only used for debugging purposes */

	SQ_TYPE last_decided_sqn;
	SQ_TYPE last_accepted_sqn; /* last squence number acceppted for metric */
	SQ_TYPE last_valid_sqn;		 /* last and best known squence number */
	SQ_TYPE last_wavg_sqn;		 /* last sequence number used for estimating ogi */

	// From nodes with several interfaces we may know several originators,
	// this points to the originator structure of the primary interface of a node
	struct orig_node *primary_orig_node;
	int16_t pog_refcnt;

	uint8_t last_path_ttl;

	uint8_t ogx_flag;
	uint8_t pws;
	uint8_t ogm_misc;
	uint32_t ogi_wavg;
	uint32_t rt_changes;

	/* additional information about primary originators (POG) of NeighBoring nodes (these are not necessearily link nodes) */
	batman_time_t last_pog_link; /* when the last time a direct OGM has been received via any of this primary OGs' interfaces */

	uint16_t id4him; /* NB ID assigned by me to the neighboring node, when last_link expired id4him must be reset */
//stephan: MAX_ID4HIM ist eine id die nur fuer direkte nachbarn vergeben wird. fuer einen einfachen knoten ist es
//wohl unwarscheinlich, dass 255 erreicht wird. tbbs sind nur mit einem einzelnen knoten verbunden und die commandline
//schafft nur bis max 240 interfaces. reicht dafuer auch. aber fuer wlan hauptknoten könnten mehr knoten direkt verbunden
//sein. so werde ich diese auf 1024 setzen. das define beschränkt damit den speicherbedarf
//#define MAX_ID4HIM 255
#define MAX_ID4HIM 1024
	uint16_t id4me; /* the ID given by the neighboring POG node to me */

	/*additional information about links to neighboring nodes */
	struct link_node *link_node;

	/*size of plugin data is defined during intialization and depends on registered plugin-data hooks */
	void *plugin_data[];
};

#define SQN_LOUNGE_SIZE (8 * sizeof(uint32_t)) /* must correspond to bits of neigh_node->considered_seqnos */

struct sq_record
{
	SQ_TYPE wa_clr_sqn;		// SQN upto which waightedAverageVal has been purged
	SQ_TYPE wa_set_sqn;		// SQN which has been applied (if equals wa_pos) then wa_unscaled MUST NOT be set again!
	uint32_t wa_unscaled; // unscaled summary value of processed SQNs
	uint32_t wa_val;			// scaled and representative value of processed SQNs
};

struct link_node_dev
{
	LIST_ENTRY list;
	batman_time_t last_lndev;
	struct batman_if *bif;

	struct sq_record rtq_sqr; // my last OGMs as true bits as rebroadcasted by this node and rcvd by me
	struct sq_record rq_sqr;
};

/* MUST be allocated and initiated all or nothing !
 * MUST be initiated with any unidirectional received OGM
 * from a direct link NB
 */
/* Only OG interfaces which are direct link neighbors have a link_node
 * Because neighboring interfaces may be seen via several of our own interfaces
 * each link_node points to one or several link_node_dev structures
 */
struct link_node
{
	LIST_ENTRY list;
	uint32_t orig_addr; // avl key

	struct orig_node *orig_node;

	LIST_ENTRY lndev_list; // list with one link_node_dev element per link
};

struct neigh_node_key
{
	uint32_t addr;
	struct batman_if *iif;
};

/* Path statistics per neighbor via which OGMs of the parent orig_node have been received */
/* Every OG has one ore several neigh_nodes. */
struct neigh_node
{
	LIST_ENTRY list;
	struct neigh_node_key key;


	batman_time_t last_aware; /* when last packet via this neighbour was received */

	SQ_TYPE last_considered_seqno;
	//stephan: also check ttl. if ogm with ttl=1 from non primary interface was received and after from same originator a ogm
	//         with ttl 50, then actually this ogm is not rebroadacast (scheduled). the node will not be known on next hop
	uint8_t last_considered_ttl;

	struct sq_record longtm_sqr;
	struct sq_record recent_sqr;
};

/* list element to store all the disabled tunnel rule netmasks */
struct throw_node
{
	LIST_ENTRY list;
	uint32_t addr;
	uint8_t netmask;
};

/* list element for fast access to all neighboring nodes' primary interface originators */
struct pifnb_node
{
	LIST_ENTRY list;
	struct orig_node *pog;
};

struct srv_node
{
	LIST_ENTRY list;
	uint32_t srv_addr;
	uint16_t srv_port;
	uint8_t srv_seqno;
};

struct gw_node
{
	LIST_ENTRY list;
	struct orig_node *orig_node;
	uint16_t unavail_factor;
	batman_time_t last_failure;
};

struct gw_client
{
	uint32_t addr;
	batman_time_t last_keep_alive;
};

/**
 * functions prototypes
 */

void batman(void);


#endif /* _BATMAN_BATMAN_H */
