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


#include <stdio.h>
#include <string.h>

#include "batman.h"
#include "os.h"
#include "originator.h"
#include "metrics.h"


void flush_sq_record( struct sq_record *sqr ) {
	
	sqr->wa_val = sqr->wa_unscaled = 0;
        sqr->wa_clr_sqn = sqr->wa_set_sqn = ((SQ_TYPE) (sqr->wa_clr_sqn - (MAX_PATH_LOUNGE + MAX_PWS + 1)));

}



void update_lounged_metric(uint8_t probe, uint8_t lounge_size, SQ_TYPE sqn_incm, SQ_TYPE sqn_max, struct sq_record *sqr, uint8_t ws)
{
        SQ_TYPE sq_upd;

//	dbgf_all( DBGT_INFO, "probe=%d, lounge_size=%d, sqn_incm=%d, sqn_max=%d, ws=%d ", probe, lounge_size, sqn_incm, sqn_max, ws );

        if ( probe )
                sq_upd = sqn_incm;

        else if ( ((SQ_TYPE)(sqn_max - sqr->wa_clr_sqn )) > lounge_size )
                sq_upd = sqn_max - lounge_size;

        else
                return;


        uint32_t m_weight = ws/2;
	SQ_TYPE i, offset = sq_upd - sqr->wa_clr_sqn;

	if ( offset >= ws ) {

		sqr->wa_unscaled = 0;

	} else {

		for ( i=0; i < offset; i++ )
			sqr->wa_unscaled -= ( sqr->wa_unscaled / m_weight );

	}

	sqr->wa_clr_sqn = sq_upd;

	if ( probe /* &&  sqr->wa_set_sqn != sq_upd */  ) {

                // paranoia( -500197, (sqr->wa_set_sqn == sq_upd) /*check validate_considered_order()*/ );

                if ( sqr->wa_set_sqn != sq_upd ) {
                        sqr->wa_unscaled += ((probe * WA_SCALE_FACTOR) / m_weight);

                        sqr->wa_set_sqn = sq_upd;
                } else {
//stephan:
//das habe ich nur bei wlan verbindungen beobachtet. es werden ueber das wlan interface ein packet mit
//zwei ogms empfangen (der andere wlan knoten packt die ogms, die fuer diesen node bestimmt sind in ein udp packet).
//einmal reflektiert er das ogm für das primary interface (ttl=50) und einmal reflektiert er das link-bezogene ogm (ttl=1)
//und decrementiert bei beiden ogm den ttl. das prime-ogm ist im non-prim ogm "verlinkt".
//es scheint kein fehler zu sein. Also mache ich hier ein INFO draus.

                        dbgf_all( DBGT_INFO /*DBGT_ERR*/,
                                "update_lounged_metric() probe %d ls %d sqn_in %d sqn_max %d ws %d",
                                probe, lounge_size, sqn_incm, sqn_max, ws );

                }
        }

	sqr->wa_val = sqr->wa_unscaled/WA_SCALE_FACTOR;


}




uint32_t upd_wavg( uint32_t *wavg, uint32_t probe, uint8_t weight_exp ) {
	
#ifndef NOPARANOIA
	if ( weight_exp > 10 || (weight_exp && probe >= (uint32_t)(0x01<<(32-weight_exp))) )
		dbg( DBGL_SYS, DBGT_ERR, 
		     "probe or weight_exp value to large to calculate weighted average!"
		     "upd_wavg(wavg: %d, probe: %d, weight_exp: %d ) = %d:",
		     *wavg, probe, weight_exp, *wavg>>weight_exp );
#endif
	
	if ( *wavg )
		*wavg += probe - ((*wavg)>>weight_exp);
	else
		*wavg = probe<<weight_exp;
	
	
	return WAVG(*wavg,weight_exp);
}
