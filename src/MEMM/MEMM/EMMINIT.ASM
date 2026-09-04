

	page 58,132
;******************************************************************************
	title	EMMINIT - Expanded Memory Manager initialization
;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp. 1986
;
;   Title:	MEMM.EXE - MICROSOFT Expanded Memory Manager 386 Driver
;
;   Module:	EMMINIT - Expanded Memory Manager initialization routine
;
;   Version:	0.05
;
;   Date:	May 24 ,1986
;
;   Author:
;
;******************************************************************************
;
;	Change Log:
;
;	DATE	 REVISION	Description
;	-------- --------	--------------------------------------------
;	04/16/86 Original	Adapted from DOS clock driver.
;	05/24/86 0.00		From EMML test driver.
;	06/21/86 0.02		added cld to EMM_Init
;	06/28/86 0.02		Name change from MEMM386 to MEMM
;	06/29/86 0.02		INC AX (was INC AL) for emm_free init
;	07/06/86 0.04		Size _emm_page,_emm_free, & _pft386 based
;				on # of pages in system
;	07/06/86 0.04		Changed assume to DGROUP
;	07/10/86 0.05		moved int 67h patch to INIT
;	06/07/88		added FRS_array initialization (Paul Chan)
;
;******************************************************************************
;   Functional Description:
;	This module initializes the data structures for the EMM
;   and sets the current emm data break address (_emm_brk).
;
;******************************************************************************
.lfcond
.386p
	page
;******************************************************************************
;			P U B L I C   D E C L A R A T I O N S
;******************************************************************************
;
	public	EMM_Init
	page
;******************************************************************************
;			L O C A L   C O N S T A N T S
;******************************************************************************
;
	include	vdmseg.inc
	include emmdef.inc

FALSE	equ	0
TRUE	equ	not FALSE

EMM_HW_ERROR	equ	81h		; EMM h/w error status

;******************************************************************************
;			E X T E R N A L    R E F E R E N C E S
;******************************************************************************
;
LAST	segment
extrn	xbase_addr_h:byte	; bit 16-24 of address of first byte of emm memory
extrn	xbase_addr_l:word	; bit  0-15 of address of first byte of emm memory
extrn	sys_size:word		; number of 16k pages taken away from conv. mem

LAST	ends

_DATA	segment

extrn	PageT_Seg:word		; segment of system page table

extrn	_PF_Base:word		 ; segment addr of page frame base
extrn	_page_frame_pages:word	; number of pages in 3.2 page frame

extrn	_mappable_pages:word	; mappable page array
extrn	_physical_page_count:word   ; number of physical pages
extrn	_physical_page_ids:byte
extrn	_mappable_page_count:word   ; number of mappable pages

extrn	_cntxt_pages:byte	; pages in a context
extrn	_cntxt_bytes:byte	; bytes in a context

extrn	_emm_page:word		; ptr to array of EMM pages
extrn	_free_count:word	; # of free EMM pages
extrn	_emmpt_start:word	; start of empty part of emm page
extrn	_emm_free:word		; ptr to array of free EMM pages
extrn	_free_top:word		; top of _emm_free

extrn	_total_pages:word	; total # of EMM pages available
extrn	_pft386:word		; ptr to array of page table entries

extrn	_emm_brk:word		; offset for emm data break address

extrn	FRS_array:word		; pointer to runtime-sized FRS array
extrn	CurRegSetn:byte
extrn	CurRegSet:word
extrn	FRS_free:byte
extrn	_altreg_count:word

extrn	_handle_table:word
extrn	_handle_count:word
extrn	_handle_table_size:word
extrn	_save_map:word
extrn	_Handle_Name_Table:word

_DATA	ends

ifndef	NOHIMEM
else
VDATA	segment
extrn	vdata_begin:byte
VDATA	ends
endif

LAST	segment
extrn	mappable_segs:byte
extrn	pool_size:word    	; size of EMM Pages Pool in kbytes
extrn	banking_base:word
extrn	requested_page_count:byte
extrn	requested_page_ids:byte
extrn	requested_page_segments:word
LAST	ends

_TEXT	segment
extrn  InitELIM:far
_TEXT	ends

LAST	segment
extrn	InitEPage:near
LAST	ends


	page
;******************************************************************************
;			S E G M E N T   D E F I N I T I O N
;******************************************************************************
;
;******************************************************************************
;
;	Code Segment
;
;******************************************************************************
;******************************************************************************
; MACROS used in the EMM initialisation code
;******************************************************************************
;******************************************************************************
;
; Get_FRS_window - get pointer to Fast Register Set window
;
;	ENTRY:	Reg - points to an FRS_struc
;
;	EXIT:	Reg - points to FRS_window entry in the structure
;
;	USES:	Reg
;
;******************************************************************************
Get_FRS_window	MACRO	Reg

	mov	Reg, word ptr [CurRegSet]	; just offset (assume dgroup)
	add	Reg, FRS_window			; points to FRS window entries
	ENDM

;******************************************************************************
;**init_MAPPABLE_PAGES: macro to fill the _mappable_pages segment array.  The
;  physical page is derived from the dense index and _page_frame_pages.
;
;  ENTRY: SI = internal physical page number
;	  BX = Segment of physical page
;	  DI = Index into _mappable_pages
;
;******************************************************************************
init_mappable_pages	MACRO
;
	call	assign_external_page_id
    push    di
;
    shl     di,1		    ; convert index into offset in word array
;
    mov     _mappable_pages[di],bx  ; fill in segment
;
    pop     di
;
    ENDM

;******************************************************************************
; INVALIDATE_MAPPABLE_PAGE_ENTRY: macro to remove the page from the mappable
; page temporary list we are using.  this is to facilitate the recognition
; of pages above A000 which are not page frame pages.  When we recognise page
; frame pages we invalidate them so that the subsequent pass for pages doesn't
; include these.
;
;  ENTRY: BX = Segment of physical page
;******************************************************************************
inv_mpbl    MACRO
;
    push    bx
;
    shr     bx,10		    ; convert segment to 16k page #
    mov     cs:mappable_segs[bx],PAGE_NOT_MAPPABLE
;
    pop     bx
;

    ENDM

;
LAST	segment     USE16
	assume	cs:LAST, ds:DGROUP, es:DGROUP

;******************************************************************************
; LOCAL VARIABLES
;******************************************************************************
first_sys_ppage  dw	 0ffffh      ; physical page number of first system page

	page
;******************************************************************************
;
; CODE FOR INITIALISATION
;
;******************************************************************************


	page
;******************************************************************************
;	EMM_Init - initialization routine for EMM.
;			Patches int 67h vector.
;
;	ENTRY: none
;
;	EXIT:	EMM vector initialized.
;		EMM data structures initialized
;		NC => no errors
;		C => errors
;
;	USED: none
;
;******************************************************************************
; Record the caller-visible Pn= number for dense physical index SI at segment
; BX. The core keeps dense arrays; only the public identifier is sparse.
assign_external_page_id proc near
	push	ax
	push	bx
	push	cx
	push	dx
	push	di
	mov	ax,si
	xor	dx,dx
	xor	di,di
	xor	ch,ch
	mov	cl,[requested_page_count]
	jcxz	short assign_external_store
assign_external_loop:
	cmp	requested_page_segments[di],bx
	je	short assign_external_found
	inc	dx
	add	di,2
	loop	assign_external_loop
	xor	ax,ax			; choose the lowest unreserved public ID
assign_external_candidate:
	xor	di,di
	xor	ch,ch
	mov	cl,[requested_page_count]
assign_external_check_requested:
	jcxz	short assign_external_check_used
	cmp	al,requested_page_ids[di]
	je	short assign_external_next_candidate
	inc	di
	loop	assign_external_check_requested
assign_external_check_used:
	xor	di,di
	mov	cx,si
assign_external_used_loop:
	jcxz	short assign_external_store
	cmp	al,_physical_page_ids[di]
	je	short assign_external_next_candidate
	inc	di
	loop	assign_external_used_loop
	jmp	short assign_external_store
assign_external_next_candidate:
	inc	al
	jmp	short assign_external_candidate
assign_external_found:
	mov	di,dx
	mov	al,requested_page_ids[di]
assign_external_store:
	mov	_physical_page_ids[si],al
	pop	di
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
assign_external_page_id endp

EMM_Init	proc	near
;
	pusha
	push	ds
	push	es
;
;  set DS,ES to DGROUP segment
;
	mov	ax,seg DGROUP
	mov	ds,ax
	mov	es,ax
;
	cld				; strings foward
;
; set total # of EMM pages
;
	mov	cx,[pool_size]		; CX = kbytes of expanded memory
	shr	cx,4			; CX = # of EMM pages available
	mov	[_total_pages],cx	; pages total
;
; Lay out option-sized resident tables at the start of VDATA. Keeping only the
; requested A= and H= capacities avoids charging every machine for the maxima
; while preserving the complete documented ranges.
;
	shl	cx,1			; CX = bytes in total_pages words

ifndef	NOHIMEM
else
	mov	ax,seg VDATA
	sub	ax,seg DGROUP
	shl	ax,4			; convert into offset from dgroup
	add	ax,offset VDATA:vdata_begin
	mov	di,ax

	mov	[_save_map],di
	mov	bx,[_handle_table_size]
EMIN_init_save_maps:
	push	bx
	mov	ax,NULL_SAVE_MAP
	stosw				; impossible first page marks slot free
	mov	ax,NULL_PAGE
	mov	cx,EMM32_PHYS_PAGES-1	; remaining unmapped windows
	rep	stosw
	pop	bx
	dec	bx
	jnz	short EMIN_init_save_maps

	mov	[_handle_table],di
	mov	bx,[_handle_table_size]
EMIN_init_handles:
	mov	ax,NULL_PAGE
	stosw				; ht_index
	xor	ax,ax
	stosw				; ht_count
	dec	bx
	jnz	short EMIN_init_handles

	mov	[_Handle_Name_Table],di
	mov	ax,[_handle_table_size]
	mov	bx,4			; eight-byte name = four words
	mul	bx
	mov	cx,ax
	xor	ax,ax
	rep	stosw

	mov	[_emm_page],di
	mov	cx,[_total_pages]
	shl	cx,1			; bytes in each word-sized page array
endif


	mov	ax,[_emm_page]		; AX = ptr to emm_page array
	add	ax,cx			; AX = ptr to word just past emm_page[]
	mov	[_emm_free],ax		; set ptr for emm_free[]
	add	ax,cx			; AX = ptr to word just past emm_free[]
	mov	[_pft386],ax		; set ptr for _pft386[]
	shl	cx,1			; CX = bytes in total_pages dwords
	add	ax,cx			; AX = ptr to word just past _pft386[]
	mov	[_emm_brk],ax		; set break address for emm data
	shr	cx,2			; CX = total_pages again
;
; init free pages array
;
	mov	[_free_count],cx	; all pages free initially
	mov	[_free_top],0		;  top ptr pts to first free page
	mov	di,[_emm_free]		; ES:DI pts to _emm_free[0]
	mov	bx,[_free_top]		;  BX = current top of free list
	shl	bx,1
	add	di,bx			; ES:DI pts to begin of free page area
	xor	ax,ax			; start with EMM page#0
EMMP_loop:				;   copy free pages into _emm_free
	stosw				; store EMM page#
	inc	ax			;(0.02) increment page#
	loop	EMMP_loop		;Q: all entries in _emm_free[] ?
					;  N: do next page.
;
; fix _page_frame_pages to be a maximum of 4 (for the LIM 3.2 frame)
;
	cmp	[_page_frame_pages],4
	jbe	EMIN_1
	mov	[_page_frame_pages],4
EMIN_1:
;
; See validity of page frame
;
	test	[_PF_base],3ffh        ; if any of these bits are set it is
					; invalid
	jne	EMIN_2			 ;
	cmp	[_PF_base],0E400h	; in the ROM area
	jae	EMIN_2			 ; also invalid
	cmp	[_PF_base],0C000h	; or in the video area
	jnb	EMIN_3			 ; C000-E000 adapter space is valid
	push	ax
	int	12h			 ; M10-M14 require conventional RAM <= frame
	mov	cl,6
	shl	ax,cl			 ; KiB to segment address
	cmp	[_PF_base],ax
	pop	ax
	jae	EMIN_3
EMIN_2:
;
; Page Frame invalid, set it to FFFFh and _page_frame_pages to 0
;
	mov	[_PF_base],0FFFFh
	mov	[_page_frame_pages],0
;
EMIN_3:
;
; setting up _mappable_pages
;	     _physical_page_count
;	     _mappable_page_count
;
;
;
;   -----------------	    -----------------	    -----------------
;   |	for pages   |	    |	 for pages  |	    |		    |FC00h
;   |	  below     |	    |	  below     |	    |---------------|
;   |	  A000h     |	    |	  A000h     |	    |		    |
;   -----------------	    -----------------	    |		    |
;   |		    |	    |		    |	    |	   .	    |
;   |	for pages   |	    |	for pages   |	    |	   .	    |
;   |	  above     |	    |	above	    |	    |	   .	    |
;   |	  A000h     |	    |	A000h	    | <--   |		    |
;   |		    |	    |		    |	|   |---------------|
;   -----------------	    -----------------	|   |		    |4800h
;   | for page frame|	    | for page frame|	|   |---------------|
;   | pages even if |	    | pages only if |	|-------	    |4400h
;   |	they don't  |       |   they exist  |       |---------------|
;   |	  exist     |	    |		    |	    |		    |4000h
;   -----------------	    -----------------	    -----------------
;
;   derived PTE offset	    _mappable_pages
;
;   Each entry reps	    Each entry reps
;   a physical page.	    a mappable ph. page
;
;   WORD.		    WORD
;
;   segment / 64		    1st WORD: segment
;   (not retained)	    of ph. page
;
;
; 1. Set up the page frame pages when a complete frame exists. Missing frame
;    slots still reserve internal physical numbers 0..3.
;
    ;
    ; initialise indexes.
    ;
	xor	si,si			; index into _page_frame_pages
					; thus also physical page number
	xor	di,di			; index into _mappable_pages
    ;
    ; set up for page frame pages
    ;
	mov	cx,[_page_frame_pages]	; get number
	jcxz	EMIN_5			 ; if none exist then skip next portion
    ;
	mov	bx,[_PF_base]		; get page frame base
    ;
    ; the setup loop:
    ;
EMIN_4:
	init_mappable_pages
	inv_mpbl
    ;
    ; update counters for next entry
    ;
	inc	si
	inc	di
	add	bx,0400h
    ;
    ; and loop back
    ;
	loop	EMIN_4
;
EMIN_5:
;
; 2. If page frame pages were less than 4 then also we should set aside
;    four entries in the physical page array
;
	mov	si,4
;
; 3. Setup for the mappable pages above A000h.	Search the mappable_segs
;    array for mappable pages above A000h and for each mappable page make
;    an entry in the arrays
;
    ;
    ; setup the segment and the count of pages we have to look for. also
    ; the index into the mappable_segs array
    ;
	mov	bx,0A000h		; segment
	mov	dx,bx			;
	shr	dx,10			; page # corresponding to segment
    ;
	mov	cx,64			; max page #
	sub	cx,dx			;
    ;
    ; setup loop
EMIN_6:
    ;
    ; see if page mappable
    ;
	xchg	dx,bx
	cmp	cs:mappable_segs[bx],PAGE_MAPPABLE ;
	xchg	dx,bx
	jnz	EMIN_7
    ;
    ; page mappable. set up entries for it
    ;
	init_mappable_pages		; set up the mappable_pages entry
    ;
    ; update counters for next entry
    ;
	inc	si			; these two are only updated
	inc	di			; if an entry is found
EMIN_7:
	inc	dx			; and these two are updated in
	add	bx,0400h		; any case
    ;
    ; and loop back
    ;
	loop	EMIN_6

;
; 4. Finally set up for the system pages
;
    ;
    ; store the physical page # of the 1st system page.
    ;
	mov	cs:[first_sys_ppage],si
    ;
    ; setup the segment and the count of pages we have to look for. also
    ; the index into the mappable_segs array
    ;
	mov	bx,[banking_base]	; lowest segment selected by B=
	mov	dx,bx			;
	shr	dx,10			; page # corresponding to segment
    ;
	mov	cx,40			; max page #
	sub	cx,dx			;
					; number of pages to be examined
    ;
    ; setup loop
EMIN_8:
    ;
    ; see if page mappable.
    ;
	xchg	dx,bx
	cmp	cs:mappable_segs[bx],PAGE_MAPPABLE ;
	xchg	dx,bx
	jnz	EMIN_9
    ;
    ; page mappable. set up entries for it
    ;
	init_mappable_pages		; set up the mappable_pages entry
    ;
    ; update counters for next entry
    ;
	inc	si			; these two are only updated
	inc	di			; if an entry is found
EMIN_9:
	inc	dx			; and these two are updated in
	add	bx,0400h		; any case
    ;
    ; and loop back
    ;
	loop	EMIN_8
;
; 5. finally use the indexes to fill up the counts of the number of entries in
;    each array.
;
	mov	[_physical_page_count],si
	mov	[_mappable_page_count],di
;
;
; 6. and the pages in a context and the number of bytes needed to save a
;    context.
;
	inc	si			; cntxt_pages = (physical_page_count
					; + 1) & NOT 1
	and	si, NOT 0001h		; to round up si to higher even #
	mov	ax,si
	mov	[_cntxt_pages],al	; number of pages in a context
;
	shl	si,1
	add	si,2			; cntxt_bytes = cntxt_pages*2 + 2
	mov	ax,si
	mov	[_cntxt_bytes],al	;
;
	; Allocate each alternate register set for the mapping context exposed by
	; this machine, not the 52-window architectural maximum. _frs_size aliases
	; this word-sized context value. The maximum B=/A= configuration still
	; computes and retains the full structure.
	mov	di,[_emm_brk]
	mov	[FRS_array],di
	mov	bx,[_altreg_count]
	inc	bx			; set zero plus A= alternate sets
EMIN_init_frs:
	push	bx
	xor	ax,ax
	stosw				; FRS_alloc
	mov	ax,NULL_PAGE
	xor	ch,ch
	mov	cl,[_cntxt_pages]
	rep	stosw
	pop	bx
	dec	bx
	jnz	short EMIN_init_frs
	mov	[_emm_brk],di
;

;
; initialize FRS_array
;
	mov	si,[FRS_array]		; DS:SI <-- FRS_array
	mov	[si.FRS_alloc], 1	; mark FRS set 0 as allocated
	mov	[CurRegSetn], 0		; use FRS set 0
	mov	ax,[_altreg_count]
	mov	[FRS_free],al		; set 0 is the current mapping set
	mov	word ptr [CurRegSet], SI; save current FRS pointer

;
; NOW for some Handle 0 initialisation.  We have to reclaim the pages we
; released to the emm page pool from the conventional memory.  This is
; easy.  These happen to be the first k pages in the emm page pool.  We
; need to fix the following data structures to reclaim these.
;
; k pages need to be transferred to emm_page array from emm_free array
; and emmpt_start, _free_top, _free_count and _handle_table and _handle_count
; updated
    ;
    ; find out the number of pages to be reclaimed
    ;
	mov	cx,[sys_size]	    ; in kb
	shr	cx, 4		    ; convert to number of 16k pages
    ;
    ; transfer these many pages from the emm_free array to the emm_pages array
    ;
	push	cx
    ;
	mov	si,_emm_free	    ;
	add	si,_free_top	    ;
	add	si,_free_top	    ; get offset to free page
    ;
	mov	di,_emm_page	    ;
	add	di,_emmpt_start     ;
	add	di,_emmpt_start     ; get offset to next available loc in
				    ; emm_page
    ;
	cld
	rep	movsw		    ; transfer the pages over
    ;
	pop	cx
    ;
    ; fix entry for handle 0 in handle table
    ;
	mov	dx, [_emmpt_start]
	mov	di,[_handle_table]
	mov	[di.ht_index],dx	; offset into emm_page array
	mov	[di.ht_count],cx		; number of pages
    ;
    ; handle_count needs to be incremented to indicate that handle 0 is
    ; allocated
    ;
	inc	[_handle_count]
    ;
    ; fix ptr in emm page tracking arrays
    ;
	add	[_emmpt_start],cx
	add	[_free_top],cx
	sub	[_free_count],cx
;
; Initialise FRS initialisation
;
; di = pointer into FRS. bx = physical page number. si = pointer into emm_page
; cx = number of pages mapped.
;
	mov	si,[_handle_table]
	mov	si,[si.ht_index]	; get pointer into emm_page
	shl	si,1		    ; emm_page is a word array
	add	si,[_emm_page]	    ;
    ;
	GET_FRS_WINDOW	di	    ; get pointer to FRS area

	mov	bx,cs:[first_sys_ppage]
	shl	bx,1
	add	di,bx		    ;
    ;
	cld
	rep	movsw
    ;
;
; the way we have allocated the pages we don't need to  update the Page table
; the pages that have been mapped
;
;  init ELIM h/w emulation (DMA PORTS)
;
	call	InitELIM

;
;  init EMM_PTE - ptrs to EMM pages
;
	call	InitEPage
;
;  leave - no errors
;
	pop	es
	pop	ds
	popa
;
	xor	ax,ax
	clc
	ret
;
EMM_Init	endp

;
LAST	ends

	end
