	PAGE	,132
	TITLE	DOS - GRAPHICS Command  -	Command line parsing module
;; DOS - GRAPHICS Command
;; (C) Copyright 1988 Microsoft
;; File Name:  GRPARMS.ASM
;; ----------
;; Description:
;; ------------
;;	 This file contains modules for parsing the GRAPHICS.COM
;;	 command line; using the DOS PARSER.
;; Documentation Reference:
;; ------------------------
;;	 OASIS High Level Design
;;	 OASIS GRAPHICS I1 Overview
;;	 DOS 3.3 Message Retriever Interface Supplement.
;;	 TUPPER I0 Document - PARSER HIGH LEVEL DESIGN REVIEW
;; Procedures Contained in This File:
;; ----------------------------------
;;	 PARSE_PARMS	  - Parse the command line
;;	 GET_R		  - Get /R
;;	 GET_B		  - Get /B
;;	 GET_LCD	  - Get /LCD
;;	 GET_PRINTBOX	  - Get /PRINTBOX
;;	 GET_PROFILE	  - Get the profile path and file name
;;	 GET_TYPE	  - Get the printer type
;; Include Files Required:
;; -----------------------
;;	 GRINST.EXT  - Externals for installation modules
;;	 GRPARSE.EXT - Externals for the DOS parser code
;;	 GRSHAR.STR  - Shared Data Area Structure
;;	 GRMSG.EQU   - Equates for GRAPHICS.COM error messages
;;	 STRUC.INC   - Macros for using structured assembly language
;; External Procedure References:
;; ------------------------------
;;	 FROM FILE  GRINST.ASM:
;;	      GRAPHICS_INSTALL - Main module for the installation of GRAPHICS
;;	 SYSPARSE - DOS system parser
;;	 SYSDISPMSG - DOS message retriever
;; Linkage Instructions:
;; --------------------
;;	 Refer to GRAPHICS.ASM
CODE	SEGMENT PUBLIC 'CODE'
	ASSUME	CS:CODE,DS:CODE
PARSE_PARMS PROC NEAR
	jmp	PARSE_PARMS_START
PUBLIC PARSE_PARMS
.XLIST
INCLUDE GRMSG.EQU		; Include GRAPHICS error messages equates
INCLUDE GRSHAR.STR		; Include the Shared data area structure
INCLUDE GRINST.EXT		; Include externals for the installation module
INCLUDE GRPARSE.EXT		; Include externals for the DOS parse code
INCLUDE STRUC.INC		; Include macros for using STRUCTURES
.LIST
PAGE
;===============================================================================
; PARSE_PARMS : PARSE THE COMMAND LINE PARAMETERS.
;-------------------------------------------------------------------------------
;	INPUT:	DS,ES		= SEGMENT CONTAINING THE PROGRAM PREFIX SEGMENT ;AN000;(PSP)
;	OUTPUT: SWITCHES	= A bit mask in the shared data area indicating
;				  which command line switches are set.
;		PROFILE_PATH	= The profile file name and path (ASCIIZ string)
;		PRINTBOX_ID_PTR = Offset of the printbox id (ASCIIZ string)
;		PRINTER_TYPE_PARM = printer type (ASCIIZ string)
;		CARRY FLAG IS SET if an error occurred
;-------------------------------------------------------------------------------
; DESCRIPTION: Call the DOS parser to parse the command line parameters
; of the GRAPHICS  command line which is obtained from the PSP (Program Segment
; Prefix).
; The format of the command line is:
;	GRAPHICS  {prt_type {profile}}	 {/R}  {/B}  {[/LCD | /PRINTBOX:id]}
;	(All arguments are optional, /PRINTBOX can be spelled /PB.)
; If no printer type is specified then, a null pointer is returned.
; If no profile name is supplied then, a null string is returned.
; If "/LCD" is specified then, a pointer to the printbox id: "LCD" is returned.
; LOGIC:
; Set addressibility to the command line parameters in the PSP
; CALL SYSPARSE       ; Call the system parser
; While not (End Of Line) AND no error
;   IF argument is the profile name
;   THEN Get the profile name
;   IF argument is the printbox switch
;   THEN Get the printbox id
;   IF argument is a /r
;   THEN Get /r
;   IF argument is /b
;   THEN Get /b
;   IF argument /lcd
;   THEN Get /lcd
;   CALL SYSPARSE
; If error
; Then display the appropriate error message
;-------------------------------------------------------------------------------
; BIT MASK INDICATING THE COMMAND LINE SWITCHES PARSED SO FAR:
;-------------------------------------------------------------------------------
SWITCH_PARSED DB   0
GOT_R	      EQU  1			; Found /R
GOT_B	      EQU  2			; Found /B
GOT_LCD       EQU  4			; Found /LCD
GOT_PRINTBOX  EQU  8			; Found /PB:id or /PRINTBOX:id
;===============================================================================
; CONTROL BLOCK DEFINITIONS FOR THE PARSER:
;===============================================================================
;-------------------------------------------------------------------------------
; PARMS INPUT BLOCK
;-------------------------------------------------------------------------------
PARMS LABEL WORD
	DW	PARMSX			; Offset of parms extension block
	DB	0			; No delimiters to define
					;  or end of line markers.
;-------------------------------------------------------------------------------
; PARMS EXTENSION BLOCK : Describe what's on the command line
;-------------------------------------------------------------------------------
PARMSX	LABEL BYTE
	DB	0,2			; Max. 2 positional parameters
	DW	TYPE_CTL		; Offset of type control block
	DW	PROF_CTL		; Offset of profile control block
	DB	4			; Max. 4 switch types
	DW	PRINTBOX_CTL		; Offset of control for Printbox
	DW	R_CTL			; Offset of control for /R
	DW	B_CTL			; Offset of control for /B
	DW	LCD_CTL 		; Offset of control for /LCD
	DB	0			; No keywords
;-------------------------------------------------------------------------------
; Describe the printer type parameter:
;-------------------------------------------------------------------------------
TYPE_CTL LABEL	WORD
	DW	2001H		 ; Optional simple string
	DW	0002H		 ; Capitalize it
	DW	TYPE_RESULT	 ; Offset of result buffer for printer type
	DW	NO_VALUES	 ; No values (NOTE: The type returned is checked
	DB	0		 ;		   for validity by LOAD_PROFILE)
NO_VALUES	DB	0
TYPE_RESULT	LABEL BYTE
	DB	?		; Type
	DB	?		; Item tag
	DW	?		; Offset of synomym
	DD	?		; Pointer to string found
;-------------------------------------------------------------------------------
; Describe the format of the PROFILE parameter:
;-------------------------------------------------------------------------------
PROF_CTL LABEL WORD
	DW	0201H		; File spec. - Optional
	DW	0001h		; Capitalize
	DW	PROFILE_RESULT	; Offset of result buffer for Profile
	DW	NO_VALUES	; No values needed
	DB	0
PROFILE_RESULT	LABEL BYTE
	DB	?		; Type
	DB	?		; Item tag
	DW	?		; Offset of synomym
	DD	?		; Offset of string
;-------------------------------------------------------------------------------
; Describe the format of /R
;-------------------------------------------------------------------------------
R_CTL	LABEL WORD
	DW	0		;
	DW	0		;
	DW	R_RESULT	; Offset of result buffer for a simple switch
	DW	NO_VALUES	; No values can be given with these switches.
	DB	1		; 1 name for this switch
	DB	"/R",0          ;   Reverse
R_RESULT LABEL BYTE
	DB	?		; Type
	DB	?		; Item tag
	DW	?		; Offset of synomym
	DD	?		; Offset of value
;-------------------------------------------------------------------------------
; Describe the format of /B
;-------------------------------------------------------------------------------
B_CTL	LABEL WORD
	DW	0		;
	DW	0		;
	DW	B_RESULT	; Offset of result buffer for a simple switch
	DW	NO_VALUES	; No values can be given with these switches.
	DB	1		; 1 name allowed for this switch
	DB	"/B",0          ;   Background
B_RESULT LABEL BYTE
	DB	?		; Type
	DB	?		; Item tag
	DW	?		; Offset of synomym
	DD	?		; Offset of value
;-------------------------------------------------------------------------------
; Describe the format of /LCD
;-------------------------------------------------------------------------------
LCD_CTL LABEL WORD
	DW	0		;
	DW	0		;
	DW	LCD_RESULT	; Offset of result buffer for a /LCD
	DW	NO_VALUES	; No values can be given with these switches.
	DB	1		; 1 name:
	DB	"/LCD",0        ;  /LCD
LCD_RESULT  LABEL BYTE
	DB	?		; Type
	DB	?		; Item tag
	DW	?		; Offset of synomym
	DD	?		; Offset of value
;-------------------------------------------------------------------------------
; Describe the format of the PRINTBOX switch:
;-------------------------------------------------------------------------------
PRINTBOX_CTL LABEL WORD
	DW	2001H		; Optional simple string
	DW	0001H		; Capitalize
	DW	PRINTBOX_RESULT ; Offset of result buffer for Printbox
	DW	NO_VALUES	; Values will be validated when loading profile
	DB	2		; 2 synomym for this switch:
	DB	"/PRINTBOX",0   ;
	DB	"/PB",0
PRINTBOX_RESULT LABEL BYTE
	DB	?		; Type
	DB	?		; Item tag
	DW	?		; Offset of synomym
	DD	?		; Offset of value
;===============================================================================
; DOS "MESSAGE RETRIEVER" Substitution list control block:
;-------------------------------------------------------------------------------
SUBLIST        LABEL DWORD		   ; List for substitution:
	       DB	11		   ; Size of this list
	       DB	0		   ; Reserved
SAVE_SI        DD	?		   ; Ptr to data item
	       DB	1		   ; Variable to be substitued: %1
	       DB	00010000B	   ; %1 is an ASCIIZ string left justifi;AN000;ed
	       DB	0		   ; Unlimited size for %1
	       DB	1		   ; Minimum size is 1 character
	       DB	" "                ; Delimiter is "space"
;===============================================================================
; START OF EXECUTABLE CODE:
;-------------------------------------------------------------------------------
PARSE_PARMS_START:
	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	SI
	PUSH	DI
	PUSH	ES
;-------------------------------------------------------------------------------
; Set up addressibility for the parser
;-------------------------------------------------------------------------------
	MOV	SI,81H			; DS:SI := Command line parameters
					;  to be parsed
	PUSH	CS
	POP	ES
	LEA	DI,PARMS		; ES:DI := Parms control block
;(deleted ;AN001;) XOR DX,DX		; CX,DX must be zero for the
	XOR	CX,CX			; Initially, CX should be zero
	MOV	AX,0			; No error yet
;-------------------------------------------------------------------------------
; Parse FIRST argument
;-------------------------------------------------------------------------------
;(deleted ;AN001;) CALL SYSPARSE	; Get one argument from the command line
	CALL	CALL_SYSPARSE		; Get one argument from the command line
;(deleted ;AN001;) MOV BX,DX		; BX := Offset of result block
.WHILE <AX EQ RC_NO_ERROR>		; While there is no error
;-------------------------------------------------------------------------------
; Get the argument:
;-------------------------------------------------------------------------------
       .SELECT
       .WHEN <BX EQ <OFFSET TYPE_RESULT>>
	  CALL	GET_TYPE
       .WHEN <BX EQ <OFFSET PROFILE_RESULT>>
	  CALL	GET_PROFILE_NAME
       .WHEN <BX EQ <OFFSET LCD_RESULT >>
	  CALL	GET_LCD
       .WHEN <BX EQ <OFFSET R_RESULT>>
	  CALL	GET_REVERSE
       .WHEN <BX EQ <OFFSET B_RESULT>>
	  CALL	GET_BACKGROUND
       .WHEN <BX EQ <OFFSET PRINTBOX_RESULT>>
	  CALL	GET_PRINTBOX_ID
       .OTHERWISE
;-------No result block was returned by the parser
	STC				; Set error
       .ENDSELECT
       .LEAVE C 			; IF error occurred while parsing the
					;  previous argument, exit the loop:
					;   stop parsing the command line.
;-------------------------------------------------------------------------------
; Parse next argument:
;-------------------------------------------------------------------------------
;(deleted ;AN001;) XOR DX,DX		;
;(deleted ;AN001;) CALL SYSPARSE	; Get one argument from the command line
	CALL	CALL_SYSPARSE		; Get one argument from the command line
;(deleted ;AN001;) MOV BX,DX		; ES:BX := Offset of result block
.ENDWHILE
;-------------------------------------------------------------------------------
; Check for error, select and display an error message
;-------------------------------------------------------------------------------
.IF <AL NE RC_EOL>			; IF an error occurred
.THEN					; then, display error message
    MOV 	CX,0			; Assume no substitutions
   .SELECT				; (CX := Number of substitutions
   .WHEN <AL EQ RC_TOO_MANY>		; When RC = Too many parameters
	MOV	AX,TOO_MANY_PARMS	;   (AL = Message number to display)
   .WHEN <AL EQ RC_Not_In_Val>		; When RC = Not in value list provided
	MOV	AX,VALUE_NOT_ALLOWED	;   (AL = Message number to display)
   .WHEN <AL EQ RC_Not_In_Sw>		; When RC = Not in switch list provided
	MOV	CX,1			;   1 substitution in this message
	MOV	BYTE PTR [SI],0 	; PUT NUL AT END OF THIS PARM
	LEA	SI,SUBLIST		;   DS:[SI]:="Invalid parm" Substitution;AN000; list
;(deleted ;AN001;) LES DX,ES:[BX+4]	;   ES:DX := Offset of offending parm.
;(deleted ;AN001;) MOV [SI]+2,DX	;   Store offset to this offender in the
	MOV	[SI]+4,ES		;    substitution list control block
	MOV	AX,INVALID_PARM 	;   AL := 'Invalid parameter' msg number
   .WHEN <AL EQ RC_INVLD_COMBINATION>	; When RC = Invalid combination of parms
	MOV	AX,INVALID_COMBINATION	;   (AL = Message number to display)
   .WHEN <AL EQ RC_DUPLICATE_PARMS>	; When RC = Invalid combination of parms
	MOV	AX,DUPLICATE_PARM	;   (AL = Message number to display)
   .OTHERWISE				;
	MOV	AX,FORMAT_NOT_CORRECT	; RC = Anything else, tell the user
					;	something is wrong with his
   .ENDSELECT				;	 command line.
    CALL DISP_ERROR			; Display the selected error message
    STC 				; Indicate parse error occurred
.ENDIF
	POP	ES
	POP	DI
	POP	SI
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	RET				; Return to GRAPHICS_INSTALL
PARSE_PARMS ENDP
CALL_SYSPARSE PROC NEAR 		;COMMON INVOCATION OF SYSPARSE
;INPUT: - CX=ORDINAL VALUE
;	  DS:SI=WHERE COMMAND LINE IS, SAVED IN "SAVE_SI"
;	  ES:DI=WHERE PARMS DESCRIPTOR BLOCK IS
;OUTPUT:  CX=NEW ORDINAL VALUE
;	  BX=OFFSET OF RESULT BLOCK, IF ONE IS RETURNED
;	  SI=OFFSET OF CHAR BEYOND PARSED PARM IN COMMAND LINE
	XOR	DX,DX			;CLEAR DX FOR PARSER
	MOV	WORD PTR SAVE_SI,SI	;REMEMBER WHERE TO START LOOKING
	CALL	SYSPARSE		;GO PARSE THE NEXT PARM
	MOV	BX,DX			; BX := Offset of result block
	RET				;RETURN TO CALLER
CALL_SYSPARSE ENDP
PAGE
;===============================================================================
; PROCEDURE_NAME: GET_PROFILE
; INPUT:  ES:[BX] := Result block
; OUTPUT: PROFILE_PATH = The profile file name and path (ASCIIZ string)
;-------------------------------------------------------------------------------
GET_PROFILE_NAME PROC
	PUSH	AX
	PUSH	BX
	PUSH	DX
	PUSH	SI
	PUSH	DI
;-------------------------------------------------------------------------------
; Get the name of the profile path found on the command line:
;-------------------------------------------------------------------------------
	MOV	DI,ES:[BX+4]	; DI := Offset of filename found
	XOR	BX,BX		; BX := Byte index
	MOV	SI,OFFSET PROFILE_PATH	; [BX][SI] := Where to store it
.IF <<BYTE PTR [DI]> NE 0>	; Don't copy a NULL parm
  .REPEAT			; While not end of path name (NULL terminated)
	MOV	AL,[BX][DI]	; Copy the byte (including the NULL)
	MOV	[BX][SI],AL
	INC	BX		; Get next one
  .UNTIL <<BYTE PTR [BX-1][DI]> EQ 0> ;
.ENDIF
	POP	DI
	POP	SI
	POP	DX
	POP	BX
	POP	AX
	CLC
	RET
GET_PROFILE_NAME ENDP
PAGE
;===============================================================================
; PROCEDURE_NAME: GET_TYPE
; INPUT:  ES:[BX] := Result block
;	  PRINTER_TYPE_LENGTH := Maximum length for the printer type string
; OUTPUT: PRINTER_TYPE_PARM = ASCIIZ string containing
;			       the Printer type.
;	  AX		    = Error code
;-------------------------------------------------------------------------------
GET_TYPE PROC
	PUSH	BX
	PUSH	CX
	PUSH	SI
	PUSH	DI
;----------------------------------------------------------------------
; Overwrite the DEFAULT TYPE with the type found on the command line
;----------------------------------------------------------------------
  MOV	  SI,ES:[BX+4]		       ; DS:SI := Offset of printer type found
 .IF <<BYTE PTR [SI]> NE 0>	       ; Do not copy an empty string
 .THEN				       ;
    MOV     CL,PRINTER_TYPE_LENGTH     ; CX := Maximum number of bytes
    XOR     CH,CH		       ;	to copy
    MOV     DI,OFFSET PRINTER_TYPE_PARM; ES:DI := Where to store it
    REP     MOVSB		       ; Copy the string
  ;----------------------------------------------------------------------
  ; Verify that the string supplied is not too long:
  ;----------------------------------------------------------------------
   .IF	<<BYTE PTR [DI-1]> EQ 0>       ; If the last byte is a null
   .THEN			       ; then, the string was not longer
				       ;       than the maximum
      CLC			       ;   Clear the carry flag = No error
   .ELSE			       ; else, string provided is too long
      MOV  AX,RC_Not_In_Sw	       ;   Error := RC for Invalid parm
      STC			       ; Set error
   .ENDIF			       ; ENDIF string too long
 .ENDIF 			       ; ENDIF string provided
GET_TYPE_END:
	POP	DI
	POP	SI
	POP	CX
	POP	BX
	RET
GET_TYPE  ENDP
PAGE
;===============================================================================
; PROCEDURE_NAME: GET_REVERSE
; INPUT:  ES:[BX]	:= Result block
;	  SWITCH_PARSED := The command line switches parsed so far (bit mask)
; OUTPUT: CS:[BP].SWITCHES (Bit mask in the Shared data area) is updated
;			    with the value of the switch found.
;	  GOT_R is set in SWITCH_PARSED
;	  AX		:= Error message number.
;	  CARRY FLAG IS SET IF ERROR FOUND
;-------------------------------------------------------------------------------
GET_REVERSE	PROC
	TEST	SWITCH_PARSED,GOT_R		; If already parsed this switch
	JNZ	DUPLICATE_R			; then, error
	OR	SWITCH_PARSED,GOT_R		; else, say we parsed it.
;-------------------------------------------------------------------------------
; Set the Reverse switch in the Shared data area
;-------------------------------------------------------------------------------
	OR	CS:[BP].SWITCHES,REVERSE_SW	; Set the command line switch
	CLC					; Clear the error flag
	JMP	SHORT GET_REVERSE_END		; Return
DUPLICATE_R:					; Already got this switch
	MOV	AX,RC_DUPLICATE_PARMS		; AX := error message number
	STC					; SET ERROR
GET_REVERSE_END:
	RET
GET_REVERSE	ENDP
PAGE
;===============================================================================
; PROCEDURE_NAME: GET_BACKGROUND
; INPUT:  ES:[BX] := Result block
;	  SWITCH_PARSED := The command line switches parsed so far (bit mask)
; OUTPUT: CS:[BP].SWITCHES (Bit mask in the Shared data area) is updated
;			    with the value of the switch found.
;	  GOT_B is set in SWITCH_PARSED
;	  AX		:= Error message number.
;	  CARRY FLAG IS SET IF ERROR FOUND
;-------------------------------------------------------------------------------
GET_BACKGROUND	PROC
	TEST	SWITCH_PARSED,GOT_B		; If already parsed this switch
	JNZ	DUPLICATE_B			; then, error
	OR	SWITCH_PARSED,GOT_B		; else, say we parsed it.
;-------------------------------------------------------------------------------
; Set the switch in the Shared data area
;-------------------------------------------------------------------------------
	OR	CS:[BP].SWITCHES,BACKGROUND_SW	; Set the command line switch
	CLC					; Clear the error flag
	JMP	SHORT GET_BACKGROUND_END	; Return
DUPLICATE_B:					; Already got this switch
	MOV	AX,RC_DUPLICATE_PARMS		; AX := error message number
	STC					; SET ERROR
GET_BACKGROUND_END:
	RET
GET_BACKGROUND	ENDP
PAGE
;===============================================================================
; PROCEDURE_NAME: GET_LCD
; INPUT:  SWITCH_PARSED   := The command line switches parsed so far (bit mask)
; OUTPUT: PRINTBOX_ID_PTR := Point to /LCD ASCIIZ string.
;	  GOT_B is set in SWITCH_PARSED
;	  AX		  := Error message number.
;	  CARRY FLAG IS SET IF ERROR FOUND
;-------------------------------------------------------------------------------
; Data Referenced:
;	  LCD_BOX = An ASCIIZ string representing the LCD printbox id.
;-------------------------------------------------------------------------------
GET_LCD PROC
	TEST	SWITCH_PARSED,GOT_LCD	   ; If already parsed this switch
	JNZ	DUPLICATE_LCD		   ; then, error: Duplicate switch
	TEST	SWITCH_PARSED,GOT_PRINTBOX ; If printbox already mentioned
	JNZ	BAD_COMBINATION 	   ; then, error: Invalid combination
;-------------------------------------------------------------------------------
; Set the pointer to the print box id to "LCD"
;-------------------------------------------------------------------------------
	MOV	AX,OFFSET LCD_BOX	   ; PRINTBOX id := LCD
	MOV	PRINTBOX_ID_PTR,AX	   ; Save pointer to this printbox id.
	OR	SWITCH_PARSED,GOT_LCD	   ; Say we found this switch
	CLC				   ; Clear the error flag
	JMP	SHORT GET_LCD_END	   ; Return
;-------------------------------------------------------------------------------
; /LCD was already parsed:
;-------------------------------------------------------------------------------
DUPLICATE_LCD:				   ; Already got this switch
	MOV	AX,RC_DUPLICATE_PARMS	   ; AX := error message number
	STC				   ; SET ERROR
	JMP	SHORT GET_LCD_END	   ; Return
;-------------------------------------------------------------------------------
; /PRINTBOX was already parsed:
;-------------------------------------------------------------------------------
BAD_COMBINATION:			   ; /LCD and /PRINTBOX invalid at same
	MOV	AX,RC_INVLD_COMBINATION    ;  time, Set the error flag
	STC				   ;   AX := Error code
GET_LCD_END:
	RET
GET_LCD 	ENDP
PAGE
;===============================================================================
; PROCEDURE_NAME: GET_PRINTBOX
; INPUT:  ES:[BX]	:= Result block
;	  SWITCH_PARSED := The command line switches parsed so far (bit mask)
; OUTPUT: DEFAULT_BOX	:= Is overwritten to contain the printbox id. found on
;			    the command line.
;	  GOT_PRINTBOX is set in SWITCH_PARSED
;	  AX		:= Error message number.
;	  CARRY FLAG IS SET IF ERROR FOUND
;-------------------------------------------------------------------------------
GET_PRINTBOX_ID PROC
	PUSH	CX
	PUSH	SI
	PUSH	DI
;-------------------------------------------------------------------------------
; Test for error in the printbox statement:
;-------------------------------------------------------------------------------
	TEST	SWITCH_PARSED,GOT_LCD	    ; If /LCD	  already mentioned
	JNZ	BAD_COMBINATION2	    ; then, error: Invalid combination
	TEST	SWITCH_PARSED,GOT_PRINTBOX  ; If already parsed this switch
	JNZ	DUPLICATE_PRINTBOX	    ; then, error: Duplicate switch
	MOV	DI,ES:[BX+4]		    ; DI := Offset of switch VALUE found
       .IF <<BYTE PTR [DI]> EQ 0>	    ; IF no printbox id
       .THEN				    ; then,
	 ;----------------------------------------------------------------------
	 ; No printbox id. was found:
	 ;----------------------------------------------------------------------
	  MOV	  AX,FORMAT_NOT_CORRECT     ;	AX := Error code
	  STC				    ;	Set the error flag
       .ELSE				    ; else,
	  OR	  SWITCH_PARSED,GOT_PRINTBOX;	Say we found this switch
	 ;----------------------------------------------------------------------
	 ; Overwrite DEFAULT_BOX with the Printbox id. found
	 ;----------------------------------------------------------------------
	  MOV	  CL,PRINTBOX_ID_LENGTH     ;	  CX := Maximum number of bytes
	  XOR	  CH,CH 		    ;		 to copy
	  MOV	  SI,DI 		    ;	  [DS][SI] :=  Value found
	  MOV	  DI,OFFSET DEFAULT_BOX     ;	  [ES][DI] :=  Default value
	  REP	  MOVSB 		    ;	  Copy the string
	 ;----------------------------------------------------------------------
	 ; Verify that the Printbox id. string is not too long:
	 ;----------------------------------------------------------------------
	 .IF  <<BYTE PTR [DI-1]> EQ 0>	    ; If the last byte is a null
	 .THEN				    ; then, the string was not longer
					    ;	    than the maximum
	    CLC 			    ;	Clear the carry flag = No error
	 .ELSE				    ; else, string provided is too long
	    MOV  AX,RC_Not_In_Sw	    ;	Error := RC for Invalid parm
	    STC 			    ; Set error
	 .ENDIF 			    ; ENDIF printbox id. too long
       .ENDIF				    ; ENDIF printbox id. provided
	JMP	SHORT GET_PRINTBOX_END	    ; Return
;-------------------------------------------------------------------------------
; /PRINTBOX was already parsed:
;-------------------------------------------------------------------------------
DUPLICATE_PRINTBOX:			    ; Already got this switch
	MOV	AX,RC_DUPLICATE_PARMS	    ; AX := error message number
	STC				    ; SET ERROR
	JMP	SHORT GET_PRINTBOX_END	    ; Return
;-------------------------------------------------------------------------------
; /LCD was already parsed:
;-------------------------------------------------------------------------------
BAD_COMBINATION2:			    ; /LCD and /PRINTBOX invalid at same
	MOV	AX,RC_INVLD_COMBINATION     ;  time, Set the error flag
	STC				    ;	AX := Error code
GET_PRINTBOX_END:
	POP	DI
	POP	SI
	POP	CX
	RET
GET_PRINTBOX_ID ENDP
CODE  ENDS
	END
