page	60,132				;
name	_replace
title	Critical error or control break exit
;-------------------------------------------------------------------
;
;	MODULE: 	_replace
;
;	PURPOSE:	Supplies assembler exit routines for
;			critical error or control break situations
;
;	CALLING FORMAT:
;			crit_err_handler;
;			ctl_brk_handler;
;
;	DATE:		10/87
;
;-------------------------------------------------------------------


	public	_crit_err_handler
	public	_ctl_brk_handler

;-------------------------------------------------------------------
RET_EXIT equ	4ch			; terminate
CTLBRK	equ	3			; errorlevel return in al
ABORT	equ	2			; if >=, retry
XABORT	equ	1			; errorlevel return in al
;-------------------------------------------------------------------


NULL	SEGMENT PARA PUBLIC 'BEGDATA'
NULL	ENDS
_DATA	SEGMENT PARA PUBLIC 'DATA'
	extrn	_oldint24:dword
_DATA	ENDS
CONST	SEGMENT WORD PUBLIC 'CONST'
CONST	ENDS
_BSS	SEGMENT WORD PUBLIC 'BSS'
_BSS	ENDS
STACK	SEGMENT PARA STACK 'DATA'
STACK	ENDS

PGROUP	GROUP	_TEXT
DGROUP	GROUP	NULL, _DATA, CONST, _BSS, STACK



_TEXT	segment para public 'CODE'
	ASSUME	CS:PGROUP

	extrn	_restore:near

;-------------------------------------------------------------------
; CRITICAL ERROR HANDLER
;-------------------------------------------------------------------
vector	dd	0			;receives a copy of _oldint24

_crit_err_handler proc near

	pushf				; req by int24 handler
	push	ax			; will use ax
	push	ds			; will use ds

	mov	ax,dgroup		; setup
	mov	ds,ax			;
	ASSUME	DS:DGROUP

	mov	ax,word ptr _oldint24	; load vector so we can use it
	mov	word ptr vector,ax	;
	mov	ax,word ptr _oldint24+2 ;
	mov	word ptr vector+2,ax	;

	pop	ds			; finished with ds
	ASSUME	DS:NOTHING

	pop	ax			; finished with ax

	call	dword ptr vector	; invoke DOS err hndlr

	cmp	al,ABORT		; what was the user's response
	jnge	retry			;

	mov	ax,(RET_EXIT shl 8)+XABORT ; return to DOS w/criterr error
	call	call_restore		; restore user's orig append/x
; =================== this call does not return ===============

retry:
	ASSUME	DS:NOTHING
	ASSUME	ES:NOTHING

	iret				; user response was "retry"

_crit_err_handler endp


;-------------------------------------------------------------------
; CONTROL BREAK HANDLER
;-------------------------------------------------------------------
_ctl_brk_handler proc near

	ASSUME	DS:NOTHING
	ASSUME	ES:NOTHING

	mov	ax,(RET_EXIT shl 8)+CTLBRK ; return to DOS w/ctlbrk error
;-------------------------------------------------------------------
	call	call_restore		; restore user's orig append/x
;-------------------------------------------------------------------
; =================== this call does not return ===============

_ctl_brk_handler endp

call_restore proc near
;input: ah has the RETURN TO DOS WITH RET CODE function request
;	al has the ERRORLEVEL return code to be passed back to DOS
;output: this routine does NOT RETURN, but exits to DOS with ret code.

	push	ax			;save errorlevel return code
	push	ds
	push	es

	mov	ax,dgroup		; setup "c" code regs
	mov	ds,ax			;
	ASSUME	DS:DGROUP

	mov	es,ax			;
	ASSUME	ES:DGROUP

;-------------------------------------------------------------------
	call	_restore		; restore user's orig append/x
;-------------------------------------------------------------------

	pop	es
	pop	ds
	pop	ax			;restore return code
	int	21h			;
	int	20h			; in case int21 fails

call_restore endp

_TEXT	ends				; end code segment
	end
