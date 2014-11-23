/* 
 * Copyright (C) 2006 B.A.T.M.A.N. contributors:
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

#define ARG_OGI "ogm_interval"
#define DEF_OGI 1000
#define MIN_OGI 50
#define MAX_OGI 100000
extern int32_t my_ogi; // my originator interval

#define ARG_OGI_PWRSAVE "ogi_power_save"


#define MIN_AGGR_IVAL 35
#define MAX_AGGR_IVAL 4000
#define DEF_AGGR_IVAL 500
#define ARG_AGGR_IVAL "aggreg_interval"

void init_schedule( void );
void start_schedule( void );
void change_selects( void );
void cleanup_schedule( void );
void register_task( uint32_t timeout, void (* task) (void *), void *data );
void remove_task( void (* task) (void *), void *data );
uint32_t whats_next( void );
void wait4Event( uint32_t timeout );
void schedule_own_ogm( struct batman_if *batman_if );
void debug_send_list( struct ctrl_node *cn );
void remove_outstanding_ogms( struct batman_if *bif );
void schedule_rcvd_ogm( uint16_t oCtx, uint16_t neigh_id, struct msg_buff *mb );
