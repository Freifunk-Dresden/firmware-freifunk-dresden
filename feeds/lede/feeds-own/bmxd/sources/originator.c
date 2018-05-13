/* Copyright (C) 2006 B.A.T.M.A.N. contributors:
 * Simon Wunderlich, Marek Lindner, Axel Neumann
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
#include <arpa/inet.h>
#include <linux/if.h>     /* ifr_if, ifr_tun */
#include <linux/rtnetlink.h>

#include "batman.h"
#include "os.h"
#include "metrics.h"
#include "originator.h"
#include "plugin.h"
#include "schedule.h"
//#include "avl.h"

static int32_t my_seqno;


int32_t my_pws = DEF_PWS;

int32_t local_lws = DEF_LWS;

int32_t local_rtq_lounge = DEF_RTQ_LOUNGE;

int32_t my_path_lounge = DEF_PATH_LOUNGE;

static int32_t my_path_hystere = DEF_PATH_HYST;

static int32_t my_rcnt_hystere = DEF_RCNT_HYST;

static int32_t my_rcnt_pws = DEF_RCNT_PWS;

/*
static int32_t my_rcnt_lounge = DEF_RCNT_LOUNGE;
*/

static int32_t my_rcnt_fk = DEF_RCNT_FK;

static int32_t my_late_penalty = DEF_LATE_PENAL;

static int32_t drop_2hop_loop = DEF_DROP_2HLOOP;

static int32_t purge_to = DEF_PURGE_TO;

int32_t dad_to = DEF_DAD_TO;

static int32_t Asocial_device = DEF_ASOCIAL;

int32_t Ttl = DEF_TTL;

int32_t wl_clones = DEF_WL_CLONES;

static int32_t my_asym_weight = DEF_ASYM_WEIGHT;

static int32_t my_hop_penalty = DEF_HOP_PENALTY;

static int32_t my_asym_exp = DEF_ASYM_EXP;


static SIMPEL_LIST( pifnb_list );
SIMPEL_LIST( link_list );
//struct avl_tree link_avl = {sizeof( uint32_t), NULL};
AVL_TREE( link_avl, sizeof( uint32_t) );

struct batman_if *primary_if = NULL;
uint32_t primary_addr = 0;

//struct avl_tree orig_avl = {sizeof( uint32_t), NULL};
AVL_TREE( orig_avl, sizeof( uint32_t) );

SIMPEL_LIST( if_list );





static void update_routes( struct orig_node *orig_node, struct neigh_node *new_router ) {
	
	prof_start( PROF_update_routes );
	static char old_nh_str[ADDR_STR_LEN], new_nh_str[ADDR_STR_LEN];
	
	dbgf_all( DBGT_INFO, " " );
	
	addr_to_str( (new_router        ? new_router->nnkey_addr :        0 ), new_nh_str );
	addr_to_str( (orig_node->router ? orig_node->router->nnkey_addr : 0 ), old_nh_str );
	
	/* update routing table and check for changed hna announcements */
	if ( orig_node->router != new_router )
        dbgf_all( DBGT_INFO, "change route to %-15s via %-15s %s %3d / %3d (prev. via %-15s %s %3d)",
		     orig_node->orig_str, 
		     new_nh_str, 
		     (new_router ? new_router->nnkey_iif->dev : "--"),
		     (new_router ? new_router->longtm_sqr.wa_val : 0),
		     orig_node->pws, 
		     old_nh_str, 
		     (orig_node->router ? orig_node->router->nnkey_iif->dev : "--"),
		     (orig_node->router ? orig_node->router->longtm_sqr.wa_val : 0) );
	
	
	if (  orig_node->router != new_router  ) {
		
		if ( new_router ) {
			dbgf_all( DBGT_INFO, "Route to %s via %s", orig_node->orig_str, new_nh_str );
		}
		
		/* route altered or deleted */
		if ( orig_node->router ) {
			
			add_del_route( 	orig_node->orig, 32, orig_node->router->nnkey_addr, 0,
			               	orig_node->router->nnkey_iif->if_index,
			               	orig_node->router->nnkey_iif->dev,
			               	RT_TABLE_HOSTS, RTN_UNICAST, DEL, TRACK_OTHER_HOST );
			
		}
		
		/* route altered or new route added */
		if ( new_router ) {
			
			orig_node->rt_changes++;
			
			add_del_route( orig_node->orig, 32, new_router->nnkey_addr, primary_addr,
			               new_router->nnkey_iif->if_index,
			               new_router->nnkey_iif->dev,
			               RT_TABLE_HOSTS, RTN_UNICAST, ADD, TRACK_OTHER_HOST );
			
		}
		
		orig_node->router = new_router;
		
	}
	
	prof_stop( PROF_update_routes );
	
}

static void flush_orig( struct orig_node *orig_node, struct batman_if *bif ) {
	struct list_head *neigh_pos /*, *neigh_temp, *neigh_prev */;
	struct neigh_node *neigh_node = NULL;
	
	dbgf_all( DBGT_INFO, "%s", ipStr( orig_node->orig ) );
	
	list_for_each( neigh_pos, &orig_node->neigh_list ) {

		neigh_node = list_entry( neigh_pos, struct neigh_node, list );
		
		if ( !bif  ||  bif == neigh_node->nnkey_iif ) {
			flush_sq_record( &neigh_node->longtm_sqr );
			flush_sq_record( &neigh_node->recent_sqr );
                }
	}

	
	if ( !bif  ||  ( orig_node->router  &&  orig_node->router->nnkey_iif == bif ) ) {
		
		update_routes( orig_node, NULL );
	
		cb_plugin_hooks( orig_node, PLUGIN_CB_ORIG_FLUSH );
	}

/*
 * plugins must be called with PLUGIN_CB_ORIG_FLUSH and PLUGIN_CB_ORIG_DESRTROY
 * before orig_node->router can be destroyed:
 *
        neigh_prev = (struct list_head *) & orig_node->neigh_list;
        // for all neighbours towards this originator ...

        list_for_each_safe(neigh_pos, neigh_temp, &orig_node->neigh_list) {

                neigh_node = list_entry(neigh_pos, struct neigh_node, list);

                if (!bif || (neigh_node->iif == bif)) {

                        list_del(neigh_prev, neigh_pos, &orig_node->neigh_list);

                        debugFree(neigh_node, 1403);

                } else {
                        neigh_prev = &neigh_node->list;
                }
        }
*/


}


static
struct neigh_node *init_neigh_node( struct orig_node *orig_node, uint32_t neigh, struct batman_if *iif, uint16_t seqno, batman_time_t last_aware )
{
	dbgf_all( DBGT_INFO, " " );

	struct neigh_node *neigh_node = debugMalloc( sizeof (struct neigh_node), 403 );
	memset( neigh_node, 0, sizeof(struct neigh_node) );
	INIT_LIST_HEAD( &neigh_node->list );

	neigh_node->nnkey_addr = neigh;
	neigh_node->nnkey_iif = iif;
	neigh_node->last_aware = last_aware;
	
	list_add_tail( &neigh_node->list, &orig_node->neigh_list );
        avl_insert(&orig_node->neigh_avl, neigh_node );
	return neigh_node;

}

static
struct neigh_node *update_orig(struct orig_node *on, uint16_t *oCtx, struct msg_buff *mb)
{
	prof_start( PROF_update_originator );
	
	struct list_head *neigh_pos;
	struct neigh_node *incm_rt = NULL, *tmp_neigh = NULL;
	struct neigh_node *curr_rt = on->router;
        struct neigh_node *old_rt;
	struct bat_packet_ogm *ogm = mb->bp.ogm;

        old_rt = curr_rt;
        uint32_t max_othr_longtm_val = 0;
	uint32_t max_othr_recent_val = 0;

	dbgf_all( DBGT_INFO, "%s", on->orig_str );

	/* only used for debugging purposes */
        if (!on->first_valid_sec)
                on->first_valid_sec = batman_time_sec;
	
	// find incoming_neighbor and purge outdated SQNs of alternative next hops
	list_for_each( neigh_pos, &on->neigh_list ) {

		uint8_t probe = 0;

		tmp_neigh = list_entry( neigh_pos, struct neigh_node, list );

		if ( ( tmp_neigh->nnkey_addr == mb->neigh ) && ( tmp_neigh->nnkey_iif == mb->iif ) ) {

			incm_rt = tmp_neigh;

                        if (*oCtx & IS_ACCEPTED) {

                                if (*oCtx & IS_NEW)
                                        probe = PROBE_RANGE;
                                else
                                        probe = PROBE_RANGE - (my_late_penalty * PROBE_TO100);
                        }
                }

                update_lounged_metric(probe, my_path_lounge, ogm->ogm_seqno, on->last_valid_sqn, &tmp_neigh->longtm_sqr,
                        on->pws);

                if ( incm_rt != tmp_neigh)
                        max_othr_longtm_val = MAX(max_othr_longtm_val, tmp_neigh->longtm_sqr.wa_val);



                if ( my_rcnt_fk == MAX_RCNT_FK )
                        continue;

                //if (*oCtx & IS_NEW || (((SQ_TYPE) (on->last_valid_sqn - ogm->ogm_seqno)) <= my_rcnt_lounge))

                update_lounged_metric(probe, my_path_lounge, ogm->ogm_seqno, on->last_valid_sqn, &tmp_neigh->recent_sqr,
                        my_rcnt_pws);
                

                if ( incm_rt != tmp_neigh )
                        max_othr_recent_val = MAX(max_othr_recent_val, tmp_neigh->recent_sqr.wa_val);

        }



        paranoia( -500001, !incm_rt );

        /*
         * The following if-else-else branch implements my currently best known heuristic
         * Its tuned for fast path convergence as well as long-term path-quality awareness.
         * In the future this should be configurable by each node participating in the mesh.
         * Its Fuzzy! The following path-quality characteristics are judged:
         * - Recent vers. Longterm  path quality
         * - eXtreme vers. Conservative  distinction to alternative paths
         * - Best  vers. Worst  path quality
         * allowing combinations like:
         *   Recent_Conservative_Best (RCB)  --  Recent_eXtreme_Best (RXB)  --  Longterm_Conservative_Best (LCB)
         * The  general idea is to keep/change the path (best neighbor) if:
         *   -  change: (RXB (implying RCB)) || (RCB && LCB)
         *   -  keep:  RXB || RCB || LCB
         *   -  not-yet-rebroadcasted (not-yet-finally-decided based on) this or newer seqno
         *    - incoming packet has been received via incoming_neighbor which is better than all other router
         *    - curr_router == incoming_neighbor is really the best neighbor towards our destination
         * */
        int8_t RXB = 0, RCB = 0, LCB = 0, changed = 0;

//wenn ogm ueber eine andere route (ip) kommt, oder das erstemal kommt
        if ( ( curr_rt != incm_rt ) &&
             ( ((SQ_TYPE)( on->last_decided_sqn - ogm->ogm_seqno ) >= on->pws ) )  &&

             ( ( ( my_rcnt_fk == MAX_RCNT_FK ) &&
                 ( (   LCB = ((int)incm_rt->longtm_sqr.wa_val >  (int)(max_othr_longtm_val)                    + (my_path_hystere * PROBE_TO100)) ) )

               ) || (

                 ( my_rcnt_fk != MAX_RCNT_FK ) &&

                 ( ( ( LCB = ((int)incm_rt->longtm_sqr.wa_val >  (int)(max_othr_longtm_val)                    + (my_path_hystere * PROBE_TO100)) ) &&
                     ( RCB = ((int)incm_rt->recent_sqr.wa_val >  (int)(max_othr_recent_val)                                                     ) ) )
                   ||
                   (   RXB = ((int)incm_rt->recent_sqr.wa_val >  (int)((max_othr_recent_val * my_rcnt_fk)/100) + (my_rcnt_hystere * PROBE_TO100)) )

                 )
               )
             )
           ) {

                curr_rt = incm_rt;
                on->last_decided_sqn = ogm->ogm_seqno;
                *oCtx |= IS_BEST_NEIGH_AND_NOT_BROADCASTED;
                changed = YES;
		dbgf_all( DBGT_INFO, "%s, (1) IS_BEST_NEIGH_AND_NOT_BROADCASTED, ogm_seqno=%d, RXB=%d, RCB=%d, LCB=%d, last_decided_sqn=%d, my_rcnt_fk=%d", on->orig_str, ogm->ogm_seqno,RXB,RCB,LCB, on->last_decided_sqn,my_rcnt_fk );
//wenn ogm ueber gleiche route (ip) kommt. 
        } else if
           ( ( curr_rt == incm_rt ) &&
             ( ((SQ_TYPE)( on->last_decided_sqn - ogm->ogm_seqno ) >= on->pws ) )  &&

             ( ( ( my_rcnt_fk == MAX_RCNT_FK ) &&
                 ( (   LCB = ((int)incm_rt->longtm_sqr.wa_val >= (int)(max_othr_longtm_val)                    - (my_path_hystere * PROBE_TO100)) ) )

               ) || (

                 ( my_rcnt_fk != MAX_RCNT_FK ) &&

                 ( ( ( LCB = ((int)incm_rt->longtm_sqr.wa_val >= (int)(max_othr_longtm_val)                    - (my_path_hystere * PROBE_TO100)) ) ||
                     ( RCB = ((int)incm_rt->recent_sqr.wa_val >= (int)(max_othr_recent_val)                                                     ) ) )
                 )
               )
             )
           ) {

                on->last_decided_sqn = ogm->ogm_seqno;
                *oCtx |= IS_BEST_NEIGH_AND_NOT_BROADCASTED;
		dbgf_all( DBGT_INFO, "%s, (1) IS_BEST_NEIGH_AND_NOT_BROADCASTED, ogm_seqno=%d, RXB=%d, RCB=%d, LCB=%d, last_decided_sqn=%d, my_rcnt_fk=%d", on->orig_str, ogm->ogm_seqno,RXB,RCB,LCB, on->last_decided_sqn,my_rcnt_fk );

        }

        if ( changed && !LCB ) {

                dbgf(DBGL_CHANGES, DBGT_INFO,
                        "%s path to %-15s via %-15s (old %-15s incm %-15s) due to %s %s %s PH: "
                        "recent incm %3d  othr %3d  fk %-4d  "
                        "longtm incm %3d  othr %3d",
                        changed ? "NEW" : "OLD",
                        on->orig_str,
                        curr_rt ? ipStr(curr_rt->nnkey_addr) : "----",
                        old_rt ? ipStr(old_rt->nnkey_addr) : "----",
                        ipStr(incm_rt->nnkey_addr),
                        LCB ? " LCB" : "!LCB",
                        RCB ? " RCB" : "!RCB",
                        RXB ? " RXB" : "!RXB",
                        incm_rt->recent_sqr.wa_val / PROBE_TO100,
                        max_othr_recent_val, my_rcnt_fk,
                        incm_rt->longtm_sqr.wa_val / PROBE_TO100,
                        max_othr_longtm_val
                        );
        }

        if ( curr_rt != incm_rt ) {

		// only evaluate and change recorded attributes and route if arrived via best neighbor
		prof_stop( PROF_update_originator );
		return curr_rt;
	}


	on->last_path_ttl = ogm->ogm_ttl;
	
	on->ogx_flag = ogm->ogx_flag;
	
	on->ogm_misc = ogm->ogm_misc;
	
	
	if ( on->pws != ogm->ogm_pws ) {
	
		dbg( DBGL_SYS, DBGT_INFO, 
		     "window size of OG %s changed from %d to %d, flushing packets and route!",
		     on->orig_str, on->pws, ogm->ogm_pws );
	
		on->pws = ogm->ogm_pws;
		flush_orig( on, NULL );
		prof_stop( PROF_update_originator );
		return NULL;
	}
	
	prof_stop( PROF_update_originator );
	return curr_rt;
}



static
void free_pifnb_node( struct orig_node *orig_node ) {
	struct pifnb_node *pn;
	struct list_head *pifnb_pos, *pifnb_pos_tmp, *prev_list_head;
	
	paranoia( -500013, ( !orig_node->id4him ) ); //free_pifnb_node(): requested to free pifnb_node with id4him of zero
	
	prev_list_head = (struct list_head *)&pifnb_list;

	list_for_each_safe( pifnb_pos, pifnb_pos_tmp, &pifnb_list ) {

		pn = list_entry(pifnb_pos, struct pifnb_node, list);

		if ( pn->pog == orig_node ) {
			
			list_del( prev_list_head, pifnb_pos, &pifnb_list );
			
			orig_node->id4him = 0;
			
			debugFree( pn, 1429 );

			break;

		} else {

			prev_list_head = &pn->list;

		}
	}
	
	paranoia( -500012, ( orig_node->id4him != 0 )); //free_pifnb_node(): requested to free non-existent pifnb_node
	
	
}


static
int8_t init_pifnb_node( struct orig_node *orig_node ) {
	struct pifnb_node *pn_tmp = NULL;
	struct list_head *list_pos, *prev_list_head;
	uint16_t id4him = 1;
	
	paranoia( -500011, ( orig_node->id4him != 0 ) );//init_pifnb_node(): requested to init already existing pifnb_node
	
        dbgf_all( DBGT_INFO, " %16s ", orig_node->orig_str);
	
	prev_list_head = (struct list_head *)&pifnb_list;

	list_for_each( list_pos, &pifnb_list ) {

		pn_tmp = list_entry( list_pos, struct pifnb_node, list );

		if ( pn_tmp->pog->id4him > id4him )
			break;
		
		id4him++;
		
		if ( id4him >= MAX_ID4HIM ) {
			dbgf( DBGL_SYS, DBGT_ERR, "Max numbers of pifnb_nodes reached!");
			return FAILURE;
		}
		
		prev_list_head = &pn_tmp->list;
		
		pn_tmp = NULL;
	}
	
	struct pifnb_node *pn = debugMalloc( sizeof(struct pifnb_node), 429 );
	memset( pn, 0, sizeof(struct pifnb_node) );
	INIT_LIST_HEAD( &pn->list );
	pn->pog = orig_node;
	orig_node->id4him = id4him;

        dbgf_all( DBGT_INFO, "%16s -> id4him %d", orig_node->orig_str, id4him);
	
	if ( pn_tmp )
		list_add_before( prev_list_head, list_pos, &pn->list );
		
	else if ( ( pn_tmp == NULL ) || ( pn_tmp->pog->id4him <= orig_node->id4him ) )
		list_add_tail( &pn->list, &pifnb_list );

	return SUCCESS;
}



static
void free_link_node( struct orig_node *orig_node, struct batman_if *bif ) {
	
	struct link_node *ln;
	struct list_head *list_pos, *list_tmp, *list_prev;
	
	dbgf_all( DBGT_INFO, "of orig %s", orig_node->orig_str);
	
	
	paranoia( -500010, ( orig_node->link_node == NULL ) ); //free_link_node(): requested to free non-existing link_node
	
	
	ln = orig_node->link_node;
	
	list_prev = (struct list_head *)&ln->lndev_list;
	
	list_for_each_safe( list_pos, list_tmp, &ln->lndev_list ) {
		
		struct link_node_dev *lndev = list_entry( list_pos, struct link_node_dev, list );
		
		if ( !bif  ||  lndev->bif == bif ) {
		
			dbgf_all( DBGT_INFO, "purging lndev %16s %10s %s",
			     orig_node->orig_str, lndev->bif->dev, lndev->bif->if_ip_str );
		
			list_del( list_prev, list_pos, &ln->lndev_list );
			debugFree( list_pos, 1429 );
			
		} else {
			
			list_prev = list_pos;
		}
	}
		
	
	
	list_prev = (struct list_head *)&link_list;
			
	list_for_each_safe( list_pos, list_tmp, &link_list ) {

		ln = list_entry( list_pos, struct link_node, list);

		if ( ln->orig_node == orig_node  &&  list_empty( &ln->lndev_list ) ) {

                        dbgf_all( DBGT_INFO, "purging link_node %16s ", orig_node->orig_str);

			list_del( list_prev, list_pos, &link_list );
                        avl_remove(&link_avl, /*(uint32_t*)*/orig_node->link_node);
			
			debugFree( orig_node->link_node, 1428 );
			
			orig_node->link_node = NULL;
			
			break;

		} else {
			list_prev = list_pos;
		}
	}
}


static
void flush_link_node_seqnos( void ) {
	struct list_head *ln_pos, *lndev_pos, *lndev_tmp;
	struct link_node *ln = NULL;
	
	list_for_each( ln_pos, &link_list ) {

		ln = list_entry( ln_pos, struct link_node, list );
		
		list_for_each_safe( lndev_pos, lndev_tmp, &ln->lndev_list ) {
			
			struct link_node_dev *lndev = list_entry( lndev_pos, struct link_node_dev, list );
			
			dbgf( DBGL_CHANGES, DBGT_INFO, "purging lndev %16s %10s %s",
			     ln->orig_node->orig_str, lndev->bif->dev, lndev->bif->if_ip_str );
			
			list_del( (struct list_head *)&ln->lndev_list, lndev_pos, &ln->lndev_list );
			debugFree( lndev_pos, 1429 );
		}
	}
}

static
void init_link_node( struct orig_node *orig_node ) {
	
	struct link_node *ln;
	
	dbgf_all( DBGT_INFO, "%s", orig_node->orig_str );
	
	ln = orig_node->link_node = debugMalloc( sizeof(struct link_node), 428 );
	memset( ln, 0, sizeof(struct link_node) );
	INIT_LIST_HEAD( &ln->list );
	
	ln->orig_node = orig_node;
        ln->orig_addr = orig_node->orig;
	
	INIT_LIST_HEAD_FIRST( ln->lndev_list );
	
	list_add_tail ( &ln->list, &link_list );
        avl_insert(&link_avl, ln);
}


static
int8_t validate_orig_seqno( struct orig_node *orig_node, uint32_t neigh, SQ_TYPE ogm_seqno ) {
	
	// this originator IP is somehow known..(has ever been valid)
	if ( orig_node->last_valid_time  ||  orig_node->last_valid_sqn ) {
		
		if ( (uint16_t)( ogm_seqno + my_path_lounge - orig_node->last_valid_sqn )  >
		     MAX_SEQNO - orig_node->pws ) {
			
			dbg_mute( 25, DBGL_CHANGES, DBGT_WARN,
			          "drop OGM %-15s  via %4s NB %-15s  with old SQN %5i  "
                      "(prev %5i  lounge-margin %2i  pws %3d  lvld %llu) !",
			          orig_node->orig_str, 
			          (orig_node->router && orig_node->router->nnkey_addr == neigh) ? "best" : "altn",
			          ipStr(neigh), 
			          ogm_seqno, 
			          orig_node->last_valid_sqn, 
                      my_path_lounge, orig_node->pws, (unsigned long long)orig_node->last_valid_time );
			
			return FAILURE;
		}


                if (// if seqno is more than 10 times out of dad timeout
                        ((uint16_t) (ogm_seqno + my_path_lounge - orig_node->last_valid_sqn)) >
                        (my_path_lounge +
                        ((1000 * dad_to) / MIN(WAVG(orig_node->ogi_wavg, OGI_WAVG_EXP), MIN_OGI))) &&
                        // but we have received an ogm in less than timeout sec
                        LESS_U32(batman_time, (orig_node->last_valid_time + (1000 * dad_to))))
		{
			
			dbg_mute( 26, DBGL_SYS, DBGT_WARN, 
			          "DAD-alert! %s  via NB %s  with out-of-range SQN %i  lounge-margin %i "
                      "lvld %i  at %llu  dad_to %d  wavg %d  Reinit in %d s",
			          orig_node->orig_str, ipStr(neigh), ogm_seqno, my_path_lounge,
                      orig_node->last_valid_sqn, (unsigned long long)orig_node->last_valid_time,
                                dad_to, WAVG(orig_node->ogi_wavg, OGI_WAVG_EXP),
			          ((orig_node->last_valid_time + (1000 * dad_to)) - batman_time)/1000 );
			
			return FAILURE;
		}
		
	} else { 
		// init orig sqns to reasonable values
//stephan: init values
		orig_node->last_valid_sqn = ogm_seqno;
		orig_node->last_valid_time = batman_time;
	}
	
	return SUCCESS;
}

static void set_primary_orig( struct orig_node *orig_node, uint32_t new_primary_addr ) {
	
	
	if ( orig_node->primary_orig_node  &&  ( !new_primary_addr  ||  orig_node->primary_orig_node->orig != new_primary_addr ) ) {
		
		// remove old:
		if ( orig_node->primary_orig_node != orig_node ) {
			
			orig_node->primary_orig_node->pog_refcnt--;
			paranoia( -500152, orig_node->pog_refcnt < 0 );
		}
		
		orig_node->primary_orig_node = NULL;
	}
	
	if ( new_primary_addr  &&  ( !orig_node->primary_orig_node  ||  orig_node->primary_orig_node->orig != new_primary_addr ) ) {
		
		// add new:
		
		if ( orig_node->orig != new_primary_addr ) {

                        orig_node->primary_orig_node = get_orig_node( new_primary_addr, YES/*create*/ );
			orig_node->primary_orig_node->pog_refcnt++;
			
		} else {
			
			orig_node->primary_orig_node = orig_node;
		}
	
	}
	
}


static
int8_t validate_primary_orig( struct orig_node *orig_node, struct msg_buff *mb, uint16_t oCtx ) {
	
	if ( mb->rcv_ext_len[EXT_TYPE_64B_PIP] ) {
		
		struct ext_packet *pip = mb->rcv_ext_array[EXT_TYPE_64B_PIP];
		
		dbgf_all( DBGT_INFO, "orig %s  neigh %s", mb->orig_str, mb->neigh_str );

		if ( orig_node->primary_orig_node ) {
			
			if ( orig_node->primary_orig_node->orig != pip->EXT_PIP_FIELD_ADDR ) { 
				
				dbg_mute( 45, DBGL_SYS, DBGT_WARN,
				          "neighbor %s changed his primary interface from %s to %s !",
				          orig_node->orig_str, 
				          orig_node->primary_orig_node->orig_str, 
				          ipStr( pip->EXT_PIP_FIELD_ADDR ) );
				
				if ( orig_node->primary_orig_node->id4him )
					free_pifnb_node( orig_node->primary_orig_node );
				
				set_primary_orig( orig_node, pip->EXT_PIP_FIELD_ADDR );
				//orig_node->primary_orig_node = get_orig_node( pip->EXT_PIP_FIELD_ADDR, YES/*create*/ );
				
			}
			
		} else {
		
			set_primary_orig( orig_node, pip->EXT_PIP_FIELD_ADDR );
			//orig_node->primary_orig_node = get_orig_node( pip->EXT_PIP_FIELD_ADDR, YES/*create*/ );
			
		}
		
		if ( pip->EXT_PIP_FIELD_PIPSEQNO  &&  //remain compatible to COMPAT_VERSION 10 
		     validate_orig_seqno( orig_node->primary_orig_node, 0, ntohs( pip->EXT_PIP_FIELD_PIPSEQNO ) ) == FAILURE )
		{
			//orig_node->primary_orig_node = NULL;
			set_primary_orig( orig_node, 0 );
			return FAILURE;
		}
		
		
	} else {
		
		if ( orig_node->primary_orig_node ) { 
			
			if ( orig_node->primary_orig_node != orig_node ) { 
				
				dbg_mute( 30, DBGL_SYS, DBGT_WARN, 
				          "neighbor %s changed primary interface from %s to %s !",
				          orig_node->orig_str, 
				          orig_node->primary_orig_node->orig_str,
				          orig_node->orig_str );
				
				if ( orig_node->primary_orig_node->id4him )
					free_pifnb_node( orig_node->primary_orig_node );
				
				//orig_node->primary_orig_node = orig_node;
				set_primary_orig( orig_node, orig_node->orig );
			
			}
		
		} else {
			
			//orig_node->primary_orig_node = orig_node;
			set_primary_orig( orig_node, orig_node->orig );
		
		}
		
	}
	
	orig_node->primary_orig_node->last_aware = batman_time;
	
	
	if ( (oCtx & IS_DIRECT_NEIGH)  &&  !(orig_node->primary_orig_node->id4him) )
		return init_pifnb_node( orig_node->primary_orig_node );
	
	
	return SUCCESS;
}

static
void update_rtq_link(struct orig_node *orig_node_neigh, uint16_t oCtx, struct msg_buff *mb,
        struct batman_if *iif, struct bat_packet_ogm *ogm, struct link_node_dev *lndev)
{

        dbgf_all(DBGT_INFO,
                "received own OGM via NB, lastTxIfSeqno: %d, currRxSeqno: %d  oCtx: 0x%X "
                "link_node %s primary_orig %s",
                (iif->if_seqno - OUT_SEQNO_OFFSET), ogm->ogm_seqno, oCtx,
                (orig_node_neigh->link_node ? "exist" : "NOT exists"),
                (orig_node_neigh->primary_orig_node ? "exist" : "NOT exists"));

        if (!(oCtx & HAS_DIRECTLINK_FLAG) || (oCtx & HAS_CLONED_FLAG) || iif->if_addr != ogm->orig)
                return;

// bugfix (stephan): correct seqno for this interface. the error occours when an interface
// was added after starting bmxd but only sometimes, probably when there is much delay
// in receiving OGMs. in firmware I add all tbb interfaces. so this should not happen.
if ((iif->if_seqno - OUT_SEQNO_OFFSET) < ogm->ogm_seqno)
{
    dbgf_all(DBGT_ERR,
        		"###  if %s, lastTxIfSeqno: %d, currRxSeqno: %d - correct interface seqno",
			 iif->dev, (iif->if_seqno - OUT_SEQNO_OFFSET), ogm->ogm_seqno);
 	iif->if_seqno = ogm->ogm_seqno + OUT_SEQNO_OFFSET;
}

        if (((SQ_TYPE) ((iif->if_seqno - OUT_SEQNO_OFFSET) - ogm->ogm_seqno)) >  local_rtq_lounge ) {

                dbg_mute(51, DBGL_CHANGES, DBGT_WARN,
                        "late reception of own OGM via NB %s  lastTxIfSqn %d  rcvdSqn %d  margin %d ! "
                        "Try configureing a greater --%s value .",
                        mb->neigh_str, (iif->if_seqno - OUT_SEQNO_OFFSET),
                        ogm->ogm_seqno, local_rtq_lounge, ARG_RTQ_LOUNGE);

                return;
        }

        /* neighbour has to indicate direct link and it has to come via the corresponding interface */
        /* if received seqno equals last send seqno save new seqno for bidirectional check */
        if (orig_node_neigh->link_node && orig_node_neigh->primary_orig_node && lndev) {

                update_lounged_metric(PROBE_RANGE, local_rtq_lounge, ogm->ogm_seqno, (iif->if_seqno - OUT_SEQNO_OFFSET),
                        &lndev->rtq_sqr, local_lws);


                if (orig_node_neigh->primary_orig_node->id4me != ogm->prev_hop_id) {

                        if (orig_node_neigh->primary_orig_node->id4me != 0)
                                dbg_mute(53, DBGL_CHANGES, DBGT_WARN,
                                "received changed prev_hop_id from neighbor %s !!!",
                                mb->neigh_str);

                        orig_node_neigh->primary_orig_node->id4me = ogm->prev_hop_id;
                }

                dbgf_all(DBGT_INFO, "indicating bidirectional link");

        }
}


static
void update_rq_link( struct orig_node *orig_node, SQ_TYPE sqn, struct batman_if *iif, uint16_t oCtx ) {

	if ( !( (oCtx & IS_DIRECT_NEIGH)  ||  orig_node->link_node ) )
		return;
	
	
	if ( oCtx & IS_DIRECT_NEIGH ) {

		orig_node->primary_orig_node->last_pog_link = batman_time;

		if ( !orig_node->link_node )
			init_link_node( orig_node );
	}
	
	
	dbgf_all( DBGT_INFO, "OG %s  SQN %d  IF %s  ctx %x  ln %s  cloned %s  direct %s", 
	          orig_node->orig_str, sqn, iif->dev, oCtx, 
	          orig_node->link_node ? "YES":"NO", 
	          (oCtx & HAS_CLONED_FLAG) ? "YES":"NO",
	          (oCtx & IS_DIRECT_NEIGH) ? "YES":"NO" );
	

        // skip updateing link_node if this SQN is known but not new
	if ( ( orig_node->last_valid_time  ||  orig_node->last_valid_sqn )  &&
	     ( (uint16_t)( sqn + RQ_LINK_LOUNGE - orig_node->last_valid_sqn )  >  MAX_SEQNO - local_lws - MAX_PATH_LOUNGE) )
		return;
	
	paranoia( -500156, !orig_node->link_node );
		
	struct list_head *lndev_pos;
	struct link_node_dev *lndev, *this_lndev = NULL;
	
	dbgf_all( DBGT_INFO, "[%10s %3s %3s %3s]", "dev","RTQ","RQ","TQ" );
	
	list_for_each( lndev_pos, &orig_node->link_node->lndev_list ) {
		
		lndev = list_entry( lndev_pos, struct link_node_dev, list );
			
		dbgf_all( DBGT_INFO, "[%10s %3i %3i %3i] before", lndev->bif->dev,
		          (((lndev->rtq_sqr.wa_val))/PROBE_TO100),
		          (((lndev->rq_sqr.wa_val))/PROBE_TO100),
		          (((tq_rate( orig_node, lndev->bif, PROBE_RANGE )))/PROBE_TO100) ); 
		
		if ( lndev->bif == iif ) {
		
			this_lndev = lndev;
		
		} else {
			update_lounged_metric( 0, RQ_LINK_LOUNGE, sqn, orig_node->last_valid_sqn, &lndev->rq_sqr, local_lws );
			
		}
		
	}
	
	if ( !this_lndev  &&  (oCtx & IS_DIRECT_NEIGH) )
		this_lndev = get_lndev( orig_node->link_node, iif, YES/*create*/ );
	
	if ( this_lndev ) {
		
		uint8_t probe = ( (oCtx & IS_DIRECT_NEIGH) &&  !(oCtx & HAS_CLONED_FLAG) ) ? PROBE_RANGE : 0;

                update_lounged_metric(probe, RQ_LINK_LOUNGE, sqn, orig_node->last_valid_sqn, &this_lndev->rq_sqr, local_lws);

                if ( probe)
                        this_lndev->last_lndev = batman_time;
                
	}		
	
	//orig_node->link_node->last_rq_sqn = in_seqno;

	/*
	list_for_each( lndev_pos, &orig_node->link_node->lndev_list ) {
		lndev = list_entry( lndev_pos, struct link_node_dev, list );
		dbgf_all( DBGT_INFO, "[%10s %3i %3i %3i] afterwards", lndev->bif->dev, 
				(((lndev->rtq_sqr.wa_val))/PROBE_TO100), 
				(((lndev->rq_sqr.wa_val))/PROBE_TO100), 
				(((tq_rate( orig_node, lndev->bif, PROBE_RANGE )))/PROBE_TO100)  ); 
	}
	*/
	
	
	return;
}


static
int tq_power( int tq_rate_value, int range ) {
	
	int tq_power_value = range;
	int exp_counter;
	
	for ( exp_counter = 0; exp_counter < my_asym_exp; exp_counter++ )
		tq_power_value = ((tq_power_value * tq_rate_value) / range);
	
	return tq_power_value;
}



static
int8_t validate_considered_order( struct orig_node *orig_node, SQ_TYPE seqno, uint8_t ttl, uint32_t neigh, struct batman_if *iif ) {

        struct neigh_node_key key = {neigh, iif};
        struct avl_node *an = avl_find( &orig_node->neigh_avl, &key );
        struct neigh_node *nn = an ? (struct neigh_node*) an->key : NULL;

        if (nn) {

                paranoia( -500198, (nn->nnkey_addr != neigh || nn->nnkey_iif != iif ) );

                nn->last_aware = batman_time;

                if (seqno == nn->last_considered_seqno /* && ttl <= nn->last_considered_ttl */) {

                        return FAILURE;

                } else if (((SQ_TYPE) (seqno - nn->last_considered_seqno)) > MAX_SEQNO - my_pws) {

                        dbgf_ext(DBGT_WARN,
                                "rcvd illegal SQN %d order from %s via %s %s (last considered sqn %d",
                                seqno, orig_node->orig_str, ipStr(neigh), iif->dev,
                                nn->last_considered_seqno);

                        return FAILURE;
                }

                nn->last_considered_seqno = seqno;
		nn->last_considered_ttl = ttl;
                return SUCCESS;
        }
	
	nn = init_neigh_node( orig_node, neigh, iif, seqno, batman_time );
	
	nn->last_considered_seqno = seqno;
	nn->last_considered_ttl = ttl;
	return SUCCESS;
}

/* this function finds and may create an originator entry for the given address */
struct orig_node *get_orig_node( uint32_t addr, uint8_t create ) {
	
	prof_start( PROF_get_orig_node );
        struct avl_node *an = avl_find( &orig_avl, &addr);

        struct orig_node *orig_node = an ? (struct orig_node *) an->key : NULL;

	if ( !create ) {
		prof_stop( PROF_get_orig_node );
		return orig_node;
	}
	
	if ( orig_node ) {
		orig_node->last_aware = batman_time;
		prof_stop( PROF_get_orig_node );
		return orig_node;
	}
	
	orig_node = debugMalloc( (sizeof(struct orig_node) + (plugin_data_registries[PLUGIN_DATA_ORIG] * sizeof(void*)) ), 402 );
	memset( orig_node, 0, (sizeof(struct orig_node) + (plugin_data_registries[PLUGIN_DATA_ORIG] * sizeof(void*) ) ) );
	
	INIT_LIST_HEAD_FIRST( orig_node->neigh_list );
        AVL_INIT_TREE( orig_node->neigh_avl, sizeof( struct neigh_node_key ) );

	
	addr_to_str( addr, orig_node->orig_str );
	dbgf_all( DBGT_INFO, "creating new originator: %s with %d plugin_data_registries", 
	          orig_node->orig_str, plugin_data_registries[PLUGIN_DATA_ORIG] );
	
	orig_node->orig = addr;
	orig_node->last_aware = batman_time;
	orig_node->router = NULL;
	orig_node->link_node = NULL;
//	orig_node->path_lounge = my_path_lounge;
        orig_node->pws = my_pws;
//        orig_node->path_hystere = my_path_hystere;
//        orig_node->late_penalty = my_late_penalty;
//        orig_node->hop_penalty = my_hop_penalty;
//        orig_node->asym_weight = my_asym_weight;
//        orig_node->asym_exp = my_asym_exp;
//        orig_node->rcnt_pws = my_rcnt_pws;
//        orig_node->rcnt_lounge = my_rcnt_lounge;
//        orig_node->rcnt_hystere = my_rcnt_hystere;
//        orig_node->rcnt_fk = my_rcnt_fk;


        upd_wavg(&orig_node->ogi_wavg, DEF_OGI, OGI_WAVG_EXP);

        avl_insert( &orig_avl, /*(uint32_t*)*/orig_node);

	cb_plugin_hooks( orig_node, PLUGIN_CB_ORIG_CREATE );
	
	prof_stop( PROF_get_orig_node );
	return orig_node;
	
}

void purge_orig( batman_time_t curr_time, struct batman_if *bif ) {
	
	prof_start( PROF_purge_originator );
	struct list_head *neigh_pos, *neigh_temp, *neigh_prev;
	struct orig_node *orig_node = NULL;
        struct avl_node *an;
	struct neigh_node *neigh_node;
	static char neigh_str[ADDR_STR_LEN];
	
    dbgf_all( DBGT_INFO, "%llu %s", (unsigned long long)curr_time, bif ? bif->dev : "???" );
	
	//checkIntegrity();
	
	/* for all origins... */
        uint32_t orig_ip = 0;

        while ((orig_node = (struct orig_node*) ((an = avl_next(&orig_avl, &orig_ip)) ? an->key : NULL))) {

                orig_ip = orig_node->orig;

                dbgf_all( DBGT_INFO, "%llu %s %s", (unsigned long long)curr_time, bif ? bif->dev : "???", orig_node->orig_str );


		
        if ( !curr_time  ||  bif  ||  LESS_U32( orig_node->last_aware + (1000*((batman_time_t)purge_to)), curr_time ) ) {
                        /* purge outdated originators completely */
			
            dbgf_all( DBGT_INFO, "originator timeout: %s, last_valid %llu, last_aware %llu",
                      orig_node->orig_str, (unsigned long long)orig_node->last_valid_time, (unsigned long long)orig_node->last_aware );
			
			
			flush_orig( orig_node, bif );
			
			
			if ( !bif  &&  ( !curr_time || !orig_node->pog_refcnt ) )
				cb_plugin_hooks( orig_node, PLUGIN_CB_ORIG_DESTROY );
			
			
			neigh_prev = (struct list_head *)&orig_node->neigh_list;
			// for all neighbours towards this originator ...
			list_for_each_safe( neigh_pos, neigh_temp, &orig_node->neigh_list ) {
				
				neigh_node = list_entry( neigh_pos, struct neigh_node, list );
				
				if ( !bif  ||  ( neigh_node->nnkey_iif == bif ) ) {
					
					list_del( neigh_prev, neigh_pos, &orig_node->neigh_list );
                                        avl_remove( &orig_node->neigh_avl, neigh_node );
					
					debugFree( neigh_node, 1403 );
					
				} else {
					neigh_prev = &neigh_node->list;
				}
				
			}
			
			
			/* remove link information of node */
			
			if ( orig_node->link_node )
				free_link_node( orig_node, bif );
			
			
			if ( !bif  &&  ( !curr_time || !orig_node->pog_refcnt ) ) {
				
				
				if ( orig_node->id4him )
					free_pifnb_node( orig_node );
				
				set_primary_orig( orig_node, 0 );
				
                                avl_remove( &orig_avl, /*(uint32_t*)*/orig_node);
				
				debugFree( orig_node, 1402 );
			}
			
		} else {
			
			/* purge selected outdated originator elements */
			
			/* purge outdated links */
			
			if ( orig_node->link_node ) {
				
				uint8_t free_ln = YES;
				
				struct list_head *lndev_pos, *lndev_tmp;
				struct list_head *lndev_prev = (struct list_head*)&orig_node->link_node->lndev_list;
				
				list_for_each_safe( lndev_pos, lndev_tmp, &orig_node->link_node->lndev_list ) {
					
					//uint8_t free_lndev = YES;
					
					struct link_node_dev *lndev = list_entry( lndev_pos, struct link_node_dev, list );
					
					
                    if ( LESS_U32( (lndev->last_lndev + (1000*((batman_time_t)purge_to))), curr_time) ) {
						
						dbgf( DBGL_CHANGES, DBGT_INFO, 
						      "purging lndev %16s %10s %s",
						      orig_node->orig_str, lndev->bif->dev, lndev->bif->if_ip_str );
						list_del( lndev_prev, lndev_pos, &orig_node->link_node->lndev_list );
						debugFree( lndev, 1429 );
						
					} else {
						free_ln = NO;
						lndev_prev = lndev_pos;
						
					}
					
				}
				
				if ( free_ln )
					free_link_node( orig_node, NULL );
				
			}
			
			
			/* purge outdated PrimaryInterFace NeighBor Identifier */
            if ( orig_node->id4him  &&  LESS_U32( (orig_node->last_pog_link + (1000*((batman_time_t)purge_to))), curr_time)  )
				free_pifnb_node( orig_node );
			
			
			/* purge outdated neighbor nodes, except our best-ranking neighbor */
			
			neigh_prev = (struct list_head *)&orig_node->neigh_list;
			
			/* for all neighbours towards this originator ... */
			list_for_each_safe( neigh_pos, neigh_temp, &orig_node->neigh_list ) {
				
				neigh_node = list_entry( neigh_pos, struct neigh_node, list );
				
                if (  LESS_U32( (neigh_node->last_aware + (1000*((batman_time_t)purge_to))), curr_time )  &&
				      orig_node->router != neigh_node  ) 
				{
					
					addr_to_str( neigh_node->nnkey_addr, neigh_str );
					dbgf_all( DBGT_INFO, 
					          "Neighbour timeout: originator %s, neighbour: %s, last_aware %u",
					          orig_node->orig_str, neigh_str, neigh_node->last_aware );
					
					list_del( neigh_prev, neigh_pos, &orig_node->neigh_list );

                                        avl_remove( &orig_node->neigh_avl, neigh_node );
					
					debugFree( neigh_node, 1403 );
					
				} else {
					
					neigh_prev = &neigh_node->list;
					
				}
			}
		}
	}
	
	//checkIntegrity();
	
	prof_stop( PROF_purge_originator );
}


struct link_node_dev *get_lndev( struct link_node *ln, struct batman_if *bif, uint8_t create ) {
	struct list_head *lndev_pos;
	struct link_node_dev *lndev;
	
	list_for_each( lndev_pos, &ln->lndev_list ) {
		
		lndev = list_entry( lndev_pos, struct link_node_dev, list );
		
		if ( lndev->bif == bif )
			return lndev;
		
	}
	
	if ( !create )
		return NULL;
	
	
	lndev = debugMalloc( sizeof( struct link_node_dev ), 429 );
	
	memset( lndev, 0, sizeof( struct link_node_dev ) );
	
	INIT_LIST_HEAD( &lndev->list );
	lndev->bif = bif;
	
	dbgf( DBGL_CHANGES, DBGT_INFO, "creating new lndev %16s %10s %s",
	      ln->orig_node->orig_str, bif->dev, bif->if_ip_str );
	
	
	list_add_tail( &lndev->list, &ln->lndev_list );
	
	return lndev;
	
}

int tq_rate( struct orig_node *orig_node_neigh, struct batman_if *iif, int range ) {
	
	int rtq, rq, tq;
	struct link_node_dev *lndev;
	
	if ( orig_node_neigh->link_node == NULL )
		return 0;
	
	if ( !( lndev = get_lndev( orig_node_neigh->link_node, iif, NO/*create*/ ) ) )
		return 0;
	
	rtq = lndev->rtq_sqr.wa_val;
	
	rq = lndev->rq_sqr.wa_val;
	
	if ( rtq <= 0 || rq <= 0 ) 
		return 0;
	
	tq = ( (range * rtq ) / rq );
	
	return MIN( tq, range );
	
}


void process_ogm( struct msg_buff *mb ) {
	
	prof_start( PROF_process_ogm );
	
	struct list_head *list_pos;
	struct orig_node *orig_node, *orig_node_neigh; 
	struct link_node_dev *lndev = NULL;
	
	struct batman_if *iif = mb->iif;
	uint32_t neigh = mb->neigh;
	struct bat_packet_ogm *ogm = mb->bp.ogm;
	
	uint16_t oCtx = 0;
	
	oCtx |= (Asocial_device) ? IS_ASOCIAL : 0;
	oCtx |= (ogm->flags & UNIDIRECTIONAL_FLAG) ? HAS_UNIDIRECT_FLAG : 0;
	oCtx |= (ogm->flags & DIRECTLINK_FLAG) ? HAS_DIRECTLINK_FLAG : 0;
	oCtx |= (ogm->flags & CLONED_FLAG) ? HAS_CLONED_FLAG : 0;
	oCtx |= (ogm->orig == neigh) ? IS_DIRECT_NEIGH : 0;
	
	
	dbgf_all( DBGT_INFO, "OG %s  via IF %s %s  NB %s  "
	          "SQN %d  TTL %d  V %d  UDF %d  IDF %d  DPF %d, directNB %d, asocial %d(%d)", 
	          ipStr( ogm->orig ), iif->dev, iif->if_ip_str, mb->neigh_str, 
	          ogm->ogm_seqno, ogm->ogm_ttl, COMPAT_VERSION, 
	          (oCtx & HAS_UNIDIRECT_FLAG), (oCtx & HAS_DIRECTLINK_FLAG), 
	          (oCtx & HAS_CLONED_FLAG), (oCtx & IS_DIRECT_NEIGH), (oCtx & IS_ASOCIAL), Asocial_device);
	
	
	if ( ogm->ogm_pws < MIN_PWS  ||  ogm->ogm_pws > MAX_PWS ) {
		
		dbg_mute( 30, DBGL_SYS, DBGT_WARN, "drop OGM: %s unsopported path window size %d !",
				ipStr( ogm->orig ), ogm->ogm_pws );
		goto process_ogm_end;
	}
	
	
	list_for_each( list_pos, &if_list ) {
		
		struct batman_if *bif = list_entry( list_pos, struct batman_if, list );
        //eine ogm, die das interface nicht verlassen hat und gleich hier zurück gespiegelt wird
        //könnte passieren wenn es ein loopback ist.
		if ( neigh == bif->if_addr ) {
			
			dbgf_all( DBGT_INFO, "drop OGM: rcvd my own broadcast via: %s", mb->neigh_str );
			goto process_ogm_end;
			
		}
		
		if ( neigh == bif->if_broad ) {
			
			dbg_mute( 30, DBGL_SYS, DBGT_WARN, "drop OGM: %s ignoring all packets with broadcast source IP",
			          mb->neigh_str );
			goto process_ogm_end;
		}
        //der absender (erfinder der ogm) hat die gleiche ip wie eines meiner interfaces. also
        //ist das meine ogm
		if ( ogm->orig == bif->if_addr ) {
			
			oCtx |=  IS_MY_ORIG;
			break;
		}
		
	}
	
    //unidirect wird nur vom nachbar node gesetzt wenn die ogm, die ich vorher ueber
    //das interface zu diesem nachbar, noch nicht das direct flag gesetzt hat.
    //das wird verwendet, um eine direkte nachbar verbindung zu erkennen.
    //wenn es meine ogm ist und der nachbar hat das uni flag gesetzt, so wird dann
    //in einer nächsten ogm an diesen nachbar über dieses interface das direct flag in dieser bmxd
    //instance (dieser knoten) gesetzt. damit weiss dann dieser nachbar, dass er die ogm
    //weiterleiten darf und er direkt mit mir verbunden ist.
	if ( oCtx & HAS_UNIDIRECT_FLAG && !(oCtx & IS_MY_ORIG) ) {
		dbgf_all( DBGT_INFO, "drop OGM: unidirectional flag and not my OGM" );
		goto process_ogm_end;
	} 
	
    //suche den nachbar, der mir die ogm weitergeleitet hat. wenn nicht in meiner liste
    //dann ist das die erste ogm und es wird ein eintrag in der liste gespeichert.
	orig_node_neigh = get_orig_node( neigh, YES/*create*/ );
	
	
	if ( !(oCtx & IS_DIRECT_NEIGH) && !(orig_node_neigh->last_valid_time) ) {
		dbgf_all( DBGT_INFO, "drop OGM: rcvd via unknown neighbor!" );
		goto process_ogm_end;
	}

        if ((oCtx & HAS_CLONED_FLAG) && !orig_node_neigh->primary_orig_node) {
                dbgf_all(DBGT_INFO, "drop OGM: first contact with neighbor MUST be without cloned flag!");
		goto process_ogm_end;
	}

        if (orig_node_neigh->link_node)
                lndev = get_lndev(orig_node_neigh->link_node, iif, NO/*create*/);

	
	if ( oCtx & IS_MY_ORIG ) {
                update_rtq_link(orig_node_neigh, oCtx, mb, iif, ogm, lndev);
		goto process_ogm_end;
	} 

        if ( ogm->ogm_ttl == 0 ) {
		dbgf_all( DBGT_INFO, "drop OGM: TTL of zero!" );
		goto process_ogm_end;
	}

	
        if ( lndev  &&  lndev->rtq_sqr.wa_val > 0 )
		oCtx |= IS_BIDIRECTIONAL;

	
	// drop packet if sender is not a direct NB and if we have no route towards the rebroadcasting NB
        if (!(oCtx & IS_DIRECT_NEIGH) && !(orig_node_neigh->router)) {
		dbgf_all(DBGT_INFO, "drop OGM: %s via unknown (%s) (non-direct) neighbor!", ipStr(ogm->orig), mb->neigh_str);
                goto process_ogm_end;
        }
	

        if (!(oCtx & IS_DIRECT_NEIGH)) {

                if (!orig_node_neigh->primary_orig_node || !orig_node_neigh->primary_orig_node->id4me) {

                        dbgf_all(DBGT_INFO, "drop OGM: %s via NB %s %s (primary_orig_node 0x%p, id4me=%d, str=%s)!!!!",
                                ipStr(ogm->orig), mb->neigh_str, "with unknown primaryOG", orig_node_neigh->primary_orig_node, 
				orig_node_neigh->primary_orig_node ? orig_node_neigh->primary_orig_node->id4me : 123456, orig_node_neigh->primary_orig_node->orig_str);
                        goto process_ogm_end;
                }

                if (drop_2hop_loop &&
                        orig_node_neigh->primary_orig_node &&
                        orig_node_neigh->primary_orig_node->id4me == ogm->prev_hop_id) {

                        dbgf_all(DBGT_INFO, "drop OGM: %s via NB %s %s !!!!",
                                ipStr(ogm->orig), mb->neigh_str, " via two-hop loop ");
                        goto process_ogm_end;
                }
        }
	
	
	mb->orig_node = orig_node = 
		(oCtx & IS_DIRECT_NEIGH) ? orig_node_neigh : get_orig_node( ogm->orig, YES/*create*/ );


        if (validate_orig_seqno(orig_node, neigh, ogm->ogm_seqno) == FAILURE) {
                dbgf_all( DBGT_WARN, "drop OGM: %15s, via NB %15s, SQN %i\n",
                        ipStr(ogm->orig), mb->neigh_str, ogm->ogm_seqno);
                goto process_ogm_end;
	}
		
	
	if ( validate_primary_orig( orig_node, mb, oCtx ) == FAILURE ) {
		dbg( DBGL_SYS, DBGT_WARN, "drop OGM: primary originator/if conflict!" );
		goto process_ogm_end;
	}
	
	
	if ( validate_considered_order( orig_node, ogm->ogm_seqno, ogm->ogm_ttl, neigh, iif ) == FAILURE ) {
		dbgf_all( DBGT_INFO, "drop OGM: already considered this OGM and SEQNO %d, ttl %d via this link neighbor!", ogm->ogm_seqno, ogm->ogm_ttl );
		goto process_ogm_end;
	}
	
	
	uint16_t rand_100 = rand_num( 100 );
	
	addr_to_str( ogm->orig, mb->orig_str );
		
	if ( ((SQ_TYPE)( orig_node->last_valid_sqn - ogm->ogm_seqno )) >= orig_node->pws ) {
		
		// we've never seen a valid sqn of this size before, therefore:
		// everything which is out of our current path-window is new!
		oCtx |= IS_NEW;

                // estimating average originaotr interval of this node
                if (orig_node->last_valid_time && LESS_U32(orig_node->last_valid_time, batman_time)) {

                        if (((SQ_TYPE) (ogm->ogm_seqno - (orig_node->last_wavg_sqn + 1))) < orig_node->pws) {
                                upd_wavg(&orig_node->ogi_wavg,
                                        ((batman_time - orig_node->last_valid_time) /
                                        (ogm->ogm_seqno - orig_node->last_wavg_sqn)),
                                        OGI_WAVG_EXP);
                        }

                        orig_node->last_wavg_sqn = ogm->ogm_seqno;
                }

		orig_node->last_valid_sqn = ogm->ogm_seqno;
		orig_node->last_valid_time = batman_time;

	} else if ( ((SQ_TYPE)( orig_node->last_valid_sqn - ogm->ogm_seqno )) <= my_path_lounge ) {
		
		// everything else which is still within SQN_ENTRY_QUEUE is acceptable
		oCtx |= IS_ACCEPTABLE;
	}
	
	
        //MUST be after validate_primary_orig()
	update_rq_link( orig_node, ogm->ogm_seqno, iif, oCtx );


	
	int tq_rate_value = tq_rate( orig_node_neigh, iif, PROBE_RANGE );
	
	
	if ( (oCtx & IS_BIDIRECTIONAL)  &&  
	     ((oCtx & IS_NEW) || (oCtx & IS_ACCEPTABLE))  &&
             rand_100  >=  my_hop_penalty  &&
//	     rand_100  <=  (MAX_ASYM_WEIGHT - asym_weight)  +  ( (tq_power(tq_rate_value,PROBE_RANGE)/PROBE_TO100) * 99) / 100    ) 
	     rand_100  <=  (MAX_ASYM_WEIGHT - my_asym_weight)  +  ( (tq_power(tq_rate_value,PROBE_RANGE)/PROBE_TO100) ) )
	{
		
		// finally we only accept OGMs with probability TQ of its incoming link
		// tq_power() returns value between [0..PROBE_RANGE]. return value of PROBE_RANGE means 100% acceptance 
		oCtx |= IS_ACCEPTED;
	}
	
	
	struct neigh_node *old_router = orig_node->router;
	
	struct neigh_node *new_router = update_orig( orig_node, &oCtx, mb );
	
	
	if ( old_router != new_router )
		update_routes( orig_node, new_router );
	
	if ( !new_router || new_router != orig_node->router ) {
		
		dbgf_all( DBGT_INFO, //as long as incoming link is not bidirectional,...
		      "new_rt %s for %s is zero or differs from installed rt %s  "
                        "(old_rt %s  rcvd vi %s %s",
		      ipStr( new_router ? new_router->nnkey_addr : 0 ),
		      orig_node->orig_str,
		      ipStr( orig_node->router ? orig_node->router->nnkey_addr : 0 ),
		      ipStr( old_router ? old_router->nnkey_addr : 0 ), mb->neigh_str, mb->iif->dev );
	}

        // new_router can be zero !!!
        //paranoia( -500195, ( !new_router || new_router != orig_node->router ) );
	
	// check if ogm_hooks would reject new_router
	if ( cb_ogm_hooks( mb, oCtx, old_router ) != CB_OGM_ACCEPT ) {
		
		flush_orig( orig_node, NULL );
		goto process_ogm_end;
	}
	
	
	dbgf_all( DBGT_INFO,
	          "done OGM accepted %s  acceptable %s  bidirectLink %s  new %s  BNTOG %s  asocial %s(%d)  tq %d  "
	          "hop_penalty %d  asym_w %d  acceptSQN %d  rcvdSQN %d  rand100 %d",
	          ( oCtx & IS_ACCEPTED   ? "Y" : "N" ), 
	          ( oCtx & IS_ACCEPTABLE ? "Y" : "N" ), 
	          ( oCtx & IS_BIDIRECTIONAL ? "Y" : "N" ), 
	          ( oCtx & IS_NEW ? "Y" : "N" ), 
	          ( oCtx & IS_BEST_NEIGH_AND_NOT_BROADCASTED ? "Y" : "N" ), 
	          ( oCtx & IS_ASOCIAL ? "Y" : "N" ), Asocial_device,
	          tq_rate_value, my_hop_penalty, my_asym_weight, orig_node->last_accepted_sqn, ogm->ogm_seqno, rand_100 );
	
	
	// either it IS_DIRECT_NEIGH, then validate_primary_orig() with orig_node=orig_neigh_node has been called
	//or NOT IS_DIRECT_NEIGH, then if orig_node_neigh->primary_orig_node == NULL it has been dropped
	paranoia( -500014, ( !orig_node_neigh->primary_orig_node ) );
	
	//paranoia( -5000151, (!orig_node_neigh->primary_orig_node->id4him) );	
	if ( !orig_node_neigh->primary_orig_node->id4him ) {

                dbgf( DBGL_SYS, DBGT_WARN, "invalid id4him for orig %s via %s",
                        orig_node->orig_str, mb->neigh_str );

		goto process_ogm_end;
	}
	
	schedule_rcvd_ogm( oCtx, orig_node_neigh->primary_orig_node->id4him, mb );
	
process_ogm_end:
	
	prof_stop( PROF_process_ogm );
	
	return;
}




static
int32_t opt_show_origs ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	struct orig_node *orig_node;
        struct avl_node *an;
	uint16_t batman_count = 0;
	
    int rq, tq, rtq;
	
	if ( cmd == OPT_APPLY ) {
		
		if ( !strcmp( opt->long_name, ARG_ORIGINATORS ) ) {
			
			int nodes_count = 0, sum_packet_count = 0, sum_recent_count = 0;
			int sum_lvld = 0, sum_last_pws = 0, sum_ogi_avg = 0;
			int sum_reserved_something = 0, sum_route_changes = 0, sum_hops = 0;
			
			
			dbg_printf( cn, "Originator      outgoingIF bestNextHop      TQ(rcnt) "
			            "knownSince lsqn(diff) lvld pws ~ogi cpu hop\n");
                        uint32_t orig_ip = 0;

                        while ((orig_node = (struct orig_node*) ((an = avl_next(&orig_avl, &orig_ip)) ? an->key : NULL))) {

                                orig_ip = orig_node->orig;

				if ( !orig_node->router  ||  orig_node->primary_orig_node != orig_node )
				{
					continue;
				}
                                /*
                                struct orig_node *onn = get_orig_node( orig_node->router->addr, NO );

                                if ( !onn  ||  !onn->last_valid_time  ||  !onn->router )
                                        continue;
                                 */
/*
				int estimated_rcvd = (( (100 * orig_node->router->accepted_sqr.wa_val)/PROBE_TO100 )+99) /
					(((tq_power( tq_rate( onn, onn->router->iif, PROBE_RANGE ), PROBE_RANGE ) )/PROBE_TO100)+1);
*/
				
				nodes_count++;
				batman_count++;
				
				
				dbg_printf( cn, "%-15s %-10s %-15s %3i %3i  %s %5i %3i %5i %3i %4i %3i %3i\n",
				            orig_node->orig_str, orig_node->router->nnkey_iif->dev,
				            ipStr( orig_node->router->nnkey_addr ),
				            orig_node->router->longtm_sqr.wa_val/PROBE_TO100,
				            orig_node->router->recent_sqr.wa_val/PROBE_TO100,
//				            estimated_rcvd > 100 ? 100 : estimated_rcvd,
                            get_human_uptime( orig_node->first_valid_sec, 0 ),
				            orig_node->last_valid_sqn,
                                            orig_node->router->longtm_sqr.wa_clr_sqn - orig_node->last_valid_sqn,
				            ( batman_time - orig_node->last_valid_time)/1000,
				            orig_node->pws,
				            WAVG( orig_node->ogi_wavg, OGI_WAVG_EXP ),
				            orig_node->ogm_misc,
				            (Ttl+1 - orig_node->last_path_ttl)
				          ); 
				
				sum_packet_count+= orig_node->router->longtm_sqr.wa_val/PROBE_TO100; /* accepted */
				sum_recent_count+= orig_node->router->recent_sqr.wa_val/PROBE_TO100; /* accepted */
//				sum_rcvd_all_bits+= MIN( estimated_rcvd, 100 );
				sum_lvld+= (batman_time - orig_node->last_valid_time)/1000;
				sum_last_pws+= orig_node->pws;
				sum_ogi_avg+= WAVG( orig_node->ogi_wavg, OGI_WAVG_EXP );
				sum_reserved_something+= orig_node->ogm_misc;
				sum_route_changes+= orig_node->rt_changes;
				sum_hops+= (Ttl+1 - orig_node->last_path_ttl);
			}
			
			dbg_printf( cn, "%8d %-33s %3i %3i                        %5i %3i %4i %3i %3i\n",
			            nodes_count, "known Originator(s), averages: ", 
			            (nodes_count > 0 ? ( sum_packet_count / nodes_count ) : -1 ), 
			            (nodes_count > 0 ? ( sum_recent_count / nodes_count ) : -1 ),
//			            (nodes_count > 0 ? ( sum_rcvd_all_bits / nodes_count ) : -1 ),
			            (nodes_count > 0 ? ( sum_lvld / nodes_count ) : -1),
			            (nodes_count > 0 ? ( sum_last_pws / nodes_count ) : -1 ), 
			            (nodes_count > 0 ? ( sum_ogi_avg / nodes_count ) : -1), 
			            (nodes_count > 0 ? ( sum_reserved_something / nodes_count ) : -1),
			            (nodes_count > 0 ? ( sum_hops / nodes_count ) : -1) );
			
		
		} else if ( !strcmp( opt->long_name, ARG_STATUS ) ) {
			
			dbg_printf( cn, "BMX %s%s, "
			            "%s, LWS %i, PWS %i, OGI %4ims, "
			            "UT %s, CPU %d.%1d\n",
			            SOURCE_VERSION, 
			            ( strncmp( REVISION_VERSION, "0", 1 ) != 0 ? REVISION_VERSION : "" ),
			            ipStr( primary_addr ),
			            local_lws, my_pws, my_ogi,
                        get_human_uptime( 0 , 1),
			            s_curr_avg_cpu_load/10, s_curr_avg_cpu_load%10
			          );
			
		} else if ( !strcmp( opt->long_name, ARG_LINKS ) ) {
			
			
			dbg_printf( cn, "Neighbor        viaIF      Originator      RTQ  RQ  TQ     "
			            "  lseq lvld rid nid\n");

                        uint32_t orig_ip = 0;
                        struct link_node * ln;

                        while ((ln = (struct link_node*) ((an = avl_next(&link_avl, &orig_ip)) ? an->key : NULL))) {

                                orig_ip = ln->orig_addr;

/*
			struct list_head *link_pos;
			list_for_each( link_pos, &link_list ) {
				
				struct link_node *ln = list_entry(link_pos, struct link_node, list);
*/


				orig_node = ln->orig_node;
				
				if ( !orig_node->router )
					continue;
				
/*
				struct orig_node *onn = get_orig_node( orig_node->router->addr, NO );
				
				if ( !onn  ||  !onn->last_valid_time  ||  !onn->router )
					continue;
*/
				
				
				struct list_head *lndev_pos;
				
				list_for_each( lndev_pos, &ln->lndev_list ) {
					
					struct link_node_dev *lndev = list_entry( lndev_pos, struct link_node_dev, list );
					
					rq = lndev->rq_sqr.wa_val;
					tq = tq_rate( orig_node, lndev->bif, PROBE_RANGE );
					rtq = lndev->rtq_sqr.wa_val;
					
					dbg_printf( cn, "%-15s %-10s %-15s %3i %3i %3i      %5i %4i %3d %3d\n",
					            orig_node->orig_str, lndev->bif->dev,
					            orig_node->primary_orig_node ? orig_node->primary_orig_node->orig_str : "???",
					            rtq/PROBE_TO100, rq/PROBE_TO100, tq/PROBE_TO100,
                                                //  accepted and rebroadcasted:
                                                //  orig_node->router->accepted_sqr.wa_val/PROBE_TO100,
                                                //  estimated_rcvd > 100 ? 100 : estimated_rcvd,
                                                //  get_human_uptime( orig_node->first_valid_sec ),
					            orig_node->last_valid_sqn,
//					            ( batman_time - orig_node->last_valid_time)/1000,
					            ( batman_time - lndev->last_lndev)/1000,
					            ( orig_node->primary_orig_node ?
					              orig_node->primary_orig_node->id4me : -1 ),
					            ( orig_node->primary_orig_node ?
					              orig_node->primary_orig_node->id4him : -1 )
                                                );
					
				}
				
			}
			
			
		} else if ( !strcmp(opt->long_name, ARG_ROUTES ) ) {
			
			struct list_head *neigh_pos;
			struct neigh_node *neigh_node;
			
			dbg_printf( cn, "%-16s brc %16s [%10s]  %20s ... [MainIF/IP: %s/%s, UT: %s]\n",
			            "Originator", "Nexthop", "outgoingIF", "Potential nexthops", 
			            primary_if ? primary_if->dev : "--",
			            ipStr( primary_addr ),
                        get_human_uptime( 0 , 1) );
			
                        uint32_t orig_ip = 0;

                        while ((orig_node = (struct orig_node*) ((an = avl_next(&orig_avl, &orig_ip)) ? an->key : NULL))) {

                                orig_ip = orig_node->orig;

				if ( !orig_node->router  ||  orig_node->primary_orig_node != orig_node )
					continue;
				
/*
				struct orig_node *onn = get_orig_node( orig_node->router->addr, NO );
				
				if ( !onn  ||  !onn->last_valid_time  ||  !onn->router )
					continue;
*/
                dbg_printf(cn, "%-15s (%3i) %15s [%10s] ",
                                        orig_node->orig_str,
                                        orig_node->router->longtm_sqr.wa_val/PROBE_TO100,
                                        ipStr( orig_node->router->nnkey_addr ),
                                        orig_node->router->nnkey_iif->dev );

                list_for_each( neigh_pos, &orig_node->neigh_list ) {
                    neigh_node = list_entry( neigh_pos, struct neigh_node, list );

                    if( neigh_node->nnkey_addr != orig_node->router->nnkey_addr ) {

                            dbg_printf(cn,	" %15s (%3i)",
                                      ipStr( neigh_node->nnkey_addr ),
                                      neigh_node->longtm_sqr.wa_val/PROBE_TO100 );

                    }
                }

                dbg_printf( cn, "\n");
         }
			
		} else {
			return FAILURE;
		}
		
		dbg_printf( cn, "\n" );
	}
	
	return SUCCESS;
}



static
int32_t opt_dev_show ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	struct list_head *pos;
	
	if ( cmd == OPT_APPLY ) {
		
		list_for_each( pos, &if_list ) {
			
			struct batman_if *bif = list_entry( pos, struct batman_if, list );

			dbg_cn( cn, DBGL_ALL, DBGT_NONE, "%-10s %5d %8s %15s/%-2d  brc %-15s  SQN %5d  TTL %2d  %11s  %8s  %11s",
			        bif->dev,
                                bif->if_index,
			        !bif->if_active ? "-" : 
			        ( bif->if_linklayer == VAL_DEV_LL_LO ? "loopback": 
			          ( bif->if_linklayer == VAL_DEV_LL_LAN ? "ethernet": 
			            ( bif->if_linklayer == VAL_DEV_LL_WLAN ? "wireless": "???" ) ) ),
			        bif->if_ip_str,
			        bif->if_prefix_length,
			        ipStr(bif->if_broad),
			        bif->if_seqno,
			        bif->if_ttl,
			        bif->if_singlehomed ? "singlehomed" : "multihomed",
			        bif->if_active ? "active" : "inactive",
			        bif == primary_if ? "primary" : "non-primary"
			      );
			
		}
	}
	return SUCCESS;
}

static
int32_t opt_dev ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	struct list_head *list_pos, *list_tmp, *list_prev;
	struct batman_if *bif = NULL;
	
	struct batman_if test_bif;
	
	char *colon_ptr;
	
	dbgf_all( DBGT_INFO, "cmd: %s opt: %s  instance %s",
	          opt_cmd2str[cmd], opt->long_name, patch ? patch->p_val : "");
	
	if ( cmd == OPT_CHECK  ||  cmd == OPT_APPLY ) {
		
		if ( strlen(patch->p_val) >= IFNAMSIZ ) {
			dbg_cn( cn, DBGL_SYS, DBGT_ERR, "dev name MUST be smaller than %d chars", IFNAMSIZ );
			return FAILURE;
		}
		
		list_prev = (struct list_head*)&if_list;
		list_for_each_safe( list_pos, list_tmp, &if_list ) {
			bif = list_entry( list_pos, struct batman_if, list );
			if ( wordsEqual( bif->dev, patch->p_val ) )
				break;
			list_prev = list_pos;
			bif = NULL;
		}
		
		
		if ( patch->p_diff == DEL ) {
			
			if ( bif  &&  primary_if == bif ) {
				
				dbg_cn( cn, DBGL_SYS, DBGT_ERR, 
				        "primary interface %s %s can not be removed!",
				        bif->dev, bif->if_ip_str );
				
				return FAILURE;
				
			} else if ( bif  &&  cmd == OPT_APPLY ) {
				
				if ( bif->if_active )
					if_deactivate( bif );
				
				remove_outstanding_ogms( bif );
				
				list_del( list_prev, list_pos, &if_list );

                                debugFree(bif, 1214);
				
				return SUCCESS;
				
				
			} else if ( !bif ) {
				
				dbgf_cn( cn, DBGL_SYS, DBGT_ERR, "Interface does not exist!" );
				return FAILURE;
			}
		}
		
		if ( !bif ) {
			
			if ( cmd == OPT_APPLY ) {

                                bif = debugMalloc( sizeof(struct batman_if), 206 );
                                memset(bif, 0, sizeof (struct batman_if));

                                INIT_LIST_HEAD(&bif->list);

                                if ( list_empty( &if_list ) )
					primary_if = bif;

				list_add_tail( &bif->list, &if_list );

                        } else {

				bif = &test_bif;
                                memset(bif, 0, sizeof (struct batman_if));

                        }
                        
                        bif->aggregation_out = bif->aggregation_out_buff;

			snprintf( bif->dev, wordlen(patch->p_val)+1, "%s", patch->p_val );
			snprintf( bif->dev_phy, wordlen(patch->p_val)+1, "%s", patch->p_val );
			
		/* if given interface is an alias record physical interface name*/
			if ( ( colon_ptr = strchr( bif->dev_phy, ':' ) ) != NULL )
				*colon_ptr = '\0';
			
			dbgf_all( DBGT_INFO, "assign dev %s physical name %s", bif->dev, bif->dev_phy );
			
			bif->if_seqno_schedule = batman_time;
			
            bif->if_seqno = (primary_if && primary_if != bif) ? primary_if->if_seqno : my_seqno;
			
			bif->aggregation_len = sizeof( struct bat_header );
			
			
			// some configurable interface values - initialized to unspecified:
			bif->if_ttl_conf  = -1;
			bif->if_send_clones_conf  = -1;
			bif->if_ant_diversity_conf = -1;
			bif->if_linklayer_conf = -1;
			bif->if_singlehomed_conf = -1;
						
		}
		
		if ( cmd == OPT_CHECK )
			return SUCCESS;
		
		list_for_each( list_pos, &patch->childs_instance_list ) {
			
			struct opt_child *c = list_entry( list_pos, struct opt_child, list );
			
			int32_t val = c->c_val ? strtol( c->c_val , NULL , 10 ) : -1 ;
			
			if ( !strcmp( c->c_opt->long_name, ARG_DEV_TTL ) ) {
				
				bif->if_ttl_conf = val ;
				
			} else if ( !strcmp( c->c_opt->long_name, ARG_DEV_CLONE ) ) {
				
				bif->if_send_clones_conf = val;
				
			} else if ( !strcmp( c->c_opt->long_name, ARG_DEV_ANTDVSTY ) ) {
				
				bif->if_ant_diversity_conf = val;
				
			} else if ( !strcmp( c->c_opt->long_name, ARG_DEV_LL ) ) {
				
				bif->if_linklayer_conf = val;
				bif->if_conf_hard_changed = YES;
				
			} else if ( !strcmp( c->c_opt->long_name, ARG_DEV_HIDE ) ) {
				
				bif->if_singlehomed_conf = val;
			}
			
			bif->if_conf_soft_changed = YES;
			
		}
		
		
	} else if ( cmd == OPT_POST  &&  opt  &&  !opt->parent_name ) {
		
		check_interfaces(); //will always be called whenever a parameter is changed (due to OPT_POST)
		/*
		if ( !on_the_fly ) {
			
			// add rule for hosts and announced interfaces and networks
			if ( prio_rules ) { 
				add_del_rule( 0, 0, RT_TABLE_HOSTS,      RT_PRIO_HOSTS,      0, RTA_DST, ADD, TRACK_STANDARD );
				add_del_rule( 0, 0, RT_TABLE_NETWORKS,   RT_PRIO_NETWORKS,   0, RTA_DST, ADD, TRACK_STANDARD );
			}
			
			// add rules and routes for interfaces
			if ( update_interface_rules( IF_RULE_SET_NETWORKS ) < 0 )
				cleanup_all( CLEANUP_FAILURE );
			
		}
		*/
	}
	
	return SUCCESS;
}


static int32_t opt_purge ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	if ( cmd == OPT_APPLY )
		purge_orig( 0, NULL );
	
	return SUCCESS;
}


static int32_t opt_seqno ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	struct list_head *list_pos;
	
	if ( cmd == OPT_REGISTER ) {
		
		my_seqno = rand_num( MAX_SEQNO );
		
	} else if ( cmd == OPT_APPLY ) {
		
		list_for_each( list_pos, &if_list )
			(list_entry( list_pos, struct batman_if, list ))->if_seqno = my_seqno;
		
	}
	
	return SUCCESS;
}


static int32_t opt_if_soft ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	if ( cmd == OPT_APPLY )
		if_conf_soft_changed = YES;
	
	return SUCCESS;
}

#ifdef WITHUNUSED
static int32_t opt_if_hard ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	if ( cmd == OPT_APPLY )
		if_conf_hard_changed = YES;
	
	return SUCCESS;
}
#endif

static int32_t opt_lws ( uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn ) {
	
	if ( cmd == OPT_APPLY )
		flush_link_node_seqnos();
	
	return SUCCESS;
}



static struct opt_type originator_options[]= 
{
//        ord parent long_name          shrt Attributes				*ival		min		max		default		*func,*syntax,*help
	
	{ODI,5,0,0,			0,  0,0,0,0,0,				0,		0,		0,		0,		0,
			0,		"\nProtocol options:"},
		
	{ODI,5,0,ARG_STATUS,		0,  A_PS0,A_USR,A_DYN,A_ARG,A_ANY,	0,		0, 		0,		0, 		opt_show_origs,
			0,		"show status\n"},
	
	{ODI,5,0,ARG_ROUTES,		0,  A_PS0,A_USR,A_DYN,A_ARG,A_ANY,	0,		0, 		0,		0, 		opt_show_origs,
			0,		"show routes\n"},
		
	{ODI,5,0,ARG_LINKS,		0,  A_PS0,A_USR,A_DYN,A_ARG,A_ANY,	0,		0, 		0,		0, 		opt_show_origs,
			0,		"show links\n"},
		
	{ODI,5,0,ARG_ORIGINATORS,	0,  A_PS0,A_USR,A_DYN,A_ARG,A_ANY,	0,		0, 		0,		0, 		opt_show_origs,
			0,		"show originators\n"},
		
	{ODI,5,0,ARG_DEV,		0,  A_PMN,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0, 		0,		0, 		opt_dev,
			"<interface-name>", "add or change device or its configuration, options for specified device are:"},

#ifndef LESS_OPTIONS
	{ODI,5,ARG_DEV,ARG_DEV_TTL,	't',A_CS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		MIN_TTL,	MAX_TTL,	DEF_TTL,	opt_dev,
			ARG_VALUE_FORM,	"set TTL of generated OGMs"},
		
	{ODI,5,ARG_DEV,ARG_DEV_CLONE,	'c',A_CS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		MIN_WL_CLONES,	MAX_WL_CLONES,	DEF_WL_CLONES,	opt_dev,
			ARG_VALUE_FORM,	"broadcast OGMs per ogm-interval with given probability (e.g. 200% will broadcast the same OGM twice)"},
		
	/* Antenna-diversity support for bmxd seems working but unfortunately there are few wireless drivers which support 
	 * my understanding of the typical antenna-diversity implementation. This is what I hoped (maybe I am wrong): 
	 * - The RX-antenna is detected on-the-fly on a per-packet basis by comparing 
	 *   the rcvd signal-strength via each antenna during reception of the phy-preamble.
	 * - The TX-antenna is determined per MAC-address based on the last detected best RX-antenna for this MAC.
	 * - Broadcast packets should be send round-robin like via each enabled TX-antenna (e.g. alternating via ant1 and ant2). */
	{ODI,5,ARG_DEV,ARG_DEV_ANTDVSTY,0,  A_CS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		1,		2,		1,		opt_dev,
			ARG_VALUE_FORM,	0/*"set number of broadcast antennas (e.g. for antenna-diversity use /d=2 /c=400 aggreg_interval=100)"*/},
		
		
	{ODI,5,ARG_DEV,ARG_DEV_HIDE,	'h',A_CS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		0,		1,		0,		opt_dev,
			ARG_VALUE_FORM,	"disable/enable hiding of OGMs generated to non link-neighboring nodes. Default for non-primary interfaces"},
#endif
//stephan: allow loopback
	{ODI,5,ARG_DEV,ARG_DEV_LL,	'l',A_CS1,A_ADM,A_DYI,A_CFA,A_ANY,	0,		VAL_DEV_LL_LO,	VAL_DEV_LL_WLAN,0,		opt_dev,
			ARG_VALUE_FORM,	"manually set device type for linklayer specific optimization (0=loopback, 1=lan, 2=wlan)"},
		
	{ODI,5,0,ARG_INTERFACES,	0,  A_PS0,A_USR,A_DYI,A_ARG,A_ANY,	0,		0,		1,		0,		opt_dev_show,
			0,		"show configured interfaces"},
		
	{ODI,5,0,ARG_LWS,       	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&local_lws,	MIN_LWS, 	MAX_LWS,	DEF_LWS,	opt_lws,
			ARG_VALUE_FORM,	"set link window size (LWS) for link-quality calculation (link metric)"},

#ifndef LESS_OPTIONS

	{ODI,5,0,ARG_RTQ_LOUNGE, 	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&local_rtq_lounge,MIN_RTQ_LOUNGE,MAX_RTQ_LOUNGE,DEF_RTQ_LOUNGE, opt_lws,
			ARG_VALUE_FORM, "set local LLS buffer size to artificially delay OGM processing for ordered link-quality calulation"},

	{ODI,5,0,ARG_PWS,       	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_pws,	MIN_PWS, 	MAX_PWS,	DEF_PWS,	opt_if_soft,
			ARG_VALUE_FORM,	"set path window size (PWS) for end2end path-quality calculation (path metric)"},

	{ODI,5,0,ARG_PATH_LOUNGE,	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_path_lounge,MIN_PATH_LOUNGE,MAX_PATH_LOUNGE,DEF_PATH_LOUNGE,opt_purge,
			ARG_VALUE_FORM, "set default PLS buffer size to artificially delay my OGM processing for ordered path-quality calulation"},

	{ODI,5,0,ARG_PATH_HYST, 	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_path_hystere,MIN_PATH_HYST,	MAX_PATH_HYST,	DEF_PATH_HYST,	opt_purge,
			ARG_VALUE_FORM,	"use hysteresis to delay route switching to alternative next-hop neighbors with better path metric"},


	{ODI,5,0,ARG_RCNT_PWS,	        0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_rcnt_pws,   MIN_RCNT_PWS,   MAX_RCNT_PWS,   DEF_RCNT_PWS,   opt_purge,
			ARG_VALUE_FORM, ""},

/*
	{ODI,5,0,ARG_RCNT_LOUNGE,       0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_rcnt_lounge,MIN_RCNT_LOUNGE,MAX_RCNT_LOUNGE,DEF_RCNT_LOUNGE,opt_purge,
			ARG_VALUE_FORM, ""},
*/

	{ODI,5,0,ARG_RCNT_HYST, 	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_rcnt_hystere,MIN_RCNT_HYST,	MAX_RCNT_HYST,	DEF_RCNT_HYST,	opt_purge,
			ARG_VALUE_FORM,	"use hysteresis to delay fast-route switching to alternative next-hop neighbors with a recently extremely better path metric"},

	{ODI,5,0,ARG_RCNT_FK,	        0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_rcnt_fk,    MIN_RCNT_FK,    MAX_RCNT_FK,    DEF_RCNT_FK,    opt_purge,
			ARG_VALUE_FORM,	"configure threshold faktor for dead-path detection"},


	{ODI,5,0,ARG_DROP_2HLOOP,	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&drop_2hop_loop,MIN_DROP_2HLOOP,MAX_DROP_2HLOOP,DEF_DROP_2HLOOP,0,
			ARG_VALUE_FORM,	"drop OGMs received via two-hop loops"},


	{ODI,5,0,ARG_ASYM_EXP,		0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_asym_exp,	MIN_ASYM_EXP,	MAX_ASYM_EXP,	DEF_ASYM_EXP,	0,
			ARG_VALUE_FORM,	"ignore OGMs (rcvd via asymmetric links) with TQ^<val> to radically reflect asymmetric-links"},

	{ODI,5,0,"asocial_device",	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&Asocial_device,MIN_ASOCIAL,	MAX_ASOCIAL,	DEF_ASOCIAL,	0,
			ARG_VALUE_FORM,	"disable/enable asocial mode for devices unwilling to forward other nodes' traffic"},

	{ODI,5,0,ARG_WL_CLONES,		0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&wl_clones,	MIN_WL_CLONES,	MAX_WL_CLONES,	DEF_WL_CLONES,	opt_if_soft,
			ARG_VALUE_FORM,	"broadcast OGMs per ogm-interval for wireless devices with\n"
			"	given probability [%] (eg 200% will broadcast the same OGM twice)"},

	{ODI,5,0,ARG_ASYM_WEIGHT,	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_asym_weight,	MIN_ASYM_WEIGHT,MAX_ASYM_WEIGHT,DEF_ASYM_WEIGHT,0,
			ARG_VALUE_FORM,	"ignore OGMs (rcvd via asymmetric links) with given probability [%] to better reflect asymmetric-links"},

	{ODI,5,0,ARG_HOP_PENALTY,	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_hop_penalty,	MIN_HOP_PENALTY,MAX_HOP_PENALTY,DEF_HOP_PENALTY,0,
			ARG_VALUE_FORM,	"ignore OGMs with given probability [%] to better reflect path-hop distance"},

                        // there SHOULD! be a minimal lateness_penalty >= 1 ! Otherwise a shorter path with equal path-cost than a longer path will never dominate
	{ODI,5,0,ARG_LATE_PENAL,	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_late_penalty,MIN_LATE_PENAL,MAX_LATE_PENAL, DEF_LATE_PENAL, opt_purge,
			ARG_VALUE_FORM,	"penalize non-first rcvd OGMs "},

	{ODI,5,0,ARG_PURGE_TO,  	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&purge_to,	MIN_PURGE_TO,	MAX_PURGE_TO,	DEF_PURGE_TO,	0,
			ARG_VALUE_FORM,	"timeout in seconds for purging stale originators"},

#endif
	{ODI,5,0,ARG_DAD_TO,    	0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&dad_to,	MIN_DAD_TO,	MAX_DAD_TO,	DEF_DAD_TO,	0,
			ARG_VALUE_FORM,	"duplicate address (DAD) detection timout in seconds"},

	{ODI,5,0,"seqno", 		0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_seqno,	MIN_SEQNO,	MAX_SEQNO,	DEF_SEQNO,	opt_seqno,0,0},


	{ODI,5,0,"ttl",			't',A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&Ttl,		MIN_TTL,	MAX_TTL,	DEF_TTL,	opt_if_soft,
			ARG_VALUE_FORM,	"set time-to-live (TTL) for OGMs of primary interface"},
		
		
	{ODI,5,0,"flush_all",		0,  A_PS0,A_ADM,A_DYN,A_ARG,A_ANY,	0,		0, 		0,		0, 		opt_purge,
			0,		"purge all neighbors and routes on the fly"}
};


void init_originator( void ) {
	
	register_options_array( originator_options, sizeof( originator_options ) );
	
}

