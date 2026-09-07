page	60,132
name	asm2c
title	Limited assembler to C interface
;-------------------------------------------------------------------
;
;	MODULE: 	asm2c
;
;	PURPOSE:
;		This routine is used as to map the assembly language
;		call made by xxx to a C language call.
;
;	INPUT:
;
;		ES:DI points to the buffer area where the table data
;		will be copied
;
;	CALLING FORMAT:
;
;	DATE:		7-16-87
;
;-------------------------------------------------------------------


	public	gget_status
	public	asm2cInRegs
	public	asm2coutregs
	public	asm2csegregs

_TEXT	segment byte public 'CODE'
_TEXT	ends
_DATA	segment word public 'DATA'
_DATA	ends
CONST	segment word public 'CONST'
CONST	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	GROUP	CONST, _BSS, _DATA

_DATA	segment word public 'DATA'

;-------------------------------------------------------------------
;	define an assembly language version of the C regs structure
;-------------------------------------------------------------------

asm2cInRegs	equ	$

i_ax		dw	0
i_bx		dw	0
i_cx		dw	0
i_dx		dw	0
i_si		dw	0
i_di		dw	0
i_cflag 	dw	0

Asm2cOutRegs	equ	$

o_ax		dw	0
o_bx		dw	0
o_cx		dw	0
o_dx		dw	0
o_si		dw	0
o_di		dw	0
o_cflag 	dw	0


Asm2cSegRegs	equ	$
s_es		dw	0
s_cs		dw	0
s_ss		dw	0
s_ds		dw	0

	extrn	_end:far

_DATA	ends

_TEXT	segment byte public 'CODE'

	extrn	_get_status:near

	ASSUME	CS: _TEXT
	assume	ds: nothing
	assume	es: nothing
;-------------------------------------------------------------------
;-------------------------------------------------------------------
page
;-------------------------------------------------------------------
;	ggetstatus
;
;		This routine will reside in the C code segment
;
;-------------------------------------------------------------------

segment_of_dgroup	dw	seg dgroup

SAVE_STACK	LABEL  DWORD
SAVE_SP 	DW	0
SAVE_SS 	DW	0

SAVE_DS 	DW	0
SAVE_ES 	DW	0

gget_status	 proc	 far

	MOV	SAVE_DS,DS
	MOV	SAVE_ES,ES

	MOV	SAVE_SS,SS
	MOV	SAVE_SP,SP

	mov	ss,segment_of_dgroup
	add	sp,offset DGROUP:_end
	ASSUME	SS: DGROUP

	MOV	DS,segment_of_dgroup
	ASSUME	DS: DGROUP

;-------------------------------------------------------------------
;	set up InRegs
;-------------------------------------------------------------------

	mov	i_ax,ax 	;AN000; make InRegs look like real registers
	mov	i_bx,bx
	mov	i_cx,cx
	mov	i_dx,dx
	mov	i_si,si
	mov	i_di,di

;-------------------------------------------------------------------
;	set up SegRegs
;-------------------------------------------------------------------

	IRP	XX,<ES,SS,DS>
	MOV	AX,SAVE_&XX
	MOV	S_&XX,AX
	ENDM

	mov	s_cs,cs

;-------------------------------------------------------------------
;	put far pointers on stack
;-------------------------------------------------------------------

;	push	ds		; push far pointer to SegRegs
	lea	ax,DGROUP:Asm2cSegRegs
	push	ax

;	push	ds		; push far pointer to OutRegs
	lea	ax,DGROUP:Asm2cOutRegs
	push	ax

;	push	ds		; push far pointer to InRegs
	lea	ax,DGROUP:Asm2cInRegs
	push	ax

;-------------------------------------------------------------------
	call	_get_status
;-------------------------------------------------------------------
	add	sp,6
;-------------------------------------------------------------------
;	set up real registers
;-------------------------------------------------------------------

	mov	ax,o_ax 	;AN000; make real registers look like OutRegs
	mov	bx,o_bx
	mov	cx,o_cx
	mov	dx,o_dx
	mov	si,o_si
	mov	di,o_di

;-------------------------------------------------------------------
;	must remove the things we put on the stack
;-------------------------------------------------------------------

	MOV	DS,SAVE_DS
	MOV	ES,SAVE_ES
	MOV	SS,SAVE_SS
	MOV	SP,SAVE_SP

	ret


gget_status	 endp

_TEXT	ends			;AN000; end code segment

;-------------------------------------------------------------------
;-------------------------------------------------------------------


	end

