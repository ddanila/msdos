

PAGE	60,132
NAME	SELECT
TITLE	SELECT0 - DOS - SELECT.EXE
SUBTTL	select0.asm
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	SELECT0.ASM : Copyright 1988 Microsoft
;
;	DATE:	 July 4/87
;
;	COMMENTS: Assemble with MASM 3.0 (using the /A option)
;
;		  Panel flow is defined in the following files:
;
;		      - SELECT1.ASM
;		      - SELECT2.ASM
;		      - SELECT3.ASM
;		      - SELECT4.ASM
;		      - SELECT5.ASM
;		      - SELECT6.ASM
;
CODE	  SEGMENT PARA PUBLIC 'CODE'                            ;AN000; Segment for CASS libraries
CODE	  ENDS
								;
CODE_FAR  SEGMENT PARA PUBLIC 'CODE'                            ;AN000; Segment for miscellaneous routines
CODE_FAR  ENDS
								;
_TEXT	segment byte public 'CODE'
_TEXT	ends
_DATA	segment word public 'DATA'
_DATA	ends
CONST	segment word public 'CONST'
CONST	ends
_BSS	segment word public 'BSS'
_BSS	ends
								;
								;
DATA	  SEGMENT BYTE PUBLIC 'DATA'                            ;AN000; Segment for Data values
DATA	  ENDS
								;
SELECT	SEGMENT PARA PUBLIC 'SELECT'
SELECT	  ENDS

SERVICE   SEGMENT PARA PUBLIC 'SERVICE'                         ;AN000; Segment for CAS_SERVICE routines
SERVICE   ENDS
								;
OUR_STACK SEGMENT BYTE	STACK				;AN000; Segment for Local Stack
	  DB   512  DUP('IBM ')
LAST_STACK EQU $
OUR_STACK ENDS
								;
PARSER	  SEGMENT PARA PUBLIC 'PARSER'                          ;AN000; Segment for PARSE code
PARSER	  ENDS

PCINPUT   SEGMENT PARA PUBLIC 'PCINPUT'
PCINPUT   ENDS
								;
ZSEG	  SEGMENT PARA PUBLIC 'ZSEG'                            ;AN000; Dummy segment for End-of-Code
ZSEG	  ENDS
								;
AGROUP GROUP CODE,CODE_FAR,DATA,PARSER,SERVICE,SELECT,OUR_STACK,ZSEG
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.XLIST
	INCLUDE PANEL.MAC
	INCLUDE STRUC.INC
	INCLUDE MACROS.INC
	INCLUDE SYSMSG.INC
	INCLUDE ROUT_EXT.INC
	INCLUDE EXT.INC
	INCLUDE PAN-LIST.INC
.LIST
								;
	EXTRN	DEALLOCATE_MEMORY_CALL:FAR
	EXTRN	CHECK_VERSION:NEAR
								;
	PUBLIC	INSTALL
	PUBLIC	SYSDISPMSG
	PUBLIC	EXIT_SELECT
	PUBLIC	EXIT_SELECT2
	PUBLIC	INITIALIZATION
	PUBLIC	ABORT_SELECT
								;
	MSG_UTILNAME <SELECT>
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SELECT	SEGMENT PARA PUBLIC 'SELECT'
	ASSUME	CS:SELECT,DS:DATA,SS:our_STACK
								;
OLD_STACK_SEG	DW	?
OLD_STACK_OFF	DW	?
								;
	INCLUDE CASEXTRN.INC
								;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Beginning of code
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
INSTALL PROC	FAR
	; WLINK may express a grouped entry as AGROUP:offset.  Normalize CS to
	; the SELECT segment before any CS-relative data or near control flow.
	MOV	AX,SEG SELECT
	PUSH	AX
	MOV	AX,OFFSET INSTALL_CANONICAL_CS
	PUSH	AX
	RETF
INSTALL_CANONICAL_CS:
	CLI
	MOV	AX,SS
	MOV	OLD_STACK_SEG,AX
	MOV	OLD_STACK_OFF,SP
	mov	ax,SEG our_stack
	mov	ss,ax
	mov	sp,512*4
	STI
								;
	MOV	AX,SEG DATA
	MOV	DS,AX
	JMP	INITIALIZATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	CODE TO LEAVE SELECT WITH!!!!
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
EXIT_SELECT:
								;
	FIND_FILE	     S_AUTO_REBOOT, 0			;AN000;DT Make sure INSTALL disk in drive
	.IF < c >
	   .REPEAT						;AN000;DT make sure diskette
	      CLEAR_SCREEN					;AN000;DT with COMMAND.COM in drive
	      DISPLAY_MESSAGE  19				;AN000;DT Insert INSTALL diskette
	      GET_FUNCTION	   FK_ENT
	      FIND_FILE 	   S_AUTO_REBOOT, 0
		 .LEAVE < nc >
		  HANDLE_ERROR	       ERR_DOS_DISK, 2
	   .UNTIL
	   CLEAR_SCREEN2
	.ENDIF
								;
EXIT_SELECT2:
								;
	DEALLOCATE_MEMORY					;AN000;free up allocated segment
	.IF < NC >
	   CALL    RESTORE_INT_23				;AN074;SEH restore ctrl-break before exiting
	   MOV	   AX,OLD_STACK_SEG
	   MOV	   SS,AX
	   MOV	   SP,OLD_STACK_OFF
	   CALL    CURSORON
	   MOV	   AX,4C00H
	   INT	   21H
	 .ELSE
ABORT_SELECT:							;AN000;exit without handling allocated memory
	   CALL    RESTORE_INT_23				;AN074;SEH restore ctrl-break before exiting
	   MOV	   AX,OLD_STACK_SEG
	   MOV	   SS,AX
	   MOV	   SP,OLD_STACK_OFF
	   CALL    CURSORON
	   MOV	   AX,4C00H
	   INT	   21H
	.ENDIF
INSTALL ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Message Retriever code inserted at this point....
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
 MSG_SERVICES <NOVERCHECKmsg, FARmsg, GETmsg, DISPLAYmsg, LOADmsg>
 MSG_SERVICES <SELECT.CLA,SELECT.CLB>
 MSG_SERVICES <SELECT.CL1,SELECT.CL2>
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Start of SELECT.EXE code
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
INITIALIZATION:
	LOAD_MESSAGES
	JMP	CHECK_VERSION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


SELECT	ENDS

include msgdcl.inc

	END	SELECT:INSTALL
