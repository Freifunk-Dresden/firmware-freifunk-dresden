/*
 * Copyright (C) 2006 BATMAN contributors:
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
 
#ifndef _BATMAN_METRICS_H
#define _BATMAN_METRICS_H


#define MAX_BITS_RANGE 1024

#define OGI_WAVG_EXP 3


void flush_sq_record( struct sq_record *sqr );

void update_lounged_metric( uint8_t probe, uint8_t lounge_size, SQ_TYPE sqn_incm, SQ_TYPE sqn_max, struct sq_record *sqr, uint8_t ws );

#define WAVG( wavg , weight_exp ) ( (uint32_t) ( (wavg) >> (weight_exp) ) )

uint32_t upd_wavg( uint32_t *wavg, uint32_t probe, uint8_t weight_exp );

#endif
