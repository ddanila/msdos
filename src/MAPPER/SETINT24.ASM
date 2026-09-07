;0
page 80,132

;**********************************************************************
;*
;*   MODULE:   set_int24_vector
;*
;*   Critical error handler for C programs BACKUP and RESTORE
;*
;*********************************************************************
;------------------------------------------------------------;;;
databuff  segment   public  'databuff'                       ;;;
databuff   ends 					     ;;;
;------------------------------------------------------------;;;


dosxxx	segment byte public 'dos'
	assume	cs:dosxxx,ds:nothing,es:nothing,ss:nothing


	    public   set_int24_vector
	    .sall
	    .xlist
	    include  macros.inc
	    .list

str	    struc
old_bp	    dw	     ?
Return	    dd	     ?
Flag	    dw	     ?
str	    ends


set_int24_vector   proc  far
	Enter	set_int24_vector

	mov	ax,seg databuff
	mov	ds,ax
	assume	ds:databuff

	mov	ax,03524h		;Get Int24 Vector
	int	21h
					;Save it
	mov	word ptr cs:OldInt24,bx
	mov	word ptr cs:OldInt24+2,es

					;Get address of my Int24 Handler
	mov	dx,cs
	mov	ds,dx
	mov	dx,offset AppErrorHandler

	mov	ax,02524H	       ;Set new INT24 vector
	int	21h

	xor	ax,ax		       ;Set good error return

exit:	mexit			       ; pop all registers
	ret	size str - 6	       ; return

set_int24_vector    endp





;-------------------------------------------------------
;
;	    ****   Error Handler  ******
;
;-------------------------------------------------------
Ignore		equ	0
Retry		equ	1
Abort		equ	2
Fail		equ	3

OldInt24   dd	?			;AN000; ;save old interrupt handler address  ;;;

AppErrorHandler    proc    near
	pushf
	call	dword ptr cs:OldInt24	;AN000; Get user to respond
	cmp	al,Abort		;AN000; For any resonse other than Abort
	jne	rett			;AN000;  retry the operation

	int	023h

rett:
	iret				;AN000; return to caller
AppErrorHandler 	endp
;-------------------------------------------------------
;-------------------------------------------------------

dosxxx	    ends
	   end
