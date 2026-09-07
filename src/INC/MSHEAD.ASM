; TITLE   MSHEAD.ASM -- MS-DOS DEFINITIONS
PAGE
; MS-DOS  High-performance operating system for the 8086  version 1.28
;	by Microsoft MSDOS development group:
;	    TP (Ret.)
;	    AR
;	    NP (Parenting)
;	    MZ
;	    CP (BIOS) (ret.)

INCLUDE DOSSYM.INC
INCLUDE DEVSYM.INC

Break <SEGMENT DECLARATIONS>

; The following are all of the segments used.  They are declared in the order
; that they should be placed in the executable

;
; segment ordering for MSDOS
;

include dosseg.asm

AsmVar	<Installed>

START		SEGMENT BYTE PUBLIC 'START'
		ASSUME	CS:DOSGROUP,DS:NOTHING,ES:NOTHING,SS:NOTHING
	JMP	near ptr DOSINIT
	; The HMA-addressability padding lives at the beginning of CONSTANTS so
	; resident utilities which replicate DOS data receive identical offsets.
START		ENDS

LAST		SEGMENT PARA PUBLIC 'LAST'
	Extrn	DOSINIT:NEAR
LAST		ENDS
