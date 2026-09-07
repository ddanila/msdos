 page 80,132
TITLE	COMMAND interface to SYSPARSE

.xlist
.xcref
	INCLUDE comseg.asm
.list
.cref

TRANSPACE	SEGMENT PUBLIC BYTE

	CmpxSW	equ	0		;AN000; do not check complex list
	KeySW	equ	0		;AN000; do not support keywords
	Val2SW	equ	0		;AN000; do not Support value definition 2
	IncSW	equ	0		;AN000; do not include psdata.inc
	QusSW	equ	0		;AN025; do not include quoted string
	LFEOLSW equ	0		;AN044; do not use 0ah as line terminator
	TPARSE_SHORT_JUMPS equ 1	; JWasm: preserve COMMAND transient layout

.xlist
.xcref

include psdata.inc

.list
.cref

TRANSPACE	ENDS

TRANCODE	SEGMENT PUBLIC BYTE

ASSUME	CS:TRANGROUP,DS:NOTHING,ES:NOTHING,SS:NOTHING

; ****************************************************************
; *
; * ROUTINE:	 CMD_PARSE
; *
; * FUNCTION:	 Interface for transient COMMAND to invoke
; *		 SYSPARSE.
; *
; * INPUT:	 inputs to SYSPARSE
; *
; * OUTPUT:	 outputs from SYSPARSE
; *
; ****************************************************************

	public	Cmd_parse

.xlist
.xcref
	INCLUDE parse.asm
.list
.cref

Cmd_parse	Proc  near

	call	sysparse

	ret

Cmd_parse	endp

	public	Append_parse

Append_parse	Proc  Far

	call	sysparse

	ret

Append_parse	endp

trancode    ends
	    end
