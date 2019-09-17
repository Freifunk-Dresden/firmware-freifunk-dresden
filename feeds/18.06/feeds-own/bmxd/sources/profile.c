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


#include <stdio.h>

#include "profile.h"


#if defined PROFILE_DATA


static struct prof_container prof_container[PROF_COUNT];

void prof_init( int32_t index, char *name ) {

	prof_container[index].total_time = 0;
	prof_container[index].calls = 0;
	prof_container[index].name = name;

}

void prof_start( int32_t index ) {

	if ( prof_container[index].start_time == 0 )
		prof_container[index].start_time = clock();

}



void prof_stop( int32_t index ) {

	if ( prof_container[index].start_time == 0)
		return;
	
	prof_container[index].calls++;
	prof_container[index].total_time += clock() - prof_container[index].start_time;
	prof_container[index].start_time = 0;

}


void prof_print( struct ctrl_node *cn ) {

	int32_t index;
	float total_cpu_time=1;
	
	dbg_printf( cn, "\nProfile data:\n" );

	for ( index = 0; index < PROF_COUNT; index++ ) {

		if( index == 0 )
			total_cpu_time = (float)prof_container[0].total_time/CLOCKS_PER_SEC;
			
		dbg_printf( cn, "   %30s:  %5.1f, cpu time = %10.3f, calls = %10i, avg time per call = %4.10f \n", 
			prof_container[index].name,
			100 * ( ((float)prof_container[index].total_time/CLOCKS_PER_SEC) / total_cpu_time ),
			(float)prof_container[index].total_time/CLOCKS_PER_SEC, 
			prof_container[index].calls, 
   			( (float)prof_container[index].calls == 0  ?  0.0  :
   			  ( ( (float)prof_container[index].total_time/CLOCKS_PER_SEC ) / (float)prof_container[index].calls ) ) );

	}
	
	dbg_printf( cn, "\n" );
}

void init_profile( void ) {
	
	/* for profiling the functions */
	prof_init( PROF_all, "all" );
	prof_init( PROF_ipStr, "ipStr" );
	prof_init( PROF_update_routes, "update_routes" );
	prof_init( PROF_get_orig_node, "get_orig_node" );
	prof_init( PROF_update_originator, "update_orig" );
	prof_init( PROF_update_orig_bits, "update_orig_bits" );
	prof_init( PROF_purge_originator, "purge_orig" );
	prof_init( PROF_schedule_rcvd_ogm, "schedule_rcvd_ogm" );
	prof_init( PROF_send_outstanding_ogms, "send_outstanding_ogms" );
	prof_init( PROF_process_packet, "process_packet" );
	prof_init( PROF_schedule_own_ogm, "schedule_own_ogm" );
	prof_init( PROF_wait4Event, "wait4Event" );
	prof_init( PROF_wait4Event_select, "wait4Event_select" );
	prof_init( PROF_wait4Event_5, "wait4Event_5" );
	prof_init( PROF_strip_packet, "strip_packet" );
	prof_init( PROF_send_aggregated_ogms, "send_aggregated_ogms" );
	prof_init( PROF_debugMalloc, "debugMalloc" );
	prof_init( PROF_debugFree, "debugFree" );
	prof_init( PROF_debugRealloc, "debugRealloc" );
	prof_init( PROF_cb_ogm_hooks, "cb_ogm_hooks" );
	prof_init( PROF_process_ogm, "process_ogm" );

}


#endif

