;******************************************************************************
;   IFSFUNC Parse Symbol File
;   Parsing: NAMES = n		     ;;;alias[n | (n {m})]
IFSF_PARMS	LABEL	WORD	; IFSFUNC parms input block
	DW	IFSF_PARMSX	; offset of ifsfunc parms extension block
	DB	0		; No extra delimeters or eol chars
IFSF_PARMSX	LABEL	BYTE	; IFSFUNC parm extension block
	DB	0,0,0		; 0 positionals, 0 switches
	DB	1		; 1 keyword (NAMES=)
	DW	IFSF_K1
IFSF_K1 	LABEL	WORD	; IFSFUNC 1 keyword
	DW	8001h		; Numeric/optional(NAMES=   ok)
	DW	0		; no function
	DW	IFSF_RESULT	; Result buffer
	DW	IFSF_K1_VAL	; value list
	DB	1		; 1 keyword
	DB	"NAMES=",0
IFSF_K1_VAL	LABEL	BYTE	; value definition
	DB	1		; # value defns: get one: n or (n,m)
	DB	1		; # ranges
	DB	"N"             ; value to return if n in range
	DD	0,255		; range
;;;alias Complex control blocks
; IFSF_COMPLEX_PARMS  LABEL WORD
;	  DW	  IFSF_COMPLEX_PARMSX
;	  DB	  0		  ; No extra delimeters or eol chars
; IFSF_COMPLEX_PARMSX LABEL BYTE  ;
;	  DB	  1,2		  ; Min 1, Max 2 positionals
;	  DW	  IFSF_COMPLEX_POS1
;	  DW	  IFSF_COMPLEX_POS2
;	  DB	  0,0		  ; 0 switches, 0 keywords
; IFSF_COMPLEX_POS1 LABEL  WORD   ;
;	  DW	  8001h 	  ; N - optional
;	  DW	  0		  ; no function
;	  DW	  IFSF_RESULT	  ; Result buffer
;	  DW	  IFSF_POS_VAL	  ; value list
;	  DB	  0		  ; no switches/keywords
; IFSF_COMPLEX_POS2 LABEL  WORD   ;
;	  DW	  8001H 	  ; Numeric value, optional
;	  DW	  0		  ; no function
;	  DW	  IFSF_RESULT	  ; Result value buffer
;	  DW	  IFSF_POS_VAL	  ; value list
;;;alias  DB	  0		  ; no switches/keywords
;FSF_POS_VAL	LABEL	BYTE	; value definition
;	DB	2		; N and M
;	DB	2		; 2 ranges
;	DB	"N"             ; item tag for N
;	DD	0,255		; range of N
;	DB	"M"             ; item tag for M
;;;aliasDD	0,8160		; range of M
IFSF_RESULT	LABEL	BYTE
	DB	?		; type - 1=number, 4=complex
IFSF_TAG DB	?		; item tag returned: N,M or FF
	DW	?
IFSF_NM DB	?		; actual n or m value
	DB	?
	DB	?
	DB	?
; parser assemble switches
DateSW	equ	0
TimeSW	equ	0
FileSW	equ	0
CAPSW	equ	0
DrvSW	equ	0
QusSW	equ	0
SwSW	equ	0
Val3SW	equ	0
	include PARSE.ASM			;together with PSDATA.INC
