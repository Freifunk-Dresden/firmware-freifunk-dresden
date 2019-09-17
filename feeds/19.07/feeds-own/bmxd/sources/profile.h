/* Copyright (C) 2006 B.A.T.M.A.N. contributors:
 * Simon Wunderlich, Marek Lindner
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

#include <stdint.h>
#include <time.h>


#if defined PROFILE_DATA



enum {
	PROF_all,
 PROF_ipStr,
 PROF_update_routes,
 PROF_get_orig_node,
 PROF_update_originator,
 PROF_update_orig_bits,
 PROF_purge_originator,
 PROF_schedule_rcvd_ogm,
 PROF_send_outstanding_ogms,
 PROF_process_packet,
 PROF_schedule_own_ogm,
 PROF_wait4Event,
 PROF_wait4Event_select,
 PROF_wait4Event_5,
 PROF_strip_packet,
 PROF_send_aggregated_ogms,
 PROF_debugMalloc,
 PROF_debugFree,
 PROF_debugRealloc,
 PROF_cb_ogm_hooks,
 PROF_process_ogm,
 PROF_COUNT
};


struct prof_container {

	clock_t start_time;
	clock_t total_time;
	char *name;
	uint32_t calls;

};


void prof_init( int32_t index, char *name );
void prof_start( int32_t index );
void prof_stop( int32_t index );
void prof_print( struct ctrl_node *cn );
void init_profile( void );


#else 

#define prof_init( ... )
#define prof_start( ... )
#define prof_stop( ... )
#define prof_print( ... )
#define init_profile( ... )

#endif

