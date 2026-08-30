

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
arg_token_len	db	0

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
	jnc	short parsed_ok
	call	report_invalid_parameter
	jmp	short term_no_message
parsed_ok:
	cmp	ax,no_arg		; q: no argument?
	jne	short set_requested_status
	cmp	cs:[weitek_seen],0	; W= alone only updates hardware policy
	jne	short weitek_only
	call	report_ems		; DOS 6 command-mode statistics
	jmp	short get_status
weitek_only:
	mov	dx,offset weitek_missing
	call	print_dollar
	mov	cs:[weitek_seen],0
	jmp	term_no_message
set_requested_status:
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
term_no_message:
	pop	di
	pop	dx
	pop	ax

	ret
onf_func	endp

report_invalid_parameter proc near
	push	ax
	push	cx
	push	dx
	push	si
	mov	dx,offset invalid_parameter_prefix
	call	print_dollar
	mov	si,offset arg_str
	xor	cx,cx
	mov	cl,cs:[arg_token_len]
invalid_parameter_char:
	jcxz	short invalid_parameter_done
	lodsb
	cmp	al,'a'
	jb	short invalid_parameter_emit
	cmp	al,'z'
	ja	short invalid_parameter_emit
	sub	al,'a'-'A'
invalid_parameter_emit:
	mov	dl,al
	mov	ah,2
	int	MSDOS
	loop	invalid_parameter_char
invalid_parameter_done:
	call	print_crlf
	pop	si
	pop	dx
	pop	cx
	pop	ax
	ret
report_invalid_parameter endp

; Print the DOS 6 command-mode EMS summary.  Values come through the public
; LIM 4.0 API, so this reports the live manager rather than build constants.
report_ems	proc	near
	push	ax
	push	bx
	push	cx
	push	dx
	xor	ah,ah
	call	ELIM_link
	mov	cs:[report_saved_mode],ah
	test	ah,1			; real-mode OFF state hides INT 67h
	jz	short report_manager_ready
	xor	ax,ax			; temporarily enter virtual mode for queries
	mov	ah,1
	call	ELIM_link
report_manager_ready:

	mov	dx,offset report_header
	call	print_dollar
	mov	ah,42h			; unallocated and total pages
	int	67h
	push	dx			; total pages
	push	bx			; free pages
	mov	dx,offset report_available_kb
	call	print_dollar
	pop	ax
	mov	cl,4
	shl	ax,cl			; 16 KiB per EMS page
	call	print_decimal
	mov	dx,offset report_kb_suffix
	call	print_dollar

	mov	dx,offset report_version
	call	print_dollar
	mov	ah,46h
	int	67h
	push	ax
	xor	ah,ah
	mov	cl,4
	shr	al,cl
	call	print_decimal
	mov	dl,'.'
	mov	ah,2
	int	MSDOS
	pop	ax
	and	ax,000fh
	call	print_decimal
	call	print_crlf

	mov	dx,offset report_total_pages
	call	print_dollar
	pop	ax
	call	print_decimal
	call	print_crlf
	mov	dx,offset report_free_pages
	call	print_dollar
	mov	ah,42h
	int	67h
	mov	ax,bx
	call	print_decimal
	call	print_crlf

	mov	dx,offset report_total_handles
	call	print_dollar
	mov	ax,5402h		; LIM 4.0 total handle capacity
	int	67h
	mov	ax,bx
	call	print_decimal
	call	print_crlf
	mov	dx,offset report_active_handles
	call	print_dollar
	mov	ah,4bh
	int	67h
	mov	ax,bx
	call	print_decimal
	call	print_crlf

	mov	dx,offset report_frame
	call	print_dollar
	mov	ah,41h
	int	67h
	mov	ax,bx
	call	print_hex4
	mov	dx,offset report_hex_suffix
	call	print_dollar

	mov	al,cs:[report_saved_mode]
	test	al,1
	jz	short report_mode_restored
	cmp	al,3
	je	short report_restore_auto
	mov	ax,0101h		; restore explicit OFF
	call	ELIM_link
	jmp	short report_mode_restored
report_restore_auto:
	mov	ax,0102h		; restore AUTO (AutoUpdate selects ON/OFF)
	call	ELIM_link
report_mode_restored:

	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
report_ems	endp

print_dollar	proc	near
	push	ax
	mov	ah,9
	int	MSDOS
	pop	ax
	ret
print_dollar	endp

print_crlf	proc	near
	push	dx
	mov	dx,offset report_newline
	call	print_dollar
	pop	dx
	ret
print_crlf	endp

print_decimal	proc	near
	push	ax
	push	bx
	push	cx
	push	dx
	xor	cx,cx
	mov	bx,10
decimal_divide:
	xor	dx,dx
	div	bx
	push	dx
	inc	cx
	or	ax,ax
	jnz	decimal_divide
decimal_emit:
	pop	dx
	add	dl,'0'
	mov	ah,2
	int	MSDOS
	loop	decimal_emit
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
print_decimal	endp

print_hex4	proc	near
	push	ax
	push	cx
	push	dx
	mov	cx,4
hex_emit:
	rol	ax,4
	mov	dl,al
	and	dl,0fh
	add	dl,'0'
	cmp	dl,'9'
	jbe	short hex_digit
	add	dl,'A'-'9'-1
hex_digit:
	push	ax
	mov	ah,2
	int	MSDOS
	pop	ax
	loop	hex_emit
	pop	dx
	pop	cx
	pop	ax
	ret
print_hex4	endp

report_header db "MICROSOFT Expanded Memory Manager 386  Version 4.49",CR,LF
	      db "Copyright Microsoft Corporation 1986, 1994",CR,LF,"$"
report_available_kb db "  Available expanded memory . . . . . . . . ","$"
report_kb_suffix db " KB",CR,LF,"$"
report_version db "  LIM/EMS version . . . . . . . . . . . . . ","$"
report_total_pages db "  Total expanded memory pages . . . . . . . ","$"
report_free_pages db "  Available expanded memory pages . . . . . ","$"
report_total_handles db "  Total handles . . . . . . . . . . . . . . ","$"
report_active_handles db "  Active handles  . . . . . . . . . . . . . ","$"
report_frame db "  Page frame segment  . . . . . . . . . . . ","$"
report_hex_suffix db " H",CR,LF,"$"
report_newline db CR,LF,"$"
report_saved_mode db 0
invalid_parameter_prefix db "Invalid parameter - ","$"

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
	mov	cs:[arg_token_len],cl
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
