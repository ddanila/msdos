/*******************************************************************************
 * 
 * (C) Copyright Microsoft Corp. 1986
 * 
 *    TITLE:	VDMM
 *
 *    MODULE:	EMM40.C - EMM 4.0 functions code.
 *
 *    VERSION:	0.00
 *
 *    DATE:	Feb 25, 1987
 *
 *******************************************************************************
 *	CHANGE LOG
 *  Date     Version	   Description
 * --------  --------	-------------------------------------------------------
 * 02/25/87	0.00	Orignal
 *
 *******************************************************************************
 *     FUNCTIONAL DESCRIPTION
 *
 * Paged EMM Driver for the iAPX 386.
 * Extra functions defined in the 4.0 spec required by Windows.
 * 
 ******************************************************************************/ 

/******************************************************************************
	INCLUDE FILES
 ******************************************************************************/ 
#include "emm.h"
/*#include "mem_mgr.h"*/


/******************************************************************************
	EXTERNAL DATA STRUCTURES
 ******************************************************************************/ 
/*
 * handle_table
 *	This is an array of handle pointers.
 *	page_index of zero means free
 */
extern unsigned char	handle_table_size;	/* number of entries */
extern unsigned char	handle_count;		/* active handle count */

/*
 * EMM Page table
 *	this array contains lists of indexes into the 386
 *	Page Table.  Each list is pointed to by a handle
 *	table entry and is sequential/contiguous.  This is
 *	so that maphandlepage doesn't have to scan a list
 *	for the specified entry.
 */
extern unsigned	short *emm_page;	/* _emm_page array */
extern int	free_count;		/* current free count */
extern int	total_pages;		/* number being managed */
extern unsigned	emmpt_start;		/* next free entry in table */

/*
 * EMM free table
 *	this array is a stack of available page table entries. 
 *	each entry is an index into the pseudo page table
 */
/*extern	unsigned free_stack_count;	/* number of entries */

/*
 * 4.0 EXTRAS
 */

extern unsigned char altreg_count;		/* extra register sets */
extern unsigned char cntxt_bytes;		/* bytes in a saved context */
/*extern char	VM1_cntxt_pages;		/* pages in a VM1 context */
/*extern char	VMn_cntxt_pages;		/* pages in a VM context */
/*extern char	VM1_cntxt_bytes;		/* bytes in a VM1 context */
/*extern char	VMn_cntxt_bytes;		/* bytes in a VM context */
extern unsigned short PF_Base;
/*extern unsigned short VM1_EMM_Offset;*/
extern char	OSEnabled;			/* OS/E function flag */
extern long	OSKey;				/* Key for OS/E function */

/******************************************************************************
	EXTERNAL FUNCTIONS
 ******************************************************************************/ 
extern	unsigned far	*source_addr(); 		/* get DS:SI far ptr */
extern	unsigned far	*dest_addr();			/* get ES:DI far ptr */
extern	unsigned	wcopyb();
extern	unsigned	copyout();


/******************************************************************************
	ROUTINES
 ******************************************************************************/ 

#if !defined(EMM40_QUERY_ONLY) && !defined(EMM40_INFO_ONLY) && \
    !defined(EMM40_NAMES_ONLY)

/*
 * Reallocate Pages
 *	parameters:
 *		bx    -- new number of pages
 *		dx    -- handle
 *	returns:
 *		bx    -- new number of pages
 *
 * Change the number of pages allocated to a handle.
 *
 * ISP 5/23/88 Updated for MEMM
 */
ReallocatePages() 
{
#define	handle	((unsigned short)regp->hregs.x.rdx)

	unsigned count, index, h;
	unsigned			new_size;
	register unsigned 		n_pages;
	register unsigned 		next;

	if (!HandleValid())
		return;		/* (error code already set) */

	setAH(OK);			/* Assume success */
	new_size = regp->hregs.x.rbx;
	count = HandleCount(handle);
	if ( new_size == count )
		return;				/* do nothing... */

	if ( new_size > count ) {
		if ( new_size > total_pages ) {
			setAH(NOT_ENOUGH_EXT_MEM);
			return;
		}
		n_pages = new_size - count;
		if ( n_pages > free_count ) {
			setAH(NOT_ENOUGH_FREE_MEM);
			return;
		}
		if ( count == 0 ) {
			next = emmpt_start;
			SetHandleIndex(handle, next);
		} else
			next = HandleIndex(handle) + count;
		SetHandleCount(handle, new_size);
		if ( next != emmpt_start ) {
				/*
				 * Must shuffle emm_page array to make room
				 * for the extra pages.  wcopyb correctly
				 * handles this case where the destination
				 * overlaps the source.
				 */
			wcopyb(emm_page+next, emm_page+next+n_pages,
			       emmpt_start - next);
			/* Now tell other handles where their pages went */
			for (h = 0; h < handle_table_size; h++) {
				index = HandleIndex(h);
				if (index != NULL_PAGE && index >= next)
					SetHandleIndex(h, index + n_pages);
			}
		}
		emmpt_start += n_pages;
		if ( get_pages(n_pages, next) == NULL_PAGE) { /* strange failure */
			setAH(NOT_ENOUGH_FREE_MEM);
			new_size = HandleCount(handle) - n_pages;  /* as it was! */
			setBX(new_size);
			goto shrink;			/* and undo damage */
		}
	} else {
		/* Shrinking - make handle point to unwanted pages */
	shrink:
		SetHandleCount(handle, HandleCount(handle) - new_size);
		SetHandleIndex(handle, HandleIndex(handle) + new_size);
		free_pages(handle);    /* free space in emm_page array */
		/* Undo damage to handle, the index was not changed */
		SetHandleCount(handle, new_size);
		SetHandleIndex(handle, HandleIndex(handle) - new_size);
	}

#undef	handle
}


#endif /* reallocation-only or full build */

#ifndef EMM40_REALLOC_ONLY

#if defined(EMM40_INFO_ONLY) || \
    (!defined(EMM40_QUERY_ONLY) && !defined(EMM40_NAMES_ONLY))

/*
 * Get Expanded Memory Hardware Information
 *	parameters:
 *		al == 0
 *		es:di -- user array
 *	returns:
 *		es:di[0] = raw page size in paragraphs
 *		es:di[2] = number of EXTRA fast register sets
 *		es:di[4] = number of bytes needed to save a context 
 *		es:di[6] = number of settable DMA channels
 *
 *	parameters:
 *		al == 1
 *	returns:
 *		bx = number of free raw pages
 *		dx = total number of raw pages
 *		
 * ISP	5/23/88 Updated for MEMM. Made u_ptr into far ptr.
 */
GetInformation() 
{
	unsigned far *u_ptr;
	unsigned pages;

	if ( OSEnabled >= OS_DISABLED ) {
		setAH(ACCESS_DENIED);		/* Denied by operating system */
		return;
	}

	if ( regp->hregs.h.ral == 0 ) {
		u_ptr = dest_addr();		/* ES:DI */
		u_ptr[0] = 0x0400;		/* raw page size in paragraphs */
		u_ptr[1] = altreg_count;
		u_ptr[2] = cntxt_bytes;
		u_ptr[3] = 0;			/* settable DMA channels */
		u_ptr[4] = 0;			/* DMA channel operation */
		setAH(OK);
	} else if ( regp->hregs.h.ral == 1 ) {
		GetUnallocatedPageCount();	/* Use existing code */
	} else
		setAH(INVALID_SUBFUNCTION);
}

#endif /* EMM40_INFO_ONLY || full build */

#if defined(EMM40_NAMES_ONLY) || \
    (!defined(EMM40_INFO_ONLY) && !defined(EMM40_QUERY_ONLY))

/*
 * GetSetHandleName
 *
 *  Subfunction 0 Gets the name of a given handle
 *  Subfunction 1 Sets a new name for handle
 *
 *	parameters:
 *		al == 0
 *		es:di == Data area to copy handle name to
 *		dx    -- handle
 *	returns:
 *		[es:di] == Name of DX handle
 *
 *	parameters:
 *		al == 1
 *		ds:si == new handle name
 *		dx    -- handle
 *	returns:
 *		ah = Status
 *
 * ISP 5/23/88 Updated for MEMM. Name made into far *. Copyin routine used
 *	       to copy name in into handle name table.
 */
GetSetHandleName()
{
	register unsigned short handle = ((unsigned short)regp->hregs.x.rdx);
	register char far *Name;

    /* Validate subfunction */
	if ( (regp->hregs.h.ral != 0) && (regp->hregs.h.ral != 1) ) {
		setAH(INVALID_SUBFUNCTION);
		return;
	}

    /* Validate handle */

	if (!HandleValid())
		return; 	/* (error code already set) */

    /* Implement subfunctions 0 and 1 */
	if ( regp->hregs.h.ral == 0 ) {
		Name = (char far *)dest_addr(); 	   /* ES:DI */
		ReadHandleName(handle & 0xFF, Name);
		setAH(OK);
	} else {
		GetHandleDirectory();		/* See if already there */
		switch ( regp->hregs.h.rah ) {
		case NAMED_HANDLE_NOT_FOUND:
			break;
		case DUPLICATE_HANDLE_NAMES:
			return;
		default:
			if ( handle == regp->hregs.x.rdx )
				break;		/* same handle, OK */
			regp->hregs.x.rdx = handle;
			setAH(DUPLICATE_HANDLE_NAMES);
			return;
		}
		Name = (char far *)source_addr();
		WriteHandleName(handle & 0xFF, Name);
		setAH(OK);
	}

}




/*
 * GetHandleDirectory
 *
 *  Subfunction 0 Returns a directory of handles and handle names
 *  Subfunction 1 Returns the handle specified by the name at [ds:si]
 *
 *	parameters:
 *		al == 0
 *		es:di == Data area to copy handle name to
 *	returns:
 *		al == Number of entries in the handle_dir array
 *		[es:di] == Handle_Dir array
 *
 *	parameters:
 *		al == 1
 *		[ds:si] == Handle name to locate
 *	returns:
 *		ah == Status
 *
 *	parameters:
 *		al == 2
 *	returns:
 *		bx == Total handles in system
 *
 * ISP 5/23/88 Updated for MEMM.  nameaddress and dir_entry made into far *
 *	       copyin routine used to copy name into local area for search.
 */
GetHandleDirectory()
{
	char far			*NameAddress;
	struct Handle_Dir_Entry far	*Dir_Entry;
	unsigned short			Handle_Num, Found;
/*
 * since all local variables are allocated on stack (SS seg)
 * and DS and SS has grown apart (ie DS != SS),
 * we need variables in DS seg (ie static variables) to pass
 * to copyout(),copyin() and MatchHandleName() which expects those
 * parameters that are near pointers to be in DS
 *
 * PC 08/03/88
 */
	static Handle_Name			Name;
	static unsigned short		Real_Handle;

	if ( regp->hregs.h.ral == 0 ) {
		Dir_Entry = (struct Handle_Dir_Entry far *)dest_addr();
		for (Handle_Num = 0; Handle_Num < handle_table_size; Handle_Num++) {
		    if (HandleIndex(Handle_Num) != NULL_PAGE) {
			Real_Handle =  Handle_Num;
			copyout(Dir_Entry, &Real_Handle, sizeof(short));
			ReadHandleName(Handle_Num, Dir_Entry->Dir_Handle_Name);
			Dir_Entry++;
		    }
		} setAX(handle_count);
	} else if ( regp->hregs.h.ral == 1 ) {
		NameAddress = (char far *)source_addr();
		copyin(Name, NameAddress, Handle_Name_Len);
		Found = 0;
		Handle_Num = 0;
		while ((Handle_Num < handle_table_size) && (Found < 2)) {
		    if (HandleIndex(Handle_Num) != NULL_PAGE) {
			if (MatchHandleName(Handle_Num, Name)) {
			    Found++;
			    Real_Handle = Handle_Num;
			}
		    }
		    Handle_Num++;
		}
		switch (Found) {
		    case 0:
			setAH((unsigned char)NAMED_HANDLE_NOT_FOUND);
			break;
		    case 1:
			setDX(Real_Handle);
			setAH(OK);
			break;
		    default:
			setAH((unsigned char)DUPLICATE_HANDLE_NAMES);
		}

	} else if ( regp->hregs.h.ral == 2 ) {
		setBX(handle_table_size);
		setAH(OK);
	} else
		setAH(INVALID_SUBFUNCTION);

#undef	handle
}

#endif /* EMM40_NAMES_ONLY || full build */

#if !defined(EMM40_INFO_ONLY) && !defined(EMM40_NAMES_ONLY)

/*
 * Enable/Disable OS/E Function Set Functions
 *
 *	Enable/Disable access to functions 26, 28 and 30
 *
 *	parameters:
 *		AL = 0		Enable Functions
 *		AL = 1		Disable Functions
 *		AL = 2		Return Access Key
 *		BX, CX		Access Key
 *	returns:
 *		AH = OK
 *		BX, CX		Access Key if successful
 *
 * 05/09/88 ISP Updated for MEMM. Removed check for pCurVMID
 *
 */
OSDisable()
{
	unsigned char function = regp->hregs.h.ral;

	if ( function > 2 ) {
		setAH(INVALID_SUBFUNCTION);
		return;
	}

	if ( OSEnabled == OS_IDLE ) {		/* First invocation */
		if ( function == 2 ) {
			setAH(ACCESS_DENIED);
			return;
		}
		OSKey = Get_Key_Val();		/* Suitably random number */
		regp->hregs.x.rbx = (short)OSKey;
		regp->hregs.x.rcx = (short)(OSKey >> 16);
	} else {				/* Check Key */
		if ( (short)OSKey != regp->hregs.x.rbx
		     || (short)(OSKey >> 16) != regp->hregs.x.rcx ) {
			setAH(ACCESS_DENIED);
			return;
		}
	}
	if ( function == 0 )			/* enable */
		OSEnabled = 1;
	else if ( function == 1 )		/* disable */
		OSEnabled = 2;
	else if ( function == 2 )		/* return key */
		OSEnabled = 0;

	setAH(OK);
}

#endif /* !EMM40_INFO_ONLY && !EMM40_NAMES_ONLY */

#endif /* !EMM40_REALLOC_ONLY */
