/******************************************************************************
*  File:        objlist.c
*  Date:    7.4.2000
*
*  Author:      Stephan Enderlein
*  Abstract:
*               Implementation of the list related functions
*******************************************************************************/

#include <objlist.h>

/**
  Initializes the ListHead to an empty list.
  ListHead only contains two members pointing to
  previous and next element in the list. The list
  was designed as a ring list.
  @param  ListHead pointer to a new list entry, that should be used as list head<p>
    @see  OLInsertHeadList(), OLInsertTailList(),
      OLIsListEmpty(), OLRemoveEntryList(), OLRemoveHeadList(),
      OLRemoveTailList(), LIST_ENTRY, OLGetNext(), OLGetPrev(), IsSameListEntry()
*/
void OLInitializeListHead(IN PLIST_ENTRY ListHead)
{
  // initialize ListHead to an empty list
  // build ring
  ListHead->next = ListHead;
  ListHead->prev = ListHead;
}

/**
  Inserts <i>Entry</i> right behind <i>ListHead</i>. <i>ListHead</i> may
  be any list entry.
  @param  ListHead point where Entry should be inserted behind
  @param  Entry   Entry to insert<p>
    @see  OLInsertTailList(),
      OLRemoveEntryList(), OLRemoveHeadList(),
      OLRemoveTailList(), LIST_ENTRY, OLGetNext(), OLGetPrev(), IsSameListEntry()
*/
void OLInsertHeadList(IN PLIST_ENTRY ListHead, IN PLIST_ENTRY Entry)
{
  // inserts Entry before first entry in list
  Entry->next = ListHead->next;
  Entry->prev = ListHead;

  ListHead->next->prev = Entry;
  ListHead->next = Entry;
}

/**
  Inserts <i>Entry</i> right before <i>ListHead</i>. <i>ListHead</i> may
  be any list entry.
  - List is a ring list, therefor I insert the new before head. so it is the
  last entry in the list.
  - when ListHead is an entry of the list, then new entry will be inserted before that
  @param  ListHead point where Entry should be inserted before
  @param  Entry   Entry to insert<p>
    @see  OLInsertHeadList(),
      OLRemoveEntryList(), OLRemoveHeadList(),
      OLRemoveTailList(), LIST_ENTRY, OLGetNext(), OLGetPrev(), IsSameListEntry()
*/
void OLInsertTailList(IN PLIST_ENTRY ListHead, IN PLIST_ENTRY Entry)
{
  Entry->next = ListHead;
  Entry->prev = ListHead->prev;

  ListHead->prev->next = Entry;
  ListHead->prev = Entry;
}

/**
  It returns true if the list spezified by <i>ListHead</i> is empty.
  @param  ListHead points to the list to check<p>

    @see  OLInsertHeadList(), OLInsertTailList(),
      OLIsListEmpty(), OLRemoveEntryList(), OLRemoveHeadList(),
      OLRemoveTailList(), LIST_ENTRY, OLGetNext(), OLGetPrev(), IsSameListEntry()
*/
int OLIsListEmpty(IN PLIST_ENTRY ListHead)
{
  // returns true if list is empty
  // only one test needed, because if list is empty prev and next are equal
  if (ListHead->next == ListHead)
    return 1;
  return 0;
}

/**
  Removes <i>Entry</i> from its list.
  @param  Entry entry to remove<p>

    @see  OLInsertHeadList(), OLInsertTailList(),
      OLIsListEmpty(), OLRemoveEntryList(), OLRemoveHeadList(),
      OLRemoveTailList(), LIST_ENTRY, OLGetNext(), OLGetPrev(), IsSameListEntry()
*/
void OLRemoveEntryList(IN PLIST_ENTRY Entry)
{
  // removes current entry from list an resets it back to double linked list
  Entry->prev->next = Entry->next;
  Entry->next->prev = Entry->prev;
  Entry->next = Entry;
  Entry->prev = Entry;
}

/**
  Removes and returns the first entry from list.
  <i>ListHead</i> may also be any entry. In this case the
  next item is removed without checking if the removed entry
  is the list head. If the removed entry was the list head,
  the list head is reinitialized to an empty list. This could
  be wanted, if another list entry should play the roles of
  the new list head and a data entry.
  @param  ListHead list to remove the entry from<p>

    @see  OLInsertHeadList(), OLInsertTailList(),
      OLIsListEmpty(), OLRemoveEntryList(), OLRemoveTailList(), LIST_ENTRY,
      OLGetNext(), OLGetPrev(), IsSameListEntry()
*/
PLIST_ENTRY OLRemoveHeadList(IN PLIST_ENTRY ListHead)
{
  // removes first entry from list and returns pointer to it
  PLIST_ENTRY pEntry = ListHead->next;

  OLRemoveEntryList(pEntry);
  return pEntry;
}

/**
  Removes and returns the last entry from list.
  <i>ListHead</i> may also be any entry. In this case the
  previous item is removed without checking if the removed entry
  is the list head. If the removed entry was the list head,
  the list head is reinitialized to an empty list. This could
  be wanted, if another list entry should play the roles of
  the new list head and a data entry.
  @param  ListHead list to remove the entry from<p>

    @see  OLInsertHeadList(), OLInsertTailList(),
      OLIsListEmpty(), OLRemoveEntryList(), OLRemoveHeadList(), LIST_ENTRY,
      OLGetNext(), OLGetPrev(), IsSameListEntry()
*/
PLIST_ENTRY OLRemoveTailList(IN PLIST_ENTRY ListHead)
{
  // removes last entry from list and returns pointer to it
  PLIST_ENTRY pEntry = ListHead->prev;

  OLRemoveEntryList(pEntry);
  return pEntry;
}
