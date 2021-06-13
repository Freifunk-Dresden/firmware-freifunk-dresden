/******************************************************************************
*  File:        objlist.h
*  Date:    7.4.2000
*
*  Author:      Stephan Enderlein
*
*  Abstract:
*               Implementation of the list related functions
*
*        Usage:  each object (structure) that should be managed by a list
*            needs to include LIST_ENTRY struct as a member.
*            It is recommend to place this member as the first member
*            befor all others. So a simple cast from LIST_ENTRY to
*            the object structure allows the access to the object.
*            If not, it is quite difficult to calulate the start
*            address of object from LIST_ENTRY member,
*        Example:
*              here only the essential code is shown. All tests for robustness
*            needs to included by developer
*
*
*            struct myObj
*            {
*              LIST_ENTRY ListEntry;
*              int sample_member1;
*              int sample_member2;
*              ...
*            };
*
*            void main(void)
*            {
*              LIST_ENTRY listhead;
*              struct myObj * pMyObj;
*
*                OLInitializeListHead(listhead);  // first initialize listhead
*
*                //create and initialize object
*                pMyObj = malloc(sizeof(myObj));
*
*                // append object
*                OLInsertTailList(listhead,pMyObj);
*
*                // insert object 2 after object 1
*                OLInsertTailList(pMyObj1,pMyObj2);
*            }
*
*******************************************************************************/

#ifndef _OBJLIST_H
#define _OBJLIST_H

/** Simple list entry, used in ring list.
<pre>
  struct _list_entry
  {
    struct _list_entry * prev;
    struct _list_entry * next;
  } LIST_ENTRY, *PLIST_ENTRY;


This list entry contains two members pointing to the previous
and next entry in the ring-list.
Normally this structure is included as the first member in a
user object (structure) that should be held in such a ring list.
So the user structure and the list entry have the same address.
The list functions does not know anything about the whole structure.
If you want to access your own data, just have to cast the pointer
from PLIST_ENTRY to a pointer of the orginal data type.
Any user data object may be included only in one ring list. But
in many cases this will be sufficient.
An advantage of this kind of list is, that there are no internal
pointer checks or allocation necessary.


     Example:
         here only the essential code is shown. All tests for
         robustness needs to included by developer


         struct myObj
         {
            LIST_ENTRY ListEntry;
            int sample_member1;
            int sample_member2;
            ...
         };


         void main(void)
         {
            LIST_ENTRY listhead;
            struct myObj * pMyObj;


            // first initialize listhead
            OLInitializeListHead(&listhead);


            //create and initialize object
            pMyObj = malloc(sizeof(myObj));


            // append object
            OLInsertTailList(listhead,pMyObj);


            // insert object 2 after object 1
            OLInsertTailList(pMyObj1,pMyObj2);
         }
</pre>

  @author  Stephan Enderlein<p>
  @see  OLInsertHeadList(), OLInsertTailList(),
        OLIsListEmpty(), OLRemoveEntryList(), OLRemoveHeadList(),
        OLRemoveTailList(), LIST_ENTRY

*/
typedef struct _list_entry LIST_ENTRY, *PLIST_ENTRY;
struct _list_entry
{
  struct _list_entry *prev;
  struct _list_entry *next;
};

#ifndef IN
#define IN
#endif

#ifndef OUT
#define OUT
#endif

/** Returns TRUE if both pointers are same.
      @see LIST_ENTRY, OLGetNext(), OLGetPrev(), OLInsertHeadList()*/
#define IsSameListEntry(a, b) (((PLIST_ENTRY)(a)) == ((PLIST_ENTRY)(b)))
/** Returns the next element after the given list entry.
      @see LIST_ENTRY, OLGetPrev(), IsSameListEntry(), OLInsertHeadList()*/
#define OLGetNext(pListEntry) (((PLIST_ENTRY)(pListEntry))->next)
/** Returns the previous element before the given list entry.
      @see LIST_ENTRY, OLGetNext(), IsSameListEntry(), OLInsertHeadList()*/
#define OLGetPrev(pListEntry) (((PLIST_ENTRY)(pListEntry))->prev)

#define OLRemoveEntry(pListEntry) OLRemoveEntryList((PLIST_ENTRY)pListEntry)
#define OLForEach(var, type, list_head) for (type *var = (type *)OLGetNext(&list_head); !IsSameListEntry(var, &list_head); var = (type *)OLGetNext(var))

void OLInitializeListHead(IN PLIST_ENTRY ListHead);
void OLInsertHeadList(IN PLIST_ENTRY ListHead, IN PLIST_ENTRY Entry);
void OLInsertTailList(IN PLIST_ENTRY ListHead, IN PLIST_ENTRY Entry);
int OLIsListEmpty(IN PLIST_ENTRY ListHead);
void OLRemoveEntryList(IN PLIST_ENTRY Entry);
PLIST_ENTRY OLRemoveHeadList(IN PLIST_ENTRY ListHead);
PLIST_ENTRY OLRemoveTailList(IN PLIST_ENTRY ListHead);

#endif // _OBJLIST_H
