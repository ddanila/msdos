

page	58,132
;******************************************************************************
	title	RetReal - Return-To-Real routine(s) for the 386
;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp. 1986
;
;   Title:    MEMM.EXE - MICROSOFT Expanded Memory Manager 386 Driver
;
;   Module:   RetReal - Return-To-Real routine(s) for the 386
;
;   Version:  0.04
;
;   Date:     February 20, 1986
;
;   Author:
;
;******************************************************************************
;
;   Change log:
;
;     DATE    REVISION			DESCRIPTION
;   --------  --------	-------------------------------------------------------
;   02/20/86  Original
;   05/12/86  A 	Cleanup and segment reorganization
;   06/01/86		Removed Real386a (loadall version) and left only
;			RetReal via PE bit
;   06/21/86  0.02	Saved Eax
;   06/28/86  0.02	Name changed from MEMM386 to MEMM
;   07/02/86  0.03	Reset TSS busy bit
;   07/05/86  0.04	Added Real_Seg label for _TEXT fixup
;   07/06/86  0.04	changed assume to DGROUP
;
;******************************************************************************
;
;   Functional Description:
;
;   This module contains the routine RetReal which goes from Ring 0 protected
;   mode to Real Mode by resetting the PE bit (and the PG bit).
;
;   NOTE: this module only works on the B0 and later parts.  The A2 part
;	  will leave the CS non writeable.
;
;******************************************************************************
.lfcond 				; list false conditionals
.386p
	page
;******************************************************************************
;			P U B L I C   D E C L A R A T I O N S
;******************************************************************************
;
	IFNDEF	RETREAL_HIGH_ONLY
	public	RetRealResume
	ENDIF
	IFNDEF	RETREAL_LOW_ONLY
	public	RetRealHigh
	public	Real_Seg
	ENDIF

	page
;******************************************************************************
;			I N C L U D E	F I L E S
;******************************************************************************

include VDMSEG.INC
include VDMSEL.INC
include INSTR386.INC
include OEMDEP.INC

;
;******************************************************************************
;			E X T E R N A L   R E F E R E N C E S
;******************************************************************************
;
_DATA	segment
	extrn	Active_Status:byte
	extrn	state_a20:byte
_DATA	ends

_TEXT	segment
	IFNDEF	RETREAL_LOW_ONLY
	extrn	SelToSeg:near		; stack selector to segment
	extrn	RetRealResume:near
	ENDIF
	IFNDEF	RETREAL_HIGH_ONLY
	extrn	DisableA20:near 	; disable A20 line	(MODESW)
	ENDIF

_TEXT	ends
;******************************************************************************
;			L O C A L   C O N S T A N T S
;******************************************************************************
;
FALSE	equ	0
TRUE	equ	not FALSE

	page
;******************************************************************************
;			S E G M E N T	D E F I N I T I O N
;******************************************************************************

_TEXT	segment
	assume	cs:_TEXT, ds:DGROUP
	IFNDEF	RETREAL_LOW_ONLY

real_gdt	label	qword
real_idt	dw	0FFFFh		; limit
		dw	0000		; base
		dw	0000

	ENDIF

;***	RetReal - cause a 386 mode switch to real mode
;
;	ENTRY	Ring 0 protected mode
;		CLI - interrupts disabled
;		NMI should also be disabled here.
ifndef NOHIMEM
;		FS = Diag segment selector
endif
;
;	EXIT	Real Mode
;		DGROUP:[Active_Status] = 0
;		CS = _TEXT
;		DS = ES = FS = GS = DGROUP
;		SS = stack segment
;		general registers preserved
;		flags modified
;		interrupts disabled
;		A20 disabled
ifndef NOHIMEM
;		high system memory LOCKED
endif
;
;	USES	see exit conditions above
;
;	DESCRIPTION
;
	IFNDEF	RETREAL_LOW_ONLY
RetRealHigh proc near
	pushad				; preserve the complete 386 caller frame
	cli				; disable ints

	smsw	ax			;check to see if we are in real mode
	test	ax,1
	jnz	rl386_a 		;jump if in protected mode
	sti
	popad
	ret				;otherwise return

rl386_a:

;
;   reset TSS busy bit before returning to Real Mode
;
	mov	ax, GDTD_GSEL
	mov	es, ax			; ES:0 = ptr to gdt

	and	byte ptr ES:[TSS_GSEL + 5], 11111101B

;
;   lock high system ROM before returning to real
;
	HwTabLock

;
;	First save return ss:sp. We have to translate
;	the current ss (a selector) into a segment number.
;	Calculate a real mode segment corresponding to the
;	current protected mode stack selector base address.
;
;	We get the base address from the descriptor table,
;	and convert it to a paragraph number.
;
	call	SelToSeg		; BX = setup stack segment
;
;
;  Intel shows DS,ES,FS,GS,and SS set up to make sure 'Real Mode' type
;  access rights, and limit are installed.  In this program, that happens
;  to already be the case, but for general purposeness, VDMD_GSEL fits
;  the bill.
;
	mov	ax,VDMD_GSEL		; selector with real mode attributes
	mov	ds,ax
	mov	es,ax
	mov	ss,ax
	MOV_FS_AX
	MOV_GS_AX
;
;  Intel recommends the following code for resetting the PE bit.  Mine
;  works OK, but maybe it's not general purpose enough (I was counting
;  on knowing that paging wasn't enabled).
;
	MOV_EAX_CR0			;  get CR0

	mov	[Active_Status],0	; publish the transition while DGROUP is selected
	; Interrupts and NMI are disabled, so install the real IVT descriptor
	; immediately before clearing PE and keep the descriptor out of the low copy.
	lidt	fword ptr cs:[real_idt]
	and	eax,07FFFFFFEh		; force real mode and shut down paging

	MOV_CR0_EAX			; set CR0

					; flush prefetched instructions with:
	db	0EAh			; Far Jump opcode
	dw	offset _TEXT:RetRealResume ; destination offset in retained low copy
Real_Seg	label	word
	dw	_TEXT			; destination segment
RetRealHigh endp
	ENDIF

	IFNDEF	RETREAL_HIGH_ONLY
RetRealResume:
	; RetRealHigh already cleared CR0.PG, which invalidates the 386/486 TLB.
	; GoVirtual also reloads CR3 before paging is enabled again.

	mov	ss,bx			; ss = real mode stack segment
	mov	ax,DGROUP
	mov	ds,ax
	mov	es,ax
	MOV_FS_AX
	MOV_GS_AX

	cmp	[state_a20],0		; restore the client's logical A20 state
	jne	short RetRealA20Done	; protected mode already left it enabled
	call	DisableA20
RetRealA20Done:

	popad
	ret				; *** RETURN ***
	ENDIF

_TEXT	ends
	end

