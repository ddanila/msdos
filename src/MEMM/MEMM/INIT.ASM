

	page 58,132
;******************************************************************************
	TITLE	INIT - initialization code for MEMM
;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp. 1986
;
;   Title:	MEMM.EXE - MICROSOFT Expanded Memory Manager 386 Driver
;
;   Module:	INIT - initialization code for MEMM
;
;   Version:	0.05
;
;   Date:	May 24,1986
;
;   Author:
;
;******************************************************************************
;
;	Change Log:
;
;	DATE	 REVISION	Description
;	-------- --------	--------------------------------------------
;	05/24/86 Original
;	06/18/86 0.01		Added AUTO as a valid config line parameter.
;	06/25/86 0.02		Added call to debug init.
;	06/27/86 0.02		Check for Mx length = 2 and only 2
;	06/28/86 0.02		Change name from MEMM386 to MEMM
;	06/29/86 0.02		Size > 8192 were used instead of converted
;				to 256
;	07/03/86 0.04		Added TEXT_Seg
;	07/06/86 0.04		changed assume to DGROUP
;	07/06/86 0.04		moved init messages to LAST
;	07/10/86 0.05		added int15 patch and int67 patch here
;	07/20/88		removed debugger codes (pc)
;	07/29/88		removed ON/OFF/AUTO support
;
;******************************************************************************
;   Functional Description:
;	This module allocates the pool of extended memory to be used for
;   expanded memory, then call routines to initialize the data structures
;   for EMM and VDM.
;
;******************************************************************************
.lfcond
.386p
	page
;******************************************************************************
;			P U B L I C   D E C L A R A T I O N S
;******************************************************************************
;
	public	Init_MEMM386

	public	pool_size
	public	min_xms
	public	dma_page_limit
	public	banking_base
	public	requested_page_count
	public	requested_page_ids
	public	requested_page_segments
	public	msg_flag
	public	Active_Status
	public	Auto_Mode
	public	initial_mode
	public	dos_version
	public	TEXT_Seg
	public	TEXT_Phys
	public	STACK_Seg
	public	GDT_Seg
	public	IDT_Seg
	public	TSS_Seg
	public	driver_end
	public	powr10


	page
;******************************************************************************
;			L O C A L   C O N S T A N T S
;******************************************************************************
;
	include vdmseg.inc
	include vdmsel.inc	; for Deb386 Init
	include desc.inc	; "   "      "
	include emm386.inc
	include driver.equ
	include driver.str
	include ascii_sm.equ
	include emmdef.inc
	include page.inc
;
;  maximum value for SIZE parameter
;
MAX_SIZE	equ	32 * 1024	; 32K => 32Meg

;
MS_DOS		equ	21h
PRINT_STRING	equ	09h
GET_VERSION	equ	30h
;
FALSE	equ	0
TRUE	equ	not FALSE
DOS3X_ADJ	equ	1		; DOS 3.x base memory adjustment

;
;   macro for printing messages located in LAST segment
;	ENTRY: DX = offset LAST:message
;
PRINT_MSG	macro
	push	ds
	push	seg LAST
	pop	ds		; ds = LAST
	mov	ah,PRINT_STRING
	int	MS_DOS		; output init message
	pop	ds
	ENDM


;******************************************************************************
;			E X T E R N A L    R E F E R E N C E S
;******************************************************************************
;
;
LAST	segment
	extrn	ext_size:word	    ; size of extended memory allocated
	extrn	sys_size:word	    ; size of system memory allocated

LAST	ends

_DATA	segment

;	 extrn	 himem_use:byte      ;* this is defined in oemproc.asm since it
				    ;  deals with memory so oem dependent
	extrn	PF_Base:word
	extrn	_page_frame_pages:byte
	extrn	_free_count:word
	extrn	_free_top:word
	extrn	_emm_free:word
	extrn	_pft386:word
	extrn	PageT_Seg:word
	extrn	_handle_table_size:byte
	extrn	_altreg_count:byte

_DATA	ends

ABS0	segment use16 at 0
	org 4*15h		; int 15h vector
i15_vector	dw	0
		dw	0

	org 4*67h		; int 67h vector
i67_vector	dw	0
		dw	0
ABS0	ends

;
R_CODE	segment
extrn	i15_Entry:near		; int15h patch code
extrn	EMM_rEntry:near 	; int67h patch code
extrn	i15_Old:word		; old int15 vector
extrn	ELIM_Entry:far		; installed ON/OFF/AUTO control
R_CODE	ends

;
_TEXT	segment

	extrn	Inst_chk_f:far		; check for MEMM already installed
	extrn	FarGoVirtual:far	; go to virtual mode
	extrn	get_token:near		; get token from command line

_TEXT	ends
;
LAST	segment
	extrn	RelocateText:near
	extrn	CompactVData:near

	extrn	VerifyMachine:near
	extrn	InitMess:byte
	extrn	InstallMess:byte
	extrn	ISizeMess:byte
	extrn	ExtSizeMess:byte
	extrn	SysSizeMess:byte
	extrn	PFBAMess:byte
	extrn	ActiveMess:byte
	extrn	InactiveMess:byte
	extrn	AutoMess:byte
	extrn	InvParm:byte
	extrn	InvPFBA:byte
	extrn	InvMRA:byte
	extrn	Adj_Size:byte
	extrn	InsfMem:byte
	extrn	Incorrect_DOS:byte
	extrn	Incorrect_PRT:byte
	extrn	Already_Inst:byte
	extrn	No_PF_Avail:byte
	extrn	PFWarning:byte

	extrn	Is386:far		; check for 386
	extrn	EMM_Init:near		; initialization for EMM data structs
	extrn	AllocMem:near		; allocate extended memory routine
	extrn	InitTab:near		; OEM init code for tables
	extrn	VDM_Init:near		; initialize VDM
	extrn	DeallocMem:near 	; deallocate hi/extended memory routine

	extrn	find_phys_pages:near	; find the mappable pages in 0-1M range
	extrn	exclude_segments:near	; exclude segments within a range
	extrn	estb_mach_state:near	; establish machine environment
	extrn	mappable_segs:byte

powr10		dw	1,10,100,1000,10000

LAST	ends

	page
;******************************************************************************
;			S E G M E N T	D E F I N I T I O N
;******************************************************************************

	page
;******************************************************************************
;	Data segment
;******************************************************************************
_DATA	segment
;
max_arg_len	equ	11		; maximum length of argument on cmd line
;
;  Active_Status is used to signal the termination condition for the
;	driver.  After the driver installs, Active_Status holds the
;	current status (ON or OFF).
;  Auto_Mode is set when MEMM is running in AUTO mode.
;
Active_Status	db	0FFh	; 0 => OFF , non-zero => ON
Auto_Mode	db	0h	; non-zero => auto mode

;
;  The following pointers are segment addresses for various segments
;
TEXT_Seg	dw	seg _TEXT	; current segment for _TEXT
GDT_Seg 	dw	seg GDT 	; current segment for GDT
TSS_Seg 	dw	seg TSS 	; current segment for TSS

_DATA	ends

LAST	segment
; Installation diagnostics and tokenization state are not used by the
; installed driver. Later ON/OFF/AUTO invocations load their own image.
msg_flag	dw	0	; installation message flags
arg_str 	db	max_arg_len+1	dup(0)
TEXT_Phys	dd	0		; protected-mode copy in locked XMS
STACK_Seg	dw	seg STACK	; initialization stack segment
IDT_Seg 	dw	seg IDT 	; initialization IDT segment
LAST	ends


;******************************************************************************
;
;	Code Segments
;
;******************************************************************************
;
_TEXT	segment
	assume	cs:_TEXT


;*************************************************************************
;
;	get_token_far	call get_token which must be near since it is
;			also part of a .COM file
;
;*************************************************************************
get_token_far		proc	far
	call	get_token
	ret
get_token_far		endp
_TEXT	ends

LAST	segment
	assume	cs:LAST, ds:DGROUP, es:DGROUP

; P=/FRAME option bookkeeping is consumed only while the discardable LAST
; initialization code builds the physical-page map. Keep it out of resident
; DGROUP and address it through CS from all initialization modules.
requested_page_count db	0
requested_page_ids db	20 dup (0)
requested_page_segments dw 20 dup (0)
p_frame_seen	db	0
p_frame_segments dw	4 dup (0ffffh)
dos_version	db	0h	; MS-DOS version during installation
pool_size	dw	0	; requested EMM pool in KiB
min_xms		dw	0	; extended memory that L= keeps available to XMS
dma_page_limit	dw	1	; D= buffered DMA capacity in 16 KiB pages
banking_base	dw	4000h	; B= lowest conventional banking segment
page_id_temp	db	0
umb_mode	db	0	; RAM or NOEMS requested paging-backed UMBs
noems_mode	db	0	; NOEMS suppresses the EMS page frame
initial_mode	db	0h	; 0 => ON, 1 => OFF, 2 => AUTO
ifdef EMM_SPLIT_PREPARE
prepare_request dd 0             ; borrowed SYSINIT packet, not an INIT stack slot
resume_target dw 0
endif
ifdef EMM_ACTIVATION_STACK
resume_ss dw 0
resume_sp dw 0
resume_flags dw 0
ifdef EMM_ACTIVATION_BAD_STACK
resume_guard dw 0               ; negative control for the stack witness
else
resume_guard dw 0cafeh
endif
resume_stack db 2048 dup (0)
resume_stack_top LABEL BYTE
endif
ifdef EMM_REJECT_PREPARED
prepare_xms_entry dd 0
prepare_xms_largest dw 0
prepare_xms_total dw 0
prepare_xms_valid db 0
endif
mode_seen	db	0h
weitek_mode	db	0h	; parsed DOS 5 W= setting; hardware remains optional
driver_end	dw	0	; end of driver -> driver brk address
		dw	seg LAST

UMB_FIRST_PAGE	equ	0a000h / 0400h
UMB_PAGE_COUNT	equ	(0f000h - 0a000h) / 0400h
umb_peer	db	0
umb_candidates	db	UMB_PAGE_COUNT dup (0)
umb_includes	db	UMB_PAGE_COUNT dup (0)
umb_excludes	db	UMB_PAGE_COUNT dup (0)
umb_backing_count dw	0
; Discarded selector workspace: one physical base per current 128 KiB region.
umb_dma_base	dd	0
umb_dma_limit	dw	0
umb_registered	db	0
umb_registration dw	1, 0
ifdef UMB_SUBPAGE_MAPPING
		dw	24 dup (0, 0)
umb_coarse_candidates db UMB_PAGE_COUNT dup (0)
umb_saved_windows db UMB_PAGE_COUNT dup (0)
umb_active_masks db UMB_PAGE_COUNT dup (0)
umb_original_ptes dd (UMB_PAGE_COUNT * 4) dup (0)
umb_fine_attempt db 1
ifndef UMB_SUBPAGE_DISCOVERY
	.err <UMB_SUBPAGE_MAPPING requires UMB_SUBPAGE_DISCOVERY>
endif
else
		dw	UMB_PAGE_COUNT dup (0, 0)
endif
ifdef UMB_SUBPAGE_DISCOVERY
; Diagnostic only: no fine mask is consumed by the installed mapper yet.
umb_fine_allowed db     32 dup (0), 48 dup (1)
umb_fine_masks  db      UMB_PAGE_COUNT dup (0)
umb_fine_label  db      'UMB_FINE=',0
endif

	page
;******************************************************************************
;	Init - Initialization routine for MEMM.
;
;	ENTRY: DS:BX pts to INIT request header.
;
;	EXIT:  AX = INIT status for request header
;		if NO errors :
;			MEMM initialized.
;			if [ON] parameter specified on command line
;			    exit in Virtual mode and MEMM active.
;			else ( [OFF] parameter specified )
;			    exit in Real mode and MEMM inactive.
;		if errors:
;			Real Mode
;	USED: none
;
;******************************************************************************
; Development-only phase witness. Binary E9 records: 'IP', stage byte,
; SMSW word and INT 15h / INT 67h far pointers, all little endian.
; This observes live state; it neither defers initialization nor changes owners.
INIT_PHASE MACRO stage
ifdef EMM_INIT_PHASE_TRACE
        pushf
        pusha
        push ds
        cld
        mov dx,0e9h
        mov al,'I'
        out dx,al
        mov al,'P'
        out dx,al
        mov al,stage
        out dx,al
        smsw ax
        out dx,al
        mov al,ah
        out dx,al
        xor ax,ax
        mov ds,ax
        mov si,15h*4
        mov cx,4
        rep_phase_15_&stage:
        lodsb
        out dx,al
        loop rep_phase_15_&stage
        mov si,67h*4
        mov cx,4
        rep_phase_67_&stage:
        lodsb
        out dx,al
        loop rep_phase_67_&stage
        pop ds
        popa
        popf
endif
ENDM

ifdef EMM_SPLIT_PREPARE
PREPARE_ERROR TEXTEQU <ProviderPrepareFailed>
else
PREPARE_ERROR TEXTEQU <IE_exit>
endif

Init_MEMM386	proc	far
	push	bx		; BP+10
	push	dx		; BP+8
	push	bp		; BP+6
	push	di		; BP+4
	push	ds		; BP+2
	push	es		; BP+0
	mov	bp,sp
ifdef EMM_SPLIT_PREPARE
        mov word ptr cs:[prepare_request],bx
        mov word ptr cs:[prepare_request+2],ds
endif
;
;  set up DS = DGROUP and ES:BX to request header
;
	push	ds
	pop	es			; ES:BX pts to req hdr
	mov	ax,seg DGROUP
	mov	ds,ax			; DS = DGROUP

;
;	initialize break address to not install
;
	mov	word ptr ES:[bx.BRK_OFF],0000	; set it
	mov	ax,seg R_CODE		; get brk addr segment
	inc	ax			; reserve dos link pointer
	mov	ES:[bx.BRK_SEG],ax	; break addr = cs - don't install
	mov	byte ptr es:[bx.NUM_UNITS],0	; 0 - don't install
ifdef EMM_SPLIT_PREPARE
        ; Preparation returns before descriptors, UMB publication or PE entry.
        ; This adapter resumes immediately, but the service entry returns
        ; independently of this caller's saved-register frame.
        call PrepareProvider
        jc ProviderAdapterFinish
        INIT_PHASE 9
ifdef EMM_POISON_INIT_REQUEST
        ; Test only: activation must not recover the request from saved DS/BX.
        ; Restore only when the adapter returns, even on failure.
        mov word ptr ss:[bp+2],0
        mov word ptr ss:[bp+10],0
endif
ifdef EMM_REJECT_PREPARED
        or [msg_flag],MEM_ERR_MSG
        jmp ProviderAdapterFinish
endif
        mov cs:[resume_target],offset ActivateProvider
        jmp short ProviderAdapterResume
ProviderAdapterFinish:
        mov cs:[resume_target],offset FinishProvider
ProviderAdapterResume:
ifdef EMM_ACTIVATION_STACK
        push bp
        push dx
        pushf
        pop cs:[resume_flags]
        mov cs:[resume_ss],ss
        mov cs:[resume_sp],sp
        cli
        mov dx,cs
        mov ss,dx
        mov sp,offset resume_stack_top
        xor bp,bp
        push cs:[resume_flags]
        popf
        INIT_PHASE 12
endif
        call word ptr cs:[resume_target]
ifdef EMM_ACTIVATION_STACK
        cmp sp,offset resume_stack_top
        jne ProviderStackBad
        cmp cs:[resume_guard],0cafeh
        jne ProviderStackBad
        INIT_PHASE 13
        jmp short ProviderRestoreStack
ProviderStackBad:
        INIT_PHASE 14
ProviderRestoreStack:
        cli
        mov dx,cs:[resume_ss]
        mov ss,dx
        mov sp,cs:[resume_sp]
        push cs:[resume_flags]
        popf
        pop dx
        pop bp
endif
ifdef EMM_POISON_INIT_REQUEST
        push ax
        mov ax,word ptr cs:[prepare_request+2]
        mov ss:[bp+2],ax
        mov ax,word ptr cs:[prepare_request]
        mov ss:[bp+10],ax
        pop ax
endif
        pop es
        pop ds
        pop di
        pop bp
        pop dx
        pop bx
        retf
        PUBLIC PrepareProvider
PrepareProvider LABEL NEAR
endif
;
;	verify that MEMM is not already installed
;
	call	Inst_chk_f
	or	ax,ax			; q: already installed?
	jz	chk_pt			; n: go check processor type
	or	[msg_flag],INS_ERR_MSG	; y: error
	jmp	PREPARE_ERROR 		; quit
;
;  verify processor type
;
chk_pt:
	call	Is386			;Q: is this a 386 ?
	jc	inc_prc 		;  N: no, set error (Is386 returns carry)
					;  Y: check machine type
;
;  verify machine type
;
chk_mt:
	stc				; Indicate this is verify from INIT
	call	VerifyMachine		;Q: is this a good machine to run on?
	jnc	chk_dos 		; y: ok so far. go check dos version
inc_prc:
	or	[msg_flag],INC_PRC_MSG	; n: incorrect processor type
	jmp	PREPARE_ERROR 		; quit
;
;  get DOS version - accept >= 3.1
;
chk_dos:
	push	bx
	mov	ah,GET_VERSION
	int	MS_DOS			; get dos version #
	mov	[dos_version],al	; save it.
	pop	bx
	cmp	al,4			;Q: DOS 4.00 or later?
	jae	IE_parse		;  Y: OK - continue install
	cmp	al,3			;Q: DOS 3.xx ?
	jl	IE_dos_err		;  N: return error
	cmp	ah,10			;Q: current DOS >= 3.10 ?
	jae	IE_parse		;  Y: OK - continue install
IE_dos_err:
	or	[msg_flag],INC_DOS_MSG	;  N: set error and exit
	jmp	PREPARE_ERROR
;
;  parse command line for
;	(1) requested size for expanded memory
;	(2) page frame base address
;	(3) I/O addresses for board emulations
;	(4) Driver exit mode (virtual or real)
;
IE_parse:
	les	di,ES:[bx.ARG_PTR]	; ES:DI pts to config.sys command
					;	line parameters
	call	parser			; parse the parameters
	test	[msg_flag],KILLER_MSG	;Q: any killer messages?
	jz	IE_mach_state		;  N: go to establish machine state
	jmp	PREPARE_ERROR 		;  Y: exit with error

IE_mach_state:
;
	push	ds
	pop	es			; ES:DGROUP
;
	call	estb_mach_state 	; since we are an environment, we need
					; to find the state we exist in right
					; now and maintain it.
	test	[msg_flag],KILLER_MSG	;Q: any killer messages?
	jz	IE_find_phys		;  N:go to find physical pages
	jmp	PREPARE_ERROR 		;  Y: exit with error
;
IE_find_phys:
	call	find_phys_pages 	; find mappable physical pages
					; and page frame
	test	[msg_flag],KILLER_MSG	;Q: any killer messages
	jnz	short IE_find_error
	cmp	[noems_mode],0
	je	short IE_prepare_umb
	mov	[PF_Base],0ffffh	; EMM_Init converts this to no page frame
IE_prepare_umb:
	cmp	[umb_mode],0
	je	short IE_skip_prepare_umb
	call	Prepare_UMB		; remove safe UMA candidates from EMS windows
IE_skip_prepare_umb:
	jmp	IE_alloc		; Go allocate logical pages
IE_find_error:
	jmp	PREPARE_ERROR 		; exit with error
;
;  find and allocate logical emm pages
;
IE_alloc:
ifdef EMM_REJECT_PREPARED
        pusha
        push es
        mov ax,4310h
        int 2fh
        mov word ptr cs:[prepare_xms_entry],bx
        mov word ptr cs:[prepare_xms_entry+2],es
        mov ah,08h
        call dword ptr cs:[prepare_xms_entry]
        mov cs:[prepare_xms_largest],ax
        mov cs:[prepare_xms_total],dx
        mov cs:[prepare_xms_valid],1
        pop es
        popa
endif
	INIT_PHASE 1
	call	AllocMem
	test	[msg_flag],KILLER_MSG	;Q: any killer messages?
ifdef EMM_SPLIT_PREPARE
        jnz ProviderPrepareFailed
        clc
        retn
ProviderPrepareFailed:
        stc
        retn
else
	jz	IE_InitEMM		;  N: init EMM
	jmp	IE_exit 		;  Y: exit
endif
;
;  init EMM data
;
IE_InitEMM:
ifdef EMM_SPLIT_PREPARE
        PUBLIC ActivateProvider
ActivateProvider LABEL NEAR
endif

	call	EMM_Init
	test	[msg_flag],KILLER_MSG	;Q: any killer messages?
	jz	IE_InitVDM		;  N: init VDM
	jmp	IE_exit 		;  Y: exit
;
;  init VDM - GDT,IDT,TSS,Page Tables
;
IE_InitVDM:
	call	VDM_Init
	test	[msg_flag],KILLER_MSG	;Q: any killer messages?
	jz	IE_CommitUMB		;  N: finish low-table consumers
	jmp	IE_exit 		;  Y: exit
;
;  Install UMB mappings while the initialization-only state in LAST and the
;  original page tables are still resident. InitTab may then copy the complete
;  mappings and discard PAGESEG/LAST safely.
;
IE_CommitUMB:
	INIT_PHASE 2
	cmp	[umb_mode],0
	je	short IE_InitTAB
	call	Commit_UMB		; map backing and publish atomically

;  set up segment pointers to Tables & OEM table init
;
IE_InitTAB:
	INIT_PHASE 3
	call	InitTab
	INIT_PHASE 4
	jnc	IE_InitT_Good		;Q: any memory allocation error?
	or	[msg_flag],MEM_ERR_MSG	;  Y: Some serious memory error
IE_InitT_Good:
	test	[msg_flag],KILLER_MSG	;Q: any killer messages?
	jnz	short IE_table_error
	jmp	IE_chkbase		; check base memory left
IE_table_error:
	jmp	IE_exit 		; exit
;
;	Verify that we will have at least 64k of base memory after MEMM
;	is loaded
;
IE_chkbase:
	int	12h			; get base memory size
	push	ax			; save it
	mov	ax,[driver_end] 	; get offset of end of MEMM resident
	add	ax,15			; convert to paragraphs
	shr	ax,4
	add	ax,[driver_end+2]	; add in segment of brk address
	add	ax,63			; round up to kbytes (64 paras per K)
	shr	ax,6			; AX = kbytes to end of MEMM resident
	add	ax,DOS3X_ADJ+64 	; add in dos 3.xx adjustment and 64k
	pop	dx			; get base memory back
	cmp	dx,ax			; q: do we have enough?
	jae	IE_setbrk		; y: continue
	or	[msg_flag],MEM_ERR_MSG	; n: set memory error
	jmp	IE_exit 		;    and exit

;
;   set driver break addr in Init Request Header
;
IE_setbrk:
ifdef EMM_SPLIT_PREPARE
        les bx,cs:[prepare_request]
else
	mov	bx,[bp+2]		; get entry DS from stack
	mov	es,bx
	mov	bx,[bp+10]		; ES:BX pts to req hdr
endif
	mov	ax,[driver_end] 	; get brk addr offset
	mov	ES:[bx.BRK_OFF],ax	; set it
	mov	ax,[driver_end+2]	; get brk addr segment
	mov	ES:[bx.BRK_SEG],ax	; set it
;
;   check exit status of VDM/MEMM  (now with lim 4.0) exit must be ON
;
;	 cmp	 [Auto_Mode],0		 ;Q: exit in Auto mode ?
;	 je	 IE_chkOFF		 ;  N: then continue
;	 mov	 [Active_Status],0	 ;  Y: exit in OFF state
;IE_chkOFF:
;	 cmp	 [Active_Status],0	 ;Q: exit in real mode - OFF
;	 je	 IE_Exit		 ;  Y: continue

; Initialize DEBX_GSEL GDT Selector and Deb386
;
	ifndef NoBugMode
	push	ds
	push	es
	push	ax
	push	bx
	push	cx
	push	si
	push	di

	push	[IDT_Seg]
	pop	es				; ES:DI <-- IDT
	push	[GDT_Seg]
	pop	ds				; DS:SI <-- GDT
	mov	bx, DEBX_GSEL
	and	bl, SEL_LOW_MASK
	mov	word ptr [bx], 1800h		; Limit = 20M
	mov	word ptr [bx + 2], 0	
	mov	byte ptr [bx + 4], 0		; Base = 0
	mov	byte ptr [bx + 5], D_DATA0	; Ring 0 Data
	mov	byte ptr [bx + 6], 80h		; Page Granularity

	mov	ax, 4400h			; Initialize Deb386
	mov	bx, DEBX_GSEL			; BIG selector for all addresses
	mov	cx, DEB1_GSEL			; start of 5 working Selector
	xor	si, si
	xor	di, di
	int	68h

	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	ax
	pop	es
	pop	ds
	endif

	call	RelocateText
	INIT_PHASE 5
	call	FarGoVirtual		;  N: go into virtual mode
	; Finish resident ownership while activation is established and no
	; protected frame is live. OFF/idle AUTO must not skip table/stack
	; compaction merely because their final execution mode is inactive.
	call	CompactVData
	INIT_PHASE 6
	mov	al,[initial_mode]
	or	al,al
	jz	short IE_initial_mode_done
	mov	ah,1
	call	ELIM_Entry
IE_initial_mode_done:
	INIT_PHASE 7
	; CompactVData may lower the resident break after the request header was
	; first populated. Publish the final value returned to SYSINIT.
ifdef EMM_SPLIT_PREPARE
        les bx,cs:[prepare_request]
else
	mov	bx,[bp+2]
	mov	es,bx
	mov	bx,[bp+10]
endif
	mov	ax,[driver_end]
	mov	es:[bx.BRK_OFF],ax
	mov	ax,[driver_end+2]
	mov	es:[bx.BRK_SEG],ax

;
;  exit - display status messages and set exit status
;
IE_exit:
ifdef EMM_SPLIT_PREPARE
        PUBLIC FinishProvider
FinishProvider LABEL NEAR
endif
;
;  display signon message first
;
	mov	dx,offset LAST:InitMess
	PRINT_MSG
;
; check for messages to display
;
IE_Install:
	mov	cx,MAX_MSG		; number of potential msgs
	mov	si,offset msg_tbl	; table of messages
m_loop:
	test	[msg_flag],01		; q:is this one set?
	jz	m_inc_ptr		; n: increment table pointer
	mov	dx,cs:[si]		; y: display message
	PRINT_MSG
	cmp	cx,KILL_MSG		; q: is this one a killer?
	jbe	m_inc_ptr		; n: continue
	jmp	IE_not_installed	; y: don't install
m_inc_ptr:
	inc	si			; increment msg table ptr
	inc	si
	shr	[msg_flag],1		; look for next flag
	loop	m_loop
;
	mov	ax,[pool_size]		; size of EMM page pool in Kbytes
	mov	di,offset LAST:ISizeMess; store decimal size in ASCII here.
	call	b2asc10 		; convert to ASCII...
;
	mov	ax,[ext_size]
IFNDEF	NOHIMEM
	add	ax,[hi_size]
endif
	mov	di,offset LAST:ExtSizeMess ; store decimal size of ext/hi alloc
					   ; here
	call	b2asc10

	mov	ax,[sys_size]
	mov	di,offset LAST:SysSizeMess ; system memory allocated
	call	b2asc10
;
	mov	ax,[PF_Base]		; page frame base addr
	shr	ax,8			; shift right to get significant digits
	mov	di,offset LAST:PFBAMess+1; where to put ascii base address
base_loop:
	push	ax			; save all digits
	and	ax,0fh			; get one digit
	cmp	ax,9			; q: digit <=9
	jbe	skip_dig_adj		; y: don't adjust
	add	ax,'A'-':'
skip_dig_adj:
	add	ax,'0'			; make it ascii
	mov	CS:[di],al		; store in message
	dec	di			; update pointer
	pop	ax			; get all digits back
					; shift right for next digit
	shr	ax,4			; q: done?
	jnz	base_loop		; n: do another
;					  y: print it
	mov	dx,offset LAST:InstallMess
	PRINT_MSG
;
;	 mov	 dx,offset LAST:AutoMess	 ; assume AUTO
;	 cmp	 [Auto_Mode],0			 ;Q: auto mode ?
;	 jne	 print_mode			 ;  Y: display message
;	 mov	 dx,offset LAST:InactiveMess	 ;  N: assume OFF
;	 cmp	 [Active_Status],0		 ; q: OFF specified?
;	 jz	 print_mode			 ; y
;	 mov	 dx,offset LAST:ActiveMess	 ; n
;print_mode:
;	 PRINT_MSG
;
;   Ok, now we can patch int15h - must be careful not to install
;	patch when Active_Status set, but not in virtual mode
;
	pushf
	cli				; clear ints
	xor	ax,ax
	mov	ds,ax				; DS -> 0:0
	ASSUME	DS:ABS0
	les	bx,dword ptr [i15_vector]	; DS:BX -> pts to old one
	mov	ax,offset R_CODE:i15_Entry
	mov	[i15_vector],ax 		; set new ip
	mov	ax,seg R_CODE			;
	mov	[i15_vector+2],ax		; set new cs
	mov	ds,ax				; DS -> R_CODE
	ASSUME	DS:R_CODE
	mov	[i15_Old],bx			; save old IP
	mov	[i15_Old+2],es			; save old CS
	popf					; restore IF
	mov	ax,seg DGROUP
	mov	ds,ax				; DS -> dgroup
	ASSUME	DS:DGROUP
;
;   now patch int67 for EMM functions
;
	pushf
	cli				; clear ints
	xor	ax,ax
	mov	ds,ax				; DS -> 0:0
	ASSUME	DS:ABS0
	mov	ax,offset R_CODE:EMM_rEntry
	mov	[i67_vector],ax 		; set new ip
	mov	ax,seg R_CODE			;
	mov	[i67_vector+2],ax		; set new cs
	popf					; restore IF
	mov	ax,seg DGROUP
	mov	ds,ax				; DS -> dgroup
	ASSUME	DS:DGROUP
;
; all done with no errors
;
	INIT_PHASE 8
	xor	ax,ax			; NO errors
;
IE_leave:
ifdef EMM_SPLIT_PREPARE
        retn
else
	pop	es
	pop	ds
	pop	di
	pop	bp
	pop	dx
	pop	bx
	ret
endif
;
IE_not_installed:
	call	Rollback_UMB		; undo provider state before releasing XMS
	call	DeallocMem		; put back any memory we took
ifdef EMM_REJECT_PREPARED
        ; The rejection witness must recover the original XMS pool, not just
        ; return with unchanged interrupt vectors. No DOS-high owner is used
        ; by this test fixture while comparing the before/after pool sizes.
        cmp cs:[prepare_xms_valid],0
        je IE_prepare_rejected
        mov ah,08h
        call dword ptr cs:[prepare_xms_entry]
ifdef EMM_PREPARE_BAD_POOL
        inc dx                  ; negative control: corrupt the observed total
endif
        cmp ax,cs:[prepare_xms_largest]
        jne IE_prepare_leaked
        cmp dx,cs:[prepare_xms_total]
        jne IE_prepare_leaked
        INIT_PHASE 10
        jmp short IE_prepare_rejected
IE_prepare_leaked:
        INIT_PHASE 11
IE_prepare_rejected:
endif
	mov	ax,ERROR		; error return
	jmp	IE_leave
;
Init_MEMM386	endp

;
page
;******************************************************************************
;
;	parser - parse out MEMM parameters and set appropriate values
;		 for expanded memory size ([pool_size]), page frame base
;		 address ([PF_Base])
;
;			entry:	es:di ==  config.sys command line parameters
;				ds = DGROUP
;
;			exit:	[pool_size] = expanded memory size
;				[PF_Base] = page frame base address
;				[Active_Status] =flag for virtual/real mode exit
;				[msg_flag] = appropriate messages to display
;
;			used:	none
;
;******************************************************************************
;
parser	proc	near
	push	ax		; BP+16
	push	bx		; BP+14
	push	cx		; BP+12
	push	dx		; BP+10
	push	si		; BP+8
	push	di		; BP+6
	push	bp		; BP+4
	push	ds		; BP+2
	push	es		; BP+0
	mov	bp,sp		;
	cld			; make sure we go forward
	xor	ax,ax		; clear accumulator
;
;	Skip past MEMM.EXE in command line
;
parm1_loop:				; find 1st parameter
	mov	al,es:[di]
	cmp	al,' '			; q: find end of MEMM.exe?
	jbe	ploop1			; y: start parsing
	inc	di			; n: try next one
	jmp	short parm1_loop
jmp_def:
	jmp	set_def
;
jmp_PF:
	jmp	chk_PF
;
;jmp_onf:
;	 jmp	 chk_onf
;
;jmp_auto:
;	 jmp	 chk_auto
;
jmp_Hx:
	jmp	chk_Hx
;
jmp_Xs:
	jmp	chk_Xs
jmp_Is:
	jmp	chk_Is
jmp_FRAME:
	jmp	chk_FRAME
jmp_slash_P:
	jmp	chk_slash_P

ploop1:
	push	ds
	push	cs
	pop	ds
	mov	si,offset LAST:arg_str ; discardable token storage
	mov	cx,max_arg_len		; maximum length of argument
	call	get_token_far		; get next token
	pop	ds
	or	cx,cx			; q: anything there?
	jz	jmp_def 		; n: go set default values
	mov	al,cs:[si]		; y: get 1st char
	inc	si
	cmp	al,'m'			; q: PF base address?
	je	jmp_PF			;   maybe: go validate it
	cmp	al,'h'			; q: Himem enable /disable?
	je	jmp_Hx			;   maybe: go validate it
	cmp	al,'x'			; q: Exclude segment parameter
	je	jmp_Xs			;   maybe: go validate it
	cmp	al,'i'			; q: Include segment parameter
	je	jmp_Is			;   maybe: go validate it
	cmp	al,'f'			; q: FRAME= direct page frame?
	je	jmp_FRAME
	cmp	al,'/'			; q: /Pmmmm direct page frame?
	je	jmp_slash_P
	cmp	al,'p'			; q: Pn= explicit physical page?
	je	chk_page_assignment
	cmp	al,'o'			; q: ON or OFF initial state?
	je	chk_initial_onoff
	cmp	al,'a'			; q: AUTO initial state?
	jne	short dispatch_not_a
	cmp	byte ptr cs:[si],'='
	je	chk_altregs
	jmp	chk_initial_auto
dispatch_not_a:
	cmp	al,'w'			; q: W=ON or W=OFF?
	je	chk_weitek
	cmp	al,'l'			; q: L= minimum remaining XMS?
	je	chk_min_xms
	cmp	al,'d'			; q: D= buffered DMA memory?
	je	chk_dma_size
	cmp	al,'b'			; q: B= lowest banking address?
	je	chk_banking_base
	cmp	al,'r'			; q: RAM activation mode?
	je	chk_RAM
	cmp	al,'n'			; q: NOEMS activation mode?
	je	chk_NOEMS
	cmp	al,'0'			; q: is it a digit (size)
	jb	inv_parm		; n: invalid
	cmp	al,'9'			; q: is it a digit?
	jbe	chk_siz 		; y: validate the size
inv_parm:
	or	[msg_flag],INV_PARM_MSG ; set invalid parameter flag
	jmp	short ploop1		; continue

chk_initial_onoff:
	cmp	[mode_seen],0
	jne	inv_prm
	cmp	cx,2
	je	short chk_initial_on
	cmp	cx,3
	jne	inv_prm
	cmp	byte ptr cs:[si],'f'
	jne	inv_prm
	cmp	byte ptr cs:[si+1],'f'
	jne	inv_prm
	mov	[initial_mode],1
	jmp	short initial_mode_done
chk_initial_on:
	cmp	byte ptr cs:[si],'n'
	jne	inv_prm
	mov	[initial_mode],0
initial_mode_done:
	mov	[mode_seen],1
	jmp	ploop1

chk_initial_auto:
	cmp	[mode_seen],0
	jne	inv_prm
	cmp	cx,4
	jne	inv_prm
	cmp	byte ptr cs:[si],'u'
	jne	inv_prm
	cmp	byte ptr cs:[si+1],'t'
	jne	inv_prm
	cmp	byte ptr cs:[si+2],'o'
	jne	inv_prm
	mov	[initial_mode],2
	mov	[mode_seen],1
	jmp	ploop1

chk_weitek:
	cmp	cx,4
	jb	inv_prm
	cmp	cx,5
	ja	inv_prm
	cmp	byte ptr cs:[si],'='
	jne	inv_prm
	cmp	byte ptr cs:[si+1],'o'
	jne	inv_prm
	cmp	byte ptr cs:[si+2],'n'
	je	short weitek_check_on_length
	cmp	cx,5
	jne	inv_prm
	cmp	byte ptr cs:[si+2],'f'
	jne	inv_prm
	cmp	byte ptr cs:[si+3],'f'
	jne	inv_prm
	mov	[weitek_mode],0
	jmp	ploop1
weitek_check_on_length:
	cmp	cx,4
	jne	inv_prm
weitek_on:
	mov	[weitek_mode],1
	jmp	ploop1

chk_min_xms:
	cmp	cx,3
	jb	inv_prm
	cmp	byte ptr cs:[si],'='
	jne	inv_prm
	inc	si
	dec	cx
	call	parse_decimal_token
	jc	inv_prm
	mov	[min_xms],ax
	jmp	ploop1

chk_dma_size:
	cmp	cx,3
	jb	inv_prm
	cmp	byte ptr cs:[si],'='
	jne	inv_prm
	inc	si
	dec	cx
	call	parse_decimal_token
	jc	inv_prm
	cmp	ax,16
	jb	inv_prm
	cmp	ax,256
	ja	inv_prm
	add	ax,15			; reserve whole 16 KiB pages
	mov	cl,4
	shr	ax,cl
	mov	[dma_page_limit],ax
	jmp	ploop1

chk_banking_base:
	cmp	cx,6
	jne	inv_prm
	cmp	byte ptr cs:[si],'='
	jne	inv_prm
	inc	si
	mov	cx,4
	call	htoi
	or	cx,cx
	jnz	inv_prm
	cmp	ax,1000h
	jb	inv_prm
	cmp	ax,4000h
	ja	inv_prm
	test	ax,03ffh
	jnz	inv_prm
	mov	[banking_base],ax
	jmp	ploop1

chk_page_assignment:
	cmp	cx,4
	jb	inv_prm
	dec	cx			; the dispatcher consumed the leading 'P'
	xor	ax,ax
page_number_loop:
	cmp	byte ptr cs:[si],'='
	je	short page_number_done
	mov	bl,cs:[si]
	cmp	bl,'0'
	jb	inv_prm
	cmp	bl,'9'
	ja	inv_prm
	sub	bl,'0'
	xor	bh,bh
	push	cx
	mov	cx,10
	mul	cx
	pop	cx
	or	dx,dx
	jnz	inv_prm
	add	ax,bx
	jc	inv_prm
	cmp	ax,255
	ja	inv_prm
	inc	si
	dec	cx
	jmp	short page_number_loop
page_number_done:
	cmp	cx,5			; '=' plus exactly four hex digits
	jne	inv_prm
	mov	[page_id_temp],al	; requested external physical-page ID
	inc	si
	dec	cx
	call	htoi
	or	cx,cx
	jnz	inv_prm
	call	validate_page_segment
	jc	inv_prm
	mov	dl,[page_id_temp]
	mov	dh,[requested_page_count]
	cmp	dh,20
	jae	inv_prm
	xor	ch,ch
	mov	cl,dh
	xor	bx,bx
	xor	si,si
page_assignment_duplicate_loop:
	jcxz	short page_assignment_store
	cmp	dl,requested_page_ids[bx]
	je	inv_prm
	cmp	ax,requested_page_segments[si]
	je	inv_prm
	inc	bx
	add	si,2
	loop	page_assignment_duplicate_loop
page_assignment_store:
	xor	bx,bx
	mov	bl,dh
	mov	requested_page_ids[bx],dl
	shl	bx,1
	mov	requested_page_segments[bx],ax
	inc	[requested_page_count]
	cmp	dl,3
	ja	short page_assignment_stored
	cmp	[PF_Base],0ffffh
	jne	inv_prm
	mov	[p_frame_seen],1
	xor	bx,bx
	mov	bl,dl
	shl	bx,1
	mov	p_frame_segments[bx],ax
page_assignment_stored:
	jmp	ploop1

; AX is a Pn= segment. Accept the two DOS 5 windows at 16 KiB alignment.
validate_page_segment proc near
	test	ax,03ffh
	jnz	short validate_page_segment_bad
	cmp	ax,08000h
	jb	short validate_page_segment_bad
	cmp	ax,09c00h
	jbe	short validate_page_segment_ok
	cmp	ax,0c000h
	jb	short validate_page_segment_bad
	cmp	ax,0ec00h
	ja	short validate_page_segment_bad
validate_page_segment_ok:
	clc
	ret
validate_page_segment_bad:
	stc
	ret
validate_page_segment endp

chk_altregs:
	cmp	cx,3
	jb	inv_prm
	cmp	byte ptr cs:[si],'='
	jne	inv_prm
	inc	si
	dec	cx
	call	parse_decimal_token
	jc	inv_prm
	cmp	ax,254
	ja	inv_prm
	mov	[_altreg_count],al
	jmp	ploop1

chk_RAM:
	cmp	cx,3
	jne	inv_parm
	cmp	byte ptr cs:[si],'a'
	jne	inv_parm
	cmp	byte ptr cs:[si+1],'m'
	jne	inv_parm
	mov	[umb_mode],1
	jmp	ploop1

chk_NOEMS:
	cmp	cx,5
	jne	inv_parm
	cmp	byte ptr cs:[si],'o'
	jne	inv_parm
	cmp	byte ptr cs:[si+1],'e'
	jne	inv_parm
	cmp	byte ptr cs:[si+2],'m'
	jne	inv_parm
	cmp	byte ptr cs:[si+3],'s'
	jne	inv_parm
	mov	[umb_mode],1
	mov	[noems_mode],1
	jmp	ploop1
chk_siz:
	mov	bx,cx			; bx = number of digits
	mov	byte ptr cs:[bx+si-1],' ' ; terminate string
	mov	cx,10			; decimal multiplier
	xor	dx,dx			; clear upper 16 bits
	xor	bx,bx			; clear temporary accumulator
	cmp	[pool_size],0		; q: have we already done this?
	jz	dig_loop		; n: continue
	mov	dx,1			; y: skip all of this
dig_loop:
	or	dx,dx			; q: overflow?
	jnz	new_digit		; y: just skip rest of digits
	sub	al,'0'			; get ones value
	xchg	ax,bx			; swap accumulated value to ax
	mul	cx			; times 10
	add	ax,bx			; add in ones value
	adc	dx,0			; carry to dx
	xchg	ax,bx			; temporary value to bx
;
new_digit:
	mov	al,cs:[si]		; get new char into al
	inc	si
	cmp	al,'0'			; q: between 0 & 9?
	jb	dig_exit		; n: done
	cmp	al,'9'
	ja	dig_exit
	jmp	dig_loop		; y: process it
;
dig_exit:
	cmp	al,' '			; q: any invalid digits?
	jne	ck_inv_parm		; y: invalid parameter
	or	dx,dx			; q: something wrong?
	jz	chk_siz1		; n: not yet
	cmp	[pool_size],0		; q: is this the second time for size?
	jz	siz_adj 		; n: they just asked for too much
ck_inv_parm:
	or	[msg_flag],INV_PARM_MSG ; y: only let them do it once
	jmp	ploop1			; continue
chk_siz1:
	cmp	bx,16			;q: did they ask for too little?
	jb	siz_adj 		; y: go adjust it
	cmp	bx,MAX_SIZE		;q: too much?
	ja	siz_adj 		; y: adjust it
	mov	dx,0fh			; n: make sure it was a multiple of 16k
	and	dx,bx			;q: was it?
	jz	set_siz 		; y: no problem
	sub	bx,dx			; n: drop it down
	jmp	siz_msg 		; and give them the message
siz_adj:
	mov	bx,256			; default value for size
siz_msg:
	or	[msg_flag],SIZE_ADJ_MSG ; size adjusted
set_siz:
	mov	[pool_size],bx		; save it
	jmp	ploop1			; go check more parameters

; FRAME=mmmm and /Pmmmm select the same documented page-frame addresses as
; M1-M14. Store the corresponding Map_tbl byte offset in PF_Base.
chk_FRAME:
	cmp	cx,10
	jne	inv_prm
	cmp	byte ptr cs:[si],'r'
	jne	inv_prm
	cmp	byte ptr cs:[si+1],'a'
	jne	inv_prm
	cmp	byte ptr cs:[si+2],'m'
	jne	inv_prm
	cmp	byte ptr cs:[si+3],'e'
	jne	inv_prm
	cmp	byte ptr cs:[si+4],'='
	jne	inv_prm
	add	si,5
	mov	cx,4
	call	htoi
	or	cx,cx
	jnz	inv_prm
	call	page_frame_to_index
	jc	inv_prm
	jmp	store_page_frame

chk_slash_P:
	cmp	cx,6
	jne	inv_prm
	cmp	byte ptr cs:[si],'p'
	jne	inv_prm
	inc	si
	mov	cx,4
	call	htoi
	or	cx,cx
	jnz	inv_prm
	call	page_frame_to_index
	jc	inv_prm
store_page_frame:
	cmp	[PF_Base],0ffffh
	jne	inv_prm
	cmp	[p_frame_seen],0
	jne	inv_prm
	mov	[PF_Base],ax
	jmp	ploop1

; AX=segment; return AX=word-table offset for the M1-M14 frame list.
page_frame_to_index proc near
	push	bx
	mov	bx,ax
	cmp	bx,0c000h
	jb	short page_frame_low
	cmp	bx,0e000h
	ja	short page_frame_bad
	sub	bx,0c000h
	test	bx,03ffh
	jnz	short page_frame_bad
	mov	cl,9
	shr	bx,cl
	mov	ax,bx
	pop	bx
	clc
	ret
page_frame_low:
	cmp	bx,08000h
	jb	short page_frame_bad
	cmp	bx,09000h
	ja	short page_frame_bad
	sub	bx,08000h
	test	bx,03ffh
	jnz	short page_frame_bad
	mov	cl,9
	shr	bx,cl
	add	bx,18
	mov	ax,bx
	pop	bx
	clc
	ret
page_frame_bad:
	pop	bx
	stc
	ret
page_frame_to_index endp


;
;	Check page frame base address
;
chk_PF:
	cmp	cx,2			; q: 2 and only 2 chars in argument?
	jb	inv_prm 		; n: error
	cmp	[PF_Base],0ffffh	; q: have they already specified this?
	jnz	inv_prm 		; y: don't let them do it again
	cmp	[p_frame_seen],0
	jne	inv_prm
	call	parse_decimal_token
	jc	inv_prm
	cmp	ax,1
	jb	inv_prm
	cmp	ax,14
	ja	inv_prm
	dec	ax			; make zero relative
	shl	ax,1			; make word offset
	mov	[PF_Base],ax		; store address
	jmp	ploop1			; get next parameter

;
; H= selects the caller-visible LIM handle-table size. Handle zero remains
; reserved for the operating system, as required by the existing allocator.
chk_Hx:
	cmp	cx,3
	jb	inv_prm
	cmp	byte ptr cs:[si],'='
	jne	inv_prm
	inc	si
	dec	cx
	call	parse_decimal_token
	jc	inv_prm
	cmp	ax,2
	jb	inv_prm
	cmp	ax,255
	ja	inv_prm
	mov	[_handle_table_size],al
	jmp	ploop1

;
inv_prm:
	or	[msg_flag],INV_PARM_MSG ; invalid
	jmp	ploop1			; get next parameter
;
;
; check for exclusion of segments.  this parameter is specfied thusly:
;
;	X:nnnn-mmmm where nnnn is lo segment and mmmm is hi segment of range to
;		    be excluded from being mappable.
;
; more than one of these may be specified.
;
chk_Xs:
	call	handle_Xswitch
	jc	inv_parm
	jmp	ploop1

; I= explicitly includes otherwise unused adapter space.  The recorded map is
; applied after ROM discovery and before page-frame selection.  Explicit X=
; ranges are recorded separately and always take precedence.
chk_Is:
	call	handle_Iswitch
	jc	inv_parm
	jmp	ploop1
;
;
;	Check for ON/OFF
;
;chk_onf:
;	 lodsb				 ; get next char
;	 cmp	 [Active_Status],1	 ; q: have they already specified this?
;	 jbe	 inv_prm		 ; y: ignore and set error flag
;	 cmp	 [Auto_Mode],1		 ; n:q: have they specified auto_mode?
;	 je	 inv_prm		 ;   y: ignore and set error flag
;	 cmp	 al,'n' 		 ; q: on?
;	 jne	 onf_cont		 ; n: continue
;	 cmp	 cx,2			 ; y: is that all there is?
;	 jne	 inv_prm		 ; n: error
;	 mov	 [Active_Status],1	 ; y: set on
;	 mov	 [Auto_Mode],0		 ;    clear Auto mode
;	 jmp	 ploop1 		 ; get next parameter
;onf_cont:
;	 cmp	 al,'f' 		 ; q: OF?
;	 jne	 inv_prm		 ; n: invalid
;	 lodsb				 ; y: get next char
;	 cmp	 al,'f' 		 ; q: OFF?
;	 jne	 inv_prm		 ; n: invalid
;	 cmp	 cx,3			 ; q: is that all there is?
;	 jne	 inv_prm		 ; n: error
;	 mov	 [Active_Status],0	 ; y: set OFF
;	 mov	 [Auto_Mode],0		 ;    clear Auto mode
;	 jmp	 ploop1 		 ; get next parameter
;
;	Check for AUTO
;
;chk_auto:
;	 cmp	 [Active_Status],1	 ; q: have they already specified ON/OFF?
;	 jbe	 inv_prm		 ; y: ignore and set error flag
;	 cmp	 [Auto_Mode],1		 ; n:q: have they specified auto_mode?
;	 je	 inv_prm		 ;   y: ignore and set error flag
;	 cmp	 cx,AUTO_LEN		 ;   n: q: parameter correct length ?
;	 jne	 inv_prm		 ;	n: ignore and set error flag
;	 push	 es			 ;	y: check for 'AUTO'
;	 push	 di
;	 dec	 si			 ;  DS:SI pts to begin of arg
;	 mov	 di,offset LAST:AUTO_parm
;	 push	 cs
;	 pop	 es			 ; ES:DI pts to 'AUTO'
;	 cld
;	 repe cmpsb			 ;Q: do CX bytes compare ?
;	 pop	 di			 ; restore DI
;	 pop	 es			 ; restore ES
;	 jne	 inv_prm		 ; N: invalid parameter message
;	 mov	 [Auto_Mode],1		 ; Y: set AUTO mode
;	 jmp	 ploop1 		 ; get next parameter
;
;	Set default values for those items that were not specified
;
set_def:

    ;
    ; default pool size if not defined is 256k
    ;
set_pool_size:
	cmp	[pool_size],0		; q: did they specify size?
	jnz	set_himem		; y: ok
	mov	[pool_size],256 	; n: set default
	or	[msg_flag],SIZE_ADJ_MSG ; display size adjusted

    ;
    ; default of use of hi system ram is that it should not be used
    ;
set_himem:
;	 cmp	 [himem_use],0ffh	 ; q:did they specify himem enb/dsb
;	 jnz	 parse_xit		 ; y: ok
;	 mov	 [himem_use],0		 ; n: set default that it is not used
	call	finalize_page_frame_assignments
	jnc	short parse_xit
	or	[msg_flag],INV_PARM_MSG

parse_xit:				; restore registers and exit
	pop	es
	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
parser	endp

finalize_page_frame_assignments proc near
	cmp	[p_frame_seen],0
	je	short finalize_page_frame_ok
	mov	ax,p_frame_segments[0]
	cmp	ax,0ffffh
	je	short finalize_page_frame_bad
	mov	bx,ax
	add	bx,0400h
	cmp	p_frame_segments[2],bx
	jne	short finalize_page_frame_bad
	add	bx,0400h
	cmp	p_frame_segments[4],bx
	jne	short finalize_page_frame_bad
	add	bx,0400h
	cmp	p_frame_segments[6],bx
	jne	short finalize_page_frame_bad
	call	page_frame_to_index
	jc	short finalize_page_frame_bad
	mov	[PF_Base],ax
finalize_page_frame_ok:
	clc
	ret
finalize_page_frame_bad:
	stc
	ret
finalize_page_frame_assignments endp
;
;   parser local data
;
;AUTO_parm	 db	 "auto"
;AUTO_LEN	 equ	 $-AUTO_parm


msg_tbl 	label	word
		dw	offset LAST:Incorrect_PRT ; Incorrect Processor Type
		dw	offset LAST:Incorrect_DOS ; Incorrect Version of DOS
		dw	offset LAST:InsfMem	  ; Insufficient Memory
		dw	offset LAST:Already_Inst  ; Already Installed
		dw	offset LAST:No_PF_Avail   ; No Page Frame Space Avail
kill_end	label	word		; End of messages that kill driver
		dw	offset LAST:Adj_Size	; Pool Size Adjusted
		dw	offset LAST:InvPFBA	; Page Frame Base Addr Adjusted
		dw	offset LAST:InvMRA	; Map Register Adjusted
		dw	offset LAST:InvParm	; Invalid Parameter msg
		dw	offset LAST:PFWarning	; Page Frame warning message
MAX_MSG 	equ	($ - msg_tbl)/2 ; # of messages to display
KILL_MSG	equ	($ - kill_end)/2; 1st four will abort driver
;

page
;******************************************************************************
; handle_Xswitch - processes the X switch to make some segments non-mappable  ;
;									      ;
; entry: CS:SI string with X switch parameters in form "X:nnnn-mmmm" or      ;
;        the DOS 5/6 form "X=nnnn-mmmm"                                      ;
;	 cx is length of string
;									      ;
; exit:  CY set if invalid parameter					      ;
;	 CY clear if parameter processed				      ;
;	    and non-mappable segments excluded				      ;
;									      ;
; uses: flags,ax,cx,si							      ;
;									      ;
; author: ISP 8/24/88					      ;
;									      ;
;*****************************************************************************;
handle_XSwitch	proc	near
;
	cmp	cx,5	    ; must have atleast 5 symbols
	jb	error_Xs    ;
;
	mov	al,cs:[si]	; get the next letter ":"
	inc	si
	sub	cx,2	    ;
;
	cmp	al,":"	    ; accept the historical spelling
	je	short Xs_delimiter_ok
	cmp	al,"="	    ; and the DOS 5/6 public spelling
	jne	error_Xs    ; if neither, it is a bad parameter
Xs_delimiter_ok:
;
	call	htoi	    ; convert hex to integer
	jcxz	error_Xs    ; if we have run out we have a bad parameter
;
	mov	bx,ax	    ; save in bx the start segment to be excluded
;
	mov	al,cs:[si]	; get the next letter
	inc	si
	dec	cx	    ;
	jcxz	error_Xs
	cmp	al,"-"	    ; is it the letter "-"
	jnz	error_Xs    ;
;
	call	htoi	    ; convert hex to mappable
	push	ax
	push	bx
	push	di
	mov	di,offset LAST:umb_excludes
	call	record_umb_range
	pop	di
	pop	bx
	pop	ax
	call	exclude_segments

	clc		    ; set success and
	ret		    ; return
error_Xs:
	stc		    ; set error and
	ret		    ; return
;
handle_XSwitch	endp

; Parse I= using the same public range syntax as X=.  Applying the range is
; deferred until the normal firmware scan has completed.
handle_ISwitch	proc	near
	cmp	cx,5
	jb	error_Is
	mov	al,cs:[si]
	inc	si
	sub	cx,2
	cmp	al,"="
	jne	error_Is
	call	htoi
	jcxz	error_Is
	mov	bx,ax
	mov	al,cs:[si]
	inc	si
	dec	cx
	jcxz	error_Is
	cmp	al,"-"
	jne	error_Is
	call	htoi
	push	di
	mov	di,offset LAST:umb_includes
	call	record_umb_range
	pop	di
	clc
	ret
error_Is:
	stc
	ret
handle_ISwitch	endp

; Record the 16 KiB pages in AX:BX (high:low) that intersect A000-EFFF.
; Ranges outside that window remain syntactically valid but cannot become UMBs.
record_umb_range proc near
	push	ax
	push	bx
	push	cx
	push	dx
	push	di
	cmp	ax,0a000h
	jb	short record_umb_done
	cmp	bx,0f000h
	jae	short record_umb_done
	cmp	bx,0a000h
	jae	short record_low_ok
	mov	bx,0a000h
record_low_ok:
	cmp	ax,0efffh
	jbe	short record_high_ok
	mov	ax,0efffh
record_high_ok:
	mov	cl,10
	shr	ax,cl
	shr	bx,cl
	mov	dx,bx
	sub	dx,UMB_FIRST_PAGE
	add	di,dx
	sub	ax,bx
	inc	ax
	mov	cx,ax
	mov	al,1
record_umb_loop:
	mov	cs:[di],al
	inc	di
	loop	record_umb_loop
record_umb_done:
	pop	di
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
record_umb_range endp

; Called by physical-page discovery after option-ROM scanning.  I= can reclaim
; adapter ROM space C000-EFFF by explicit user request.  A000-BFFF video memory
; and F000-FFFF system ROM are never candidates.  X= wins regardless of order.
public Apply_User_UMA_Ranges
Apply_User_UMA_Ranges proc near
	push	ax
	push	cx
	push	si
	mov	si,8			; C000 is page 8 within A000-EFFF
	mov	cx,UMB_PAGE_COUNT-8
apply_user_range_loop:
	cmp	cs:umb_includes[si],0
	je	short apply_user_exclude
	mov	cs:mappable_segs[si+UMB_FIRST_PAGE],PAGE_MAPPABLE
apply_user_exclude:
	cmp	cs:umb_excludes[si],0
	je	short apply_user_next
	mov	cs:mappable_segs[si+UMB_FIRST_PAGE],PAGE_NOT_MAPPABLE
apply_user_next:
	inc	si
	loop	apply_user_range_loop
	pop	si
	pop	cx
	pop	ax
	ret
Apply_User_UMA_Ranges endp

;-----------------------------------------------------------------------;
; htoi									;
; 									;
; Converts a string to an integer.					;
; 									;
; Arguments:								;
; 	CS:SI = string							;
; 	CX    = length							;
; Returns:								;
; 	AX    = integer							;
; 	CS:SI = remaining string					;
; 	CX    = remaining length					;
; Alters:								;
; 	nothing								;
; Calls:								;
; 	nothing								;
; History:								;
; 									;
; ISP (isp) 8/24/88 shifted from ps2emm srces		;
;-----------------------------------------------------------------------;


; Parse the decimal suffix of a one-character option. CX includes that option
; character and CS:SI points at the first digit. Return AX and carry status.
parse_decimal_token proc near
	dec	cx
	jcxz	short parse_decimal_error
	xor	ax,ax
parse_decimal_loop:
	mov	bl,cs:[si]
	inc	si
	cmp	bl,'0'
	jb	short parse_decimal_error
	cmp	bl,'9'
	ja	short parse_decimal_error
	sub	bl,'0'
	xor	bh,bh
	push	cx
	mov	cx,10
	mul	cx
	pop	cx
	or	dx,dx
	jnz	short parse_decimal_error
	add	ax,bx
	jc	short parse_decimal_error
	loop	parse_decimal_loop
	clc
	ret
parse_decimal_error:
	stc
	ret
parse_decimal_token endp

htoi	proc	near
	push	bx
	xor	ax,ax
	mov	bx,ax
htoi_loop:
	jcxz	htoi_done

; get the next character

	mov	bl,cs:[si]
	inc	si
	dec	cx

; see if it's a digit

	sub	bl,'0'
	cmp	bl,9
	jbe	have_hvalue
	sub	bl,'A'-'0'
	cmp	bl,'F'-'A'
	jbe	have_hvalue_but_10
	sub	bl,'a'-'A'
	cmp	bl,'F'-'A'
	ja	htoi_not_digit
have_hvalue_but_10:
	add	bl,10
have_hvalue:

; shift and add

	shl	ax,1
	shl	ax,1
	shl	ax,1
	shl	ax,1
	add	ax,bx
	jmp	htoi_loop
htoi_not_digit:
	inc	cx			; give back the character
	dec	si
htoi_done:
	pop	bx
	ret
htoi	endp

;=============================================================================
; Repository HIMEM/EMM386 UMB peer integration
;=============================================================================

; Snapshot safe 16 KiB UMA windows after the existing ROM/video/exclusion scan
; and remove them from the EMS mappable-window tables before those tables are
; built. The EMS page frame always remains under EMS ownership.
Prepare_UMB proc near
ifdef UMB_SUBPAGE_DISCOVERY
	call	Report_UMB_Subpages
endif
	pusha
	push	es
	mov	ax,0e700h
	int	2fh
	cmp	ax,0e7ffh
	jne	short PU_done
	cmp	bx,04d55h
	jne	short PU_done
	mov	cs:[umb_peer],1
	xor	di,di
	mov	si,UMB_FIRST_PAGE
	mov	bx,0a000h
	mov	cx,UMB_PAGE_COUNT
PU_scan:
ifdef UMB_SUBPAGE_MAPPING
	mov	al,cs:mappable_segs[si]
	mov	cs:umb_saved_windows[di],al
endif
	cmp	cs:mappable_segs[si],PAGE_MAPPABLE
	jne	short PU_next
	mov	ax,[PF_Base]
	cmp	ax,0ffffh
	je	short PU_take
	cmp	bx,ax
	jb	short PU_take
	xor	dx,dx
	mov	dl,[_page_frame_pages]
	shl	dx,10
	add	dx,ax
	cmp	bx,dx
	jb	short PU_next
PU_take:
	mov	cs:umb_candidates[di],1
	mov	cs:mappable_segs[si],PAGE_NOT_MAPPABLE
PU_next:
	inc	di
	inc	si
	add	bx,0400h
	loop	PU_scan
PU_done:
ifdef UMB_SUBPAGE_MAPPING
	cmp	cs:[umb_peer],0
	je	short PU_fine_done
	xor	di,di
PU_fine_plan:
	mov	al,cs:umb_candidates[di]
	mov	cs:umb_coarse_candidates[di],al
	mov	al,cs:umb_fine_masks[di]
	mov	cs:umb_active_masks[di],al
	or	al,al
	jz	short PU_fine_skip
	mov	cs:umb_candidates[di],1
	mov	cs:mappable_segs[di+UMB_FIRST_PAGE],PAGE_NOT_MAPPABLE
	jmp	short PU_fine_next
PU_fine_skip:
; Explicit EMS owners rejected by the fine plan must remain EMS windows,
; including during coarse fallback after window tables have been built.
	mov	cs:umb_candidates[di],0
	mov	cs:umb_coarse_candidates[di],0
	mov	al,cs:umb_saved_windows[di]
	mov	cs:mappable_segs[di+UMB_FIRST_PAGE],al
PU_fine_next:
	inc	di
	cmp	di,UMB_PAGE_COUNT
	jb	short PU_fine_plan
PU_fine_done:
endif
	pop	es
	popa
	ret
Prepare_UMB endp

ifdef UMB_SUBPAGE_DISCOVERY
; Inclusive AX:BX segment bounds; called before exclude_segments rounds them.
; Preserve all inputs, including DS (DGROUP) and flags.
public Exclude_UMB_Subpages
Exclude_UMB_Subpages proc near
	pushf
	pusha
	cmp	ax,bx
	jb	short EUS_done
	cmp	ax,0a000h
	jb	short EUS_done
	cmp	bx,0f000h
	jae	short EUS_done
	cmp	bx,0a000h
	jae	short EUS_low
	mov	bx,0a000h
EUS_low:
	cmp	ax,0efffh
	jbe	short EUS_high
	mov	ax,0efffh
EUS_high:
	sub	ax,0a000h
	sub	bx,0a000h
	shr	ax,8
	shr	bx,8
EUS_clear:
	mov	cs:umb_fine_allowed[bx],0
	inc	bx
	cmp	bx,ax
	jbe	short EUS_clear
EUS_done:
	popa
	popf
	ret
Exclude_UMB_Subpages endp

; Build and report masks only. Existing Prepare/Commit_UMB remain unchanged.
; Bit n is the nth 4 KiB slice within a 16 KiB UMA parent, starting at A000h.
Report_UMB_Subpages proc near
	pushf
	pusha
	xor	si,si
RUS_parent:
	mov	bx,si
	shl	bx,2
	xor	ax,ax
	mov	dl,1
	mov	cx,4
RUS_slice:
	cmp	cs:umb_fine_allowed[bx],0
	je	short RUS_next_slice
	or	al,dl
RUS_next_slice:
	shl	dl,1
	inc	bx
	loop	RUS_slice
; Preserve explicit legacy I= semantics, but never include video via this map.
	cmp	si,8
	jb	short RUS_reject
	cmp	cs:umb_includes[si],0
	je	short RUS_exclusions
	mov	al,0fh
RUS_exclusions:
	cmp	cs:umb_excludes[si],0
	jne	short RUS_reject
	mov	dx,si
	shl	dx,10
	add	dx,0a000h
	mov	bx,[PF_Base]
	cmp	bx,0ffffh
	je	short RUS_requested
	cmp	dx,bx
	jb	short RUS_requested
	movzx	cx,[_page_frame_pages]
	shl	cx,10
	add	bx,cx
	cmp	dx,bx
	jb	short RUS_reject
RUS_requested:
	xor	bx,bx
	movzx	cx,cs:[requested_page_count]
	jcxz	short RUS_store
RUS_request:
	cmp	cs:requested_page_ids[bx],3
	jbe	short RUS_next_request
	mov	di,bx
	shl	di,1
	cmp	dx,cs:requested_page_segments[di]
	je	short RUS_reject
RUS_next_request:
	inc	bx
	loop	RUS_request
	jmp	short RUS_store
RUS_reject:
	xor	al,al
RUS_store:
	mov	cs:umb_fine_masks[si],al
	inc	si
	cmp	si,UMB_PAGE_COUNT
	jb	RUS_parent
	mov	bx,offset umb_fine_label
RUS_prefix:
	mov	al,cs:[bx]
	inc	bx
	or	al,al
	jz	short RUS_masks
	out	0e9h,al
	jmp	short RUS_prefix
RUS_masks:
	xor	bx,bx
RUS_hex:
	mov	al,cs:umb_fine_masks[bx]
	add	al,'0'
	cmp	al,'9'
	jbe	short RUS_emit
	add	al,7
RUS_emit:
	out	0e9h,al
	inc	bx
	cmp	bx,UMB_PAGE_COUNT
	jb	short RUS_hex
	mov	al,10
	out	0e9h,al
	popa
	popf
	ret
Report_UMB_Subpages endp
endif

; Reserve one EMS backing page per candidate, install stable PTEs, coalesce the
; windows into extents, and commit the complete map to HIMEM. No window remains
; backed if the peer rejects the transaction.
Commit_UMB proc near
	pusha
	push	es
	cmp	cs:[umb_peer],0
	je	CU_done
	mov	ax,[_free_count]
	or	ax,ax
	jz	CU_done
	mov	cs:[umb_backing_count],0
	mov	cs:[umb_registration+2],0
ifdef UMB_TEST_REVERSE_FREE
; Test fixture: reverse only the available EMS stack. Ownership/counts stay
; unchanged, but sequential allocations no longer imply ascending physical
; backing. This must not be enabled in a distribution build.
	mov	di,[_free_top]
	shl	di,1
	add	di,[_emm_free]
	mov	bx,[_free_count]
	dec	bx
	shl	bx,1
	add	bx,di
CU_reverse_free:
	cmp	di,bx
	jae	short CU_reverse_done
	mov	ax,[di]
	xchg	ax,[bx]
	mov	[di],ax
	add	di,2
	sub	bx,2
	jmp	short CU_reverse_free
CU_reverse_done:
endif
ifdef UMB_SUBPAGE_MAPPING
CU_retry_plan:
endif
	xor	si,si
	mov	dx,0a000h
	xor	bp,bp			; end segment of previous extent
CU_scan:
	test	si,7
	jnz	short CU_group_ready
	call	Choose_UMB_DMA_Group
	jc	CU_rollback
CU_group_ready:
	cmp	cs:umb_candidates[si],0
	je	CU_next
	cmp	[_free_count],0
ifdef UMB_SUBPAGE_MAPPING
	je	CU_rollback
else
	je	CU_publish
endif
	movzx	eax,si
	and	ax,7
	shl	eax,14
	add	eax,cs:[umb_dma_base]
	call	Find_UMB_Free_Page
	jc	CU_rollback		; never publish unsafe backing
; Remove the selected page by swapping it onto the free-stack top. Rollback
; restores the reserved prefix as a set; free-list ordering is not ownership.
	mov	di,[_free_top]
	shl	di,1
	add	di,[_emm_free]
	mov	ax,[bx]
	xchg	ax,[di]
	mov	[bx],ax
	mov	ax,[di]			; selected backing EMM page number
	inc	[_free_top]
	dec	[_free_count]
	inc	cs:[umb_backing_count]
	call	Map_UMB_Page
	mov	cs:umb_candidates[si],2 ; candidate now has backing installed
ifdef UMB_SUBPAGE_FAIL_AFTER_MAP
	cmp	cs:[umb_fine_attempt],0
	je	short CU_no_fine_fault
	cmp	cs:[umb_backing_count],UMB_SUBPAGE_FAIL_AFTER_MAP
	jae	CU_rollback
CU_no_fine_fault:
endif
ifdef UMB_TEST_FAIL_AFTER_MAP
	cmp	cs:[umb_backing_count],UMB_TEST_FAIL_AFTER_MAP
	jae	CU_rollback
endif

ifdef UMB_SUBPAGE_MAPPING
	call	Append_UMB_Subpage_Extents
	jc	CU_rollback
else
	cmp	bp,dx
	jne	short CU_new_extent
	mov	bx,cs:[umb_registration+2]
	dec	bx
	shl	bx,1
	shl	bx,1
	add	bx,offset umb_registration+4
	add	word ptr cs:[bx+2],0400h
	jmp	short CU_extent_done
CU_new_extent:
	mov	bx,cs:[umb_registration+2]
	shl	bx,1
	shl	bx,1
	add	bx,offset umb_registration+4
	mov	word ptr cs:[bx],dx
	mov	word ptr cs:[bx+2],0400h
	inc	cs:[umb_registration+2]
CU_extent_done:
	mov	bp,dx
	add	bp,0400h
endif
CU_next:
	inc	si
	add	dx,0400h
	cmp	si,UMB_PAGE_COUNT
	jb	CU_scan
CU_publish:
ifdef UMB_SUBPAGE_FAIL_BEFORE_PUBLISH
	cmp	cs:[umb_fine_attempt],0
	jne	CU_rollback
endif
ifdef UMB_TEST_FAIL_BEFORE_PUBLISH
	jmp	CU_rollback
endif
	cmp	cs:[umb_registration+2],0
	je	short CU_rollback
	push	ds
	push	cs
	pop	ds
	mov	si,offset umb_registration
	mov	ax,0e701h
	int	2fh
	pop	ds
	cmp	ax,1
	jne	short CU_rollback
	mov	cs:[umb_registered],1
	jmp	short CU_done
CU_rollback:
	xor	si,si
	mov	dx,0a000h
CU_restore_scan:
	cmp	cs:umb_candidates[si],2
	jne	short CU_restore_next
	call	Restore_UMB_Page
	mov	cs:umb_candidates[si],1
CU_restore_next:
	inc	si
	add	dx,0400h
	cmp	si,UMB_PAGE_COUNT
	jb	short CU_restore_scan
	mov	ax,cs:[umb_backing_count]
	sub	[_free_top],ax
	add	[_free_count],ax
	mov	cs:[umb_backing_count],0
ifdef UMB_SUBPAGE_MAPPING
	cmp	cs:[umb_fine_attempt],0
	je	short CU_done
	mov	cs:[umb_fine_attempt],0
	mov	cs:[umb_registration+2],0
	xor	si,si
CU_coarse_plan:
	mov	al,cs:umb_coarse_candidates[si]
	mov	cs:umb_candidates[si],al
	or	al,al
	jz	short CU_coarse_mask
	mov	al,0fh
CU_coarse_mask:
	mov	cs:umb_active_masks[si],al
	inc	si
	cmp	si,UMB_PAGE_COUNT
	jb	short CU_coarse_plan
	mov	al,'R'
	out	0e9h,al
	jmp	CU_retry_plan
endif
CU_done:
	pop	es
	popa
	ret
Commit_UMB endp

ifdef UMB_SUBPAGE_MAPPING
; DX=parent segment, SI=parent index, BP=previous extent end. Only BP changes.
; There are at most 24 disjoint 4 KiB runs in C000h..EFFFh.
Append_UMB_Subpage_Extents proc near
	push	ax
	push	bx
	push	cx
	push	dx
	mov	al,cs:umb_active_masks[si]
	mov	cx,4
ASE_slice:
	test	al,1
	jz	short ASE_next
	mov	bx,cs:[umb_registration+2]
	cmp	bp,dx
	jne	short ASE_new
	dec	bx
	shl	bx,2
	add	word ptr cs:umb_registration[bx+6],0100h
	jmp	short ASE_end
ASE_new:
	cmp	bx,24
	jae	short ASE_failed
	shl	bx,2
	mov	word ptr cs:umb_registration[bx+4],dx
	mov	word ptr cs:umb_registration[bx+6],0100h
	inc	cs:[umb_registration+2]
ASE_end:
	mov	bp,dx
	add	bp,0100h
ASE_next:
	add	dx,0100h
	shr	al,1
	loop	ASE_slice
	clc
	jmp	short ASE_done
ASE_failed:
	stc
ASE_done:
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
Append_UMB_Subpage_Extents endp
endif

; SI starts an eight-page UMA region (last region may be shorter). Select a
; below-16-MiB physical 128 KiB region containing every requested page, at the
; same offset modulo 128 KiB. This guarantees contiguity and both DMA channel
; boundary sizes without reserving pages for excluded UMA holes. No ownership
; changes until the whole region has been checked. CF=1: no safe selection.
Choose_UMB_DMA_Group proc near
	pushad
ifdef UMB_TEST_DMA_UNAVAILABLE
; Reject the last region after earlier groups may already have been mapped.
	cmp	si,16
	jae	CUD_failed
endif
	mov	di,si
	add	di,8
	cmp	di,UMB_PAGE_COUNT
	jbe	short CUD_limit
	mov	di,UMB_PAGE_COUNT
CUD_limit:
	mov	cs:[umb_dma_limit],di
	mov	bp,si
CUD_first:
	cmp	bp,di
	jae	CUD_success		; no candidates in this region
	cmp	cs:umb_candidates[bp],0
	jne	short CUD_search
	inc	bp
	jmp	short CUD_first
CUD_search:
	mov	si,[_free_top]
	shl	si,1
	add	si,[_emm_free]
	mov	cx,[_free_count]
	jcxz	CUD_failed
CUD_try:
	mov	bx,[si]
	shl	bx,1
	shl	bx,1
	add	bx,[_pft386]
	mov	eax,[bx]
	and	eax,0fffff000h
ifdef UMB_TEST_DMA_ABOVE_ISA
; Exercise the selector's physical-address ceiling without changing the PFT.
	or	eax,01000000h
endif
	movzx	edx,bp
	and	dx,7
	shl	edx,14
	mov	ebx,eax
	and	ebx,01ffffh
	cmp	ebx,edx
	jne	short CUD_next
	and	eax,0fffe0000h
	cmp	eax,01000000h
	jae	short CUD_next
	mov	cs:[umb_dma_base],eax
	mov	di,bp
CUD_verify:
	cmp	di,cs:[umb_dma_limit]
	jae	short CUD_success
	cmp	cs:umb_candidates[di],0
	je	short CUD_verified_page
	movzx	eax,di
	and	ax,7
	shl	eax,14
	add	eax,cs:[umb_dma_base]
	call	Find_UMB_Free_Page
	jc	short CUD_next
CUD_verified_page:
	inc	di
	jmp	short CUD_verify
CUD_next:
	add	si,2
	dec	cx
	jnz	CUD_try
CUD_failed:
	popad
	stc
	ret
CUD_success:
	popad
	clc
	ret
Choose_UMB_DMA_Group endp

; EAX=physical 16 KiB page address. Return DS:BX free-stack slot and CF=0.
; Only available pages are searched; preserve the caller's iteration state.
Find_UMB_Free_Page proc near
	push	cx
	push	di
	push	edx
	mov	cx,[_free_count]
	mov	di,[_free_top]
	shl	di,1
	add	di,[_emm_free]
	jcxz	short FUF_missing
FUF_scan:
	mov	bx,[di]
	shl	bx,1
	shl	bx,1
	add	bx,[_pft386]
	mov	edx,[bx]
	and	edx,0fffff000h
	cmp	eax,edx
	je	short FUF_found
	add	di,2
	loop	FUF_scan
FUF_missing:
	pop	edx
	pop	di
	pop	cx
	stc
	ret
FUF_found:
	mov	bx,di
	pop	edx
	pop	di
	pop	cx
	clc
	ret
Find_UMB_Free_Page endp

Rollback_UMB proc near
	cmp	cs:[umb_registered],0
	je	short RU_done
	mov	ax,0e702h
	int	2fh
	cmp	ax,1
	jne	short RU_done
	xor	si,si
	mov	dx,0a000h
RU_restore_scan:
	cmp	cs:umb_candidates[si],2
	jne	short RU_restore_next
	call	Restore_UMB_Page
	mov	cs:umb_candidates[si],1
RU_restore_next:
	inc	si
	add	dx,0400h
	cmp	si,UMB_PAGE_COUNT
	jb	short RU_restore_scan
	mov	ax,cs:[umb_backing_count]
	sub	[_free_top],ax
	add	[_free_count],ax
	mov	cs:[umb_backing_count],0
	mov	cs:[umb_registered],0
RU_done:
	ret
Rollback_UMB endp

; AX=EMM backing page, DX=16 KiB UMA segment; development SI indexes its mask.
Map_UMB_Page proc near
ifdef UMB_SUBPAGE_MAPPING
	push	edx
	push	bp
endif
	push	eax
	push	bx
	push	cx
	push	di
	push	es
	mov	bx,ax
	shl	bx,1
	shl	bx,1
	add	bx,[_pft386]
	mov	eax,[bx]
	and	ax,0f000h
	or	ax,P_AVAIL
	mov	bx,[PageT_Seg]
	mov	es,bx
	mov	di,dx
	shr	di,1
	shr	di,1
	shr	di,1
	shr	di,1
	shr	di,1
	shr	di,1
	mov	cx,4
ifdef UMB_SUBPAGE_MAPPING
	mov	bp,si
	shl	bp,4
	mov	bl,1
endif
MUP_store:
ifdef UMB_SUBPAGE_MAPPING
	mov	edx,es:[di]
	mov	cs:umb_original_ptes[bp],edx
	test	cs:umb_active_masks[si],bl
	jz	short MUP_skip_slice
	mov	es:[di],eax
MUP_skip_slice:
	add	di,4
	add	bp,4
	shl	bl,1
else
	stosd
endif
	add	eax,01000h
	loop	MUP_store
	pop	es
	pop	di
	pop	cx
	pop	bx
	pop	eax
ifdef UMB_SUBPAGE_MAPPING
	pop	bp
	pop	edx
endif
	ret
Map_UMB_Page endp

; DX=16 KiB UMA segment. Normal restores identity; development SI selects
; the committed slices and their captured original PTEs, including flags.
Restore_UMB_Page proc near
ifdef UMB_SUBPAGE_MAPPING
	push	bp
endif
	push	eax
	push	bx
	push	cx
	push	di
	push	es
	movzx	eax,dx
	shl	eax,4
	or	ax,P_AVAIL
	mov	bx,[PageT_Seg]
	mov	es,bx
	mov	di,dx
	shr	di,1
	shr	di,1
	shr	di,1
	shr	di,1
	shr	di,1
	shr	di,1
	mov	cx,4
ifdef UMB_SUBPAGE_MAPPING
	mov	bp,si
	shl	bp,4
	mov	bl,1
endif
RUP_store:
ifdef UMB_SUBPAGE_MAPPING
	test	cs:umb_active_masks[si],bl
	jz	short RUP_skip_slice
	mov	eax,cs:umb_original_ptes[bp]
	mov	es:[di],eax
RUP_skip_slice:
	add	di,4
	add	bp,4
	shl	bl,1
else
	stosd
endif
	add	eax,01000h
	loop	RUP_store
	pop	es
	pop	di
	pop	cx
	pop	bx
	pop	eax
ifdef UMB_SUBPAGE_MAPPING
	pop	bp
endif
	ret
Restore_UMB_Page endp



page
;******************************************************************************
;
;	b2asc10 - converts binary to ascii decimal and store at CS:DI
;		  stores 5 ascii chars (decimal # is right justified and
;		  filled on left with blanks)
;
;	entry:	ax = binary number
;		DS = DGROUP
;		CS:di = place to store ascii chars.
;
;	exit:	ASCII decimal representation of number stored at DS:DI
;
;	used:	none
;
;	stack:
;
;******************************************************************************
;
b2asc10 proc	near
;
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
;
	mov	si,8			; pointer to base 10 table
	xor	bl,bl			; leading zeroes flag
;
;   convert binary number to decimal ascii
;
b2_loop:
	xor	dx,dx			; clear word extension
	mov	cx,CS:powr10[si]
	div	cx			; divide by power of 10
	or	bl,bl
	jnz	b2_ascii
;
	or	ax,ax			; q: zero result?
	jnz	b2_ascii		;  n: go convert to ascii
;
	mov	al,' '			;  y: go blank fill
	jmp	b2_make_strg		;
;
b2_ascii:
	add	al,'0'			; put into ascii format
	mov	bl,1			; leading zeroes on
;
b2_make_strg:
	mov	CS:[di],al		; put ascii number into string
	xchg	ax,dx
	inc	di			; increment buffer string pointer
	dec	si			; decrement power of 10 pointer
	dec	si			;
	jge	b2_loop 		; Q: Last digit?  N: Jump if not
;
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret				; *** return ***
;
b2asc10 endp
;

LAST	ends				; End of segment
;

	end				; End of module



