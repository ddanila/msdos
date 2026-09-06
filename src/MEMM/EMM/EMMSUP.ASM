page	58,132
;******************************************************************************
	title	EMMSUP - EMM support routines
;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp. 1986
;
;   Title:	CEMM.EXE - COMPAQ Expanded Memory Manager 386 Driver
;		EMMLIB.LIB - Expanded Memory Manager Functions Library
;
;   Module:	EMMSUP - EMM support routines 
;
;   Version:	0.04
;
;   Date:	May 13, 1986
;
;******************************************************************************
;
;   Change log:
;
;     DATE    REVISION                  DESCRIPTION
;   --------  --------  -------------------------------------------------------
;   5/13/86   Original	Initial _TEXT
;   6/14/86		Added _sotofar routine and removed stack define.
;   			And added protected mode check to Map_Page (SBP).
;   6/14/86		map_page now sets _current_map(SBP).
;   6/14/86		moved save_current_map and restore_map from C code (SBP)
;   6/14/86		brought SegOffTo24 and SetDescInfo in from LAST code
;			segment as local routines(SBP).
;   6/21/86    0.02	cld in copyout (SBP).
;   6/21/86    0.02	MapHandlePage added.
;   6/23/86    0.02	make_addr, sotofar removed. source_addr and dest_addr
;			added.
;   6/27/86    0.02	Fix for restore_map.
;   6/28/86    0.02	Name change from CEMM386 to CEMM (SBP).
;   7/06/86    0.04	Changed _emm_page,_emm_free, & _pft386 to ptrs (SBP).
;   7/06/86    0.04	Changed assumes from _DATA to DGROUP (SBP).
;   7/06/86    0.04	Changed internal save area structure (SBP).
;   7/06/86    0.04	moved SavePageMap and RestorePageMap to .ASM (SBP).
;   7/07/86    0.04	moved MapHandlePage,SavePageMap, and RestorePageMap to
;			emmp.asm (SBP).
;   5/09/88    1.01	moved routines names_match and flush_tlb from win386 
;   9/01/88		rename SegOffTo24/SetDescInfo to
;			SegOffTo24Resident/SetDescInfoResdient and made public
;******************************************************************************
;
;   Functional Description:
;	Support routines for emm/386
;	C callable 
;
;
;******************************************************************************
.lfcond					; list false conditionals
.386p

;******************************************************************************
;	P U B L I C S
;******************************************************************************
	public _source_addr
	public _dest_addr
	public _copyout
	public _copyin
	public SetDescInfoResident
	public SegOffTo24Resident
;
;******************************************************************************
;	 D E F I N E S
;******************************************************************************

	include	vdmseg.inc
	include vdmsel.inc
	include desc.inc
	include page.inc
;	include instr386.inc
	include	emmdef.inc

FALSE		equ	0
TRUE		equ	not FALSE
CR		equ	0dh
LF		equ	0ah

; Table offsets never escape this owner. Preserve the caller's DS/ES/FS/GS,
; flags and registers while selecting the authoritative protected data owner.
TABLE_LOAD MACRO op, dest, source, width
IFDEF EMM_HIGH_TABLES
        push gs
        push word ptr [TableSelector]
        pop gs
        IFB <width>
        op dest,gs:source
        ELSE
        op dest,width ptr gs:source
        ENDIF
        pop gs
ELSE
        IFB <width>
        op dest,source
        ELSE
        op dest,width ptr source
        ENDIF
ENDIF
ENDM
TABLE_STORE MACRO op, dest, source, width
IFDEF EMM_HIGH_TABLES
        push gs
        push word ptr [TableSelector]
        pop gs
        IFB <width>
        op gs:dest,source
        ELSE
        op width ptr gs:dest,source
        ENDIF
        pop gs
ELSE
        IFB <width>
        op dest,source
        ELSE
        op width ptr dest,source
        ENDIF
ENDIF
ENDM

	page
TABLE_SET_ES MACRO
IFDEF EMM_HIGH_TABLES
        push word ptr [TableSelector]
ELSE
        push ds
ENDIF
        pop es
ENDM
TABLE_SET_DS MACRO
IFDEF EMM_HIGH_TABLES
        push word ptr [TableSelector]
        pop ds
ENDIF
ENDM
;******************************************************************************
;	E X T E R N A L   R E F E R E N C E S
;******************************************************************************

_DATA	SEGMENT
IFDEF EMM_HIGH_TABLES
        public TableSelector
TableSelector dw VDMD_GSEL            ; explicit low fallback until publication
ENDIF
;
;  pointer to entry stack frame
;	stored as offset, SS
extrn	_regp:word

;
;   current state of mapping registers and # of mapping registers emulated
;
;extrn	_current_map:byte
;extrn	_map_size:byte

;
; total # of EMM pages in system
;
extrn	_total_pages:word

;
; ptr to table of emm page # for each handle's logical pages.
;
extrn	_emm_page:word
extrn	_emm_free:word
extrn _DMA_Pages:word, _mappable_pages:word
extrn _physical_page_exceptions:word, _physical_page_exception_count:byte
extrn CurRegSet:word
extrn FRS_array:word, CurRegSetn:byte, FRS_free:byte
extrn _cntxt_bytes:byte, _cntxt_pages:byte, _altreg_count:byte

;
; ptr to table of page table entries for the EMM pages
;
extrn	_pft386:word		; note: actually a dword array

;
;  handle data structure
;
extrn	_handle_table:word
extrn	_handle_table_size:byte
extrn	_Handle_Name_Table:word

;
;   save area for handles
;
extrn	_save_map:word

_DATA	ENDS


	page
;******************************************************************************
;	L O C A L   D A T A
;******************************************************************************
_DATA	SEGMENT
;
; kludge to prevent unresolved from C compiler
;
public	__acrtused
__acrtused	label	dword
	dd (0)
_DATA	ENDS

	page
;******************************************************************************
;	C O D E
;******************************************************************************
_TEXT	SEGMENT
assume	cs:_TEXT, ds:DGROUP, ss:DGROUP

;***********************************************
;
; _source_addr - return far pointer for source address (= int 67 entry DS:SI).
;
;  SYNOPSIS:	src = source_addr()
;		char far *src;	/* ptr to area at DS:SI */
;
;  DESCRIPTION:	This function generates a far pointer equivalent to the client's
;		DS:SI pointer.  If this code was called in protected mode, the
;		address is a (selector,offset) pair; otherwise, it is a segment
;		offset pair.  EMM1_GSEL is used if a selector is needed.
;
; 05/09/88  ISP   No update needed for MEMM
;***********************************************
_source_addr	proc	near
;
	push	bp
;
	mov	bp,[_regp]			; get entry stack frame pointer
	test	[bp.PFlag],PFLAG_VIRTUAL	;Q: real/virtual mode ?
	jnz	sa_pm				; N: go get selector/offset
	mov	ax,word ptr [bp.rSI]		; Y: get offset
	mov	dx,word ptr [bp.rDS]		;    get segment
	jmp	sa_exit				;    return DX:AX = seg:offset
;
;  protected mode - set up selector to client's DS
sa_pm:
	push	bx
	push	cx
	push	es			; save ES
	; 
	; load ES with GDT alias
	;
	push	GDTD_GSEL
	pop	es			; ES -> GDT
	;
	; compute physical address
	;
	mov	ax,word ptr [bp.rDS]	; ax <-- base addr
	mov	dx,word ptr [bp.rSI]	; dx <-- offset
	call	SegOffTo24Resident	; converts to physical addr

	;
	; set up the appropriate table entry
	;
	mov	bx,EMM1_GSEL 	; bx <-- selector 
	mov	cx,0FFFFh	; cx <-- gets limit (64k)
	mov	ah,D_DATA0	; ah <-- gets access rights
	;
	; at this point:
	;	ah -- access rights
	;	al -- bits 16-23 of linear address
	;	dx -- low 16 bits of linear address
	;	cx -- limit = 64k
	;	bx -- selector
	;	es -- selector to GDT Alias
	call	SetDescInfoResident	; set up descriptor

	; 
	; set up return pointer
	;
	xor	ax,ax		; ax <-- offset (0)
	mov	dx,bx		; dx <-- selector
	;
	pop	es		; restore ES
	pop	cx
	pop	bx
;
sa_exit:
	pop	bp
	ret
;
_source_addr	endp

;***********************************************
;
; _dest_addr - return far pointer for destination address (= int 67 entry ES:DI).
;
;  SYNOPSIS:	dest = dest_addr()
;		char far *dest;	/* ptr to area at ES:DI */
;
;  DESCRIPTION:	This function generates a far pointer equivalent to the client's
;		ES:DI pointer.  If this code was called in protected mode, the
;		address is a (selector,offset) pair; otherwise, it is a segment
;		offset pair.  EMM2_GSEL is used if a selector is needed.
;
; 05/09/88  ISP   No update needed for MEMM
;***********************************************
_dest_addr	proc	near
;
	push	bp
;
	mov	bp,[_regp]			; get entry stack frame pointer
	test	[bp.PFlag],PFLAG_VIRTUAL	;Q: real/virtual mode ?
	jnz	da_pm				; N: go get selector/offset
	mov	ax,word ptr [bp.rDI]		; Y: get offset
	mov	dx,word ptr [bp.rES]		;    get segment
	jmp	da_exit				;    return DX:AX = seg:offset
;
;  protected mode - set up selector to client's DS
da_pm:
	push	bx
	push	cx
	push	es			; save ES
	; 
	; load ES with GDT alias
	;
	push	GDTD_GSEL
	pop	es			; ES -> GDT
	;
	; compute physical address
	;
	mov	ax,word ptr [bp.rES]	; ax <-- base addr
	mov	dx,word ptr [bp.rDI]	; dx <-- offset
	call	SegOffTo24Resident	; converts to physical addr

	;
	; set up the appropriate table entry
	;
	mov	bx,EMM2_GSEL 	; bx <-- selector 
	mov	cx,0FFFFh	; cx <-- gets limit (64k)
	mov	ah,D_DATA0	; ah <-- gets access rights
	;
	; at this point:
	;	ah -- access rights
	;	al -- bits 16-23 of linear address
	;	dx -- low 16 bits of linear address
	;	cx -- limit = 64k
	;	bx -- selector
	;	es -- selector to GDT Alias
	call	SetDescInfoResident	; set up descriptor
	
	; 
	; set up return pointer
	;
	xor	ax,ax		; ax <-- offset (0)
	mov	dx,bx		; dx <-- selector
	;
	pop	es		; restore ES
	pop	cx
	pop	bx
;
da_exit:
	pop	bp
	ret
;
_dest_addr	endp

	page
;***********************************************
;
; _copyout
;
; This routine takes a far pointer, a near pointer
; and a byte count and copies from the near address
; to the far address.
;
; Parameters:
;	destptr -- sel:off 286 pointer to target area
;	srcptr --- offset of source data in current D Seg
;	count ---- byte count for copy
;
; uses:
;	cx, ax, es
;
; 05/09/88  ISP   No update needed for MEMM
;***********************************************
destptr	=	4
srcptr	=	8
count	=	10
_copyout	proc	near
	push	bp		; entry prolog
	mov	bp,sp
	push	di		; reg var
	push	si		; reg var

	les	di,[bp+destptr]	; es:di <-- destination address
	mov	si,[bp+srcptr]	; ds:si <-- source address
	mov	cx,[bp+count]	; cx <-- byte count
	cld			;  strings foward
	rep movsb		; do it

	pop	si		; restore reg var
	pop	di		; restore reg var
	pop	bp		
	ret
_copyout	endp
	page

;***********************************************
;
; _copyin
;
; This routine takes a near pointer, a far pointer
; and a byte count and copies from the far address
; to the near address.
;
; Parameters:
;	destptr -- offset of dest in current D Seg
;	srcptr --- sel:off 286 pointer to source data area
;	count ---- byte count for copy
;
; uses:
;	cx, ax, es
;
; 05/09/88  ISP   Written for MEMM.
;***********************************************
destptr	=	4
srcptr	=	6
count	=	10
_copyin	proc	near
	push	bp		; entry prolog
	mov	bp,sp
	push	di		; reg var
	push	si		; reg var
	push	ds

	push	ds
	pop	es		; es to dgroup

	mov	di,[bp+destptr]	; es:di <-- destination address
	lds	si,[bp+srcptr]	; ds:si <-- source address
	mov	cx,[bp+count]	; cx <-- byte count
	cld			;  strings foward
	rep movsb		; do it

	pop	ds
	pop	si		; restore reg var
	pop	di		; restore reg var
	pop	bp		
	ret
_copyin	endp
	page
; Indexed page-array transfers. C arguments are source index, destination
; index and word count. Owners are resolved here; no near pointers escape.
        public _CopyFreeToPages, _CopyPagesToFree, _MovePageEntries
        public ReadPageEntry
_CopyFreeToPages proc near
        xor ax,ax
        jmp short PageArrayCopy
_CopyFreeToPages endp
_CopyPagesToFree proc near
        mov ax,1
        jmp short PageArrayCopy
_CopyPagesToFree endp
_MovePageEntries proc near
        mov ax,2
PageArrayCopy:
        push bp
        mov bp,sp
        push bx
        push si
        push di
        push es
        mov bx,ax
        mov si,[bp+4]
        mov di,[bp+6]
        shl si,1
        shl di,1
        or bx,bx
        jnz short PageSourceAllocated
        add si,[_emm_free]
        jmp short PageDestination
PageSourceAllocated:
        add si,[_emm_page]
PageDestination:
        cmp bx,1
        jne short PageDestinationAllocated
        add di,[_emm_free]
        jmp short PageCopyReady
PageDestinationAllocated:
        add di,[_emm_page]
PageCopyReady:
IFDEF EMM_HIGH_TABLES
        push ds
        TABLE_SET_DS
ENDIF
        push ds
        pop es
        mov cx,[bp+8]
        cld
        jcxz short PageCopyDone
        cmp di,si
        jbe short PageCopyForward
        mov ax,cx
        dec ax
        shl ax,1
        add si,ax
        add di,ax
        std
PageCopyForward:
        rep movsw
PageCopyDone:
        cld
        xor ax,ax
IFDEF EMM_HIGH_TABLES
        pop ds
ENDIF
        pop es
        pop di
        pop si
        pop bx
        pop bp
        ret
_MovePageEntries endp

; AX = bounded page-list index; AX returns the physical-page table index.
ReadPageEntry proc near
        push si
        mov si,ax
        shl si,1
        add si,[_emm_page]
        TABLE_LOAD mov, ax, [si]
        pop si
        ret
ReadPageEntry endp

; Physical-page metadata owner. Register reader: AX index -> EAX entry.
; C reader and exchange return the original first entry in DX:AX.
        public ReadPftEntry, _ReadPft, _SwapPft
ReadPftEntry proc near
        push si
        mov si,ax
        shl si,2
        add si,[_pft386]
        TABLE_LOAD mov, eax, [si]
        pop si
        ret
ReadPftEntry endp
_ReadPft proc near
        push bp
        mov bp,sp
        mov ax,[bp+4]
        call ReadPftEntry
        mov edx,eax
        shr edx,16
        pop bp
        ret
_ReadPft endp
_SwapPft proc near
        push bp
        mov bp,sp
        push si
        push di
        mov si,[bp+4]
        mov di,[bp+6]
        shl si,2
        shl di,2
        add si,[_pft386]
        add di,[_pft386]
        TABLE_LOAD mov, eax, [si]
        TABLE_LOAD mov, edx, [di]
        TABLE_STORE mov, [si], edx
        TABLE_STORE mov, [di], eax
        mov edx,eax
        shr edx,16
        pop di
        pop si
        pop bp
        ret
_SwapPft endp

; Remaining C DMA consumers use indexes, never pointers into movable VDATA.
; Validation remains the caller's responsibility; these do not repair DMA
; capacity or fatal-exit policy. Preserve DS/ES and C's index registers.
        public _ReadDMAEntry, _WriteDMAEntry, _ReadWindowEntry, ReadWindowIndex
; BX = dense index -> BX = 16 KiB physical-page index; other registers and
; flags preserved. The caller owns bounds validation.
ReadWindowIndex proc near
        push si
        mov si,[_mappable_pages]
        TABLE_LOAD movzx, bx, [bx+si], byte
        pop si
        ret
ReadWindowIndex endp

; Current register-map entries. Bounds remain the caller's responsibility.
; Read: AX physical window -> AX mapping. Write: BX window, CX mapping.
; No current-register-set pointer leaves this owner.
        public ReadCurrentMapEntry, WriteCurrentMapEntry
ReadCurrentMapEntry proc near
        push di
        mov di,ax
        shl di,1
        add di,word ptr [CurRegSet]
        TABLE_LOAD mov, ax, [di.FRS_window]
        pop di
        ret
ReadCurrentMapEntry endp
WriteCurrentMapEntry proc near
        push di
        mov di,bx
        shl di,1
        add di,word ptr [CurRegSet]
        TABLE_STORE mov, [di.FRS_window], cx
        pop di
        ret
WriteCurrentMapEntry endp

; Snapshot CX current mapping words to caller-owned ES:DI. DI advances;
; preserve CX/SI and the low data segment. Callers supply a bounded count.
        public ReadCurrentMap, WriteCurrentMapFromFS, SaveCurrentFrame
ReadCurrentMap proc near
        push si
        push cx
        mov si,word ptr [CurRegSet]
        add si,FRS_window
IFDEF EMM_HIGH_TABLES
        push ds
        TABLE_SET_DS
ENDIF
        cld
        rep movsw
IFDEF EMM_HIGH_TABLES
        pop ds
ENDIF
        pop cx
        pop si
        ret
ReadCurrentMap endp

; Copy CX raw mapping words from FS:SI into the current map. SI advances;
; consume CX, preserve AX/BX/DX/DI and caller DS/ES. There is no public header
; in the internal record and no adjacent allocation flag may be overwritten.
WriteCurrentMapFromFS proc near
        push ds
        push es
        push di
        mov di,word ptr [CurRegSet]
        add di,FRS_window
        TABLE_SET_ES
        push fs
        pop ds
        cld
        rep movsw
        pop di
        pop es
        pop ds
        ret
WriteCurrentMapFromFS endp

; Move/exchange saves two scratch windows in the original stack order:
; high word = window 0, low word = window 1. ESI is a value, not a pointer.
        public ReadScratchMapPair, WriteScratchMapPair
ReadScratchMapPair proc near
        push bx
        mov bx,word ptr [CurRegSet]
        TABLE_LOAD mov, esi, [bx.FRS_window], dword
        rol esi,16
        pop bx
        ret
ReadScratchMapPair endp
WriteScratchMapPair proc near
        push bx
        mov bx,word ptr [CurRegSet]
        ror esi,16
        TABLE_STORE mov, [bx.FRS_window], esi, dword
        pop bx
        ret
WriteScratchMapPair endp

; Register-set records never leave this owner. BL selects a record; the
; private lookup returns SI only to the following owner-local services.
FindRegisterSet proc near
        cmp bl,[_altreg_count]
        ja short RegisterSetMissing
        movzx si,bl
        movzx ax,[_cntxt_bytes]
        dec ax
        imul si,ax
        add si,[FRS_array]
        TABLE_STORE cmp, [si.FRS_alloc], 0, byte
        je short RegisterSetMissing
        clc
        ret
RegisterSetMissing:
        stc
        ret
FindRegisterSet endp

; CF invalid; otherwise AX=1 selected, AX=0 already current nonzero set.
        public SelectRegisterSet, AllocateRegisterSet, ReleaseRegisterSet
SelectRegisterSet proc near
        push si
        call FindRegisterSet
        jc short SelectRegisterDone
        xor ax,ax
        or bl,bl
        jz short SelectRegisterPublish
        cmp bl,[CurRegSetn]
        je short SelectRegisterDone
SelectRegisterPublish:
        mov word ptr [CurRegSet],si
        mov [CurRegSetn],bl
        inc ax
        clc
SelectRegisterDone:
        pop si
        ret
SelectRegisterSet endp

; AH status, BL allocated set. Clone the current map before returning.
AllocateRegisterSet proc near
        push si
        push di
        push cx
        push es
        cmp [FRS_free],0
        je short AllocateRegisterFull
        mov di,[FRS_array]
        xor bl,bl
AllocateRegisterSearch:
        TABLE_STORE cmp, [di.FRS_alloc], 0, byte
        je short AllocateRegisterFound
        movzx ax,[_cntxt_bytes]
        dec ax
        add di,ax
        inc bl
        cmp bl,[_altreg_count]
        jbe short AllocateRegisterSearch
        mov ah,EMM_SW_MALFUNCTION
        jmp short AllocateRegisterDone
AllocateRegisterFound:
        TABLE_STORE mov, [di.FRS_alloc], 1, byte
        dec [FRS_free]
        add di,FRS_window
        TABLE_SET_ES
        movzx cx,[_cntxt_pages]
        call ReadCurrentMap
        xor ax,ax
        jmp short AllocateRegisterDone
AllocateRegisterFull:
        mov ah,NO_MORE_FRSETS
AllocateRegisterDone:
        pop es
        pop cx
        pop di
        pop si
        ret
AllocateRegisterSet endp

; AH status; set zero is ignored, active/invalid/already-free sets rejected.
ReleaseRegisterSet proc near
        push si
        xor ax,ax
        or bl,bl
        jz short ReleaseRegisterDone
        cmp bl,[CurRegSetn]
        je short ReleaseRegisterInvalid
        call FindRegisterSet
        jc short ReleaseRegisterInvalid
        TABLE_STORE mov, [si.FRS_alloc], 0, byte
        inc [FRS_free]
        xor ax,ax
        jmp short ReleaseRegisterDone
ReleaseRegisterInvalid:
        mov ah,FRSET_UNDEFINED
ReleaseRegisterDone:
        pop si
        ret
ReleaseRegisterSet endp

; AX validated handle: save the four LIM frame entries inside the table owner.
; The intermediate current-map pointer is private to EMMSUP.
SaveCurrentFrame proc near
        push es
        push di
        TABLE_SET_ES
        mov di,word ptr [CurRegSet]
        add di,FRS_window
        call WriteSavedMap
        pop di
        pop es
        ret
SaveCurrentFrame endp

; AX internal physical page -> AL public Pn= identifier. Retain the complete
; explicit/implicit ranking operation with its sparse table owner.
        public physical_to_external_id
physical_to_external_id proc near
        push bx
        push cx
        push dx
        push si
        mov dl,al
        mov si,[_physical_page_exceptions]
        xor cx,cx
        mov cl,[_physical_page_exception_count]
physical_external_explicit_loop:
        jcxz short physical_external_implicit
        TABLE_LOAD cmp, dl, [si]
        je short physical_external_explicit
        add si,2
        loop physical_external_explicit_loop
physical_external_implicit:
        mov bl,dl
        mov si,[_physical_page_exceptions]
        xor cx,cx
        mov cl,[_physical_page_exception_count]
physical_external_internal_rank:
        jcxz short physical_external_first_candidate
        TABLE_STORE cmp, [si], dl
        jae short physical_external_internal_next
        dec bl
physical_external_internal_next:
        add si,2
        loop physical_external_internal_rank
physical_external_first_candidate:
        xor al,al
physical_external_candidate:
        mov si,[_physical_page_exceptions]
        xor cx,cx
        mov cl,[_physical_page_exception_count]
physical_external_reserved_loop:
        jcxz short physical_external_candidate_free
        TABLE_LOAD cmp, al, [si+1]
        je short physical_external_candidate_used
        add si,2
        loop physical_external_reserved_loop
physical_external_candidate_free:
        or bl,bl
        jz short physical_external_done
        dec bl
physical_external_candidate_used:
        inc al
        jmp short physical_external_candidate
physical_external_explicit:
        TABLE_LOAD mov, al, [si+1]
physical_external_done:
        pop si
        pop dx
        pop cx
        pop bx
        ret
physical_to_external_id endp
_ReadDMAEntry proc near
        push bp
        mov bp,sp
        push si
        mov si,[bp+4]
        shl si,1
        add si,[_DMA_Pages]
        TABLE_LOAD mov, ax, [si]
        pop si
        pop bp
        ret
_ReadDMAEntry endp
_WriteDMAEntry proc near
        push bp
        mov bp,sp
        push si
        mov si,[bp+4]
        shl si,1
        add si,[_DMA_Pages]
        mov ax,[bp+6]
        TABLE_STORE mov, [si], ax
        pop si
        pop bp
        ret
_WriteDMAEntry endp
_ReadWindowEntry proc near
        push bp
        mov bp,sp
        push si
        mov si,[bp+4]
        add si,[_mappable_pages]
        xor ax,ax
        TABLE_LOAD mov, al, [si]
        pop si
        pop bp
        ret
_ReadWindowEntry endp
; Register validation preserves the index and all general registers.
; No handle-record pointer escapes; CF reports an invalid/inactive index.
        public CheckHandleDX, ReadHandleIndex, ReadHandleCount
CheckHandleDX proc near
        push si
        or dh,dh
        jnz short HandleDXInvalid
        cmp dl,[_handle_table_size]
        jae short HandleDXInvalid
        mov si,dx
        shl si,2
        add si,[_handle_table]
        TABLE_STORE cmp, [si.ht_index], NULL_PAGE, word
        je short HandleDXInvalid
        pop si
        clc
        ret
HandleDXInvalid:
        pop si
        stc
        ret
CheckHandleDX endp

; AX = bounded handle index; AX returns a field, other registers preserved.
ReadHandleIndex proc near
        push si
        mov si,ax
        shl si,2
        add si,[_handle_table]
        TABLE_LOAD mov, ax, [si.ht_index]
        pop si
        ret
ReadHandleIndex endp
ReadHandleCount proc near
        push si
        mov si,ax
        shl si,2
        add si,[_handle_table]
        TABLE_LOAD mov, ax, [si.ht_count]
        pop si
        ret
ReadHandleCount endp

; C validation returns a boolean and sets the saved EMS error on failure.
        public _HandleValid, _HandleIndex, _HandleCount
        public _SetHandleIndex, _SetHandleCount
_HandleValid proc near
        push bp
        push dx
        mov bp,[_regp]
        mov dx,word ptr [bp.rDX]
        call CheckHandleDX
        mov ax,0
        jc short HandleValidFailed
        inc ax
        jmp short HandleValidDone
HandleValidFailed:
        mov byte ptr [bp.rAX+1],INVALID_HANDLE
HandleValidDone:
        pop dx
        pop bp
        ret
_HandleValid endp

; Field access: index at BP+4, optional new value at BP+6. No record pointer
; escapes to C. CX bit 1 selects page_count; bit 2 selects a write.
_HandleIndex proc near
        xor cx,cx
        jmp short HandleField
_HandleIndex endp
_HandleCount proc near
        mov cx,2
        jmp short HandleField
_HandleCount endp
_SetHandleIndex proc near
        mov cx,4
        jmp short HandleField
_SetHandleIndex endp
_SetHandleCount proc near
        mov cx,6
HandleField:
        push bp
        mov bp,sp
        push si
        mov si,[bp+4]
        shl si,2
        add si,[_handle_table]
        test cx,2
        jz short HandleFieldSelected
        add si,2
HandleFieldSelected:
        test cx,4
        jnz short HandleFieldWrite
        TABLE_LOAD mov, ax, [si]
        jmp short HandleFieldDone
HandleFieldWrite:
        mov ax,[bp+6]
        TABLE_STORE mov, [si], ax
HandleFieldDone:
        pop si
        pop bp
        ret
_SetHandleCount endp

;***********************************************
;
; flush_tlb:
;
; no params, no return value, uses eax
;
; flush the Translation Look-Aside Buffer
;
; 05/09/88  ISP   Shifted in from WIN386
;***********************************************
_flush_tlb	proc	near
public	_flush_tlb
	mov	eax, cr3
	mov	cr3, eax
	ret
_flush_tlb	endp

; Indexed access boundary for the complete dynamic handle-name table.
; C ABI: index at BP+4; far client pointer or near comparison name at BP+6.
; Only this service resolves the table's owner. The initial implementation
; uses DGROUP; a high-data selector can replace that owner without exposing
; selector:offset table pointers to callers. Preserve the distinct C SS/DS.
        public _ReadHandleName, _WriteHandleName
        public _ClearHandleName, _MatchHandleName
_ReadHandleName proc near
        xor ax,ax
        jmp short HandleNameAccess
_ReadHandleName endp
_WriteHandleName proc near
        mov ax,1
        jmp short HandleNameAccess
_WriteHandleName endp
_ClearHandleName proc near
        mov ax,2
        jmp short HandleNameAccess
_ClearHandleName endp
_MatchHandleName proc near
        mov ax,3
HandleNameAccess:
        push bp
        mov bp,sp
        push bx
        push si
        push di
        push ds
        push es
        mov bx,ax
        mov si,[bp+4]
        shl si,3
        add si,[_Handle_Name_Table]
        TABLE_SET_ES
        cld
        mov cx,8
        cmp bx,3
        je short HandleNameCompare
        cmp bx,2
        je short HandleNameClear
        or bx,bx
        jnz short HandleNameWrite
        les di,[bp+6]
        TABLE_SET_DS
        rep movsb
        jmp short HandleNameDone
HandleNameWrite:
        mov di,si
        lds si,[bp+6]
        rep movsb
        jmp short HandleNameDone
HandleNameClear:
        mov di,si
        xor ax,ax
        rep stosb
        jmp short HandleNameDone
HandleNameCompare:
IFDEF EMM_HIGH_TABLES
        mov di,si
        mov si,[bp+6]
ELSE
        mov di,[bp+6]
ENDIF
        xor ax,ax
        repe cmpsb
        jne short HandleNameExit
        not ax
        jmp short HandleNameExit
HandleNameDone:
        xor ax,ax
HandleNameExit:
        pop es
        pop ds
        pop di
        pop si
        pop bx
        pop bp
        ret
_MatchHandleName endp

; Saved-map services: AX is a validated handle index. Read/write exchange
; exactly four words with ES:DI, which may name a caller's distinct stack.
; The table's near pointer never escapes this owner boundary.
        public ReadSavedMap, WriteSavedMap, ClearSavedMap, PeekSavedMap
        public _SavedMapInUse
PeekSavedMap proc near
        push si
        mov si,ax
        shl si,3
        add si,[_save_map]
        TABLE_LOAD mov, bx, [si]
        pop si
        ret
PeekSavedMap endp
_SavedMapInUse proc near
        push bp
        mov bp,sp
        push bx
        mov ax,[bp+4]
        call PeekSavedMap
        xor ax,ax
        cmp bx,NULL_SAVE_MAP
        je short SavedMapUnused
        dec ax
SavedMapUnused:
        pop bx
        pop bp
        ret
_SavedMapInUse endp
ClearSavedMap proc near
        push si
        mov si,ax
        shl si,3
        add si,[_save_map]
        TABLE_STORE mov, [si], NULL_SAVE_MAP, word
        pop si
        ret
ClearSavedMap endp
ReadSavedMap proc near
        push si
        push di
        push cx
        mov si,ax
        shl si,3
        add si,[_save_map]
        mov cx,4
IFDEF EMM_HIGH_TABLES
        push ds
        TABLE_SET_DS
ENDIF
        cld
        rep movsw
IFDEF EMM_HIGH_TABLES
        pop ds
ENDIF
        pop cx
        pop di
        pop si
        ret
ReadSavedMap endp
WriteSavedMap proc near
        push si
        push di
        push cx
        push ds
        push es
        mov si,di
        mov di,ax
        shl di,3
        add di,[_save_map]
        push es
        TABLE_SET_ES
        pop ds
        mov cx,4
        cld
        rep movsw
        pop es
        pop ds
        pop cx
        pop di
        pop si
        ret
WriteSavedMap endp

	page
;**	SetDescInfoResident - set descriptor information
;
;	The limit field of a specified descriptor is set.
;	  (limit = size - 1).
;	The base address of the specified descriptor is set.
;	The access field of the specified descriptor is set.
;
;	ENTRY	BX = selector
;		ES:0 = descriptor table to use
;		CX = limit
;		AL, DX = 24 bit base address
;		AH = access rights byte
;	EXIT	None
;	USES	Flags, other regs preserved
;
;	WARNING This code only works on a 286. It can be called in
;		either mode.

SetDescInfoResident proc near
	push	bx			; save selector
	and	bl,SEL_LOW_MASK

;	fill in the limit field

	mov	es:[bx],cx

;	fill in base address

	mov	es:[bx + 2],dx
	mov	es:[bx + 4],al

;	fill in access rights byte

	mov	es:[bx + 5],ah
	pop	bx
	ret
SetDescInfoResident endp

	page
;**	SegOffTo24Resident - convert seg:off to 24 bit physical address
;
;	The specified real mode segment:offset is converted to
;	a 24 bit physical address.
;
;	ENTRY	AX = segment
;		DX = offset
;	EXIT	AL, DX = 24 bit physical address
;	USES	AH, Flags, other regs preserved.
;
;	WARNING This code only works on a 286. It can be called in
;		either mode.

SegOffTo24Resident proc near
	push	cx

;	Convert AX:DX into 24 bit addr in AL, DX

	mov	ch,ah
	shl	ax,4
	shr	ch,4			; CH = high byte
	add	dx,ax			; DX = low word
	mov	al,ch			; AL = high byte
	adc	al,0			; propagate cy from low word

	pop	cx
	ret
SegOffTo24Resident endp

_TEXT	ENDS
END

