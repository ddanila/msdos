

	page 58,132
;******************************************************************************
	title	ELIMFUNC - MEMM functions module
;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp. 1986
;
;	Title:	MEMM.EXE - MICROSOFT Expanded Memory Manager 386 Driver
;
;	Module: ELIMFUNC - entry point for VDM functions
;
;	Version: 0.05
;
;	Date:	May 24,1986
;
;	Author:
;
;******************************************************************************
;
;	Change Log:
;
;	DATE	 REVISION	Description
;	-------- --------	--------------------------------------------
;	04/24/86 Original	From EMML LIM driver.
;	06/28/86 0.02		Name change from MEMM386 to MEMM
;	07/05/86 0.04		Added segment R_CODE
;	07/06/86 0.04		Changed assume to DGROUP
;	07/10/86 0.05		jmp $+2 before "POPF"
;
;******************************************************************************
;   Functional Description:
;	This module contains the ON/OFF functionality code for activating/
;   deactivating EMM386 from DOS.  Functions in _TEXT to reduce code in
;   R_CODE segment.
;
;******************************************************************************
.lfcond
.386p
	page
;******************************************************************************
;			P U B L I C   D E C L A R A T I O N S
;******************************************************************************
;
	public	ELIM_Entry
	public	EDispatchSeg
;
	page
;******************************************************************************
;			L O C A L   C O N S T A N T S
;******************************************************************************
;
	include vdmseg.inc

FALSE	equ	0
TRUE	equ	not FALSE

;******************************************************************************
;			E X T E R N A L    R E F E R E N C E S
;******************************************************************************
;
_DATA	segment
	extrn	Active_Status:byte
	extrn	Auto_Mode:byte
_DATA	ends

_TEXT	segment
	extrn	_AutoUpdate:near	; update auto mode status
	extrn	GoVirtual:near
	extrn	RRProc:near		; Return processor to real mode(RRTrap)
_TEXT	ends

	page
;******************************************************************************
;			S E G M E N T	D E F I N I T I O N
;******************************************************************************
;
;******************************************************************************
;
;	Code Segment R_CODE
;
;******************************************************************************
;
R_CODE	segment
	assume	cs:R_CODE, ds:DGROUP, es:DGROUP
;
EFUN_CNT	equ	2

	page
;******************************************************************************
;	ELIM_Entry - entry point for general ELIM functions
;
;	THIS IS A FAR CALL ROUTINE
;
;	ENTRY:	REAL or VIRTUAL mode only
;		AH = 0	=> get current status of VDM/EMM386
;		AH = 1	=> ON/OFF/AUTO
;
;	EXIT: EMM386 is activated/deactivated if possible
;	      NC => no errors.
;	      CY => ERROR occured.
;			AH = error number
;			AH= 01 =>invalid function.
;
;	USED: none
;
;******************************************************************************
ELIM_Entry	proc	far
;
	push	ds
;
	push	seg DGROUP
	pop	ds
;
	cmp	ah,EFUN_CNT	;Q: valid function #
	jae	EE_inv_func	;  N: return error
	db	09Ah			; far call to relocated _TEXT
	dw	offset E_Dispatch
EDispatchSeg dw	_TEXT
;
EE_exit:
	pop	ds
	ret
;
EE_inv_func:
	mov	ah,01
	stc
	jmp	short EE_exit
;
ELIM_Entry	endp

R_CODE	ends

	page
;******************************************************************************
;
;	Code Segment _TEXT
;
;******************************************************************************
_TEXT	segment
	assume	cs:_TEXT, ds:DGROUP, es:DGROUP

; ELIM exposes exactly two functions. Keep one far transition in the resident
; R_CODE gateway and select the implementation after entering _TEXT.
E_Dispatch proc far
	or	ah,ah
	jz	E_GetStatus
	jmp	E_ONOFF
E_Dispatch endp

;******************************************************************************
;	E_GetStatus - get ELIM/VDM status
;
;	ENTRY:	AH = 0
;		DS = DGROUP
;
;	EXIT:	AH = 0 => ELIM ON
;		   = 1 => ELIM OFF
;		   = 2 => ELIM in AUTO mode (ON)
;		   = 3 => ELIM in AUTO mode (OFF)
;
;	USED: none
;
;******************************************************************************
E_GetStatus	proc	far
;
	xor	ah,ah			; init to on
	cmp	[Auto_Mode],0		; Q: auto mode ?
	je	not_auto		; N: try on/off
	mov	ah,2			; Y: indicate as such
not_auto:
	cmp	[Active_Status],0	;Q: is ELIM active ?
	jne	EGS_exit		;  Y: exit with status = 0/2
	inc	ah			;  N: exit with status = 1/3
EGS_exit:
	ret
;
E_GetStatus	endp

;******************************************************************************
;	E_ONOFF  - general ON/OFF code for ELIM
;
;	ENTRY:	AH = 1
;		 AL = 0 => ON
;		 AL = 1 => OFF
;		 AL = 2 => AUTO
;		DS = DGROUP
;
;	EXIT:	Virtual mode and ELIM ON
;		OR Real mode and ELIM OFF
;
;	USED: none
;
;******************************************************************************
E_ONOFF proc	far
	cmp	al,2			;Q: go to auto mode ?
	je	EOO_AUTO		;  Y: handle AUTO separately
	ja	EOO_inv			;  N: invalid function

	mov	[Auto_Mode],0		; explicit command leaves auto mode
	cmp	[Active_Status],0	;Q: currently active ?
	je	EOO_OFF			;  N: handle the OFF state
	or	al,al			;  Y: Q: ON already requested ?
	jz	EOO_OK			;       Y: no transition needed
	inc	[Active_Status]		;       N: publish OFF (FFh -> 00h)
	call	RRProc
	jmp	short EOO_OK

EOO_AUTO:
	cmp	[Auto_Mode],0		;  Y: Q: is it already in auto mode
	jne	EOO_OK			;     Y: then just leave
	mov	[Auto_Mode],1		;     N: then go to auto mode
	call	_AutoUpdate
	jmp	short EOO_OK

EOO_OFF:
	or	al,al			;Q: OFF already requested ?
	jnz	EOO_OK			;  Y: no transition needed
	dec	[Active_Status]		;  N: publish ON (00h -> FFh)
	call	GoVirtual
;
;   leave with no errors
;
EOO_OK:
	clc

EOO_exit:
	ret
;
;  invalide ON/OFF/AUTO function call
;
EOO_inv:
	mov	ah,1
	stc
	ret
;
E_ONOFF endp

;
_TEXT	ends

	end

