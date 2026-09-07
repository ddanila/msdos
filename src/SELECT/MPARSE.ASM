.ALPHA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	DUMMY DATA SEGMENT
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DATA	SEGMENT BYTE PUBLIC 'DATA'
DATA	       ENDS			;AN000;DATA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	PARSER INFORMATION
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.XLIST
FARSW	EQU	1
DATESW	EQU	0
TIMESW	EQU	0
FILESW	EQU	0
CAPSW	EQU	0
CMPXSW	EQU	0
DRVSW	EQU	0
QUSSW	EQU	0
KEYSW	EQU	1
SWSW	EQU	0
VAL1SW	EQU	1
VAL2SW	EQU	1
VAL3SW	EQU	1
.LIST
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
PARSER	SEGMENT PARA PUBLIC 'PARSER'
	ASSUME	CS:PARSER,DS:DATA,ES:DATA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	SYSPARSE
PAGE
	INCLUDE PARSE.ASM

PARSER	ENDS
	END
