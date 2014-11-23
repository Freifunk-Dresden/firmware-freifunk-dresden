/*
 * Copyright (c) 2010  Axel Neumann
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
 */


#define REGISTER_TASK_TIMEOUT_MAX MIN( 100000, TIME_MAX>>2)


//void init_schedule( void );
void change_selects( void );
void cleanup_schedule( void );
void task_register( TIME_T timeout, void (* task) (void *), void *data, int32_t tag );
IDM_T task_remove(void (* task) (void *), void *data);
TIME_T task_next( void );
void wait4Event( TIME_T timeout );

