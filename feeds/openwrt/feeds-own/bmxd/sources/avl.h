/* Copyright (C) 2006 B.A.T.M.A.N. contributors:
 * Axel Neumann
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

/*
 * avl code inspired by:
 * http://eternallyconfuzzled.com/tuts/datastructures/jsw_tut_avl.aspx
 * where Julienne Walker said (web page from 28. 2. 2010 12:55):
 * ...Once again, all of the code in this tutorial is in the public domain.
 * You can do whatever you want with it, but I assume no responsibility
 * for any damages from improper use. ;-)
 */
#ifndef _AVL_H
#define _AVL_H

#include <stdint.h>


#define AVL_MAX_HEIGHT 128

struct avl_node {
        void *key;
        int balance;
	struct avl_node * up;
	struct avl_node * link[2];
};

struct avl_tree {
	uint16_t key_size;
        struct avl_node *root;
};


#define AVL_INIT_TREE(tree, size) do { 	tree.root = NULL; tree.key_size = (size); } while (0)
#define AVL_TREE(tree, size) struct avl_tree (tree) = { (size), NULL }

#define avl_height(p) ((p) == NULL ? -1 : (p)->balance)
#define avl_max(a,b) ((a) > (b) ? (a) : (b))


struct avl_node *avl_find( struct avl_tree *tree, void *key );
struct avl_node *avl_next( struct avl_tree *tree, void *key );
struct avl_node *avl_iterate(struct avl_tree *tree, struct avl_node *it );

void avl_insert(struct avl_tree *tree, void *key);
void *avl_remove(struct avl_tree *tree, void *key);

#ifdef AVL_DEBUG
struct avl_iterator {
	struct avl_node * up[AVL_MAX_HEIGHT];
	int upd[AVL_MAX_HEIGHT];
	int top;
};

struct avl_node *avl_iter(struct avl_tree *tree, struct avl_iterator *it );
void avl_debug( struct avl_tree *tree );
#endif


#endif
