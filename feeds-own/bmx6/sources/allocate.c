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


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>

#include "bmx.h"

#define MAGIC_NUMBER_HEADER 0xB2B2B2B2
#define MAGIC_NUMBER_TRAILOR 0xB2


#ifndef NO_DEBUG_MALLOC


struct chunkHeader *chunkList = NULL;

struct chunkHeader
{
	struct chunkHeader *next;
	uint32_t length;
	int32_t tag;
        uint32_t magicNumberHeader;
};

typedef unsigned char MAGIC_TRAILER_T;


#ifdef MEMORY_USAGE

struct memoryUsage *memoryList = NULL;


struct memoryUsage
{
	struct memoryUsage *next;
	uint32_t length;
	uint32_t counter;
	int32_t tag;
};

void addMemory(uint32_t length, int32_t tag)
{

	struct memoryUsage *walker;

	for ( walker = memoryList; walker != NULL; walker = walker->next ) {

		if ( walker->tag == tag ) {

			walker->counter++;
			break;
		}
	}

	if ( walker == NULL ) {

		walker = malloc( sizeof(struct memoryUsage) );

		walker->length = length;
		walker->tag = tag;
		walker->counter = 1;

		walker->next = memoryList;
		memoryList = walker;
	}

}

void removeMemory(int32_t tag, int32_t freetag)
{

	struct memoryUsage *walker;

	for ( walker = memoryList; walker != NULL; walker = walker->next ) {

		if ( walker->tag == tag ) {

			if ( walker->counter == 0 ) {

                                dbg_sys(DBGT_ERR, "Freeing more memory than was allocated: malloc tag = %d, free tag = %d",
				     tag, freetag );
				cleanup_all( -500069 );

			}

			walker->counter--;
			break;

		}

	}

	if ( walker == NULL ) {

                dbg_sys(DBGT_ERR, "Freeing memory that was never allocated: malloc tag = %d, free tag = %d",
		     tag, freetag );
		cleanup_all( -500070 );
	}
}

void debugMemory(struct ctrl_node *cn)
{
	
	struct memoryUsage *memoryWalker;

	dbg_printf( cn, "\nMemory usage information:\n" );

	for ( memoryWalker = memoryList; memoryWalker != NULL; memoryWalker = memoryWalker->next ) {

		if ( memoryWalker->counter != 0 )
			dbg_printf( cn, "   tag: %4i, num malloc: %4i, bytes per malloc: %4i, total: %6i\n", 
			         memoryWalker->tag, memoryWalker->counter, memoryWalker->length, 
			         memoryWalker->counter * memoryWalker->length );

	}
	dbg_printf( cn, "\n" );
	
}

#endif //#ifdef MEMORY_USAGE


void checkIntegrity(void)
{
	struct chunkHeader *walker;
	MAGIC_TRAILER_T *chunkTrailer;
	unsigned char *memory;

//        dbgf_all(DBGT_INFO, " ");

	for (walker = chunkList; walker != NULL; walker = walker->next)
	{
		if (walker->magicNumberHeader != MAGIC_NUMBER_HEADER)
{
                        dbgf_sys(DBGT_ERR, "invalid magic number in header: %08x, malloc tag = %d",
			     walker->magicNumberHeader, walker->tag );
			cleanup_all( -500073 );
		}

		memory = (unsigned char *)walker;

		chunkTrailer = (MAGIC_TRAILER_T*)(memory + sizeof(struct chunkHeader) + walker->length);

		if (*chunkTrailer != MAGIC_NUMBER_TRAILOR)
{
                        dbgf_sys(DBGT_ERR, "invalid magic number in trailer: %08x, malloc tag = %d",
			     *chunkTrailer, walker->tag );
			cleanup_all( -500075 );
		}
	}

}

void checkLeak(void)
{
	struct chunkHeader *walker;

        if (chunkList != NULL) {
		
                openlog( "bmx6", LOG_PID, LOG_DAEMON );

                for (walker = chunkList; walker != NULL; walker = walker->next) {
			syslog( LOG_ERR, "Memory leak detected, malloc tag = %d\n", walker->tag );
		
			fprintf( stderr, "Memory leak detected, malloc tag = %d \n", walker->tag );
			
		}
		
		closelog();
	}

}

void *_debugMalloc(uint32_t length, int32_t tag)
{
	
	unsigned char *memory;
	struct chunkHeader *chunkHeader;
	MAGIC_TRAILER_T *chunkTrailer;
	unsigned char *chunk;

        if (!length)
                return NULL;

	memory = malloc(length + sizeof(struct chunkHeader) + sizeof(MAGIC_TRAILER_T));

	if (memory == NULL)
	{
		dbg_sys(DBGT_ERR, "Cannot allocate %u bytes, malloc tag = %d",
		     (unsigned int)(length + sizeof(struct chunkHeader) + sizeof(MAGIC_TRAILER_T)), tag );
		cleanup_all( -500076 );
	}

	chunkHeader = (struct chunkHeader *)memory;
	chunk = memory + sizeof(struct chunkHeader);
	chunkTrailer = (MAGIC_TRAILER_T*)(memory + sizeof(struct chunkHeader) + length);

	chunkHeader->length = length;
	chunkHeader->tag = tag;
	chunkHeader->magicNumberHeader = MAGIC_NUMBER_HEADER;

	*chunkTrailer = MAGIC_NUMBER_TRAILOR;

	chunkHeader->next = chunkList;
	chunkList = chunkHeader;

#ifdef MEMORY_USAGE

	addMemory( length, tag );

#endif //#ifdef MEMORY_USAGE

	return chunk;
}

void *_debugRealloc(void *memoryParameter, uint32_t length, int32_t tag)
{

        unsigned char *result = _debugMalloc(length, tag);


	if (memoryParameter) { /* if memoryParameter==NULL, realloc() should work like malloc() !! */

                struct chunkHeader *chunkHeader =
                        (struct chunkHeader *) (((unsigned char *) memoryParameter) - sizeof (struct chunkHeader));

                MAGIC_TRAILER_T * chunkTrailer =
                        (MAGIC_TRAILER_T *) (((unsigned char *) memoryParameter) + chunkHeader->length);

		if (chunkHeader->magicNumberHeader != MAGIC_NUMBER_HEADER) {
                        dbgf_sys(DBGT_ERR, "invalid magic number in header: %08x, malloc tag = %d",
			     chunkHeader->magicNumberHeader, chunkHeader->tag );
			cleanup_all( -500078 );
                }

                if (*chunkTrailer != MAGIC_NUMBER_TRAILOR) {
                        dbgf_sys(DBGT_ERR, "invalid magic number in trailer: %08x, malloc tag = %d",
			     *chunkTrailer, chunkHeader->tag );
			cleanup_all( -500079 );
		}

                uint32_t copyLength = (length < chunkHeader->length) ? length : chunkHeader->length;

                if (copyLength)
                        memcpy(result, memoryParameter, copyLength);

		debugFree(memoryParameter, -300280);
	}

	return result;
}

void _debugFree(void *memoryParameter, int tag)
{
	MAGIC_TRAILER_T *chunkTrailer;
	struct chunkHeader *walker;
	struct chunkHeader *previous;

        struct chunkHeader *chunkHeader =
                (struct chunkHeader *) (((unsigned char *) memoryParameter) - sizeof (struct chunkHeader));

        if (chunkHeader->magicNumberHeader != MAGIC_NUMBER_HEADER)
	{
		dbgf_sys(DBGT_ERR,
		     "invalid magic number in header: %08x, malloc tag = %d, free tag = %d, malloc size = %d",
                        chunkHeader->magicNumberHeader, chunkHeader->tag, tag, chunkHeader->length);
		cleanup_all( -500080 );
	}

	previous = NULL;

	for (walker = chunkList; walker != NULL; walker = walker->next)
	{
		if (walker == chunkHeader)
			break;

		previous = walker;
	}

	if (walker == NULL)
	{
		dbg_sys(DBGT_ERR, "Double free detected, malloc tag = %d, free tag = %d malloc size = %d",
		     chunkHeader->tag, tag, chunkHeader->length );
		cleanup_all( -500081 );
	}

	if (previous == NULL)
		chunkList = walker->next;

	else
		previous->next = walker->next;


        chunkTrailer = (MAGIC_TRAILER_T *) (((unsigned char *) memoryParameter) + chunkHeader->length);

	if (*chunkTrailer != MAGIC_NUMBER_TRAILOR) {
                dbgf_sys(DBGT_ERR, "invalid magic number in trailer: %08x, malloc tag = %d, free tag = %d, malloc size = %d",
                        *chunkTrailer, chunkHeader->tag, tag, chunkHeader->length);
		cleanup_all( -500082 );
	}

#ifdef MEMORY_USAGE

	removeMemory( chunkHeader->tag, tag );

#endif //#ifdef MEMORY_USAGE

	free(chunkHeader);
	

}

#else //#ifndef NO_DEBUG_MALLOC

void checkIntegrity(void)
{
}

void checkLeak(void)
{
}

void debugMemory( struct ctrl_node *cn )
{
}

void *_debugMalloc(uint32_t length, int32_t tag)
{
        void *result = malloc(length);

        if (result == NULL && length)
	{
		dbg_sys(DBGT_ERR, "Cannot allocate %u bytes, malloc tag = %d", length, tag );
		cleanup_all( -500072 );
	}

	return result;
}

void *_debugRealloc(void *memory, uint32_t length, int32_t tag)
{
        void *result = realloc(memory, length);

        if (result == NULL && length) {
		dbg_sys(DBGT_ERR, "Cannot re-allocate %u bytes, malloc tag = %d", length, tag );
		cleanup_all( -500071 );
	}

	return result;
}

void _debugFree(void *memory, int32_t tag)
{
	free(memory);
}

#endif
