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

void update_community_route(void);

#define ARG_GW_HYSTERESIS "gateway_hysteresis"
#define MIN_GW_HYSTERE 1
#define MAX_GW_HYSTERE PROBE_RANGE / PROBE_TO100
#define DEF_GW_HYSTERE 2
static int32_t gw_hysteresis;

#define ARG_GW_COMMUNITY "community_gateway"
#define MIN_GW_COMMUNITY	0
#define MAX_GW_COMMUNITY	1
#define DEF_GW_COMMUNITY	0
static int32_t communityGateway;

#define ARG_ONLY_COMMUNITY_GW "only_community_gw"
#define MIN_ONLY_COMMUNITY_GW	0
#define MAX_ONLY_COMMUNITY_GW	1
#define DEF_ONLY_COMMUNITY_GW	0
static int32_t onlyCommunityGateway;

/* "-r" is the command line switch for the routing class,
 * 0 set no default route
 * 1 use fast internet connection
 * 2 use stable internet connection
 * 3 use use best statistic (olsr style)
 * this option is used to set the routing behaviour
 */

//#define MIN_RT_CLASS 0
//#define MAX_RT_CLASS 3
static int32_t routing_class = 0;
static uint32_t pref_gateway = 0;
static int32_t my_gw_port = 0;
static uint32_t my_gw_addr = 0;
static LIST_ENTRY gw_list;

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

static uint16_t my_gw_ext_array_len = 0;
static struct ext_packet my_gw_extension_packet; //currently only one gw_extension_packet considered
static struct ext_packet *my_gw_ext_array = &my_gw_extension_packet;

static struct gw_node *curr_gateway = NULL;

typedef enum {
  BmxdMode_None,
  BmxdMode_Client,
  BmxdMode_Gateway
} BmxdMode_t;

static BmxdMode_t _bmxdMode = { BmxdMode_None };

static void gwc_cleanup(int bCallScript);

//stephan:
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

static void update_gw_list(struct orig_node *orig_node, struct ext_packet *new_gw_extension)
{
  struct gw_node *gw_node;
  int download_speed, upload_speed;
  struct ext_packet *gw_ext = orig_node->gw_ext;

//  dbg(DBGL_SYS, DBGT_INFO, "RCV OGM [%lu] from %s, last:%llu", orig_node->last_valid_sqn, orig_node->orig_str, orig_node->last_aware);

  // --- check if we already have this gw in our list
  // search and update gateway tunnel object from ext_packet
  OLForEach(gw_node, struct gw_node, gw_list)
  {
    // do only some action if the node in the list is the selected.
    if (gw_node->orig_node == orig_node)
    {
      if(gw_ext && !new_gw_extension)
      {
//        dbg(DBGL_SYS, DBGT_INFO,
//            "originator %s curr: Gateway class %i, community %d | incomming: no info == DELETE",
//            orig_node->orig_str,
//            gw_ext->EXT_GW_FIELD_GWFLAGS,
//            gw_ext->EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY);

        // free old tunnel
        debugFree(orig_node->gw_ext, 1123);
        orig_node->gw_ext = NULL;

        // current gateway does not exisit any more -> reselect
        if(curr_gateway == gw_node)
        {
          curr_gateway = NULL;
        }

        // current node is no gw anymore -> remove from gw_list
        OLRemoveEntry(gw_node);
        debugFree(gw_node, 1103);
        // dbg(DBGL_SYS, DBGT_INFO, "NO new_gw_extension in current OGM: Gateway %s removed from gateway list", orig_node->orig_str);

      //SE: teste ob alle nodes weg sind und rufe nutzer script auf
      // um dns zurueck zu setzen.
      // Test: 	router mesht NICHT via wifi, lan,wan,vlan.
      // 				router ist mit wan internet verbnden und hat fritzbox dns
      //				router baut dann backone auf und setzt via bmxd dns auf gw
      //				wenn jetzt backbone neu gestartet wird, fallen alle knoten
      //				weg (auch gw)
      if(OLIsListEmpty(&gw_list))
      {
        dbg(DBGL_SYS, DBGT_INFO, "no more gateways -> reset dns");
        call_script("del");
      }

        return; // ogm has been processed, do not process it as 'new'
      }

// folgende bedingung duerfte nicht da sein, da wir hier durch die schleife gueltiger
// gw nodes laufen. da muss immer ien gw_ext vorhanden sein. (siehe unten, da wird es ja
// erzeugt falls nicht in liste)
      if(!gw_ext && new_gw_extension)
      {
        dbg(DBGL_SYS, DBGT_ERR,
            "originator %s curr: NO tunnel info | incomming: Gateway class %i, community %d == NEW-error",
            orig_node->orig_str,
            new_gw_extension[0].EXT_GW_FIELD_GWFLAGS,
            new_gw_extension[0].EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY);
        dbg(DBGL_SYS, DBGT_ERR, "there shouldn't be here");
        return; // ogm has been processed, do not process it as 'new'
      }

      if(gw_ext && new_gw_extension)
      {
        dbg(DBGL_SYS, DBGT_INFO,
            "originator %s curr: Gateway class %i, community %d | incomming: Gateway class %i, community %d == UPDATE",
            orig_node->orig_str,
            gw_ext->EXT_GW_FIELD_GWFLAGS,
            gw_ext->EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY,
            new_gw_extension[0].EXT_GW_FIELD_GWFLAGS,
            new_gw_extension[0].EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY);

        // free old tunnel
        debugFree(orig_node->gw_ext, 1123);
        orig_node->gw_ext = NULL;

        // store new gw info
        gw_ext = debugMalloc(sizeof(struct ext_packet), 123);
        orig_node->gw_ext = gw_ext;
        memcpy(gw_ext, new_gw_extension, sizeof(struct ext_packet));

        // dbg(DBGL_SYS, DBGT_INFO, "gw info updated");
        return; // ogm has been processed, do not process it as 'new'
      }
    }
  }

  // --- new gw found
  // we shouldn't have any valid gw_ext here
  if (gw_ext)
  {
    dbg(DBGL_SYS, DBGT_ERR, "there shouldn't be any valid gw_ext");
    debugFree(orig_node->gw_ext, 1123);
    orig_node->gw_ext = NULL;
  }

  // check if new gw infos was received
  if (new_gw_extension)
  {
    get_gw_speeds(new_gw_extension->EXT_GW_FIELD_GWFLAGS, &download_speed, &upload_speed);
//    dbg(DBGL_SYS, DBGT_INFO, "found new gateway %s, announced by %s -> community: %i, class: %i - %i%s/%i%s == NEW",
//        ipStr(new_gw_extension->EXT_GW_FIELD_GWADDR),
//        orig_node->orig_str,
//        new_gw_extension->EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY,
//        new_gw_extension->EXT_GW_FIELD_GWFLAGS,
//        (download_speed > 2048 ? download_speed / 1024 : download_speed),
//        (download_speed > 2048 ? "MBit" : "KBit"),
//        (upload_speed > 2048 ? upload_speed / 1024 : upload_speed),
//        (upload_speed > 2048 ? "MBit" : "KBit")	);

    // create new gw node object
    gw_node = debugMalloc(sizeof(struct gw_node), 103);
    memset(gw_node, 0, sizeof(struct gw_node));
    OLInitializeListHead(&gw_node->list);

    gw_node->orig_node = orig_node;

    // store new gw info
    gw_ext = debugMalloc(sizeof(struct ext_packet), 123);
    orig_node->gw_ext = gw_ext;
    memcpy(gw_ext, new_gw_extension, sizeof(struct ext_packet));

    // add new gw node object to gw_list
    OLInsertTailList(&gw_list, &gw_node->list);

    return;
  }

  cleanup_all(-500018);
}

void process_tun_ogm(struct msg_buff *mb, uint16_t oCtx, struct neigh_node *old_router)
{
  struct orig_node *on = mb->orig_node;
  struct ext_packet *gw_ext = on->gw_ext;

  /* may be GW announcements changed */
  uint16_t ext_array_len = mb->rcv_ext_len[EXT_TYPE_64B_GW] / sizeof(struct ext_packet);
  struct ext_packet *new_gw_extension = ext_array_len ? mb->rcv_ext_array[EXT_TYPE_64B_GW] : NULL;

  int reselect = 0;

  if (gw_ext && !new_gw_extension)
  {
    // remove cached gw_msg
    update_gw_list(on, NULL);
  }
  else if (!gw_ext && new_gw_extension)
  {
    // save new gw_msg
    update_gw_list(on, new_gw_extension);
  }
  else if (gw_ext && new_gw_extension &&
           ( memcmp(gw_ext, new_gw_extension, sizeof(struct ext_packet))))
  {
    // update existing gw_msg
    update_gw_list(on, new_gw_extension);
  }

  /* restart gateway selection if routing class 3 and we have more packets than curr_gateway */
  if (curr_gateway &&
      on->router &&
      routing_class == 3 &&
      gw_ext &&
      gw_ext->EXT_GW_FIELD_GWFLAGS &&
      curr_gateway->orig_node != on 	// if new originator is different from current selected
     )
  {
    // in case orig_node is gone
    if (!curr_gateway->orig_node)
    {
      dbg(DBGL_SYS, DBGT_INFO, "Restart gateway selection - orig_node gone");
      reselect = 1;
    }
    else
    {
      // either process all gateways or only community gw
      if (   ! onlyCommunityGateway
            || (onlyCommunityGateway && gw_ext->EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY) )
      {
        // if the new gw (orig) is preferred gw and not currently selected
        if ( pref_gateway == on->orig && pref_gateway != curr_gateway->orig_node->orig)
        {
          dbg(DBGL_SYS, DBGT_INFO, "Restart gateway selection - preferred found");
          reselect = 1;
        }

        // ignore "better-check" if current selected is the preferred gw
        if (   pref_gateway != curr_gateway->orig_node->orig
            && curr_gateway->orig_node->router->longtm_sqr.wa_val + (gw_hysteresis * PROBE_TO100) <= on->router->longtm_sqr.wa_val
        )
        {
          dbg(DBGL_SYS, DBGT_INFO, "Restart gateway selection - better found");
          reselect = 1;
        }
      }
    }
  }

  // reselect either when required by this function or when gateway was reset
  // by update_gw_list()
  if(reselect /* || !curr_gateway */)
  {
    curr_gateway = NULL; // trigger reselection
  }

}

static void gwc_cleanup(int bCallScript)
{
  if (_bmxdMode == BmxdMode_Client)
  {
    _bmxdMode = BmxdMode_None;
    if(bCallScript)
    {
      dbg(DBGL_SYS, DBGT_INFO, "gwc clean-up(del)");
      call_script("del");
    }
  }
}

static int8_t gwc_init(void)
{
  char addr[ADDR_STR_LEN];
  dbgf(DBGL_CHANGES, DBGT_INFO, " ");

  if (_bmxdMode != BmxdMode_None)
  {
    dbgf(DBGL_SYS, DBGT_ERR, "gateway client or server already running !");
    gwc_cleanup(1); //on error
    curr_gateway = NULL;
    return FAILURE;
  }

  if (!curr_gateway || !curr_gateway->orig_node || !curr_gateway->orig_node->gw_ext)
  {
    dbgf(DBGL_SYS, DBGT_ERR, "curr_gateway invalid!");
    gwc_cleanup(1); //on error
    curr_gateway = NULL;
    return FAILURE;
  }

  addr_to_str(curr_gateway->orig_node->orig, addr);
  call_script(addr);
  _bmxdMode = BmxdMode_Client;

  return SUCCESS;


}

static void gws_cleanup(void)
{
  my_gw_ext_array_len = 0;
  memset(my_gw_ext_array, 0, sizeof(struct ext_packet));

  if (_bmxdMode == BmxdMode_Gateway)
  {
    dbg(DBGL_SYS, DBGT_INFO, "gws clean-up");
    _bmxdMode = BmxdMode_None;
    call_script("del");
  }
}

static int32_t gws_init(void)
{
  if (_bmxdMode != BmxdMode_None)
  {
    dbg(DBGL_SYS, DBGT_ERR, "gateway client or server already running !");
    gws_cleanup();
    return FAILURE;
  }

  _bmxdMode = BmxdMode_Gateway;

  memset(my_gw_ext_array, 0, sizeof(struct ext_packet));

  my_gw_ext_array->EXT_FIELD_MSG = YES;
  my_gw_ext_array->EXT_FIELD_TYPE = EXT_TYPE_64B_GW;

  my_gw_ext_array->EXT_GW_FIELD_GWFLAGS = Gateway_class;

  my_gw_ext_array->EXT_GW_FIELD_GWTYPES = 0;
  if (Gateway_class) 	{my_gw_ext_array->EXT_GW_FIELD_GWTYPES |= ONE_WAY_TUNNEL_FLAG;}
  if (communityGateway) 	{my_gw_ext_array->EXT_GW_FIELD_GWTYPES |= COMMUNITY_GATEWAY;}

  my_gw_ext_array->EXT_GW_FIELD_GWPORT = htons(my_gw_port);
  my_gw_ext_array->EXT_GW_FIELD_GWADDR = my_gw_addr;

  my_gw_ext_array_len = 1;  // 1 * sizeof(struct ext_packet)
                            // bmx sendet pro gw nur ein ext_packet mit den infos des gws

  call_script("gateway");

  return SUCCESS;
}

void trigger_tun_update(void)
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
      (curr_gateway
     && _bmxdMode != BmxdMode_Client
      ))
  {
//if(_bmxdMode != BmxdMode_None)dbg(DBGL_SYS, DBGT_INFO, "trigger_tun_update()");
    switch(_bmxdMode)
    {
      case BmxdMode_Client: gwc_cleanup(0); break; //evt muss beim wechsel von Gateway<->Client immer die routen
      case BmxdMode_Gateway: gws_cleanup(); break; // aufgeraumt werden, wie es aktuell passiert. aber nicht "del"
      default: break;                              // ans bmxd script gliefert werden. da hier curr_gateway nicht
    }                                              // benutzt wird, eine gw selection zu triggern

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

void flush_tun_orig(struct orig_node *on)
{
  if (on->gw_ext)
  {
    update_gw_list(on, NULL);
  }
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

  OLForEach(gw_node, struct gw_node, gw_list)
  {
    // check that the gw node has valid tunnel object data (received via ext_packet)
    struct orig_node *on = gw_node->orig_node;
    struct ext_packet *gw_ext = on->gw_ext;
    if (!on->router || !gw_ext)
    {
      continue;
    }

// dbg(DBGL_SYS, DBGT_INFO, "check gateway: %s, community: %i # %i (best: %i)", on->orig_str
// , gw_ext->EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY
// ,on->router->longtm_sqr.wa_val / PROBE_TO100, best_wa_val
// );

    // check for community flag
    if(onlyCommunityGateway && ! (gw_ext->EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY))
    {
//dbg(DBGL_SYS, DBGT_INFO, "ignore gw - not a community gw");
      continue;
    }

    switch (routing_class)
    {
      case 1: /* fast connection */
        get_gw_speeds(gw_ext->EXT_GW_FIELD_GWFLAGS, &download_speed, &upload_speed);

        // is this voodoo ???
        tmp_gw_factor = (((on->router->longtm_sqr.wa_val / PROBE_TO100) *
                          (on->router->longtm_sqr.wa_val / PROBE_TO100))) *
                        (download_speed / 64);

        if (tmp_gw_factor > max_gw_factor ||
            (tmp_gw_factor == max_gw_factor &&
            on->router->longtm_sqr.wa_val > best_wa_val))
          tmp_curr_gw = gw_node;

        break;

      case 2: /* fall-through */ /* stable connection (use best statistic) */
      case 3: /* fall-through */ /* fast-switch (use best statistic but change as soon as a better gateway appears) */
      default:
        if (on->router->longtm_sqr.wa_val > best_wa_val)
        {
          tmp_curr_gw = gw_node;
          dbg(DBGL_SYS, DBGT_INFO, "select gateway: %s, community: %i # %i (best: %i)"
            , on->orig_str
            , gw_ext->EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY
            ,on->router->longtm_sqr.wa_val / PROBE_TO100, best_wa_val
            );
        }
        break;
    }

    if (gw_ext->EXT_GW_FIELD_GWFLAGS > max_gw_class)
      max_gw_class = gw_ext->EXT_GW_FIELD_GWFLAGS;

    best_wa_val = MAX(best_wa_val, on->router->longtm_sqr.wa_val);

    if (tmp_gw_factor > max_gw_factor)
      max_gw_factor = tmp_gw_factor;

    // overwrite previously found (perhaps better) gw in favour to preferred gw
    if ((pref_gateway != 0) && (pref_gateway == on->orig))
    {
      tmp_curr_gw = gw_node;

      dbg(DBGL_SYS, DBGT_INFO,
          "Preferred gateway found: %s (gw_flags: %i, packet_count: %i, ws: %i, gw_product: %i)",
          on->orig_str, gw_ext->EXT_GW_FIELD_GWFLAGS,
          on->router->longtm_sqr.wa_val / PROBE_TO100, on->pws, tmp_gw_factor);

      break;
    }
  } //for gw list

  // when we have not found any gw -> delete
  if(!tmp_curr_gw)
  {
    gwc_cleanup(1); // "del" if we have no gw found
  }
  else // update
  {
    gwc_cleanup(0); // just cleanup
  }

  if (curr_gateway != tmp_curr_gw)
  {
    /* may be the last gateway is now gone */
    if (tmp_curr_gw)
    {
      dbg(DBGL_SYS, DBGT_INFO, "using new default tunnel to GW %s (gw_flags: %i, packet_count: %i, gw_product: %i)",
          tmp_curr_gw->orig_node->orig_str, max_gw_class, best_wa_val / PROBE_TO100, max_gw_factor);
    }

    curr_gateway = tmp_curr_gw;

    update_community_route();

    trigger_tun_update();
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
    dbg_printf(cn, " %12s     %15s   #   Community      preferred gateway: %s \n", "Originator", "bestNextHop", ipStr(pref_gateway));

    OLForEach(gw_node, struct gw_node, gw_list)
    {
      struct orig_node *on = gw_node->orig_node;
      struct ext_packet *gw_ext = on->gw_ext;

      if (!gw_ext || on->router == NULL)
        continue;

      get_gw_speeds(gw_ext->EXT_GW_FIELD_GWFLAGS, &download_speed, &upload_speed);

      dbg_printf(cn, "%s %-15s %15s %3i, %i, %i%s/%i%s\n",
                 (
                 curr_gateway == gw_node) ? "=>" : "  ",
                 ipStr(on->orig), ipStr(on->router->key.addr),
                 gw_node->orig_node->router->longtm_sqr.wa_val / PROBE_TO100,
                 gw_ext->EXT_GW_FIELD_GWTYPES & COMMUNITY_GATEWAY ? 1 : 0,
                 download_speed > 2048 ? download_speed / 1024 : download_speed,
                 download_speed > 2048 ? "MBit" : "KBit",
                 upload_speed > 2048 ? upload_speed / 1024 : upload_speed,
                 upload_speed > 2048 ? "MBit" : "KBit"
                );

      batman_count++;
    }

    if (batman_count == 0)
      dbg(DBGL_GATEWAYS, DBGT_NONE, "No gateways in range...");

    dbg_printf(cn, "\n");
  }

  return SUCCESS;
}

static int32_t opt_rt_class(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
  if (cmd == OPT_APPLY)
  {
    // delete wg class
    if ( Gateway_class  && routing_class )
    {
      check_apply_parent_option(DEL, OPT_APPLY, _save, get_option(0, 0, ARG_GW_CLASS), 0, cn);
    }
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

      // trigger new gw selection
      curr_gateway = NULL;

      /* use routing class 3 if none specified */
      /*
      if ( pref_gateway && !routing_class && !Gateway_class )
        check_apply_parent_option( ADD, OPT_APPLY, _save, get_option(0,0,ARG_RT_CLASS), "3", cn );
*/
    }
  }

  return SUCCESS;
}

static int32_t opt_only_commuity_gw(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
  if (cmd == OPT_APPLY)
  {
    // trigger new gw selection
    curr_gateway = NULL;
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

      // delete routing class
      if ( gateway_class &&  routing_class )
      {
        check_apply_parent_option(DEL, OPT_APPLY, _save, get_option(0, 0, ARG_RT_CLASS), 0, cn);
      }

      dbg(DBGL_SYS, DBGT_INFO, "gateway class: %i -> propagating: %s", gateway_class, gwarg);

      // trigger new gw selection (scripts are not called when node is gateway)
      curr_gateway = NULL;

      // trigger tunnel changes; causes to call the bmx script correcly
      trigger_tun_update();

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

    {ODI, 5, 0, ARG_ONLY_COMMUNITY_GW, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &onlyCommunityGateway, MIN_ONLY_COMMUNITY_GW, MAX_ONLY_COMMUNITY_GW, DEF_ONLY_COMMUNITY_GW, opt_only_commuity_gw,
     ARG_VALUE_FORM, "only select community gateways"},

    {ODI, 5, 0, ARG_GW_CLASS, 'g', A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, 0, 0, 0, 0, opt_gw_class,
     ARG_VALUE_FORM "[/VAL]", "set GW up- & down-link class (e.g. 5mbit/1024kbit)"},

    {ODI, 5, 0, ARG_GATEWAYS, 0, A_PS0, A_USR, A_DYN, A_ARG, A_END, 0, 0, 0, 0, opt_gateways, 0,
     "show currently available gateways\n"}};

void tun_cleanup(void)
{
  set_snd_ext_hook(EXT_TYPE_64B_GW, cb_send_my_tun_ext, DEL);

//if(_bmxdMode != BmxdMode_None) dbg(DBGL_SYS, DBGT_INFO, "tun_cleanup()");
    switch(_bmxdMode)
    {
      case BmxdMode_Client: gwc_cleanup(1); break; //sehe zeile 1275 fuer gleichen kommentar
      case BmxdMode_Gateway: gws_cleanup(); break;
      default: break;
    }
}

void init_tunnel(void)
{
  OLInitializeListHead(&gw_list);

  register_options_array(tunnel_options, sizeof(tunnel_options));

  set_snd_ext_hook(EXT_TYPE_64B_GW, cb_send_my_tun_ext, ADD);

  register_task(1000, cb_choose_gw, NULL);

  trigger_tun_update();

}


//SE: create default route to the next hop that also the gateway is using.
// if all routers have this default route, the packets that are not found in sub-community are traveling
// to the gateway. This then is responsible to forward it via (e.g.: BGP) to other sub-community and
// return it back to origin node (initially sent the request)
// NOTE: I have to check for prefix/netmask. if user did not pass in this
// then no route will be added.
// The community route should only forward community pakets of the complete 10.200.er network..
// Later when ICVPN is used for other communiiies, bmxd or routing rules
// must be extended

static uint32_t community_via_addr = 0;
static int32_t community_via_dev_idx = -1;
void update_community_route(void)
{
  if(		gNetworkPrefix && gNetworkNetmask
    && 	curr_gateway && curr_gateway->orig_node && curr_gateway->orig_node->router
    )
  {
        if(  community_via_addr != curr_gateway->orig_node->router->key.addr
          || community_via_dev_idx != curr_gateway->orig_node->router->key.iif->if_index)
        {
          // remove previous route
          if(community_via_addr)
          {
            add_del_route(gNetworkPrefix, (int16_t)gNetworkNetmask,
                      community_via_addr, primary_addr,
                      community_via_dev_idx, "",
                      RT_TABLE_HOSTS, RTN_UNICAST, DEL, TRACK_OTHER_HOST);
          }

          community_via_addr = curr_gateway->orig_node->router->key.addr;
          community_via_dev_idx = curr_gateway->orig_node->router->key.iif
                                ? curr_gateway->orig_node->router->key.iif->if_index : 0;


          add_del_route(gNetworkPrefix, (int16_t)gNetworkNetmask,
                    community_via_addr, primary_addr,
                    community_via_dev_idx, "",
                    RT_TABLE_HOSTS, RTN_UNICAST, ADD, TRACK_OTHER_HOST);
        }
    }

}
