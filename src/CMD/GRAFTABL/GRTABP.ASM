	PAGE	90,132			;AN000;A2
	TITLE	GRTABP.SAL - GRAFTABL SYSTEM COMMAND LINE PARSER
;****************** START OF SPECIFICATIONS *****************************
; MODULE NAME: GRTABP.SAL
;
; DESCRIPTIVE NAME: Include the DOS system PARSER in the SEGMENT
;		    configuration expected by the modules of GRAFTABL.
;
;FUNCTION: The common code of the DOS command line PARSER is optimized by
;	   the setting of certain switches that cause the conditional
;	   assembly of only the required portions of the common PARSER.
;	   The segment registers are ASSUMED according to the type .COM.
;	   The Common PARSER is then INCLUDEd.
;
; ENTRY POINT: SYSPARSE, near
;
; INPUT:
;	ES - has seg id of the SEGMENT
;	     that contains the input control blocks,
;	     defined below.
;
;	DI - offset into ES of the PARMS INPUT BLOCK
;
;	DS - has seg id of the SEGMENT
;	     that contains the DOS input COMMAND
;	     string, which is originally presented at 81h
;	     in the PSP.
;
;	SI - offset into DS of the text of the DOS input COMMAND string
;	     as originally presented at 81H in the PSP.
;
;	DX - zero
;
;	CX - ordinal value, intially zero, updated on each subsequent call
;	     to the value returned in CX on the previous call.
;
;	CS - points to the segment containing the
;	     INCLUDE PARSE.ASM statement
;
;	DS - also points to the segment containing the INCLUDE
;	     PARSE.ASM statement.
;
; EXIT-NORMAL:	Output registers:
;	 AX - return code:
;	    RC_No_Error     equ     0	 ; No error
;	    RC_EOL	    equ     -1	 ; End of command line
;
;	 DX - Offset into ES of the selected RESULT BLOCK.
;	 BL - terminated delimiter code
;	 CX - new operand ordinal
;	 SI - set past scanned operand
;
; EXIT-ERROR: Output registers:
;	 AX - return code:
;	    RC_Too_Many     equ     1	 ; Too many operands
;	    RC_Op_Missing   equ     2	 ; Required operand missing
;	    RC_Not_In_SW    equ     3	 ; Not in switch list provided
;	    RC_Not_In_Key   equ     4	 ; Not in keyword list provided
;	    RC_Out_Of_Range equ     6	 ; Out of range specified
;	    RC_Not_In_Val   equ     7	 ; Not in value list provided
;	    RC_Not_In_Str   equ     8	 ; Not in string list provided
;	    RC_Syntax	    equ     9	 ; Syntax error
;
; INTERNAL REFERENCES:
;    ROUTINES: SYSPARSE:near (INCLUDEd in PARSE.ASM)
;
;    DATA AREAS: none
;
; EXTERNAL REFERENCES:
;    ROUTINES: none
;
;    DATA AREAS: control blocks pointed to by input registers.
;
; NOTES:
;	 This module should be processed with the SALUT preprocessor
;	 with the re-alignment not requested, as:
;
;		SALUT GRTABP,NUL,;
;
;	 To assemble these modules, the alphabetical or sequential
;	 ordering of segments may be used.
;
;	 For LINK instructions, refer to the PROLOG of the main module,
;	 GRTAB.SAL.
;
;****************** END OF SPECIFICATIONS *****************************
	IF1
	    %OUT    COMPONENT=GRAFTABL, MODULE=GRTABP.SAL...
	ENDIF
; =  =	=  =  =  =  =  =  =  =	=  =
;JWASM (HEADER macro defined later in file; this section-header call precedes its def) 	HEADER	<MACRO DEFINITION>
	INCLUDE PATHMAC.INC
; =  =	=  =  =  =  =  =  =  =	=  =

HEADER	MACRO	TEXT			;
.XLIST
	SUBTTL	TEXT
.LIST
	PAGE
	ENDM				;

; =  =	=  =  =  =  =  =  =  =	=  =
	HEADER	<SYSPARSE - SYSTEM COMMAND LINE PARSER>
CSEG	SEGMENT PARA PUBLIC
	ASSUME	CS:CSEG,DS:CSEG,ES:CSEG,SS:CSEG

FARSW	EQU	0			;AN000;CALL THE PARSER BY NEAR CALL
DATESW	EQU	0			;AN000;SUPPRESS DATE CHECKING
TIMESW	EQU	0			;AN000;SUPPRESS TIME CHECKING
FILESW	EQU	0			;AN000;SUPPRESS CHECKING FILE SPECIFICATION
CAPSW	EQU	0			;AN000;SUPPRESS FILE TABLE CAPS
CMPXSW	EQU	0			;AN000;SUPPRESS CHECKING COMPLEX LIST
DRVSW	EQU	0			;AN000;SUPPRESS SUPPORT OF DRIVE ONLY FORMAT
QUSSW	EQU	0			;AN000;SUPPRESS SUPPORT OF QUOTED STRING FORMAT
NUMSW	EQU	0			;AN000;SUPPRESS CHECKING NUMERIC VALUE
KEYSW	EQU	0			;AN000;SUPPRESS KEYWORD SUPPORT
SWSW	EQU	1			;AN000;DO SUPPORT SWITCHES
VAL1SW	EQU	0			;AN000;SUPPRESS SUPPORT OF VALUE DEFINITION 1
VAL2SW	EQU	0			;AN000;SUPPRESS SUPPORT OF VALUE DEFINITION 2
VAL3SW	EQU	1			;AN000;DO SUPPORT VALUE DEFINITION 3
BASESW	EQU	1			;AN005;SPECIFY, PSDATA POINTED TO BY "DS"
INCSW	EQU	0			;AN006;DO NOT INCLUDE PSDATA.INC


;	INCLUDE PSDATA.INC		;AN006; WORK AREA FOR PARSER
.XLIST
.XCREF
	INCLUDE PSDATA.INC		;AN006; WORK AREA FOR PARSER
.LIST
.CREF
	PATHLABL GRTABP

	PUBLIC	SYSPARSE		;AN000;SUBROUTINE ENTRY POINT

;	INCLUDE PARSE.ASM		;GENERATED CODE SUPPRESSED FROM LISTING
.XLIST
.XCREF
	INCLUDE PARSE.ASM
.LIST
.CREF
	PATHLABL GRTABP
CSEG	ENDS
	END
