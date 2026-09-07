

TITLE	 SELECT Stub
SUBTTL	 SELSTUB.ASM

PAGE	 60,132

	INCLUDE SYSMSG.INC
	MSG_UTILNAME <SELECT>

CODE	 SEGMENT PARA  PUBLIC 'CODE'
	 ASSUME  CS:code
	 ASSUME  DS:code
	 ASSUME  ES:NOTHING
	 ASSUME  SS:NOTHING

	 ORG	 100H
MAIN	 PROC	 FAR
BEGIN:	 JMP	 A0

prognm	 DB	 "SELECT.EXE",0      ;AN000; EXEC this program

execparm DW	0		;AN000; environment string
	 DW	 80H		 ;AN000; command string offset
comseg	 DW	 ?		 ;AN000; command string segment
	 DW	 5CH		 ;AN000; use the FCB's from this program
seg1	 DW	 ?		 ;AN000; .
	 DW	 6CH		 ;AN000; use the FCB's from this program
seg2	 DW	 ?		 ;AN000; .

enter	 equ	 13		 ;AN000;ENTER key
escape	 equ	 27		 ;AN000;ESC key

	 EVEN
stck	 DB	 255 DUP(0)	 ;AN000;stack
stck_beg DB	 0

A0:
	 MOV	SP,OFFSET stck_beg ;AN000;setup local stack

	 CALL	LOAD_MSG
	 MOV	AX,10		 ;AN000;insert SELECT diskette in drive A:
	 CALL	DISPLAY_MSG

AGN:
	 XOR	 AH,AH		 ;AN000;get ENTER key
	 INT	 16H
	 CMP	 AL,ESCAPE	 ;AN000;if ESC, then exit
	 JE	 EXIT
	 CMP	 AL,ENTER	 ;AN000;if ENTER
	 JE	 INPOK		 ;AN000; then continue
	 MOV	 AX,11		 ;AN000;else, sound BELL
	 CALL	 DISPLAY_MSG
	 JMP	 AGN		 ;AN000;try again
INPOK:
	 CALL	 CHECK_DISKETTE  ;AN000;ensure INSTALL diskette in drive
	 JNC	 DSKTOK 	 ;AN000;if so, continue
	 CALL	 CLEAR_SCREEN	 ;AN032;SEH
	 MOV	 AX,11		 ;AN000;else, sound BELL
	 CALL	 DISPLAY_MSG
	 MOV	 AX,10		 ;AN032;SEH  flash msg on screen to insert SELECT diskette
	 CALL	 DISPLAY_MSG	 ;AN032;     if user has not inserted it
	 JMP	 AGN		 ;AN000;try again
DSKTOK:
	 CALL	 CLEAR_SCREEN

; Issue SETBLOCK to free memory

	 PUSH	 CS		 ;AN000; restore ES pointing to this segment
	 POP	 ES		 ;AN000; .
	 LEA	 AX,endofcode	 ;AN000; get the address of the program end
	 MOV	 BL,16		 ;AN000; get the paragraph size
	 DIV	 BL		 ;AN000; get the number of paragraphs
	 INC	 AL		 ;AN000; round up to next paragraph
	 SUB	 AH,AH		 ;AN000; clear high remainder
	 MOV	 BX,AX		 ;AN000; set up call
	 MOV	 AH,4AH 	 ;AN000; setblock function code
	 INT	 21H		 ;AN000; issue function to free memory

; EXEC the main program

	 MOV	 AX,CS		 ;AN000; get our segment
	 MOV	 DS,AX
	 MOV	 comseg,AX	 ;AN000; put in parameter blocks
	 MOV	 seg1,AX	 ;AN000; .
	 MOV	 seg2,AX	 ;AN000; .
	 MOV	 DX,OFFSET prognm ;AN000; get a pointer to the program name
	 MOV	 BX,OFFSET execparm ;AN000; get a pointer to the program parms
	 MOV	 AX,4BH*256	 ;AN000; get function code - load & execute
	 INT	 21H		 ;AN000; exec SELECT
EXIT:
	 MOV	 AX,4C00H
	 INT	 21H
	 RET

endofcode DB	?

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;	Message Retriever code inserted at this point....
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
MSG_SERVICES <MSGDATA>
MSG_SERVICES <NOVERCHECKmsg, DISPLAYmsg, LOADmsg>
MSG_SERVICES <SELECT.CLA,SELECT.CLB>
MSG_SERVICES <SELECT.CL1,SELECT.CL2>

;****************************************************************************
;
;   DISPLAY_MSG:  Call the message retriever to display a message.
;
;   INPUT:
;	AX = message number
;
;   OUTPUT:
;	If CY = 1, there was an error displaying the message.
;	If CY = 0, there were no errors.
;
;   OPERATION:
;
;****************************************************************************
DISPLAY_MSG PROC NEAR
    MOV  BX, -1 		       ;AN000; HANDLE -1 ==> USE ONLY DOS FUNCTION 1-12
    MOV  SI, 0			       ;AN000; SUBSTITUTION LIST
    MOV  CX, 0			       ;AN000; SUBSTITUTION COUNT
    MOV  DL, 00 		       ;AN000; DOS INT21H FUNCTION FOR INPUT 0==> NO INPUT
    MOV  DI, 0			       ;AN000; INPUT BUFFER IF DL = 0AH
    MOV  DH,  -1		       ;AN000; MESSAGE CALL -1==> UTILITY MESSAGE
    CALL SYSDISPMSG
    RET
DISPLAY_MSG ENDP

;****************************************************************************
;
;   LOAD_MSG:  Load the message
;
;   INPUT:
;	None
;
;   OUTPUT:
;	None
;
;****************************************************************************
LOAD_MSG PROC  NEAR
    CALL SYSLOADMSG
    RET
LOAD_MSG ENDP

;****************************************************************************
;
;   CLEAR_SCREEN:  Clear the screen and move cursor to top of display
;
;   INPUT:
;	None
;
;   OUTPUT:
;	None
;
;****************************************************************************
CLEAR_SCREEN PROC NEAR

	 MOV	 CX,0000H	 ;AN000;0,0 upper left of scroll
	 MOV	 DX,184FH	 ;AC032;SEH  24,79 lower right of screen
	 MOV	 BH,07H 	 ;AN000;normal attribute
	 MOV	 AX,600H	 ;AN000;scroll screen
	 INT	 10H

	 MOV	 DX,0000H	 ;AN000;move cursor to 0,0
	 XOR	 BH,BH		 ;AN000;display page
	 MOV	 AH,2		 ;AN000;move cursor
	 INT	 10H

	 RET

CLEAR_SCREEN ENDP

;****************************************************************************
;
;   CHECK_DISKETTE:  Check for INSTALL diskette in drive A:
;
;   INPUT:
;	None
;
;   OUTPUT:
;	CY = 0	correct diskette in drive
;	CY = 1	incorrect diskette in drive
;
;****************************************************************************
CHECK_DISKETTE PROC NEAR
	 PUSH	 DS
	 PUSH	 CS
	 POP	 DS
	 MOV	 DX,OFFSET dta	 ;AN000;set new dta
	 MOV	 AH,1AH
	 INT	 21H
	 MOV	 DX,OFFSET prognm ;AN000;search for this file
	 XOR	 CX,CX		 ;AN000;search attribute
	 MOV	 AH,4EH 	 ;AN000;find first matching file
	 INT	 21H
	 POP	 DS
	 RET
CHECK_DISKETTE ENDP

DTA	 DB	 ?		 ;AN000;start of dummy DTA for find first

include msgdcl.inc

MAIN	 ENDP
CODE	 ENDS
	 END	 BEGIN

