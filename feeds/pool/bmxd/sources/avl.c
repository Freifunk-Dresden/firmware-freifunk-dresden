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

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "batman.h"
#include "os.h"

#include "avl.h"

struct avl_node *avl_find(struct avl_tree *tree, void *key)
{
        struct avl_node *an;
        int cmp;

        if(!tree || !tree->root || !key)
        {return NULL;}

        an = tree->root;

        // Search for a dead path or a matching entry
        //while (an && (cmp = memcmp(an->key, key, tree->key_size)))
        while (an)
        {
                cmp = memcmp(an->key, key, tree->key_size);
                if(cmp == 0) break;
                an = an->link[cmp < 0];
        }

        return an;
}

struct avl_node *avl_next(struct avl_tree *tree, void *key)
{
        struct avl_node *an = tree->root;
        struct avl_node *best = NULL;
        int cmp;

        while (an)
        {
                cmp = (memcmp(an->key, key, tree->key_size) <= 0);

                if (an->link[cmp])
                {
                        best = cmp ? best : an;
                        an = an->link[cmp];
                }
                else
                {
                        return cmp ? best : an;
                }
        }
        return NULL;
}


static struct avl_node *avl_create_node(void *key, void *object)
{
        struct avl_node *an = debugMalloc(sizeof(struct avl_node), 327);

        paranoia(-500189, !an);
        memset(an, 0, sizeof(struct avl_node));
        an->key = key;
        an->object = object;

        return an;
}

static struct avl_node *avl_rotate_single(struct avl_node *root, int dir)
{
        struct avl_node *save;
        int rlh, rrh, slh;

        /* Rotate */
        save = root->link[!dir];

        root->link[!dir] = save->link[dir];

        if (root->link[!dir])
                root->link[!dir]->up = root;

        save->link[dir] = root;

        if (root)
                root->up = save;

        /* Update balance factors */
        rlh = avl_height(root->link[0]);
        rrh = avl_height(root->link[1]);
        slh = avl_height(save->link[!dir]);

        root->balance = avl_max(rlh, rrh) + 1;
        save->balance = avl_max(slh, root->balance) + 1;

        return save;
}

static struct avl_node *avl_rotate_double(struct avl_node *root, int dir)
{
        root->link[!dir] = avl_rotate_single(root->link[!dir], !dir);

        if (root->link[!dir])
                root->link[!dir]->up = root;

        return avl_rotate_single(root, dir);
}

void avl_insert(struct avl_tree *tree, void *key, void *object)
{
        if (tree->root)
        {
                struct avl_node *it = tree->root;
                struct avl_node *up[AVL_MAX_HEIGHT];
                int upd[AVL_MAX_HEIGHT], top = 0;
                int done = 0;

                /* Search for an empty link, save the path */
                for (;;)
                {
                        /* Push direction and node onto stack */
                        //                        upd[top] = memcmp(it->key, key, tree->key_size) < 0;
                        upd[top] = memcmp(it->key, key, tree->key_size) <= 0;
                        up[top++] = it;

                        if (it->link[upd[top - 1]] == NULL)
                                break;

                        it = it->link[upd[top - 1]];
                }

                /* Insert a new node at the bottom of the tree */
                it->link[upd[top - 1]] = avl_create_node(key, object);
                it->link[upd[top - 1]]->up = it;

                paranoia(-500178, (it->link[upd[top - 1]] == NULL));

                /* Walk back up the search path */
                while (--top >= 0 && !done)
                {
                        int lh, rh, max;

                        lh = avl_height(up[top]->link[upd[top]]);
                        rh = avl_height(up[top]->link[!upd[top]]);

                        /* Terminate or rebalance as necessary */
                        if (lh - rh == 0)
                                done = 1;
                        if (lh - rh >= 2)
                        {
                                struct avl_node *a = up[top]->link[upd[top]]->link[upd[top]];
                                struct avl_node *b = up[top]->link[upd[top]]->link[!upd[top]];

                                if (avl_height(a) >= avl_height(b))
                                        up[top] = avl_rotate_single(up[top], !upd[top]);
                                else
                                        up[top] = avl_rotate_double(up[top], !upd[top]);

                                /* Fix parent */
                                if (top != 0)
                                {
                                        up[top - 1]->link[upd[top - 1]] = up[top];
                                        up[top]->up = up[top - 1];
                                }
                                else
                                {
                                        tree->root = up[0];
                                        up[0]->up = NULL;
                                }

                                done = 1;
                        }

                        /* Update balance factors */
                        lh = avl_height(up[top]->link[upd[top]]);
                        rh = avl_height(up[top]->link[!upd[top]]);
                        max = avl_max(lh, rh);

                        up[top]->balance = max + 1;
                }
        }
        else
        {
                tree->root = avl_create_node(key, object);
                paranoia(-500179, (tree->root == NULL));
        }

        return;
}

// returns object
void *avl_remove(struct avl_tree *tree, void *key)
{
 void *ret = NULL;

        struct avl_node *it = tree->root;
        struct avl_node *up[AVL_MAX_HEIGHT];
        int upd[AVL_MAX_HEIGHT], top = 0, cmp;

        paranoia(-500182, !it); // paranoia if not found

        //        while ((cmp = memcmp(it->key, key, tree->key_size)) ) {
        while ((cmp = memcmp(it->key, key, tree->key_size))
              || (it->link[0]
                  && !memcmp(it->link[0]->key, key, tree->key_size)))
        {
                // Push direction and node onto stack
                upd[top] = (cmp < 0);
                up[top] = it;
                top++;

                if (!(it = it->link[(cmp < 0)]))
                        return NULL;
        }

        // remember and return the found object. It might have been another one than intended
        ret = it->object;

        // Remove the node:
        if (!(it->link[0] && it->link[1]))
        { // at least one child is NULL:

                // Which child is not null?
                int dir = !(it->link[0]);

                /* Fix parent */
                if (top)
                {
                        up[top - 1]->link[upd[top - 1]] = it->link[dir];
                        if (it->link[dir])
                                it->link[dir]->up = up[top - 1];
                }
                else
                {
                        tree->root = it->link[dir];
                        if (tree->root)
                                tree->root->up = NULL;
                }
                debugFree(it, 1327);
        }
        else
        { // both childs NOT NULL:

                // Find the inorder successor
                struct avl_node *heir = it->link[1];

                // Save the path
                upd[top] = 1;
                up[top] = it;
                top++;

                while (heir->link[0])
                {
                        upd[top] = 0;
                        up[top] = heir;
                        top++;
                        heir = heir->link[0];
                }

                // Swap data
                it->key = heir->key;
                it->object = heir->object;

                // Unlink successor and fix parent
                up[top - 1]->link[(up[top - 1] == it)] = heir->link[1];

                if (heir->link[1])
                        heir->link[1]->up = up[top - 1];

                debugFree(heir, 2327);
        }

        // Walk back up the search path
        while (--top >= 0)
        {
                int lh = avl_height(up[top]->link[upd[top]]);
                int rh = avl_height(up[top]->link[!upd[top]]);
                int max = avl_max(lh, rh);

                /* Update balance factors */
                up[top]->balance = max + 1;

                // Terminate or re-balance as necessary:
                if (lh - rh >= 0) // re-balance upper path...
                        continue;

                if (lh - rh == -1) // balance for upper path unchanged!
                        break;

                if (!(up[top]) || !(up[top]->link[!upd[top]]))
                {
                        dbgf(DBGL_SYS, DBGT_ERR, "up(top) %p  link %p   lh %d   rh %d",
                             (void *)(up[top]), (void *)((up[top]) ? (up[top]->link[!upd[top]]) : NULL), lh, rh);

                        paranoia(-500187, (!(up[top])));
                        paranoia(-500188, (!(up[top]->link[!upd[top]])));
                }
                /*
                paranoia(-500183, (lh - rh <= -3) );
                paranoia(-500185, (lh - rh == 2) );
                paranoia(-500186, (lh - rh >= 3) );
*/

                // if (lh - rh <= -2):  rebalance here and upper path

                struct avl_node *a = up[top]->link[!upd[top]]->link[upd[top]];
                struct avl_node *b = up[top]->link[!upd[top]]->link[!upd[top]];

                if (avl_height(a) <= avl_height(b))
                        up[top] = avl_rotate_single(up[top], upd[top]);
                else
                        up[top] = avl_rotate_double(up[top], upd[top]);

                // Fix parent:
                if (top)
                {
                        up[top - 1]->link[upd[top - 1]] = up[top];
                        up[top]->up = up[top - 1];
                }
                else
                {
                        tree->root = up[0];
                        tree->root->up = NULL;
                }
        }

        return ret;
}

