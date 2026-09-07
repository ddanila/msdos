PAGE	    ,132
TITLE	    PARSE CODE AND CONTROL BLOCKS FOR ANSI.SYS

;****************** START OF SPECIFICATIONS **************************
;
;  MODULE NAME: PARSER.ASM
;
;  DESCRIPTIVE NAME: PARSES THE DEVICE= STATEMENT IN CONFIG.SYS FOR
;		     ANSI.SYS
;
;  FUNCTION: THE COMMAND LINE PASSED TO ANSI.SYS IN THE CONFIG.SYS
;	     STATEMENT IS PARSED TO CHECK FOR THE /X SWITCH. A FLAG
;	     IS CLEARED IF NOT FOUND.
;
;  ENTRY POINT: PARSE_PARM
;
;  INPUT: DS:SI POINTS TO EVERYTHING AFTER DEVICE=
;
;  AT EXIT:
;     NORMAL: SWITCH FLAGS WILL BE SET IF /X or /L IS FOUND
;
;     ERROR: CARRY SET
;
;  INTERNAL REFERENCES:
;
;     ROUTINES: SYSLOADMSG - MESSAGE RETRIEVER LOADING CODE
;		SYSDISPMSG - MESSAGE RETRIEVER DISPLAYING CODE
;		PARM_ERROR - DISPLAYS ERROR MESSAGE
;		SYSPARSE - PARSING CODE
;
;     DATA AREAS: PARMS - PARSE CONTROL BLOCK FOR SYSPARSE
;
;  EXTERNAL REFERENCES:
;
;     ROUTINES: N/A
;
;     DATA AREAS: SWITCH - BYTE FLAG FOR EXISTENCE OF SWITCH PARAMETER
;
;  NOTES:
;
;      Label: "DOS ANSI.SYS Device Driver"
;	      "Version 4.00 (C) Copyright 1988 Microsoft"
;	      "Licensed Material - Program Property of Microsoft"
;
;****************** END OF SPECIFICATIONS ****************************
;******************************************************************************


INCLUDE     ANSI.INC	    ; ANSI equates and structures
.XLIST
INCLUDE     STRUC.INC	    ; Structured macros

INCLUDE     SYSMSG.INC	    ; Message retriever code
MSG_UTILNAME <ANSI>	    ; Let message retriever know its ANSI.SYS
.LIST

PUBLIC	    PARSE_PARM	     ; near procedure for parsing DEVICE= statement

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Set assemble switches for parse code that is not required!!
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

DateSW	      EQU     0
TimeSW	      EQU     0
CmpxSW	      EQU     0
DrvSW	      EQU     0
QusSW	      EQU     0
NumSW	      EQU     0
KeySW	      EQU     0
Val1SW	      EQU     0
Val2SW	      EQU     0
Val3SW	      EQU     0


CODE	      SEGMENT  PUBLIC BYTE
	      ASSUME CS:CODE

.XLIST
MSG_SERVICES <MSGDATA>
MSG_SERVICES <DISPLAYmsg,LOADmsg,CHARmsg>
MSG_SERVICES <ANSI.CL1>
MSG_SERVICES <ANSI.CL2>
MSG_SERVICES <ANSI.CLA>

INCLUDE     PARSE.ASM	    ; Parsing code
.LIST


EXTRN	    SWITCH_X:BYTE	 ; /X switch flag
extrn	    Switch_L:Byte	 ;AN002; /L switch flag
extrn	    Switch_K:Byte	 ;AN003; /K switch

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PARM control blocks for ANSI
; Parsing DEVICE= statment from CONFIG.SYS
;
; DEVICE=[d:][path]ANSI.SYS [/X]
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
PARMS	       LABEL WORD
	       DW	PARMSX
	       DB	0		   ; no extra delimeters or EOLs.
PARMSX	       LABEL BYTE
	       DB	1,1		   ;AN001; 1 valid positional operand
	       DW	FILENAME	   ;AN001; filename
	       DB	1		   ;AN002; 1 switche definition in the following
	       DW	Switches
	       DB	0		   ;AN001; no keywords
FILENAME       LABEL WORD
	       DW	0200H		   ; file spec
	       DW	0001H		   ; cap by file table
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; no value checking done
	       DB	0		   ; no switch/keyword synonyms
Switches       LABEL WORD
	       DW	0		   ; switch with no value
	       DW	0		   ; no functions
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; no value checking done
	       DB	3		   ;AN002;AN003; 3 switch synonym
X_SWITCH       DB	"/X",0             ;AN002; /X name
L_SWITCH       DB	"/L",0             ;AN002; /L
K_SWITCH       DB	"/K",0             ;AN003; /K

NOVALS	       LABEL BYTE
	       DB	0		   ; no value checking done

RESULT_BUF     LABEL BYTE
	       DB	?		   ; type returned (number, string, etc.)
	       DB	?		   ; matched item tag (if applicable)
SYNONYM_PTR    DW	0		   ; synonym ptr (if applicable)
	       DD	?		   ; value
SUBLIST        LABEL DWORD		   ; list for substitution
	       DB	SUB_SIZE
	       DB	0
	       DD	?
	       DB	1
	       DB	LEFT_ASCIIZ
	       DB	UNLIMITED
	       DB	1
	       DB	" "

Old_SI		dw	?
Saved_Chr	db	0
Continue_Flag	db	ON
Parse_Err_Flag	db	OFF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PARSE_PARM
;
; FUNCTION:
; THIS PROCEDURE PARSES THE DEVICE= PARAMETERS FROM THE INIT REQUEST
; BLOCK. ERROR MESSAGES ARE DISPLAYED ACCORDINGLY.
;
; AT ENTRY: DS:SI POINTS TO EVERYTHING AFTER THE DEVICE= STATEMENT
;
; AT EXIT:
;    NORMAL: CARRY CLEAR - SWITCH FLAG BYTE SET TO 1 IF /X FOUND
;
;    ERROR: CARRY SET
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARSE_PARM    PROC     NEAR
	      CALL     SYSLOADMSG		; load message
	      .IF C NEAR
		CALL	 SYSDISPMSG		; display error message
		STC				; ensure carry still set
	      .ELSE NEAR
		PUSH	 CS			; establish ES ..
		POP	 ES			; addressability to data
		LEA	 DI,PARMS		; point to PARMS control block
		XOR	 CX,CX			; clear both CX and DX for
		XOR	 DX,DX			;  SYSPARSE
		CALL	 SYSPARSE		; move pointer past file spec
		mov	 Switch_L, OFF
		mov	 Switch_X, OFF
		.WHILE <Continue_Flag EQ ON>
		     mov Old_SI, SI		;AN001;to be use by PARM_ERROR
		     call SysParse
		     .IF <AX EQ RC_EOL>
			mov Continue_Flag, OFF
		     .ELSE
			.IF <AX NE RC_NO_ERROR>
			   mov Continue_Flag, OFF
			   mov Switch_X, OFF
			   mov Switch_L, OFF
			   mov Switch_K, OFF
			   call Parm_Error
			   mov Parse_Err_Flag,ON
			.ELSE
			   .IF <Synonym_ptr EQ <offset X_SWITCH>>
				mov	Switch_X, ON
			   .ELSE
			       .IF <Synonym_ptr EQ <offset L_SWITCH>>
				    mov     Switch_L, ON
			       .ELSE			 ;AN003;Must be /K option.
				    mov     Switch_K, ON ;AN003;/K entered.
			       .ENDIF
			   .ENDIF
			    clc
			.ENDIF
		     .ENDIF
		.ENDWHILE
		.IF <Parse_Err_Flag EQ ON>
		     stc
		.ELSE
		     clc
		.ENDIF
	      .ENDIF

;		 mov	  cs:Old_SI, SI 	 ;AN001; Save pointer to parm
;		 CALL	  SYSPARSE		 ; look for /X switch
;		 .IF <AX EQ RC_EOL>		 ; if EOL then..
;		    MOV     ES:SWITCH_X,0	 ;  no switch...clear flag
;		    CLC 			 ;  clear carry
;		 .ELSE				 ; else..
;		    .IF <AX GT RC_NO_ERROR>	 ;AN001;If any error
;			call parm_error 	 ;AN001; the show the error msg
;			stc
;		    .ELSE			 ;  else..leave flag set..
;			mov   cs:Old_SI, SI
;		       CALL    SYSPARSE 	 ; check for further parms
;		       .IF <AX NE RC_EOL>	 ; if other parms then...
;			  CALL	 PARM_ERROR	 ; display 'Invalid parameter' message
;			  STC			 ;  error!
;		       .ELSE			 ; no other parms so..
;			  CLC			 ;  clear carry
;		       .ENDIF			 ;
;		    .ENDIF			 ;
;		 .ENDIF 			 ;
;	       .ENDIF				 ;

	      RET
PARSE_PARM    ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PARM_ERROR
;
; FUNCTION:
; LOADS AND DISPLAYS "Invalid parameter" MESSAGE
;
; AT ENTRY:
;   DS:Old_SI -> parms that is invalid
;
; AT EXIT:
;    NORMAL: ERROR MESSAGE DISPLAYED
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARM_ERROR    PROC   NEAR
	      PUSH   CX
	      PUSH   SI
	      PUSH   ES 		;
	      PUSH   DS 		;

;	       PUSH   CS		 ;
;	       POP    DS		 ; establish addressability
;	       MOV    BX,DX		 ;
;	       LES    DX,[BX].RES_PTR	 ; find offending parameter
	       push   ds
	       pop    es
	       mov    si, cs:Old_SI	;AN001;Now es:dx -> offending parms
	       push   si		;AN001;Save it
Get_CR:
	       cmp    byte ptr es:[si], 13 ;AN001;CR?
	       je     Got_CR
	       inc    si
	       jmp    Get_CR
Got_CR:
	       inc    si		   ;AN001; The next char.
	       mov    al, byte ptr es:[si]
	       mov    cs:Saved_Chr, al	   ;AN001; Save the next char

	       mov    byte ptr es:[si], 0     ;AN001; and make it an ASCIIZ
	       mov    cs:Old_SI, si	;AN001; Set it again
	       pop    dx		;AN001; saved SI -> DX

	       push   cs
	       pop    ds		;AN001;for addressability

	      LEA    SI,SUBLIST 	; ..and place the offset..
	      MOV    [SI].SUB_PTR_O,DX	; ..in the SUBLIST..
	      MOV    [SI].SUB_PTR_S,ES	;
	      MOV    AX,INVALID_PARM	; load 'Invalid parameter' message number
	      MOV    BX,STDERR		; to standard error
	      MOV    CX,ONE		; 1 substitution
	      XOR    DL,DL		; no input
	      MOV    DH,UTILITY_MSG_CLASS ; parse error
	      CALL   SYSDISPMSG 	; display error message
	      mov    si, cs:Old_SI	;AN001;restore the original char.
	      mov    cl, cs:Saved_Chr
	      mov    byte ptr es:[si], cl

	      POP    DS
	      POP    ES
	      POP    SI
	      POP    CX
	      RET
PARM_ERROR    ENDP

include msgdcl.inc

CODE	      ENDS
	      END
