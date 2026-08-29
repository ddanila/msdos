

	page	58,132
;******************************************************************************
	title	MEMMONF - (C) Copyright MICROSOFT Corp. 1986
;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp. 1986
;
;   Title:    MEMM - MICROSOFT Expanded Memory Manager 386
;
;   Module:   MEMMONF - parse for on/off/auto and perform the function
;
;   Version:  0.02
;
;   Date:     June 4, 1986
;
;   Author:
;
;******************************************************************************
;
;   Change log:
;
;     DATE    REVISION			DESCRIPTION
;   --------  --------	-------------------------------------------------------
;   06/04/86  Original
;   06/28/86  0.02	Name change from MEMM386 to MEMM
;
;******************************************************************************
;
;   Functional Description:
;	MEMMONF is used by MEMM.EXE UTILITY code and MEMM.COM to parse
;   the command line for ON, OFF, or AUTO and perform the function
;   via a call to ELIM_Entry.  It also displays the appropriate message
;   depending on the results of the parsing and call to ELIM_Entry.
;
;******************************************************************************
.lfcond 				; list false conditionals
.386p
	page
;******************************************************************************
;			P U B L I C   D E C L A R A T I O N S
;******************************************************************************
;
	public	onf_func
	public	get_token
;
;******************************************************************************
;			E X T E R N A L   R E F E R E N C E S
;******************************************************************************



_TEXT	segment byte use16 public 'CODE'
	extrn	Inst_chk:near
	extrn	ELIM_link:near
_TEXT	ends
;
	page
;******************************************************************************
;			L O C A L   C O N S T A N T S
;******************************************************************************
;
MSDOS		equ	21h			; MS-DOS function call

	include ascii_sm.equ

;******************************************************************************
;			S E G M E N T	D E F I N I T I O N
;******************************************************************************
;
_TEXT	segment byte use16 public 'CODE'
	assume	cs:_TEXT, ds:_TEXT, es:_TEXT, ss:_TEXT
;
;******************************************************************************
;			L O C A L   D A T A   A R E A
;******************************************************************************
;
	include 	memm_msg.inc
;
msg_tbl 	label	word		; table of final messages to display
		dw	offset vmode	; on
		dw	offset rmode	; off
		dw	offset amode	; auto
		dw	0		; no parameter will use above msgs
		dw	offset parmerr	; invalid parameter
		dw	offset verr_msg	; error entering vmode
		dw	offset rerr	; error entering rmode
		dw	offset aerr	; error entering amode
;
;	the valid arguments
;
on_arg		db	"on"
on_len		equ	($ - on_arg)

off_arg 	db	"off"
off_len 	equ	($ - off_arg)

auto_arg	db	"auto"
auto_len	equ	($ - auto_arg)

w_on_arg	db	"w=on"
w_on_len	equ	($ - w_on_arg)

w_off_arg	db	"w=off"
w_off_len	equ	($ - w_off_arg)

max_arg_len	equ	11
arg_str 	db	max_arg_len	dup(0)		; storage for get_token
;
arg_tbl 	label	word		; table of valid arguments
		dw	offset	on_arg
		dw	offset	off_arg
		dw	offset	auto_arg
		dw	offset	w_on_arg
		dw	offset	w_off_arg
arg_count	equ	($ - arg_tbl)/2
no_arg		equ	3
invalid_arg	equ	4
;
arg_len 	label	word		; table of argument lengths
		dw	on_len
		dw	off_len
		dw	auto_len
		dw	w_on_len
		dw	w_off_len

weitek_seen	db	0

page
;******************************************************************************
;	onf_func - Check command line for ON OFF or AUTO and perform function
;
;	ENTRY: es:di points to command line terminated by CR or LF
;
;	EXIT: The appropriate message is displayed
;
;	USED: none
;
;******************************************************************************
onf_func	proc	near

	push	ax
	push	dx
	push	di

	cld
;
; check for driver installed
;
	call	Inst_chk		; ax = 0/1 => isn't/is installed
	or	ax,ax			; q: is it installed?
	jnz	drvr_installed
	mov	dx,offset not_there	; Not installed message
	jmp	term			; display message and quit
;
drvr_installed:
;
	call	parse_onf		; look for ON/OFF
	jc	msg_disp		; invalid parameter
	cmp	ax,no_arg		; q: no argument?
	je	get_status		; y: get status
	push	ax			; save on/off indicator
	mov	ah,1			; ah=1 for set status routine
	call	ELIM_link		; go turn it on or off
	pop	ax			; restore on/off indicator
	jnc	get_status		; no error in status routine
	add	ax,5 			; indicate error
	jmp	msg_disp
;
get_status:
	xor	ah,ah			; get status
	call	ELIM_link		; status in ah
	mov	al,ah
	xor	ah,ah			; status in ax
	cmp	ax,2			; q: auto mode?
	jb	msg_disp		; n: display mode
	push	ax			; save it
	mov	dx,offset amode
	mov	ah,9
	int	MSDOS			; print auto mode
	pop	ax			; restore mode
	sub	ax,2			; get on or off indicator
;
msg_disp:
	shl	ax,1			; make it a word index
	mov	di,ax			; offset into message table
	mov	dx,msg_tbl[di]		; get appropriate message
term:
	mov	ah,9
	int	MSDOS			; display error message
	cmp	cs:[weitek_seen],0
	je	short no_weitek_message
	mov	dx,offset weitek_missing
	mov	ah,9
	int	MSDOS
no_weitek_message:
;
	pop	di
	pop	dx
	pop	ax

	ret
onf_func	endp

	page
;******************************************************************************
;	get_token - Retrieve a non-white-space string from a source string
;
;	ENTRY: es:di points to command line terminated by CR or LF
;	       ds:si points to storage for token
;	       cx = maximum length to store
;
;	EXIT: cx = length of token (0 => end of source string)
;	      es:di points to first char after new token in source string
;	      string of length cx stored in ds:si (and converted to lower case)
;
;	USED: see above
;
;******************************************************************************
get_token	proc		near
	push	si		; save storage area
	push	bx
	push	ax
;
	mov	bx,cx		; number to store
	xor	cx,cx		; no chars found so far
;
; go to first non-blank character
;
gloop1:
	mov	al,es:[di]	; get a character
	inc	di		; point to next
	cmp	al,' '		; Q: space ?
	je	gloop1		; y: skip it
	cmp	al,TAB		; Q: TAB ?
	je	gloop1		; y: skip it
	dec	di		; N: start parsing and reset di
gloop2:
	mov	al,es:[di]	; get next char
	cmp	al,CR		; q: carriage return?
	je	token_xit	; y: quit
	cmp	al,LF		; q: line feed?
	je	token_xit	; y: quit
	cmp	al,' '		; Q: space ?
	je	token_xit	; y: quit
	cmp	al,TAB		; Q: TAB ?
	je	token_xit	; y: quit
	inc	di		; n: point to next
	inc	cx		; increment number of chars found
	cmp	cx,bx		; q: have we stored our limit yet?
	ja	gloop2		; y: don't store any more
	or	al,20h		; make it lower case
	mov	ds:[si],al	; store it
	inc	si		; and point to next
	jmp	short gloop2	; continue
token_xit:
;
	pop	ax
	pop	bx
	pop	si
	ret
get_token	endp

	page
;******************************************************************************
;	parse_onf - Parse ON/OFF/AUTO and the optional W= setting
;
;	ENTRY: es:di points to command line terminated by CR or LF
;
;	EXIT: ax = 0 => ON
;	      ax = 1 => OFF
;	      ax = 2 => AUTO
;	      ax = 3 => no argument encountered
;	      ax = 4 => Error in command line
;	      CARRY = cleared if no errors
;		      set if error (ax will also = 4)
;	      es:di points to end of parsed string
;
;	USED: see above
;
;******************************************************************************
parse_onf	proc		near
	push	si
	push	ds
	push	bx
	push	dx
	push	bp
	push	es

	mov	bp,no_arg		; selected mode, or no argument
	mov	cs:[weitek_seen],0
	xor	dx,dx			; token count
	cld
	push	cs
	pop	ds

parse_next:
	mov	si,offset arg_str
	mov	cx,max_arg_len
	call	get_token
	or	cx,cx
	jz	parse_good
	inc	dx
	cmp	dx,2
	ja	parse_bad

	push	di			; retain command-line position
	push	es
	push	ds
	pop	es
	xor	bx,bx
parse_compare:
	cmp	cx,arg_len[bx]
	jne	parse_not_this
	mov	di,arg_tbl[bx]
	push	si
	push	cx
	repe	cmpsb
	pop	cx
	pop	si
	je	parse_found
parse_not_this:
	add	bx,2
	cmp	bx,arg_count*2
	jb	parse_compare
	pop	es
	pop	di
	jmp	short parse_bad

parse_found:
	pop	es
	pop	di
	cmp	bx,6			; W=ON and W=OFF entries?
	jae	parse_weitek
	cmp	bp,no_arg		; duplicate mode selector?
	jne	parse_bad
	mov	bp,bx
	shr	bp,1
	jmp	short parse_next

parse_weitek:
	cmp	cs:[weitek_seen],0
	jne	parse_bad
	mov	cs:[weitek_seen],1
	jmp	short parse_next

parse_good:
	mov	ax,bp
	clc
	jmp	short parse_done
parse_bad:
	mov	cs:[weitek_seen],0
	mov	ax,invalid_arg
	stc
parse_done:
	pop	es
	pop	bp
	pop	dx
	pop	bx
	pop	ds
	pop	si
	ret
parse_onf	endp

_TEXT	ends

	end
