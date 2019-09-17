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


#ifndef NOHNA

#define ARG_UHNA		"unicast_hna"

//#define ARG_HNAS "hnas" moved to os.h to debug hnas 


// my HNA extension messages (attached to all primary OGMs)

#define A_TYPE_INTERFACE 0x00 //unused
#define A_TYPE_NETWORK   0x01
#define A_TYPE_MAX       0x01



struct hna_netmask_type
{
#if __BYTE_ORDER == __LITTLE_ENDIAN
	unsigned int anetmask:6;
	unsigned int atype:2;
#elif __BYTE_ORDER == __BIG_ENDIAN
	unsigned int atype:2;
	unsigned int anetmask:6;
#else
# error "Please fix <bits/endian.h>"
#endif
} __attribute__((packed));



#define EXT_HNA_FIELD_TYPE    nt.atype
#define EXT_HNA_FIELD_NETMASK nt.anetmask
#define EXT_HNA_FIELD_ADDR    addr

struct ext_type_hna
{
#if __BYTE_ORDER == __LITTLE_ENDIAN
	unsigned int ext_related:2;   // may be used by the related message type
	unsigned int ext_type:5;      // identifies the extension message size, type and content
	unsigned int ext_msg:1;       // MUST be set to one for extension messages
#elif __BYTE_ORDER == __BIG_ENDIAN
	unsigned int ext_msg:1;
	unsigned int ext_type:5;
	unsigned int ext_related:2;
#else
# error "Please fix <bits/endian.h>"
#endif
	
	struct hna_netmask_type nt;
	
	uint16_t reservedd;
	
	uint32_t addr;
	
} __attribute__((packed));



#define KEY_FIELD_ATYPE    nt.atype
#define KEY_FIELD_ANETMASK nt.anetmask

struct hna_key
{
	uint32_t addr;
	struct hna_netmask_type nt;
} __attribute__((packed));	


#define  HNA_HASH_NODE_EMPTY 0x00
#define  HNA_HASH_NODE_MYONE 0x01
#define  HNA_HASH_NODE_OTHER 0x02

struct hna_node
{
	struct hna_key key;
	
	//void *orig;
	struct orig_node *orig;
	//char *hna_name;
	uint8_t status;
	
};

struct hna_orig_data {
	
	int16_t  hna_array_len;
	struct ext_type_hna *hna_array;
	
};


struct plugin_v1 *hna_get_plugin_v1( void );


#endif
