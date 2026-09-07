page	60,132
name	_msgret
title	C	to Message Retriever
;-------------------------------------------------------------------
;
;	MODULE: 	_msgret
;
;	PURPOSE:	Supplies an interface between C programs and
;			the DOS 3.3 message retriever
;
;	CALLING FORMAT:
;			sysloadmsg(&inregs,&outregs);
;			sysgetmsg(&inregs,&outregs);
;			sysdispmsg(&inregs,&outregs);
;
;
;	DATE:		5-21-87
;
;-------------------------------------------------------------------

	INCLUDE SYSMSG.INC		;PERMIT SYSTEM MESSAGE HANDLER DEFINITION

	MSG_UTILNAME <REPLACE>		;IDENTIFY THE COMPONENT

	.8087
_TEXT	SEGMENT BYTE PUBLIC 'CODE'
_TEXT	ENDS
_DATA	SEGMENT WORD PUBLIC 'DATA'
_DATA	ENDS
CONST	SEGMENT WORD PUBLIC 'CONST'
CONST	ENDS
_BSS	SEGMENT WORD PUBLIC 'BSS'
_BSS	ENDS
DGROUP	GROUP	CONST, _BSS, _DATA
	ASSUME	CS: _TEXT, DS: _TEXT, SS: DGROUP, ES: DGROUP


	public	_sysloadmsg
	public	_sysgetmsg
	public	_sysdispmsg

;-------------------------------------------------------------------
;-------------------------------------------------------------------

_DATA	segment
.XLIST
.XCREF
	MSG_SERVICES <MSGDATA>		;DATA AREA FOR THE MESSAGE HANDLER
.LIST
.CREF
_DATA	ends


_TEXT	segment

;-------------------------------------------------------------------

; =  =	=  =  =  =  =  =  =  =	=  =

					;DEFAULT=CHECK DOS VERSION
					;DEFAULT=NEARmsg
					;DEFAULT=INPUTmsg
					;DEFAULT=NUMmsg
					;DEFAULT=NO TIMEmsg
					;DEFAULT=NO DATEmsg
;	MSG_SERVICES <LOADmsg,GETmsg,DISPLAYmsg,CHARmsg,NUMmsg,TIMEmsg,DATEmsg,INPUTmsg,FARmsg>
;	MSG_SERVICES <REPLACE.CLA,REPLACE.CL1,REPLACE.CL2>	   ;MSG TEXT
.XLIST
.XCREF
;	MSG_SERVICES <MSGDATA>		;DATA AREA FOR THE MESSAGE HANDLER
	MSG_SERVICES <LOADmsg,GETmsg,DISPLAYmsg,CHARmsg,NUMmsg,TIMEmsg,DATEmsg,INPUTmsg,FARmsg>
	MSG_SERVICES <REPLACE.CLA,REPLACE.CL1,REPLACE.CL2> ;MSG TEXT
.LIST
.CREF
;-------------------------------------------------------------------

_sysloadmsg proc near

	push	bp			; save user's base pointer
	mov	bp,sp			; set bp to current sp
	push	di			; save some registers
	push	si

;	copy C inregs into proper registers

	mov	di,[bp+4]		; fix di (arg 0)
	push	ds
	pop	es

;-------------------------------------------------------------------

	mov	ax,[di+0ah]		; load di
	push	ax			; the di value from inregs is now on stack

	mov	ax,[di+00]		; get inregs.x.ax
	mov	bx,[di+02]		; get inregs.x.bx
	mov	cx,[di+04]		; get inregs.x.cx
	mov	dx,[di+06]		; get inregs.x.dx
	mov	si,[di+08]		; get inregs.x.si
	pop	di			; get inregs.x.di from stack

	push	bp			; save base pointer

;-------------------------------------------------------------------
	call	sysloadmsg		; call the message retriever
;-------------------------------------------------------------------

	pop	bp			; restore base pointer
	push	di			; the di value from call is now on stack
	mov	di,[bp+6]		; fix di (arg 1)

	mov	[di+00],ax		; load outregs.x.ax
	mov	[di+02],bx		; load outregs.x.bx
	mov	[di+04],cx		; load outregs.x.cx
	mov	[di+06],dx		; load outregs.x.dx
	mov	[di+08],si		; load outregs.x.si

	lahf				; get flags into ax
	mov	al,ah			; move into low byte
	mov	[di+0ch],ax		; load outregs.x.cflag

	pop	ax			; get di from stack
	mov	[di+0ah],ax		; load outregs.x.di

;-------------------------------------------------------------------

	pop	si			; restore registers
	pop	di
	mov	sp,bp			; restore sp
	pop	bp			; restore user's bp
	ret

_sysloadmsg endp


_sysgetmsg proc near

	push	bp			; save user's base pointer
	mov	bp,sp			; set bp to current sp
	push	di			; save some registers
	push	si

;	copy C inregs into proper registers

	mov	di,[bp+4]		; fix di (arg 0)
	push	ds
	pop	es

;-------------------------------------------------------------------

	mov	ax,[di+0ah]		; load di
	push	ax			; the di value from inregs is now on stack

	mov	ax,[di+00]		; get inregs.x.ax
	mov	bx,[di+02]		; get inregs.x.bx
	mov	cx,[di+04]		; get inregs.x.cx
	mov	dx,[di+06]		; get inregs.x.dx
	mov	si,[di+08]		; get inregs.x.si
	pop	di			; get inregs.x.di from stack

	push	bp			; save base pointer

;-------------------------------------------------------------------
	call	sysgetmsg		; call the message retriever
;-------------------------------------------------------------------

	pop	bp			; restore base pointer
	push	di			; the di value from call is now on stack
	mov	di,[bp+6]		; fix di (arg 1)

	mov	[di+00],ax		; load outregs.x.ax
	mov	[di+02],bx		; load outregs.x.bx
	mov	[di+04],cx		; load outregs.x.cx
	mov	[di+06],dx		; load outregs.x.dx
	mov	[di+08],si		; load outregs.x.si

	lahf				; get flags into ax
	mov	al,ah			; move into low byte
	mov	[di+0ch],ax		; load outregs.x.cflag

	pop	ax			; get di from stack
	mov	[di+0ah],ax		; load outregs.x.di

;-------------------------------------------------------------------

	pop	si			; restore registers
	pop	di
	mov	sp,bp			; restore sp
	pop	bp			; restore user's bp
	ret

_sysgetmsg endp

_sysdispmsg proc near

	push	bp			; save user's base pointer
	mov	bp,sp			; set bp to current sp
	push	di			; save some registers
	push	si

;	copy C inregs into proper registers

	mov	di,[bp+4]		; fix di (arg 0)
	push	ds
	pop	es

;-------------------------------------------------------------------

	mov	ax,[di+0ah]		; load di
	push	ax			; the di value from inregs is now on stack

	mov	ax,[di+00]		; get inregs.x.ax
	mov	bx,[di+02]		; get inregs.x.bx
	mov	cx,[di+04]		; get inregs.x.cx
	mov	dx,[di+06]		; get inregs.x.dx
	mov	si,[di+08]		; get inregs.x.si
	pop	di			; get inregs.x.di from stack

	push	bp			; save base pointer

;-------------------------------------------------------------------
	call	sysdispmsg		; call the message retriever
;-------------------------------------------------------------------

	pop	bp			; restore base pointer
	push	di			; the di value from call is now on stack
	mov	di,[bp+6]		; fix di (arg 1)

	mov	[di+00],ax		; load outregs.x.ax
	mov	[di+02],bx		; load outregs.x.bx
	mov	[di+04],cx		; load outregs.x.cx
	mov	[di+06],dx		; load outregs.x.dx
	mov	[di+08],si		; load outregs.x.si

	lahf				; get flags into ax
	mov	al,ah			; move into low byte
	mov	[di+0ch],ax		; load outregs.x.cflag

	pop	ax			; get di from stack
	mov	[di+0ah],ax		; load outregs.x.di

;-------------------------------------------------------------------

	pop	si			; restore registers
	pop	di
	mov	sp,bp			; restore sp
	pop	bp			; restore user's bp
	ret

_sysdispmsg endp

include msgdcl.inc

_TEXT	ends				; end code segment
	end

