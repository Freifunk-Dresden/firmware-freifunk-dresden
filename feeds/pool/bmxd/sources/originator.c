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
#include <limits.h>
#include <string.h>
#include <stdlib.h>
#include <arpa/inet.h>
#include <linux/if.h> /* ifr_if, ifr_tun */
#include <linux/rtnetlink.h>

#include "batman.h"
#include "os.h"
#include "metrics.h"
#include "originator.h"
#include "plugin.h"
#include "schedule.h"
#include "tunnel.h"

void update_community_route(void);

static int32_t my_seqno;

char *gw_scirpt_name = NULL;

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

//SE: network filter
// MUST BE default 0. So if user does not pass the network parameter, no OGM will be dropped
uint32_t gNetworkPrefix = 0;
uint32_t gNetworkNetmask = 0;
//SE: added to separate networks. (network extension could be used, but
//this would cause to increase size of every packet)
int32_t gNetworkId = DEF_NETWORK_ID; //only 16bits are used, but parameter needs to be 32bit


static LIST_ENTRY pifnb_list;
LIST_ENTRY link_list;
LIST_ENTRY if_list;

struct avl_tree link_avl = {sizeof(uint32_t), NULL};

struct batman_if *primary_if = NULL;
uint32_t primary_addr = 0;

struct avl_tree orig_avl = {sizeof(uint32_t), NULL};

static void update_routes(struct orig_node *orig_node, struct neigh_node *new_router)
{
	prof_start(PROF_update_routes);
	static char old_nh_str[ADDR_STR_LEN], new_nh_str[ADDR_STR_LEN];

	dbgf_all(0, DBGT_INFO, " ");

	addr_to_str((new_router ? new_router->key.addr : 0), new_nh_str);
	addr_to_str((orig_node->router ? orig_node->router->key.addr : 0), old_nh_str);

	if (orig_node->router != new_router)
	{
		if (new_router)
		{
			dbgf_all(0, DBGT_INFO, "Route to %s via %s", orig_node->orig_str, new_nh_str);
		}

		/* route altered or deleted */
		if (orig_node->router)
		{

			add_del_route(orig_node->orig, 32, orig_node->router->key.addr, 0,
										orig_node->router->key.iif ? orig_node->router->key.iif->if_index : 0,
										orig_node->router->key.iif ? orig_node->router->key.iif->dev : NULL,
										RT_TABLE_HOSTS, RTN_UNICAST, DEL, TRACK_OTHER_HOST);
			//dbg(DBGL_SYS, DBGT_INFO,"route del %s via %s, %s:%d", ipStr(orig_node->orig), ipStr(orig_node->router->key.addr), orig_node->router->key.iif ? orig_node->router->key.iif->dev : "NULL", orig_node->router->key.iif ? orig_node->router->key.iif->if_index : 0);
		}

		orig_node->router = new_router; // put it before update_community_route(0), so this
																		// will get the new router too

		/* route altered or new route added */
		if (new_router)
		{
			orig_node->rt_changes++;

			add_del_route(orig_node->orig, 32, new_router->key.addr, primary_addr,
										new_router->key.iif ? new_router->key.iif->if_index : 0,
										new_router->key.iif ? new_router->key.iif->dev : NULL,
										RT_TABLE_HOSTS, RTN_UNICAST, ADD, TRACK_OTHER_HOST);
			//dbg(DBGL_SYS, DBGT_INFO,"route add %s via %s, %s:%d", ipStr(orig_node->orig), ipStr(orig_node->router->key.addr), orig_node->router->key.iif ? orig_node->router->key.iif->dev : "NULL", orig_node->router->key.iif ? orig_node->router->key.iif->if_index : 0);
			update_community_route();
		}
	}

	prof_stop(PROF_update_routes);
}

// removes next hop route for this originator.
// this function is called, when a nexthop should be deleted from node.
static void flush_orig(struct orig_node *orig_node, struct batman_if *bif)
{

	dbgf_all(0, DBGT_INFO, "%s", ipStr(orig_node->orig));

	OLForEach(neigh_node, struct neigh_node, orig_node->neigh_list_head)
	{

		if (!bif || bif == neigh_node->key.iif)
		{
			flush_sq_record(&neigh_node->longtm_sqr);
			flush_sq_record(&neigh_node->recent_sqr);
		}
	}

	if (!bif || (orig_node->router && orig_node->router->key.iif == bif))
	{
		update_routes(orig_node, NULL);
		flush_tun_orig(orig_node);
	}
}

static struct neigh_node *init_neigh_node(struct orig_node *orig_node,
																					uint32_t neigh, struct batman_if *iif, batman_time_t last_aware)
{
	dbgf_all(0, DBGT_INFO, " ");

	struct neigh_node *neigh_node = debugMalloc(sizeof(struct neigh_node), 403);
	memset(neigh_node, 0, sizeof(struct neigh_node));

	neigh_node->key.addr = neigh;
	neigh_node->key.iif = iif;
	neigh_node->last_aware = last_aware;

	OLInsertTailList(&orig_node->neigh_list_head, &neigh_node->list);
	avl_insert(&orig_node->neigh_avl, &neigh_node->key, neigh_node);
	return neigh_node;
}

static struct neigh_node *update_orig(struct orig_node *on, uint16_t *oCtx, struct msg_buff *mb)
{
	prof_start(PROF_update_originator);

	struct neigh_node *incm_rt = NULL;
	struct neigh_node *curr_rt = on->router;
	struct neigh_node *old_rt;
	struct bat_packet_ogm *ogm = mb->ogm;

	old_rt = curr_rt;
	uint32_t max_othr_longtm_val = 0;
	uint32_t max_othr_recent_val = 0;

	dbgf_all(3, DBGT_INFO, "%s", on->orig_str);

	/* only used for debugging purposes */
	if (!on->first_valid_sec)
		on->first_valid_sec = batman_time_sec;

	// find incoming_neighbor and purge outdated SQNs of alternative next hops
	OLForEach(tmp_neigh, struct neigh_node, on->neigh_list_head)
	{
		uint8_t probe = 0;

		if ((tmp_neigh->key.addr == mb->neigh) && (tmp_neigh->key.iif == mb->iif))
		{
			incm_rt = tmp_neigh;

			if (*oCtx & IS_ACCEPTED)
			{
				if (*oCtx & IS_NEW)
					probe = PROBE_RANGE;
				else
					probe = PROBE_RANGE - (my_late_penalty * PROBE_TO100);
			}
		}

		update_lounged_metric(probe, my_path_lounge, ogm->ogm_seqno, on->last_valid_sqn, &tmp_neigh->longtm_sqr,
													on->pws);

		if (incm_rt != tmp_neigh)
			max_othr_longtm_val = MAX(max_othr_longtm_val, tmp_neigh->longtm_sqr.wa_val);

		if (my_rcnt_fk == MAX_RCNT_FK)
			continue;

		//if (*oCtx & IS_NEW || (((SQ_TYPE) (on->last_valid_sqn - ogm->ogm_seqno)) <= my_rcnt_lounge))

		update_lounged_metric(probe, my_path_lounge, ogm->ogm_seqno, on->last_valid_sqn, &tmp_neigh->recent_sqr,
													my_rcnt_pws);

		if (incm_rt != tmp_neigh)
			max_othr_recent_val = MAX(max_othr_recent_val, tmp_neigh->recent_sqr.wa_val);
	}

	paranoia(-500001, !incm_rt);

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
	if ((curr_rt != incm_rt) &&
			(((SQ_TYPE)(on->last_decided_sqn - ogm->ogm_seqno) >= on->pws)) &&

			(((my_rcnt_fk == MAX_RCNT_FK) &&
				((LCB = ((int)incm_rt->longtm_sqr.wa_val > (int)(max_othr_longtm_val) + (my_path_hystere * PROBE_TO100))))

						) ||
			 (

					 (my_rcnt_fk != MAX_RCNT_FK) &&

					 (((LCB = ((int)incm_rt->longtm_sqr.wa_val > (int)(max_othr_longtm_val) + (my_path_hystere * PROBE_TO100))) &&
						 (RCB = ((int)incm_rt->recent_sqr.wa_val > (int)(max_othr_recent_val)))) ||
						(RXB = ((int)incm_rt->recent_sqr.wa_val > (int)((max_othr_recent_val * my_rcnt_fk) / 100) + (my_rcnt_hystere * PROBE_TO100)))

								))))
	{
		curr_rt = incm_rt;
		on->last_decided_sqn = ogm->ogm_seqno;
		*oCtx |= IS_BEST_NEIGH_AND_NOT_BROADCASTED;
		changed = YES;
		dbgf_all(3, DBGT_INFO, "%s, (A) IS_BEST_NEIGH_AND_NOT_BROADCASTED, ogm_seqno=%d, RXB=%d, RCB=%d, LCB=%d, last_decided_sqn=%d, my_rcnt_fk=%d", on->orig_str, ogm->ogm_seqno, RXB, RCB, LCB, on->last_decided_sqn, my_rcnt_fk);
		//wenn ogm ueber gleiche route (ip) kommt.
	}
	else if ((curr_rt == incm_rt) &&
					 (((SQ_TYPE)(on->last_decided_sqn - ogm->ogm_seqno) >= on->pws)) &&

					 (((my_rcnt_fk == MAX_RCNT_FK) &&
						 ((LCB = ((int)incm_rt->longtm_sqr.wa_val >= (int)(max_othr_longtm_val) - (my_path_hystere * PROBE_TO100))))

								 ) ||
						(

								(my_rcnt_fk != MAX_RCNT_FK) &&

								(((LCB = ((int)incm_rt->longtm_sqr.wa_val >= (int)(max_othr_longtm_val) - (my_path_hystere * PROBE_TO100))) ||
									(RCB = ((int)incm_rt->recent_sqr.wa_val >= (int)(max_othr_recent_val))))))))
	{
		on->last_decided_sqn = ogm->ogm_seqno;
		*oCtx |= IS_BEST_NEIGH_AND_NOT_BROADCASTED;
		dbgf_all(3, DBGT_INFO, "%s, (B) IS_BEST_NEIGH_AND_NOT_BROADCASTED, ogm_seqno=%d, RXB=%d, RCB=%d, LCB=%d, last_decided_sqn=%d, my_rcnt_fk=%d", on->orig_str, ogm->ogm_seqno, RXB, RCB, LCB, on->last_decided_sqn, my_rcnt_fk);
	}

	if (changed && !LCB)
	{
		dbgf(DBGL_CHANGES, DBGT_INFO,
				 "%s path to %-15s via %-15s (old %-15s incm %-15s) due to %s %s %s PH: "
				 "recent incm %3d  othr %3d  fk %-4d  "
				 "longtm incm %3d  othr %3d",
				 changed ? "NEW" : "OLD",
				 on->orig_str,
				 curr_rt ? ipStr(curr_rt->key.addr) : "----",
				 old_rt ? ipStr(old_rt->key.addr) : "----",
				 ipStr(incm_rt->key.addr),
				 LCB ? " LCB" : "!LCB",
				 RCB ? " RCB" : "!RCB",
				 RXB ? " RXB" : "!RXB",
				 incm_rt->recent_sqr.wa_val / PROBE_TO100,
				 max_othr_recent_val, my_rcnt_fk,
				 incm_rt->longtm_sqr.wa_val / PROBE_TO100,
				 max_othr_longtm_val);
	}

	if (curr_rt != incm_rt)
	{
		// only evaluate and change recorded attributes and route if arrived via best neighbor
		prof_stop(PROF_update_originator);
		return curr_rt;
	}

	on->last_path_ttl = ogm->ogm_ttl;

	on->ogx_flag = ogm->ogx_flag;

	on->ogm_misc = ogm->ogm_misc;

	if (on->pws != ogm->ogm_pws)
	{
		dbg(DBGL_SYS, DBGT_INFO,
				"window size of OG %s changed from %d to %d, flushing packets and route!",
				on->orig_str, on->pws, ogm->ogm_pws);

		on->pws = ogm->ogm_pws;
		flush_orig(on, NULL);
		prof_stop(PROF_update_originator);
		return NULL;
	}

	prof_stop(PROF_update_originator);
	return curr_rt;
}

static void free_pifnb_node(struct orig_node *orig_node)
{
	paranoia(-500013, (!orig_node->id4him)); //free_pifnb_node(): requested to free pifnb_node with id4him of zero

	OLForEach(pn, struct pifnb_node, pifnb_list)
	{
		if (pn->pog == orig_node)
		{
			OLRemoveEntry(pn);
			orig_node->id4him = 0;
			debugFree(pn, 1429);
			break;
		}
	}

	paranoia(-500012, (orig_node->id4him != 0)); //free_pifnb_node(): requested to free non-existent pifnb_node
}

static int8_t init_pifnb_node(struct orig_node *orig_node)
{
	uint16_t id4him = 1;

	paranoia(-500011, (orig_node->id4him != 0)); //init_pifnb_node(): requested to init already existing pifnb_node

	dbgf_all(4, DBGT_INFO, " %16s ", orig_node->orig_str);

	struct pifnb_node *pn = debugMalloc(sizeof(struct pifnb_node), 429);
	memset(pn, 0, sizeof(struct pifnb_node));
	OLInitializeListHead(&pn->list);
	pn->pog = orig_node; // copy pointer !!! orig_node is held in more than one lists.

	// looking for a unused id4him value. start with 1 and check if this
	// value is already in list. list is sorted by id4him values, so when
	// a node was found with a higer id4him -> use this id4him
	// When the new id4him is already used, then increment it.
	int inserted = 0;
	OLForEach(pn_tmp, struct pifnb_node, pifnb_list)
	{
		if (pn_tmp->pog->id4him > id4him)
		{
			// neues (pn->list) soll for gefundenen eingehangt werden
			OLInsertTailList(&pn_tmp->list, &pn->list);
			inserted = 1;
			break; //new entry should be inserted before current (pn_tmp2 != NULL)
		}

		id4him++;

		if (id4him >= MAX_ID4HIM)
		{
			dbgf(DBGL_SYS, DBGT_ERR, "Max numbers of pifnb_nodes reached!");
			debugFree(pn, 429);
			return FAILURE;
		}
	}

	// set id4him in orig object. the loop uses a pointer (pog) which is the same object.
	orig_node->id4him = id4him;

	dbgf_all(4, DBGT_INFO, "%16s -> id4him %d", orig_node->orig_str, id4him);

	if (!inserted)
	{
		// pn->list angehangt werden, da es die groesste id4him hat
		OLInsertTailList(&pifnb_list, &pn->list);
	}

	return SUCCESS;
}

// link-node representiert einen direkten nachbarn.
// diese struktur wird zweimal gehalten:
//  - globalen avl baum
//  - globalen link list
//  link-node hat wiederum eine liste von interfaces, die zuerst freigeben werden.
//  so ein nachbar, kann naemlich ueber mehrere interfaces erreichba sein.
static void free_link_node(struct orig_node *orig_node, struct batman_if *bif)
{
	dbgf_all(0, DBGT_INFO, "of orig %s", orig_node->orig_str);

	paranoia(-500010, (orig_node->link_node == NULL)); //free_link_node(): requested to free non-existing link_node

	// - remove interfaces from link_node object
	// when removing entries, I can modify lndev (because OLForEach() is a macro)
	OLForEach(lndev, struct link_node_dev, orig_node->link_node->lndev_list)
	{
		if (!bif || lndev->bif == bif)
		{
			PLIST_ENTRY prev = OLGetPrev(lndev);

			dbgf_all(0, DBGT_INFO, "purging lndev %16s %10s %s",
							 orig_node->orig_str, lndev->bif->dev, lndev->bif->if_ip_str);

			OLRemoveEntry(lndev);
			debugFree(lndev, 1429);
			lndev = (struct link_node_dev *)prev; //reset to previous entry, so for-loop can try to get new next entry
																						//after the one, that was just deleted
		}
	}

	// - remove link_node from global link_list and avl baum
	OLForEach(ln, struct link_node, link_list)
	{
		if (ln->orig_node == orig_node && OLIsListEmpty(&ln->lndev_list))
		{
			dbgf_all(0, DBGT_INFO, "purging link_node %16s ", orig_node->orig_str);

			OLRemoveEntry(ln);

			avl_remove(&link_avl, /*(uint32_t*)*/ &orig_node->link_node->orig_addr);
			debugFree(orig_node->link_node, 1428);
			orig_node->link_node = NULL;
			break;
		}
	}
}

static void flush_link_node_seqnos(void)
{
	OLForEach(ln, struct link_node, link_list)
	{
		while (!OLIsListEmpty(&ln->lndev_list))
		{
			struct link_node_dev *lndev = (struct link_node_dev *)OLRemoveHeadList(&ln->lndev_list);

			dbgf(DBGL_CHANGES, DBGT_INFO, "purging lndev %16s %10s %s",
					 ln->orig_node->orig_str, lndev->bif->dev, lndev->bif->if_ip_str);

			debugFree(lndev, 1429);
		}
	}
}

static void init_link_node(struct orig_node *orig_node)
{
	struct link_node *ln;

	dbgf_all(0, DBGT_INFO, "%s", orig_node->orig_str);

	ln = orig_node->link_node = debugMalloc(sizeof(struct link_node), 428);
	memset(ln, 0, sizeof(struct link_node));
	OLInitializeListHead(&ln->list);

	ln->orig_node = orig_node;
	ln->orig_addr = orig_node->orig;

	OLInitializeListHead(&ln->lndev_list);

	OLInsertTailList(&link_list, &ln->list);

	avl_insert(&link_avl, &ln->orig_addr, ln);
}

static int8_t validate_orig_seqno(struct orig_node *orig_node, uint32_t neigh, char * ndev, SQ_TYPE ogm_seqno)
{
	// this originator IP is somehow known..(has ever been valid)
	if (orig_node->last_valid_time || orig_node->last_valid_sqn)
	{
		//my_path_lounge ist aktuell auf 8 gesetzt. heisst, dass nur ogm verworfen werden, bei dennen die
		// seqno mind 1+8 alt sind. alle anderen werden noch weiter verarbeitet, da diese ueber andere
		// interfaces kommen koennen und damit die qualitat uber diese 8 berechnet wird und das routing
		// gesteuert wird.
		// grob: wenn last_valid_sqn neuer ist als aktuelle, dann verwerfen.
		//
		if ((uint16_t)(ogm_seqno + my_path_lounge - orig_node->last_valid_sqn) >
				MAX_SEQNO - orig_node->pws)
		{
			dbg_mute(3, 25, DBGL_CHANGES, DBGT_WARN,
							 "drop OGM %-15s  via %4s NB %-15s (%s) with old SQN %5i  "
							 "(prev %5i  lounge-margin %2i  pws %3d  lvld %llu) !",
							 orig_node->orig_str,
							 (orig_node->router && orig_node->router->key.addr == neigh) ? "best" : "altn",
							 ipStr(neigh),
							 ndev?ndev:"NULL",
							 ogm_seqno,
							 orig_node->last_valid_sqn,
							 my_path_lounge, orig_node->pws, (unsigned long long)orig_node->last_valid_time);

			return FAILURE;
		}

// das funktioniert nicht richig, da auch gueltige eigene ogms ueber interfaces (mit bmx_prime inteface ip
// oder auch ip vom link interface).
// DAD (duplicate ip) wenn ich eine ogm bekomme, wo ich fuer die ip/node bereits eine andere seqno
// habe, die nicht innerhalb von pws oder my_path_lounge (keine ahnung welches fenster) liegt.
// also irgendwie nicht neuer ist, als die gespeicherte.
// DAD aber genauso nur machen, wenn meine gespeicherte seqno nicht zu alt ist. damit wurde dann
// neue ogms wieder zugelassen mit anderen seqno.
#if 0
//original:
		if ( // if seqno is more than 10 times out of dad timeout
				((uint16_t)(ogm_seqno + my_path_lounge - orig_node->last_valid_sqn)) >
						(my_path_lounge +
						 ((1000 * dad_to) / MIN(WAVG(orig_node->ogi_wavg, OGI_WAVG_EXP), MIN_OGI))) &&
				// but we have received an ogm in less than timeout sec
				batman_time < (orig_node->last_valid_time + (1000 * dad_to)))
		{
			dbg_mute(0, 26, DBGL_SYS, DBGT_WARN,
							 "DAD-alert! %s  via NB %s (%s); SQN %i out-of-range;  lounge-margin %i "
							 "(last valid SQN %i  at %llu)  dad_to %d  wavg %d  Reinit in %d s",
							 orig_node->orig_str, ipStr(neigh),ndev?ndev:"NULL", ogm_seqno, my_path_lounge,
							 orig_node->last_valid_sqn, (unsigned long long)orig_node->last_valid_time,
							 dad_to, WAVG(orig_node->ogi_wavg, OGI_WAVG_EXP),
							 ((orig_node->last_valid_time + (1000 * dad_to)) - batman_time) / 1000);

			return FAILURE;
		}
#else
//stephan
	// Idee:
	// gibt es einen knoten mit gleicher ip, so ist sehr wahrscheinlich die sequenznummer sehr verschieden
	// zur letzten sqn ist.
	// Wie oben, betrachte ich aber nur  kuerzlich empfangene ogms (batman_time).
	// Wenn zwei knoten gleiche ip haben, dann kommen die OGMs auch zeitlich gleichzeitlich an.
	// Dann habe ich einen IP Konflikt und ogm werden ignoriert.
	//
	// "last_valid" wird nur aktualisert, wenn eine OGM keinen Konflikt erzeugte und gueltig war.
	// Wurden OGMs dad_to Sekunden lang ignoriert, werden diese wieder zuglassen. Entweder
	// hat sich der IP Konflikt aufgeloest, oder tritt erneut ein. dann wurden aber zwischenzeitlich
	// "last_valid" aktualisert und ogms werden wieder fuer dad_to Sekunden ignoriert.

	// maximal difference between seqno and last_valid_sqn.
	const uint16_t MIN_DAD_SEQNO_DIFF = 100;

	// seqnoDiff is the positive delta considering wrapping.
	int32_t _seqno = ogm_seqno + my_path_lounge;
	if( _seqno >= USHRT_MAX) _seqno -= USHRT_MAX; // on wrap: shift it back (evt.) ins negative

	int32_t seqnoDiff =   _seqno >= orig_node->last_valid_sqn
											?	_seqno >= orig_node->last_valid_sqn
											: (USHRT_MAX - orig_node->last_valid_sqn) + _seqno;

		if(    batman_time < (orig_node->last_valid_time + (1000 * dad_to))	//time check ogm alter in [ms]
			  // check seqno und erlaube minds die my_path_lounge (da diese ogms alle die gleichen sein koennten - gleiche seqno)
			  && seqnoDiff > MIN_DAD_SEQNO_DIFF

				// check IP against all IPs of this node. consider only ips from other nodes
				&& neigh 															// neigh is zero if called from validate_primary_orig
				&& orig_node->orig != neigh 					// must not be IP from my own secondary interfaces
				&& orig_node->orig != primary_addr  	// and not my primary IP
		)
		{
			dbg_mute(3, 26, DBGL_SYS, DBGT_WARN,
							 "DAD-alert! %s  via NB %s (%s), OGM SQN %i out-of-range: lounge-margin %i, "
               "batman_time %llu,"
							 "(last valid SQN %i  at %llu, SQNdiff:%ld)  dad_to %d  wavg %d",
							 orig_node->orig_str, ipStr(neigh), ndev?ndev:"NULL", ogm_seqno, my_path_lounge,
               batman_time,
							 orig_node->last_valid_sqn, (unsigned long long)orig_node->last_valid_time,
							 seqnoDiff,
							 dad_to, WAVG(orig_node->ogi_wavg, OGI_WAVG_EXP));

			return FAILURE; // ignore ogm
		}

#endif
	}

	return SUCCESS;
}

static void set_primary_orig(struct orig_node *orig_node, uint32_t new_primary_addr)
{
	if (orig_node->primary_orig_node && (!new_primary_addr || orig_node->primary_orig_node->orig != new_primary_addr))
	{
		// remove old:
		if (orig_node->primary_orig_node != orig_node)
		{
			orig_node->primary_orig_node->pog_refcnt--;
			paranoia(-500152, orig_node->pog_refcnt < 0);
		}

		orig_node->primary_orig_node = NULL;
	}

	if (new_primary_addr && (!orig_node->primary_orig_node || orig_node->primary_orig_node->orig != new_primary_addr))
	{
		// add new:

		if (orig_node->orig != new_primary_addr)
		{
			orig_node->primary_orig_node = find_or_create_orig_node_in_avl(new_primary_addr);
			orig_node->primary_orig_node->pog_refcnt++;
		}
		else
		{
			orig_node->primary_orig_node = orig_node;
		}
	}
}

// die funktion wird entweder fuer ogm aufgerufen, die emfpangen wurden
// und evt eine PIP extension haben, oder fuer meine eigen knoten.
// in beiden
static int8_t validate_primary_orig(struct orig_node *orig_node, struct msg_buff *mb, uint16_t oCtx)
{
	if (mb->rcv_ext_len[EXT_TYPE_64B_PIP])
	{
		struct ext_packet *pip = mb->rcv_ext_array[EXT_TYPE_64B_PIP];

		dbgf_all(3, DBGT_INFO, "orig %s  neigh %s", mb->orig_str, mb->neigh_str);

		if (orig_node->primary_orig_node)
		{
			if (orig_node->primary_orig_node->orig != pip->EXT_PIP_FIELD_ADDR)
			{
				dbg_mute(3, 45, DBGL_SYS, DBGT_WARN,
								 "neighbor %s changed his primary interface from %s to %s !",
								 orig_node->orig_str,
								 orig_node->primary_orig_node->orig_str,
								 ipStr(pip->EXT_PIP_FIELD_ADDR));

				if (orig_node->primary_orig_node->id4him)
					free_pifnb_node(orig_node->primary_orig_node);

				set_primary_orig(orig_node, pip->EXT_PIP_FIELD_ADDR);
			}
		}
		else
		{
			set_primary_orig(orig_node, pip->EXT_PIP_FIELD_ADDR);
		}

		if (pip->EXT_PIP_FIELD_PIPSEQNO && //remain compatible to COMPAT_VERSION 10
				validate_orig_seqno(orig_node->primary_orig_node, 0, "", ntohs(pip->EXT_PIP_FIELD_PIPSEQNO)) == FAILURE)
		{
			dbg(DBGL_SYS, DBGT_WARN, "validation primary originator %15s failed",
					ipStr(orig_node->primary_orig_node->orig));
			//orig_node->primary_orig_node = NULL;
			set_primary_orig(orig_node, 0);
			return FAILURE;
		}
	}
	else
	{
		//hier keine extension vorhaden

		if (orig_node->primary_orig_node)
		{
			if (orig_node->primary_orig_node != orig_node)
			{
				dbg_mute(3, 30, DBGL_SYS, DBGT_WARN,
								 "neighbor %s changed primary interface from %s to %s !",
								 orig_node->orig_str,
								 orig_node->primary_orig_node->orig_str,
								 orig_node->orig_str);

				if (orig_node->primary_orig_node->id4him)
					free_pifnb_node(orig_node->primary_orig_node);

				//orig_node->primary_orig_node = orig_node;
				set_primary_orig(orig_node, orig_node->orig);
			}
		}
		else
		{
			//orig_node->primary_orig_node = orig_node;
			set_primary_orig(orig_node, orig_node->orig);
		}
	}

	orig_node->primary_orig_node->last_aware = batman_time;

	if ((oCtx & IS_DIRECT_NEIGH) && !(orig_node->primary_orig_node->id4him))
	{
		uint8_t ret = init_pifnb_node(orig_node->primary_orig_node);

		//		dbg( DBGL_SYS, DBGT_WARN, "validation: no id4him for primary originator %15s. init_pifnb_node() ret=%d",
		//	                        ipStr(orig_node->primary_orig_node->orig), ret );

		return ret;
	}

	return SUCCESS;
}

static void update_rtq_link(struct orig_node *orig_node_neigh, uint16_t oCtx, struct msg_buff *mb,
														struct batman_if *iif, struct bat_packet_ogm *ogm, struct link_node_dev *lndev)
{
	dbgf_all(3, DBGT_INFO,
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
		dbgf_all(3, DBGT_ERR,
						 "###  if %s, lastTxIfSeqno: %d, currRxSeqno: %d - correct interface seqno",
						 iif->dev, (iif->if_seqno - OUT_SEQNO_OFFSET), ogm->ogm_seqno);
		iif->if_seqno = ogm->ogm_seqno + OUT_SEQNO_OFFSET;
	}

	if (((SQ_TYPE)((iif->if_seqno - OUT_SEQNO_OFFSET) - ogm->ogm_seqno)) > local_rtq_lounge)
	{
		dbg_mute(3, 51, DBGL_CHANGES, DBGT_WARN,
						 "late reception of own OGM via NB %s  lastTxIfSqn %d  rcvdSqn %d  margin %d ! "
						 "Try configureing a greater --%s value .",
						 mb->neigh_str, (iif->if_seqno - OUT_SEQNO_OFFSET),
						 ogm->ogm_seqno, local_rtq_lounge, ARG_RTQ_LOUNGE);

		return;
	}

	/* neighbour has to indicate direct link and it has to come via the corresponding interface */
	/* if received seqno equals last send seqno save new seqno for bidirectional check */
	if (orig_node_neigh->link_node && orig_node_neigh->primary_orig_node && lndev)
	{
		update_lounged_metric(PROBE_RANGE, local_rtq_lounge, ogm->ogm_seqno, (iif->if_seqno - OUT_SEQNO_OFFSET),
													&lndev->rtq_sqr, local_lws);

		if (orig_node_neigh->primary_orig_node->id4me != ogm->prev_hop_id)
		{
			if (orig_node_neigh->primary_orig_node->id4me != 0)
				dbg_mute(0, 53, DBGL_CHANGES, DBGT_WARN,
								 "received changed prev_hop_id from neighbor %s !!!",
								 mb->neigh_str);

			orig_node_neigh->primary_orig_node->id4me = ogm->prev_hop_id;
		}

		dbgf_all(0, DBGT_INFO, "indicating bidirectional link");
	}
}

static void update_rq_link(struct orig_node *orig_node, SQ_TYPE sqn, struct batman_if *iif, uint16_t oCtx)
{
	if (!((oCtx & IS_DIRECT_NEIGH) || orig_node->link_node))
		return;

	if (oCtx & IS_DIRECT_NEIGH)
	{
		orig_node->primary_orig_node->last_pog_link = batman_time;

		if (!orig_node->link_node)
			init_link_node(orig_node);
	}

	dbgf_all(0, DBGT_INFO, "OG %s  SQN %d  IF %s  ctx %x  ln %s  cloned %s  direct %s",
					 orig_node->orig_str, sqn, iif->dev, oCtx,
					 orig_node->link_node ? "YES" : "NO",
					 (oCtx & HAS_CLONED_FLAG) ? "YES" : "NO",
					 (oCtx & IS_DIRECT_NEIGH) ? "YES" : "NO");

	// skip updateing link_node if this SQN is known but not new
	if ((orig_node->last_valid_time || orig_node->last_valid_sqn) &&
			((uint16_t)(sqn + RQ_LINK_LOUNGE - orig_node->last_valid_sqn) > MAX_SEQNO - local_lws - MAX_PATH_LOUNGE))
		return;

	paranoia(-500156, !orig_node->link_node);

	struct link_node_dev *this_lndev = NULL;

	dbgf_all(0, DBGT_INFO, "[%10s %3s %3s %3s]", "dev", "RTQ", "RQ", "TQ");

	OLForEach(lndev, struct link_node_dev, orig_node->link_node->lndev_list)
	{

		dbgf_all(0, DBGT_INFO, "[%10s %3i %3i %3i] before", lndev->bif->dev,
						 (((lndev->rtq_sqr.wa_val)) / PROBE_TO100),
						 (((lndev->rq_sqr.wa_val)) / PROBE_TO100),
						 (((tq_rate(orig_node, lndev->bif, PROBE_RANGE))) / PROBE_TO100));

		if (lndev->bif == iif)
		{
			this_lndev = lndev;
		}
		else
		{
			update_lounged_metric(0, RQ_LINK_LOUNGE, sqn, orig_node->last_valid_sqn, &lndev->rq_sqr, local_lws);
		}
	}

	if (!this_lndev && (oCtx & IS_DIRECT_NEIGH))
		this_lndev = get_lndev(orig_node->link_node, iif, YES /*create*/);

	if (this_lndev)
	{
		uint8_t probe = ((oCtx & IS_DIRECT_NEIGH) && !(oCtx & HAS_CLONED_FLAG)) ? PROBE_RANGE : 0;

		update_lounged_metric(probe, RQ_LINK_LOUNGE, sqn, orig_node->last_valid_sqn, &this_lndev->rq_sqr, local_lws);

		if (probe)
			this_lndev->last_lndev = batman_time;
	}

	return;
}

static int tq_power(int tq_rate_value, int range)
{
	int tq_power_value = range;
	int exp_counter;

	for (exp_counter = 0; exp_counter < my_asym_exp; exp_counter++)
		tq_power_value = ((tq_power_value * tq_rate_value) / range);

	return tq_power_value;
}

static int8_t validate_considered_order(struct orig_node *orig_node, SQ_TYPE seqno, uint8_t ttl, uint32_t neigh, struct batman_if *iif)
{
	struct neigh_node_key key;
	struct avl_node *an;
	struct neigh_node *nn;

	memset(&key, 0, sizeof(struct neigh_node_key)); //needed by valgrind
	key.addr = neigh;
	key.iif = iif;
	an = avl_find(&orig_node->neigh_avl, &key);
	nn = an ? (struct neigh_node *)an->object : NULL;

	if (nn)
	{
		paranoia(-500198, (nn->key.addr != neigh || nn->key.iif != iif));

		nn->last_aware = batman_time;

		if (seqno == nn->last_considered_seqno /* && ttl <= nn->last_considered_ttl */)
		{
			return FAILURE;
		}
		else if (((SQ_TYPE)(seqno - nn->last_considered_seqno)) > MAX_SEQNO - my_pws)
		{
			return FAILURE;
		}

		nn->last_considered_seqno = seqno;
		nn->last_considered_ttl = ttl;
		return SUCCESS;
	}

	nn = init_neigh_node(orig_node, neigh, iif, batman_time);

	nn->last_considered_seqno = seqno;
	nn->last_considered_ttl = ttl;
	return SUCCESS;
}

/* this function finds and may create an originator entry for the given address */
struct orig_node *find_or_create_orig_node_in_avl(uint32_t addr)
{
	prof_start(PROF_find_or_create_orig_node_in_avl);
	struct avl_node *an = avl_find(&orig_avl, &addr);

	struct orig_node *orig_node = an ? (struct orig_node *)an->object : NULL;

	if (orig_node)
	{
		orig_node->last_aware = batman_time;
		prof_stop(PROF_find_or_create_orig_node_in_avl);
		return orig_node;
	}

	orig_node = debugMalloc(sizeof(struct orig_node) , 402);
	memset(orig_node, 0, sizeof(struct orig_node) );

	OLInitializeListHead(&orig_node->neigh_list_head);
	orig_node->neigh_avl.root = NULL;
	orig_node->neigh_avl.key_size = sizeof(struct neigh_node_key);

	addr_to_str(addr, orig_node->orig_str);
	dbgf_all(0, DBGT_INFO, "creating new originator: %s", orig_node->orig_str);

	orig_node->orig = addr;
	orig_node->last_aware = batman_time;
	orig_node->router = NULL;
	orig_node->link_node = NULL;
	orig_node->pws = my_pws;

	upd_wavg(&orig_node->ogi_wavg, DEF_OGI, OGI_WAVG_EXP);

	avl_insert(&orig_avl, /*(uint32_t*)*/ &orig_node->orig, orig_node);

	prof_stop(PROF_find_or_create_orig_node_in_avl);
	return orig_node;
}

//wird aufgerfen um:
//1 alle orig_nodes zu loeschen curr_time=0, bif=0
//2 um all alten orig_nodes zu loeschen, geal welches if; curr_time>0; bif=0
//3 um alle orig_nodes zu loeschen, die ueber ein bestimmtes interface
//  if rein kamen.if kann sich aendern, je nach Weg der ogm
//4 sonst: wenn keine dieser geziehlten ereignisse aufgetreten ist
//  wird von batman.c diese funktion nur mit curr_time aufgerufen.
//  wenn diese nicht abgelaufen ist (was den punkt 2 betrifft), so
//  wird nur geprueft, ob in der neighbour liste abgelaufene eintraege
//  liegen und diese aus neighbour liste geloescht.
//  die avl-liste bleibt wie sie ist
// curr_time = batman_time (milli seconds)
void purge_orig(batman_time_t curr_time, struct batman_if *bif)
{
	prof_start(PROF_purge_originator);
	struct orig_node *orig_node = NULL;
	struct avl_node *an;
	static char neigh_str[ADDR_STR_LEN];
  int purge_old = 0;

	dbgf_all(0, DBGT_INFO, "%llu %s", (unsigned long long)curr_time, bif ? bif->dev : "???");

	//checkIntegrity();

	/* for all origins... */
	uint32_t orig_ip = 0;

	while ((orig_node = (struct orig_node *)((an = avl_next(&orig_avl, &orig_ip)) ? an->object : NULL)))
	{
		orig_ip = orig_node->orig;

		purge_old = ((orig_node->last_aware + (1000 * ((batman_time_t)purge_to))) < curr_time) ? 1 : 0;

//		dbgf_all(0, DBGT_INFO, "cur: %llu last: %llu bif: %s ori: %s purge_to: %llu purge_old: %d",
//		  (unsigned long long)curr_time, (unsigned long long) orig_node->last_aware,
//			bif ? bif->dev : "???", orig_node->orig_str, (1000 * ((batman_time_t)purge_to)),
//			purge_old	);

		// purge_orig(0, NULL)  - flush all ifaces
		// purge_orig(0, bif)   - flush specific iface
		// purge_orig( *, * )   - delete if old
//Hier gehts es um die orig_nodes die geloescht werden
		if (!curr_time || bif || purge_old )
		{
			/* purge outdated originators completely */

			dbgf_all(1, DBGT_INFO, "originator timeout -> purge %s, last_valid %llu",
							 orig_node->orig_str, (unsigned long long)orig_node->last_valid_time);

			flush_orig(orig_node, bif);

//SE: siehe commentare unten
			if (!bif && ( 		(!curr_time && orig_node->pog_refcnt == 0) 		// if flush ( purge_orig(0, NULL) )
										|| 	(purge_old && orig_node->pog_refcnt == 0) ))  // if old  (  purge_orig(curr_time, NULL) )
			{
				flush_tun_orig(orig_node);
			}

			//remove all neighbours of this originator ...
			OLForEach(neigh_node, struct neigh_node, orig_node->neigh_list_head)
			{
				if (!bif || (neigh_node->key.iif == bif))
				{
					LIST_ENTRY *prev = OLGetPrev(neigh_node);
					OLRemoveEntry(neigh_node);

					//remove neighbour also from avl tree
					avl_remove(&orig_node->neigh_avl, &neigh_node->key);

					debugFree(neigh_node, 1403);
					neigh_node = (struct neigh_node *)prev;
				}
			}

			/* remove link information of node */
      // der aktuelle node ist ein direkter nachbar zum uns und hat damit
			// eine Liste von hinterfaces (meine), uber die dieser node erreichbar ist.
			// ebenso wird dieser node in der globalen link_list und globale avl baum
			// f�r direkte nachbarn gehalten und muessen ebenso geloescht werden.

			if (orig_node->link_node)
				free_link_node(orig_node, bif);

			//loesche orig_node in avl nur bei
			// -alte knoten (purge_orig(batman_time, NULL))
			// -all cleanup fuer ein interface (purge_orig(0, bif)
			// -all cleanup (purge_orig(0, NULL)
			//
			// ABER nur wenn alle referencen zu diesen knoten aufgeloest sind.
			// Das ist der fall, wenn es sich um ein "angehaengten" node handelt von einem
			// link-interface, der auf den haupt originator verweisst.
			// Wenn  die reihenfolge bloed ist,
			// so dass der "haupt node" auf den referenziert wird
			// ausgelassen wird, so wuerde hier ein memleak
			// entstehen (vorallem wenn bmxd beendet wird.)
			// um das aufzuloesen, muss in diesem fall
			// orig_ip=0 gesetzt werden, damit die schleife
			// nochmal von startet.

			if (!bif && ( 		(!curr_time && orig_node->pog_refcnt == 0) 		// if flush
										|| 	(purge_old && orig_node->pog_refcnt == 0) ))	// if old
			{
				// gib die ID wieder frei, diese wird auch in einer liste von ids gehalten
				// und die id kann dann wieder verwendet werden.
				if (orig_node->id4him)
					free_pifnb_node(orig_node);

				// when alles "ge-flusht" wird, dann sollen alle orig_nodes im avl-tree
				// geloescht werden.
				// Da aber ein nicht-primary-orig_node auf einen primary referenziert
				// muss dieser primary_node erst dann geloescht werden, wenn dessen
				// ref-counter == 0 ist.
				// Es kommt vor, dass dieser primary_node in der reihenfolge im avl-tree
				// eher betrachtet wird. dieser muss erstmal ignoriert werden, da
				// sonst die referenz-pointer ins nowana zeigen wuerden. das gilt besonsers
				// auch fuer curr_gateway strukturen.
				//
				// damit bei einem "flush" letztlich auch die primary orig_node geloescht
				// werden, muss der refcount ueberwacht werden. Sobald der letzte nicht-primary
				// orgin_node geloescht wird, muss der avl-tree wieder von vorn beginnen, um
				// letztlich das primary orgin_node ebenfalls zu loeschen.
				//
				// dieser "reset" darf aber nur fuer "flush" operationen gelten,
				// da wenn nur "outdated" orig_nodes geloescht werden sollen, nicht automatisch
				// wieder die schleife von vorn beginnen muss/braucht. "outdated" primary orign_nodes
				// werden dann beim naechsten mal entfernt.
				// ein "reset" wuerde hier die laufzeit nur erhohen und bereits geteste
				// orign_nodes erneut testen.
				if(!curr_time 		// nur bei "flush"
							&& orig_node->primary_orig_node
							&& orig_node->primary_orig_node->pog_refcnt == 1)
				{
					orig_ip = 0; // restart loop and get first entry. because all non-primary node
					 // objects are removed and primary node object (of the node which should be deleted)
					 // has no references anymore and is delete last.
				}

				//SE: when curr_time is zero then all data is destroyed
				//in this case the orig
				set_primary_orig(orig_node, 0);

				avl_remove(&orig_avl, /*(uint32_t*)*/ &orig_node->orig);

				debugFree(orig_node, 1402);
			}
		}
		else
		{
//hier geht es um orig_nodes-nachhbarn. Also die nachbar nodes fuer diesen
// aktuellen orgi_node, wo interfaces wegfallen und die entfernt werden.
//und um 	die nachbarn selbst, die dann entfernt werden fuer diesen origi_node
			// nur direkte nachbarn
			if (orig_node->link_node)
			{
				uint8_t free_ln = YES;

				// when removing entries, I can modify lndev (because OLForEach() is a macro)
				//
				// pruefe alle interaces eines direkten nachbarn node , und entferne die lokalen interfaces,
				// die keine daten mehr fuer diese nachbarn geliefert haben.
				OLForEach(lndev, struct link_node_dev, orig_node->link_node->lndev_list)
				{
					if ( (lndev->last_lndev + (1000 * ((batman_time_t)purge_to))) < curr_time )
					{
						PLIST_ENTRY prev = OLGetPrev(lndev);

						dbgf(DBGL_CHANGES, DBGT_INFO,
								 "purging lndev %16s %10s %s",
								 orig_node->orig_str, lndev->bif->dev, lndev->bif->if_ip_str);
						OLRemoveEntry(lndev);
						debugFree(lndev, 1429);
						lndev = (struct link_node_dev *)prev;
					}
					else
					{
						free_ln = NO;
					}
				}

				// link_node freigeben,wenn es keine interface mehr gibt, weil die
				// zu alt waren
				if (free_ln)
					free_link_node(orig_node, NULL);
			}

			/* purge outdated PrimaryInterFace NeighBor Identifier */
			if (orig_node->id4him && (orig_node->last_pog_link + (1000 * ((batman_time_t)purge_to))) < curr_time)
				free_pifnb_node(orig_node);

			/* purge outdated neighbor nodes, except our best-ranking neighbor */

			/* for all neighbours towards this originator ... */
//SE: ??? evt ist gemeint, gehe durch alle meine nachbarn, ueber die der orig_node
// erreichbar ist.
// pruefe welcher dieser nachbarn zu alt ist, und entferne diesen fuer diesen orig_node,
// da dieser nachbar nicht mehr verfuegbar ist.
//
// Frage, warum sollte hier ein ein nachbar ignroiert werden, wenn die router (nexthop)
// dieser nachbar ist?
// solte hier nicht diese bedingung raus sein, damit dieser tote nachbar auch geloscht
// wird?
// und zusatzlich sollte in diesem fall der router neu gesetzt werden?
			OLForEach(neigh_node, struct neigh_node, orig_node->neigh_list_head)
			{
#if 0 //original
				if (    (neigh_node->last_aware + (1000 * ((batman_time_t)purge_to))) < curr_time
				     &&	orig_node->router != neigh_node
					 )
				{
#else
				if ( (neigh_node->last_aware + (1000 * ((batman_time_t)purge_to))) < curr_time )
				{

				 // router nicht mehr nutztbar, da nachbar tot ist
				 if( orig_node->router == neigh_node )
				 {
//dbg(DBGL_SYS, DBGT_INFO,"purge-timeout: last: %llu, purge_to: %lu, curr:%llu", neigh_node->last_aware, purge_to, curr_time);

						update_routes(orig_node, NULL);
						flush_tun_orig(orig_node);
				 }
#endif
					addr_to_str(neigh_node->key.addr, neigh_str);
					dbgf_all(0, DBGT_INFO,
									 "Neighbour timeout: originator %s, neighbour: %s, last_aware %u",
									 orig_node->orig_str, neigh_str, neigh_node->last_aware);

					PLIST_ENTRY prev = OLGetPrev(neigh_node);
					OLRemoveEntry(neigh_node);

					avl_remove(&orig_node->neigh_avl, &neigh_node->key);

					debugFree(neigh_node, 1403);
					neigh_node = (struct neigh_node *)prev;
				}
			}
		}
	}

	//checkIntegrity();

	prof_stop(PROF_purge_originator);
}

struct link_node_dev *get_lndev(struct link_node *ln, struct batman_if *bif, uint8_t create)
{
	struct link_node_dev *lndev;

	OLForEach(lndev, struct link_node_dev, ln->lndev_list)
	{
		if (lndev->bif == bif)
			return lndev;
	}

	if (!create)
		return NULL;

	lndev = debugMalloc(sizeof(struct link_node_dev), 429);

	memset(lndev, 0, sizeof(struct link_node_dev));

	OLInitializeListHead(&lndev->list);
	lndev->bif = bif;

	dbgf(DBGL_CHANGES, DBGT_INFO, "creating new lndev %16s %10s %s",
			 ln->orig_node->orig_str, bif->dev, bif->if_ip_str);

	OLInsertTailList(&ln->lndev_list, &lndev->list);

	return lndev;
}

int tq_rate(struct orig_node *orig_node_neigh, struct batman_if *iif, int range)
{
	int rtq, rq, tq;
	struct link_node_dev *lndev;

	if (orig_node_neigh->link_node == NULL)
		return 0;

	if (!(lndev = get_lndev(orig_node_neigh->link_node, iif, NO /*create*/)))
		return 0;

	rtq = lndev->rtq_sqr.wa_val;

	rq = lndev->rq_sqr.wa_val;

	if (rtq <= 0 || rq <= 0)
		return 0;

	tq = ((range * rtq) / rq);

	return MIN(tq, range);
}

void process_ogm(struct msg_buff *mb)
{
	prof_start(PROF_process_ogm);

	struct orig_node *orig_node, *orig_node_neigh;
	struct link_node_dev *lndev = NULL;

	struct batman_if *iif = mb->iif;
	uint32_t neigh = mb->neigh; //IP
	struct bat_packet_ogm *ogm = mb->ogm;

	uint16_t oCtx = 0;

	oCtx |= (Asocial_device) ? IS_ASOCIAL : 0;
	oCtx |= (ogm->flags & UNIDIRECTIONAL_FLAG) ? HAS_UNIDIRECT_FLAG : 0;
	oCtx |= (ogm->flags & DIRECTLINK_FLAG) ? HAS_DIRECTLINK_FLAG : 0;
	oCtx |= (ogm->flags & CLONED_FLAG) ? HAS_CLONED_FLAG : 0;

	// when orig ip that comes from neighbour is the same as the source ip than the neighbour
	// must be directly connected.
	// The ogm for the neighbours interface was created/scheduled directly and not rebroadcasted.
	// This means that the ttl==1 which is not decremented before sending.
	// re-brodcasted ogms gets its ttl-- before sending. this can be seen if another node rebroadcasts
	// an ogm. ttl is then zero and the ogm will be ignored.
  //
	// ABER. ogm->orig ist ja die IP des knotens und neigh die ip vom gesendeten interface.
	// wenn also 10.200.4.100 in der ogm->orig sendet, aber das vom neigh=10.201.4.100 , wird hier
	// der knoten nicht aktzeptiert. das sieht man dann am log "drop OGM: rcvd via unknnown neighbor (not direct)"
	// es muss also erstmal eine ogm mit 10.201.4.100 kommen, damit dann die 10.200.4.100 akzeptiert wird.
	 oCtx |= (ogm->orig == neigh) ? IS_DIRECT_NEIGH : 0;

	dbgf_all(2, DBGT_INFO, "OG %s (via IF %s %s) NB %s  "
											"V %d SQN %d TTL %d DirectF %d UniF %d  CloneF %d, directNB %d, asocial %d(%d)",
					 ipStr(ogm->orig), iif->dev, iif->if_ip_str, mb->neigh_str,
					 COMPAT_VERSION, ogm->ogm_seqno, ogm->ogm_ttl,
					 (oCtx & HAS_DIRECTLINK_FLAG), (oCtx & HAS_UNIDIRECT_FLAG),
					 (oCtx & HAS_CLONED_FLAG), (oCtx & IS_DIRECT_NEIGH), (oCtx & IS_ASOCIAL), Asocial_device);

	if (ogm->ogm_pws < MIN_PWS || ogm->ogm_pws > MAX_PWS)
	{
		dbg_mute(2, 30, DBGL_SYS, DBGT_WARN, "drop OGM: %s unsopported path window size %d !",
						 ipStr(ogm->orig), ogm->ogm_pws);
		goto process_ogm_end;
	}

	OLForEach(bif, struct batman_if, if_list)
	{
		//eine OGM, welche von einem meiner interfaces verschickt wurde und auf
		//einem anderen wieder empfangen wurde

		if (neigh == bif->if_addr)
		{
			dbgf_all(2, DBGT_INFO, "drop OGM: rcvd my own broadcast via: %s", mb->neigh_str);
			goto process_ogm_end;
		}

		if (neigh == bif->if_broad)
		{
			dbg_mute(2, 30, DBGL_SYS, DBGT_WARN, "drop OGM: %s ignoring all packets with broadcast source IP",
							 mb->neigh_str);
			goto process_ogm_end;
		}
		//der absender (erfinder der ogm) hat die gleiche ip wie eines meiner interfaces. also
		//ist das meine ogm. kann eine 10.201.x.y sein (vom non-primary iface aber vom primary ))
		if (ogm->orig == bif->if_addr)
		{
			oCtx |= IS_MY_ORIG;
			break;
		}
	} //OLForEach(bif, struct batman_if, if_list)

	// ein neighbour antwortet mir mit unidirect flag und direct flag wenn er feststellt,
	// dass meine ogm-ip auch von einem interface mit gleicher IP ageschickt wurde.
	// Falls das nicht so ist, ist das packet nicht fuer mich.
	if (oCtx & HAS_UNIDIRECT_FLAG && !(oCtx & IS_MY_ORIG))
	{
		dbgf_all(2, DBGT_INFO, "drop OGM: unidirectional flag and not my OGM");
		goto process_ogm_end;
	}

	//suche den nachbar, der mir die ogm weitergeleitet hat. wenn nicht in meiner liste
	//dann ist das die erste ogm und es wird ein eintrag im avl-tree gespeichert.
	orig_node_neigh = find_or_create_orig_node_in_avl(neigh);

	if (!(oCtx & IS_DIRECT_NEIGH) && !(orig_node_neigh->last_valid_time))
	{
		dbgf_all(2, DBGT_INFO, "drop OGM: rcvd via unknown neighbor!");
		goto process_ogm_end;
	}

	if ((oCtx & HAS_CLONED_FLAG) && !orig_node_neigh->primary_orig_node)
	{
		dbgf_all(2, DBGT_INFO, "drop OGM: first contact with neighbor MUST be without cloned flag!");
		goto process_ogm_end;
	}

	if (orig_node_neigh->link_node)
		lndev = get_lndev(orig_node_neigh->link_node, iif, NO /*create*/);

  //meine eigene ogm ist zurueck gekommen, somit kann ich jetzt rtq brechnen (link quality)
	if (oCtx & IS_MY_ORIG)
	{
		update_rtq_link(orig_node_neigh, oCtx, mb, iif, ogm, lndev);
		goto process_ogm_end;
	}

	// ttl einer ogm wird nur durch re-broadcasts runtergezahlt. da ogm eines interfaces (primar 50) und
	// fuer ein link interface ttl==1 ist, muss das eine rebroadcasted ogm sein.
	// das kann eine sein, die ueber einen anderen re-broadcasted wurde, oder auch von dem directen nachbarn,
	// was ich erwarten wuerde.
	if (ogm->ogm_ttl == 0)
	{
		dbgf_all(2, DBGT_INFO, "drop OGM: TTL of zero!");
		goto process_ogm_end;
	}

	if (lndev && lndev->rtq_sqr.wa_val > 0)
		oCtx |= IS_BIDIRECTIONAL;

	// drop packet if sender is not a direct NB and if we have no route towards the rebroadcasting NB
	if (!(oCtx & IS_DIRECT_NEIGH) && !(orig_node_neigh->router))
	{
		dbgf_all(2, DBGT_INFO, "drop OGM: %s via unknown (%s) (non-direct) neighbor!", ipStr(ogm->orig), mb->neigh_str);
		goto process_ogm_end;
	}

	if (!(oCtx & IS_DIRECT_NEIGH))
	{
		if (!orig_node_neigh->primary_orig_node || !orig_node_neigh->primary_orig_node->id4me)
		{
			dbgf_all(2, DBGT_INFO, "drop OGM: %s via NB %s %s (primary_orig_node 0x%p, id4me=%d, str=%s)!!!!",
							 ipStr(ogm->orig), mb->neigh_str, "with unknown primaryOG", orig_node_neigh->primary_orig_node,
							 orig_node_neigh->primary_orig_node ? orig_node_neigh->primary_orig_node->id4me : 123456, orig_node_neigh->primary_orig_node->orig_str);
			goto process_ogm_end;
		}

		if (drop_2hop_loop &&
				orig_node_neigh->primary_orig_node &&
				orig_node_neigh->primary_orig_node->id4me == ogm->prev_hop_id)
		{
			dbgf_all(2, DBGT_INFO, "drop OGM: %s via NB %s %s !!!!",
							 ipStr(ogm->orig), mb->neigh_str, " via two-hop loop ");
			goto process_ogm_end;
		}
	}

	mb->orig_node = orig_node =
			(oCtx & IS_DIRECT_NEIGH) ? orig_node_neigh : find_or_create_orig_node_in_avl(ogm->orig);

	char *ndev = NULL;
	if(orig_node_neigh && orig_node_neigh->router && orig_node_neigh->router->key.iif)
	{ndev = orig_node_neigh->router->key.iif->dev;}

	if (validate_orig_seqno(orig_node, neigh, ndev, ogm->ogm_seqno) == FAILURE)
	{
		dbgf_all(2, DBGT_WARN, "drop OGM: %15s, via NB %15s, SQN %i\n",
						 ipStr(ogm->orig), mb->neigh_str, ogm->ogm_seqno);
		goto process_ogm_end;
	}

	if (validate_primary_orig(orig_node, mb, oCtx) == FAILURE)
	{
		dbg(DBGL_SYS, DBGT_WARN, "drop OGM: primary originator %15s/if conflict!",
				ipStr(ogm->orig));
		goto process_ogm_end;
	}

	if (validate_considered_order(orig_node, ogm->ogm_seqno, ogm->ogm_ttl, neigh, iif) == FAILURE)
	{
		dbgf_all(2, DBGT_INFO, "drop OGM: already considered this OGM and SEQNO %d, ttl %d via this link neighbor!", ogm->ogm_seqno, ogm->ogm_ttl);
		goto process_ogm_end;
	}

	uint16_t rand_100 = rand_num(100);

	addr_to_str(ogm->orig, mb->orig_str);

	if (((SQ_TYPE)(orig_node->last_valid_sqn - ogm->ogm_seqno)) >= orig_node->pws)
	{
		// we've never seen a valid sqn of this size before, therefore:
		// everything which is out of our current path-window is new!
		oCtx |= IS_NEW;

		// estimating average originaotr interval of this node
		if (orig_node->last_valid_time && orig_node->last_valid_time < batman_time )
		{
			if (((SQ_TYPE)(ogm->ogm_seqno - (orig_node->last_wavg_sqn + 1))) < orig_node->pws)
			{
				upd_wavg(&orig_node->ogi_wavg,
								 ((batman_time - orig_node->last_valid_time) /
									(ogm->ogm_seqno - orig_node->last_wavg_sqn)),
								 OGI_WAVG_EXP);
			}

			orig_node->last_wavg_sqn = ogm->ogm_seqno;
		}

		orig_node->last_valid_sqn = ogm->ogm_seqno;
		orig_node->last_valid_time = batman_time;
	}
	else if (((SQ_TYPE)(orig_node->last_valid_sqn - ogm->ogm_seqno)) <= my_path_lounge)
	{
		// everything else which is still within SQN_ENTRY_QUEUE is acceptable
		oCtx |= IS_ACCEPTABLE;
	}

	//MUST be after validate_primary_orig()
	update_rq_link(orig_node, ogm->ogm_seqno, iif, oCtx);

	int tq_rate_value = tq_rate(orig_node_neigh, iif, PROBE_RANGE);

	if ((oCtx & IS_BIDIRECTIONAL) &&
			((oCtx & IS_NEW) || (oCtx & IS_ACCEPTABLE)) &&
			rand_100 >= my_hop_penalty &&
			//	     rand_100  <=  (MAX_ASYM_WEIGHT - asym_weight)  +  ( (tq_power(tq_rate_value,PROBE_RANGE)/PROBE_TO100) * 99) / 100    )
			rand_100 <= (MAX_ASYM_WEIGHT - my_asym_weight) + ((tq_power(tq_rate_value, PROBE_RANGE) / PROBE_TO100)))
	{
		// finally we only accept OGMs with probability TQ of its incoming link
		// tq_power() returns value between [0..PROBE_RANGE]. return value of PROBE_RANGE means 100% acceptance
		oCtx |= IS_ACCEPTED;
	}

	struct neigh_node *old_router = orig_node->router;

	struct neigh_node *new_router = update_orig(orig_node, &oCtx, mb);

	if (old_router != new_router)
		update_routes(orig_node, new_router);

	if (!new_router || new_router != orig_node->router)
	{
		dbgf_all(2, DBGT_INFO, //as long as incoming link is not bidirectional,...
						 "new_rt %s for %s is zero or differs from installed rt %s  "
						 "(old_rt %s  rcvd via %s %s",
						 ipStr(new_router ? new_router->key.addr : 0),
						 orig_node->orig_str,
						 ipStr(orig_node->router ? orig_node->router->key.addr : 0),
						 ipStr(old_router ? old_router->key.addr : 0), mb->neigh_str, mb->iif->dev);
	}

	process_tun_ogm(mb, oCtx, old_router);

	dbgf_all(2, DBGT_INFO,
					 "done OGM accepted %s  acceptable %s  bidirectLink %s  new %s  BNTOG %s  asocial %s(%d)  tq %d  "
					 "hop_penalty %d  asym_w %d  acceptSQN %d  rcvdSQN %d  rand100 %d",
					 (oCtx & IS_ACCEPTED ? "Y" : "N"),
					 (oCtx & IS_ACCEPTABLE ? "Y" : "N"),
					 (oCtx & IS_BIDIRECTIONAL ? "Y" : "N"),
					 (oCtx & IS_NEW ? "Y" : "N"),
					 (oCtx & IS_BEST_NEIGH_AND_NOT_BROADCASTED ? "Y" : "N"),
					 (oCtx & IS_ASOCIAL ? "Y" : "N"), Asocial_device,
					 tq_rate_value, my_hop_penalty, my_asym_weight, orig_node->last_accepted_sqn, ogm->ogm_seqno, rand_100);

	// either it IS_DIRECT_NEIGH, then validate_primary_orig() with orig_node=orig_neigh_node has been called
	//or NOT IS_DIRECT_NEIGH, then if orig_node_neigh->primary_orig_node == NULL it has been dropped
	paranoia(-500014, (!orig_node_neigh->primary_orig_node));

	//paranoia( -5000151, (!orig_node_neigh->primary_orig_node->id4him) );
	if (!orig_node_neigh->primary_orig_node->id4him)
	{
		//  dbgf( DBGL_SYS, DBGT_WARN, "invalid id4him for orig %s via %s",
		//          orig_node->orig_str, mb->neigh_str );

		goto process_ogm_end;
	}

	schedule_rcvd_ogm(oCtx, orig_node_neigh->primary_orig_node->id4him, mb);

process_ogm_end:

	prof_stop(PROF_process_ogm);

	return;
}

static int32_t opt_show_origs(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	struct orig_node *orig_node;
	struct avl_node *an;
	uint16_t batman_count = 0;

	int rq, tq, rtq;

	if (cmd == OPT_APPLY)
	{
		if (!strcmp(opt->long_name, ARG_ORIGINATORS))
		{
			int nodes_count = 0, sum_packet_count = 0, sum_recent_count = 0;
			int sum_lvld = 0, sum_last_pws = 0, sum_ogi_avg = 0;
			int sum_reserved_something = 0, sum_route_changes = 0, sum_hops = 0;

			dbg_printf(cn, "Originator      outgoingIF bestNextHop      TQ(rcnt) "
										 "knownSince lsqn(diff) lvld pws ~ogi cpu hop\n");
			uint32_t orig_ip = 0;

			while ((orig_node = (struct orig_node *)((an = avl_next(&orig_avl, &orig_ip)) ? an->object : NULL)))
			{
				orig_ip = orig_node->orig;

				if (!orig_node->router || orig_node->primary_orig_node != orig_node)
				{
					continue;
				}

				nodes_count++;
				batman_count++;

				dbg_printf(cn, "%-15s %-15s %-15s %3i %3i  %s %5i %3i %5i %3i %4i %3i %3i\n",
									 orig_node->orig_str, orig_node->router->key.iif->dev,
									 ipStr(orig_node->router->key.addr),
									 orig_node->router->longtm_sqr.wa_val / PROBE_TO100,
									 orig_node->router->recent_sqr.wa_val / PROBE_TO100,
									 //				            estimated_rcvd > 100 ? 100 : estimated_rcvd,
									 get_human_uptime(orig_node->first_valid_sec, 0),
									 orig_node->last_valid_sqn,
									 orig_node->router->longtm_sqr.wa_clr_sqn - orig_node->last_valid_sqn,
									 (batman_time - orig_node->last_valid_time) / 1000,
									 orig_node->pws,
									 WAVG(orig_node->ogi_wavg, OGI_WAVG_EXP),
									 orig_node->ogm_misc,
									 (Ttl + 1 - orig_node->last_path_ttl));

				sum_packet_count += orig_node->router->longtm_sqr.wa_val / PROBE_TO100; /* accepted */
				sum_recent_count += orig_node->router->recent_sqr.wa_val / PROBE_TO100; /* accepted */
																																								//				sum_rcvd_all_bits+= MIN( estimated_rcvd, 100 );
				sum_lvld += (batman_time - orig_node->last_valid_time) / 1000;
				sum_last_pws += orig_node->pws;
				sum_ogi_avg += WAVG(orig_node->ogi_wavg, OGI_WAVG_EXP);
				sum_reserved_something += orig_node->ogm_misc;
				sum_route_changes += orig_node->rt_changes;
				sum_hops += (Ttl + 1 - orig_node->last_path_ttl);
			}

			dbg_printf(cn, "%8d %-33s %3i %3i                        %5i %3i %4i %3i %3i\n",
								 nodes_count, "known Originator(s), averages: ",
								 (nodes_count > 0 ? (sum_packet_count / nodes_count) : -1),
								 (nodes_count > 0 ? (sum_recent_count / nodes_count) : -1),
								 //			            (nodes_count > 0 ? ( sum_rcvd_all_bits / nodes_count ) : -1 ),
								 (nodes_count > 0 ? (sum_lvld / nodes_count) : -1),
								 (nodes_count > 0 ? (sum_last_pws / nodes_count) : -1),
								 (nodes_count > 0 ? (sum_ogi_avg / nodes_count) : -1),
								 (nodes_count > 0 ? (sum_reserved_something / nodes_count) : -1),
								 (nodes_count > 0 ? (sum_hops / nodes_count) : -1));
		}
		else if (!strcmp(opt->long_name, ARG_STATUS))
		{
			dbg_printf(cn, "BMX %s%s, "
										 "%s, LWS %i, PWS %i, OGI %4ims, "
										 "UT %s, CPU %d.%1d\n",
								 SOURCE_VERSION,
								 (strncmp(REVISION_VERSION, "0", 1) != 0 ? REVISION_VERSION : ""),
								 ipStr(primary_addr),
								 local_lws, my_pws, my_originator_interval,
								 get_human_uptime(0, 1),
								 s_curr_avg_cpu_load / 10, s_curr_avg_cpu_load % 10);
		}
		else if (!strcmp(opt->long_name, ARG_LINKS))
		{
			dbg_printf(cn, "Neighbor        viaIF           Originator      RTQ  RQ  TQ     "
										 "  lseq lvld rid nid\n");

			uint32_t orig_ip = 0;
			struct link_node *ln;

			while ((ln = (struct link_node *)((an = avl_next(&link_avl, &orig_ip)) ? an->object : NULL)))
			{
				orig_ip = ln->orig_addr;
				orig_node = ln->orig_node;

				if (!orig_node->router)
					continue;

				OLForEach(lndev, struct link_node_dev, ln->lndev_list)
				{
					rq = lndev->rq_sqr.wa_val;
					tq = tq_rate(orig_node, lndev->bif, PROBE_RANGE);
					rtq = lndev->rtq_sqr.wa_val;

					dbg_printf(cn, "%-15s %-15s %-15s %3i %3i %3i      %5i %4i %3d %3d\n",
										 orig_node->orig_str, lndev->bif->dev,
										 orig_node->primary_orig_node ? orig_node->primary_orig_node->orig_str : "???",
										 rtq / PROBE_TO100, rq / PROBE_TO100, tq / PROBE_TO100,
										 //  accepted and rebroadcasted:
										 //  orig_node->router->accepted_sqr.wa_val/PROBE_TO100,
										 //  estimated_rcvd > 100 ? 100 : estimated_rcvd,
										 //  get_human_uptime( orig_node->first_valid_sec ),
										 orig_node->last_valid_sqn,
										 //					            ( batman_time - orig_node->last_valid_time)/1000,
										 (batman_time - lndev->last_lndev) / 1000,
										 (orig_node->primary_orig_node ? orig_node->primary_orig_node->id4me : -1),
										 (orig_node->primary_orig_node ? orig_node->primary_orig_node->id4him : -1));
				}
			}
		}
		else if (!strcmp(opt->long_name, ARG_ROUTES))
		{
			dbg_printf(cn, "%-16s brc %16s [%10s]  %20s ... [MainIF/IP: %s/%s, UT: %s]\n",
								 "Originator", "Nexthop", "outgoingIF", "Potential nexthops",
								 primary_if ? primary_if->dev : "--",
								 ipStr(primary_addr),
								 get_human_uptime(0, 1));

			uint32_t orig_ip = 0;

			while ((orig_node = (struct orig_node *)((an = avl_next(&orig_avl, &orig_ip)) ? an->object : NULL)))
			{
				orig_ip = orig_node->orig;

				if (!orig_node->router || orig_node->primary_orig_node != orig_node)
					continue;

				dbg_printf(cn, "%-15s (%3i) %15s [%10s] ",
									 orig_node->orig_str,
									 orig_node->router->longtm_sqr.wa_val / PROBE_TO100,
									 ipStr(orig_node->router->key.addr),
									 orig_node->router->key.iif->dev);

				OLForEach(neigh_node, struct neigh_node, orig_node->neigh_list_head)
				{
					if (neigh_node->key.addr != orig_node->router->key.addr)
					{
						dbg_printf(cn, " %15s (%3i)",
											 ipStr(neigh_node->key.addr),
											 neigh_node->longtm_sqr.wa_val / PROBE_TO100);
					}
				}

				dbg_printf(cn, "\n");
			}
		}
		else
		{
			return FAILURE;
		}

		dbg_printf(cn, "\n");
	}

	return SUCCESS;
}

static int32_t opt_dev_show(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{

	if (cmd == OPT_APPLY)
	{
		OLForEach(bif, struct batman_if, if_list)
		{
			dbg_cn(cn, DBGL_ALL, DBGT_NONE, "%-10s %5d %8s %15s/%-2d  brc %-15s  SQN %5d  TTL %2d  %11s  %8s  %11s",
						 bif->dev,
						 bif->if_index,
						 !bif->if_active ? "-" : (bif->if_linklayer == VAL_DEV_LL_LO ? "loopback" : (bif->if_linklayer == VAL_DEV_LL_LAN ? "ethernet" : (bif->if_linklayer == VAL_DEV_LL_WLAN ? "wireless" : "???"))),
						 bif->if_ip_str,
						 bif->if_prefix_length,
						 ipStr(bif->if_broad),
						 bif->if_seqno,
						 bif->if_ttl,
						 bif->if_hide_interface ? "hide" : "visible",
						 bif->if_active ? "active" : "inactive",
						 bif == primary_if ? "primary" : "non-primary");
		}
	}
	return SUCCESS;
}

static int32_t opt_dev(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	struct batman_if *bif = NULL;

	struct batman_if test_bif;

	char *colon_ptr;

	dbgf_all(0, DBGT_INFO, "cmd: %s opt: %s  instance %s",
					 opt_cmd2str[cmd], opt->long_name, patch ? patch->p_val : "");

	if (cmd == OPT_CHECK || cmd == OPT_APPLY)
	{
		if (strlen(patch->p_val) >= IFNAMSIZ)
		{
			dbg_cn(cn, DBGL_SYS, DBGT_ERR, "dev name MUST be smaller than %d chars", IFNAMSIZ);
			return FAILURE;
		}

		OLForEach(tmp_bif, struct batman_if, if_list)
		{
			bif = tmp_bif;
			if (wordsEqual(bif->dev, patch->p_val))
				break;
			bif = NULL;
		}

		if (patch->p_diff == DEL)
		{
			if (bif && primary_if == bif)
			{
				dbg_cn(cn, DBGL_SYS, DBGT_ERR,
							 "primary interface %s %s can not be removed!",
							 bif->dev, bif->if_ip_str);

				return FAILURE;
			}
			else if (bif && cmd == OPT_APPLY)
			{
				if (bif->if_active)
					if_deactivate(bif);

				remove_outstanding_ogms(bif);

				LIST_ENTRY *prev = OLGetPrev(bif);

				OLRemoveEntry(bif);

				debugFree(bif, 1214);
				bif = (struct batman_if *)prev;

				return SUCCESS;
			}
			else if (!bif)
			{
				dbgf_cn(cn, DBGL_SYS, DBGT_ERR, "Interface does not exist!");
				return FAILURE;
			}
		}

		if (!bif)
		{
			if (cmd == OPT_APPLY)
			{
				bif = debugMalloc(sizeof(struct batman_if), 206);
				memset(bif, 0, sizeof(struct batman_if));

				if (OLIsListEmpty(&if_list))
				{
					primary_if = bif;
				}

				OLInsertTailList(&if_list, &bif->entry);
			}
			else
			{
				bif = &test_bif;
				memset(bif, 0, sizeof(struct batman_if));
			}

			bif->aggregation_out = bif->aggregation_out_buff;

			snprintf(bif->dev, wordlen(patch->p_val) + 1, "%s", patch->p_val);
			snprintf(bif->dev_phy, wordlen(patch->p_val) + 1, "%s", patch->p_val);

			/* if given interface is an alias record physical interface name*/
			if ((colon_ptr = strchr(bif->dev_phy, ':')) != NULL)
				*colon_ptr = '\0';

			dbgf_all(0, DBGT_INFO, "assign dev %s physical name %s", bif->dev, bif->dev_phy);

			bif->if_seqno_schedule = batman_time;

			bif->if_seqno = (primary_if && primary_if != bif) ? primary_if->if_seqno : my_seqno;

			bif->aggregation_len = sizeof(struct bat_header);

			// some configurable interface values - initialized to unspecified:
			bif->if_ttl_conf = -1;
			bif->if_send_clones_conf = -1;
			bif->if_linklayer_conf = -1;
			bif->if_hide_interface_conf = -1;
		}

		if (cmd == OPT_CHECK)
			return SUCCESS;

		OLForEach(c, struct opt_child, patch->childs_instance_list)
		{
			int32_t val = c->c_val ? strtol(c->c_val, NULL, 10) : -1;

			if (!strcmp(c->c_opt->long_name, ARG_DEV_TTL))
			{
				bif->if_ttl_conf = val;
			}
			else if (!strcmp(c->c_opt->long_name, ARG_DEV_CLONE))
			{
				bif->if_send_clones_conf = val;
			}
			else if (!strcmp(c->c_opt->long_name, ARG_DEV_LL))
			{
				bif->if_linklayer_conf = val;
				bif->if_conf_hard_changed = YES;
				//set linklayer also when changing argument
				bif->if_linklayer = val;
			}
			else if (!strcmp(c->c_opt->long_name, ARG_DEV_HIDE))
			{
				bif->if_hide_interface_conf = val;
			}

			bif->if_conf_soft_changed = YES;
		}
	}
	else if (cmd == OPT_POST && opt && !opt->parent_name)
	{
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

static int32_t opt_purge(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	if (cmd == OPT_APPLY)
	 	purge_orig(0, NULL); // opt_purge()

	return SUCCESS;
}

static int32_t opt_seqno(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	if (cmd == OPT_REGISTER)
	{
		my_seqno = rand_num(MAX_SEQNO);
	}
	else if (cmd == OPT_APPLY)
	{
		OLForEach(batman_if, struct batman_if, if_list)
		{
			batman_if->if_seqno = my_seqno;
		}
	}

	return SUCCESS;
}

static int32_t opt_if_soft(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	if (cmd == OPT_APPLY)
		if_conf_soft_changed = YES;

	return SUCCESS;
}

static int32_t opt_lws(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	if (cmd == OPT_APPLY)
		flush_link_node_seqnos();

	return SUCCESS;
}

static int32_t opt_gw_script(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	if (cmd == OPT_APPLY)
	{
		// check arg size
		size_t len = strlen(patch->p_val);
		if (len < 5 || len > 200) // at least 5 and max 200 characters for path
		{
			dbg_cn(cn, DBGL_SYS, DBGT_ERR, "E: script name length (5-200)");
			return FAILURE;
		}

		// free old memory
		if (gw_scirpt_name)
		{
			free(gw_scirpt_name);
		}

		// alloc
		gw_scirpt_name = malloc(len + 1);
		if (gw_scirpt_name)
		{
			strcpy(gw_scirpt_name, patch->p_val);
		}
	}

	return SUCCESS;
}


static int32_t opt_netw(uint8_t cmd, uint8_t _save, struct opt_type *opt, struct opt_parent *patch, struct ctrl_node *cn)
{
	uint32_t ip = 0;
	int32_t mask = 0;

	if (cmd == OPT_REGISTER)
	{
		inet_pton(AF_INET, DEF_NETW_PREFIX, &gNetworkPrefix);
		gNetworkNetmask = DEF_NETW_MASK;
	}
	else if (cmd == OPT_CHECK || cmd == OPT_APPLY)
	{
		if (str2netw(patch->p_val, &ip, '/', cn, &mask, 32) == FAILURE ||
				mask < MIN_NETW_MASK || mask > MAX_NETW_MASK)
		{
			return FAILURE;
		}

		if (ip != validate_net_mask(ip, mask, cmd == OPT_CHECK ? cn : 0))
		{
			return FAILURE;
		}

		if (cmd == OPT_APPLY)
		{
			gNetworkPrefix = ip;
			gNetworkNetmask = mask;
		}
	}

	return SUCCESS;
}


static struct opt_type originator_options[] =
		{
				//        ord parent long_name          shrt Attributes				*ival		min		max		default		*func,*syntax,*help

				{ODI, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
				 0, "\nProtocol options:"},

				{ODI, 5, 0, ARG_STATUS, 0, A_PS0, A_USR, A_DYN, A_ARG, A_ANY, 0, 0, 0, 0, opt_show_origs,
				 0, "show status\n"},

				{ODI, 5, 0, ARG_ROUTES, 0, A_PS0, A_USR, A_DYN, A_ARG, A_ANY, 0, 0, 0, 0, opt_show_origs,
				 0, "show routes\n"},

				{ODI, 5, 0, ARG_LINKS, 0, A_PS0, A_USR, A_DYN, A_ARG, A_ANY, 0, 0, 0, 0, opt_show_origs,
				 0, "show links\n"},

				{ODI, 5, 0, ARG_ORIGINATORS, 0, A_PS0, A_USR, A_DYN, A_ARG, A_ANY, 0, 0, 0, 0, opt_show_origs,
				 0, "show originators\n"},

				{ODI, 5, 0, ARG_DEV, 0, A_PMN, A_ADM, A_DYI, A_CFA, A_ANY, 0, 0, 0, 0, opt_dev,
				 "<interface-name>", "add or change device or its configuration, options for specified device are:"},

//SE: network filter; can be set dynamically
				{ODI, 5, 0, ARG_NETW, 0, A_PS1, A_ADM, A_INI|A_DYN, A_CFA, A_ANY, 0, 0, 0, 0, opt_netw,
		 			ARG_PREFIX_FORM, "community network. Packets with ip addresses of this network which are not known are sent to the same node which is used for internet gateway\n"},

				{ODI, 5, 0, ARG_NETWORK_ID, 0, A_PS1, A_ADM, A_INI|A_DYN, A_CFA, A_ANY, &gNetworkId, MIN_NETWORK_ID, MAX_NETWORK_ID, DEF_NETWORK_ID, 0,
				 ARG_VALUE_FORM, "set network ID"},

#ifndef LESS_OPTIONS
				{ODI, 5, ARG_DEV, ARG_DEV_TTL, 't', A_CS1, A_ADM, A_DYI, A_CFA, A_ANY, 0, MIN_TTL, MAX_TTL, DEF_TTL, opt_dev,
				 ARG_VALUE_FORM, "set TTL of generated OGMs"},

				{ODI, 5, ARG_DEV, ARG_DEV_CLONE, 'c', A_CS1, A_ADM, A_DYI, A_CFA, A_ANY, 0, MIN_WL_CLONES, MAX_WL_CLONES, DEF_WL_CLONES, opt_dev,
				 ARG_VALUE_FORM, "broadcast OGMs per ogm-interval with given probability (e.g. 200% will broadcast the same OGM twice)"},

				{ODI, 5, ARG_DEV, ARG_DEV_HIDE, 'h', A_CS1, A_ADM, A_DYI, A_CFA, A_ANY, 0, 0, 1, 0, opt_dev,
				 ARG_VALUE_FORM, "disable/enable hiding of OGMs generated to non link-neighboring nodes. Default for non-primary interfaces"},
#endif
				//stephan: allow loopback
				{ODI, 5, ARG_DEV, ARG_DEV_LL, 'l', A_CS1, A_ADM, A_DYI, A_CFA, A_ANY, 0, VAL_DEV_LL_LO, VAL_DEV_LL_WLAN, 0, opt_dev,
				 ARG_VALUE_FORM, "manually set device type for linklayer specific optimization (0=loopback, 1=lan, 2=wlan)"},

				{ODI, 5, 0, ARG_INTERFACES, 0, A_PS0, A_USR, A_DYI, A_ARG, A_ANY, 0, 0, 1, 0, opt_dev_show,
				 0, "show configured interfaces"},

				{ODI, 5, 0, ARG_LWS, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &local_lws, MIN_LWS, MAX_LWS, DEF_LWS, opt_lws,
				 ARG_VALUE_FORM, "set link window size (LWS) for link-quality calculation (link metric)"},

#ifndef LESS_OPTIONS

				{ODI, 5, 0, ARG_RTQ_LOUNGE, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &local_rtq_lounge, MIN_RTQ_LOUNGE, MAX_RTQ_LOUNGE, DEF_RTQ_LOUNGE, opt_lws,
				 ARG_VALUE_FORM, "set local LLS buffer size to artificially delay OGM processing for ordered link-quality calulation"},

				{ODI, 5, 0, ARG_PWS, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &my_pws, MIN_PWS, MAX_PWS, DEF_PWS, opt_if_soft,
				 ARG_VALUE_FORM, "set path window size (PWS) for end2end path-quality calculation (path metric)"},

				{ODI, 5, 0, ARG_PATH_LOUNGE, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &my_path_lounge, MIN_PATH_LOUNGE, MAX_PATH_LOUNGE, DEF_PATH_LOUNGE, opt_purge,
				 ARG_VALUE_FORM, "set default PLS buffer size to artificially delay my OGM processing for ordered path-quality calulation"},

				{ODI, 5, 0, ARG_PATH_HYST, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &my_path_hystere, MIN_PATH_HYST, MAX_PATH_HYST, DEF_PATH_HYST, opt_purge,
				 ARG_VALUE_FORM, "use hysteresis to delay route switching to alternative next-hop neighbors with better path metric"},

				{ODI, 5, 0, ARG_RCNT_PWS, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &my_rcnt_pws, MIN_RCNT_PWS, MAX_RCNT_PWS, DEF_RCNT_PWS, opt_purge,
				 ARG_VALUE_FORM, ""},

				/*
	{ODI,5,0,ARG_RCNT_LOUNGE,       0,  A_PS1,A_ADM,A_DYI,A_CFA,A_ANY,	&my_rcnt_lounge,MIN_RCNT_LOUNGE,MAX_RCNT_LOUNGE,DEF_RCNT_LOUNGE,opt_purge,
			ARG_VALUE_FORM, ""},
*/

				{ODI, 5, 0, ARG_RCNT_HYST, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &my_rcnt_hystere, MIN_RCNT_HYST, MAX_RCNT_HYST, DEF_RCNT_HYST, opt_purge,
				 ARG_VALUE_FORM, "use hysteresis to delay fast-route switching to alternative next-hop neighbors with a recently extremely better path metric"},

				{ODI, 5, 0, ARG_RCNT_FK, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &my_rcnt_fk, MIN_RCNT_FK, MAX_RCNT_FK, DEF_RCNT_FK, opt_purge,
				 ARG_VALUE_FORM, "configure threshold faktor for dead-path detection"},

				{ODI, 5, 0, ARG_DROP_2HLOOP, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &drop_2hop_loop, MIN_DROP_2HLOOP, MAX_DROP_2HLOOP, DEF_DROP_2HLOOP, 0,
				 ARG_VALUE_FORM, "drop OGMs received via two-hop loops"},

				{ODI, 5, 0, ARG_ASYM_EXP, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &my_asym_exp, MIN_ASYM_EXP, MAX_ASYM_EXP, DEF_ASYM_EXP, 0,
				 ARG_VALUE_FORM, "ignore OGMs (rcvd via asymmetric links) with TQ^<val> to radically reflect asymmetric-links"},

				{ODI, 5, 0, "asocial_device", 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &Asocial_device, MIN_ASOCIAL, MAX_ASOCIAL, DEF_ASOCIAL, 0,
				 ARG_VALUE_FORM, "disable/enable asocial mode for devices unwilling to forward other nodes' traffic"},

				{ODI, 5, 0, ARG_WL_CLONES, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &wl_clones, MIN_WL_CLONES, MAX_WL_CLONES, DEF_WL_CLONES, opt_if_soft,
				 ARG_VALUE_FORM, "broadcast OGMs per ogm-interval for wireless devices with\n"
												 "	given probability [%] (eg 200% will broadcast the same OGM twice)"},

				{ODI, 5, 0, ARG_ASYM_WEIGHT, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &my_asym_weight, MIN_ASYM_WEIGHT, MAX_ASYM_WEIGHT, DEF_ASYM_WEIGHT, 0,
				 ARG_VALUE_FORM, "ignore OGMs (rcvd via asymmetric links) with given probability [%] to better reflect asymmetric-links"},

				{ODI, 5, 0, ARG_HOP_PENALTY, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &my_hop_penalty, MIN_HOP_PENALTY, MAX_HOP_PENALTY, DEF_HOP_PENALTY, 0,
				 ARG_VALUE_FORM, "ignore OGMs with given probability [%] to better reflect path-hop distance"},

				// there SHOULD! be a minimal lateness_penalty >= 1 ! Otherwise a shorter path with equal path-cost than a longer path will never dominate
				{ODI, 5, 0, ARG_LATE_PENAL, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &my_late_penalty, MIN_LATE_PENAL, MAX_LATE_PENAL, DEF_LATE_PENAL, opt_purge,
				 ARG_VALUE_FORM, "penalize non-first rcvd OGMs "},

				{ODI, 5, 0, ARG_PURGE_TO, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &purge_to, MIN_PURGE_TO, MAX_PURGE_TO, DEF_PURGE_TO, 0,
				 ARG_VALUE_FORM, "timeout in seconds for purging stale originators"},

#endif
				{ODI, 5, 0, ARG_DAD_TO, 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &dad_to, MIN_DAD_TO, MAX_DAD_TO, DEF_DAD_TO, 0,
				 ARG_VALUE_FORM, "duplicate address (DAD) detection timout in seconds"},

				{ODI, 5, 0, "seqno", 0, A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &my_seqno, MIN_SEQNO, MAX_SEQNO, DEF_SEQNO, opt_seqno, 0, 0},

				{ODI, 5, 0, "ttl", 't', A_PS1, A_ADM, A_DYI, A_CFA, A_ANY, &Ttl, MIN_TTL, MAX_TTL, DEF_TTL, opt_if_soft,
				 ARG_VALUE_FORM, "set time-to-live (TTL) for OGMs of primary interface"},

				{ODI, 5, 0, "flush_all", 0, A_PS0, A_ADM, A_DYN, A_ARG, A_ANY, 0, 0, 0, 0, opt_purge,
				 0, "purge all neighbors and routes on the fly"},

				{ODI, 5, 0, ARG_GW_SCRIPT, 0, A_PS1, A_ADM, A_INI, A_ARG, A_ANY, 0, 0, 0, 0, opt_gw_script,
				 "<script-file>", "called on gw selection"}

};

void init_originator(void)
{
	OLInitializeListHead(&if_list);
	OLInitializeListHead(&pifnb_list);
	OLInitializeListHead(&link_list);

	register_options_array(originator_options, sizeof(originator_options));
}

void cleanup_originator(void)
{
	if (gw_scirpt_name)
	{
		free(gw_scirpt_name);
		gw_scirpt_name = NULL;
	}
}
