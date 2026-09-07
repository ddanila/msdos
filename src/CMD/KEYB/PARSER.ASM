PAGE	    ,132
TITLE	    PARSE CODE AND CONTROL BLOCKS FOR KEYB.COM

;****************** START OF SPECIFICATIONS **************************
;
;  MODULE NAME: PARSER.ASM
;
;  DESCRIPTIVE NAME: PARSES THE COMMAND LINE PARAMETERS FOR KEYB.COM
;
;  FUNCTION: THE COMMAND LINE IN THE PSP IS PARSED FOR PARAMETERS.
;
;  ENTRY POINT: PARSE_PARAMETERS
;
;  INPUT: BP POINTS TO PARAMETER LIST
;	  DS & ES POINT TO PSP
;
;  AT EXIT:
;     PARAMETER LIST FILLED IN AS REQUIRED.
;
;  INTERNAL REFERENCES:
;
;     ROUTINES: SYSPARSE - PARSING CODE
;
;     DATA AREAS: PARMS - PARSE CONTROL BLOCK FOR SYSPARSE
;
;  EXTERNAL REFERENCES:
;
;     ROUTINES: N/A
;
;     DATA AREAS: PARAMETER LIST BLOCK TO BE FILLED.
;
;  NOTES:
;
;  COPYRIGHT: "The KEYB.COM Keyboard Driver"
;	      "Version 4.00 (C) Copyright 1988 Microsoft"
;	      "Licensed Material - Program Property of Microsoft"
;
;****************** END OF SPECIFICATIONS ****************************

INCLUDE     KEYBDCL.INC

ID_VALID	     EQU  0
ID_INVALID	     EQU  1
NO_ID		     EQU  2

LANGUAGE_VALID	     EQU  0
LANGUAGE_INVALID     EQU  1
NO_LANGUAGE	     EQU  2

NO_IDLANG	     EQU  3

CODE_PAGE_VALID      EQU  0
CODE_PAGE_INVALID    EQU  1
NO_CODE_PAGE	     EQU  2
VALID_SYNTAX	     EQU  0
INVALID_SYNTAX	     EQU  1

COMMAND_LINE_START   EQU  81H
RC_EOL		     EQU  -1
RC_NO_ERROR	     EQU  0
RC_OP_MISSING	     EQU  2
RC_NOT_IN_SW	     EQU  3
;***CNS P4867 1st CHECK for /ID:ALPHA
RC_SW_FIRST	     EQU  9
;***CNS P4867 1st CHECK for /ID:ALPHA
ERROR_COND	     EQU  -1
NUMBER		     EQU  1
STRING		     EQU  3
FILE_SPEC	     EQU  5
MAX_ID		     EQU  999
LANG_LENGTH	     EQU  2

INVALID_SWITCH	     EQU  3
TOO_MANY	     EQU  1
INVALID_PARAM	     EQU  10
VALUE_DISALLOW	     EQU  8

.XLIST
INCLUDE     STRUC.INC	    ; Structured macros
.LIST

PUBLIC	    PARSE_PARAMETERS ;AN003;; near procedure for parsing command line
PUBLIC	    CUR_PTR ;AN003;; near procedure for parsing command line
PUBLIC	    OLD_PTR ;AN003;; near procedure for parsing command line
PUBLIC	    ERR_PART;AN003;; near procedure for parsing command line
EXTRN  BAD_ID:BYTE	       ;; WGR to match old code
EXTRN  FOURTH_PARM:BYTE        ;; WGR to match old code
EXTRN  ONE_PARMID:BYTE	       ;; WGR to match old code
EXTRN  FTH_PARMID:BYTE	       ;; WGR to match old code
EXTRN  ALPHA:BYTE	       ;; WGR to match old code

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
KeySW	      EQU     0
Val1SW	      EQU     0
Val2SW	      EQU     0
Val3SW	      EQU     0


CODE	      SEGMENT  PUBLIC 'CODE' BYTE
	      ASSUME CS:CODE,DS:CODE

.XLIST
INCLUDE     PARSE.ASM	    ; Parsing code
.LIST


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; PARM control blocks for KEYB
; Parsing command line as follows:
;
; KEYB [lang],[cp],[[d:][path]KEYBOARD.SYS][/ID:id]
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARMS	       LABEL WORD
	       DW	PARMSX
	       DB	0		   ;AN000;; no extra delimeters or EOLs.

PARMSX	       LABEL BYTE
	       DB	0,3		   ;AN000;; min,max positional operands
	       DW	LANG		   ;AN000;; pointer to control block
	       DW	CP		   ;AN000;; pointer to control block
	       DW	FILE_NAME	   ;AN000;; pointer to control block
	       DB	1		   ;AN000;; 1 switch
	       DW	ID_VALUE	   ;AN000;; pointer to control block
	       DB	0		   ;AN000;; no keywords

LANG	       LABEL WORD
	       DW	0A001H		   ;AN000;; sstring or numeric value (optional)
	       DW	0002H		   ;AN000;; cap result by char table (sstring)
	       DW	RESULT_BUF	   ;AN000;; result
	       DW	NOVALS		   ;AN000;; no value checking done
	       DB	0		   ;AN000;; no keyword/switch synonyms

CP	       LABEL WORD
	       DW	8001H		   ;AN000;; numeric
	       DW	0		   ;AN000;; no functions
	       DW	RESULT_BUF	   ;AN000;; result
	       DW	NOVALS		   ;AN000;; no value checking done
	       DB	0		   ;AN000;; no keyword/switch synonyms

FILE_NAME      LABEL WORD
	       DW	0201H		   ;AN000;; file spec
	       DW	0001H		   ;AN000;; cap by file table
	       DW	RESULT_BUF	   ;AN000;; result
	       DW	NOVALS		   ;AN000;; no value checking done
	       DB	0		   ;AN000;; no keyword/switch synonyms

ID_VALUE       LABEL WORD
	       DW	8010H		   ;AN000;; numeric
	       DW	0		   ;AN000;; no functions
	       DW	RESULT_BUF	   ;AN000;; result
	       DW	NOVALS		   ;AN000;; no value checking done
	       DB	1		   ;AN000;; 1 switch synonym
	       DB	"/ID",0            ;AN000;; ID switch

NOVALS	       LABEL BYTE
	       DB	0		   ;AN000;; no value checking done

RESULT_BUF     LABEL BYTE
RESULT_TYPE    DB	0		   ;AN000;; type returned (number, string, etc.)
	       DB	?		   ;AN000;; matched item tag (if applicable)
RESULT_SYN_PTR DW	?		   ;AN000;; synonym ptr (if applicable)
RESULT_VAL     DD	?		   ;AN000;; value

LOOP_COUNT     DB	0		   ;AN000;; keeps track of parameter position
;***CNS
CUR_PTR        DW	0		   ;AN003;; keeps track of parameter position
OLD_PTR        DW	0		   ;AN003;; keeps track of parameter position
ERR_PART       DW	0		   ;AN003;; keeps track of parameter position
;***CNS
					   ;AN000;; ..and reports an error condition
TEMP_FILE_NAME DB	128 DUP(0)	   ;AN000;; place for file name

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PARSE_PARAMETERS
;
; FUNCTION:
; THIS PROCEDURE PARSES THE COMMAND LINE PARAMETERS IN THE PSP FOR
; KEYB.COM. THE PARAMETER LIST BLOCK IS FILLED IN ACCORDINGLY.
;
; AT ENTRY: AS ABOVE.
;
; AT EXIT:
;    AS ABOVE.
;
; AUTHOR: WGR
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARSE_PARAMETERS       PROC	NEAR
      XOR    AX,AX				 ;AN000;; setup default parameters.
      MOV    [BP].RET_CODE_1,NO_IDLANG		 ;AN000;;
      MOV    [BP].RET_CODE_2,NO_CODE_PAGE	 ;AN000;;
      MOV    [BP].RET_CODE_3,VALID_SYNTAX	 ;AN000;;
      MOV    [BP].RET_CODE_4,NO_ID		 ;AN000;;
      MOV    [BP].PATH_LENGTH,AX		 ;AN000;;
      LEA    DI,PARMS				 ;AN000;; setup parse blocks
      MOV    SI,COMMAND_LINE_START		 ;AN000;;
;***CNS

	  PUSH AX				 ;AN003;Save environment
	  MOV AX,CUR_PTR			 ;AN003;Set advancing ptr to end of argument
	  MOV OLD_PTR,AX			 ;AN003;after saving the beginning the string
	  MOV CUR_PTR,SI
	  POP AX				 ;AN003;Restore the environment

;***CNS
      XOR    CX,CX				 ;AN000;;
      XOR    DX,DX				 ;AN000;;
      CALL   SYSPARSE				 ;AN000;;
      .WHILE <AX NE RC_EOL> near AND		 ;AN000;; while not end of line and..
      .WHILE <LOOP_COUNT NE ERROR_COND> near	 ;AN000;; parameters valid do.
	.IF <AX EQ RC_NOT_IN_SW> near OR	 ;AN000;; invalid switch?
	.IF <AX EQ RC_SW_FIRST>  near		;AN000;; invalid switch?
	  MOV	 [BP].RET_CODE_3,INVALID_SYNTAX  ;AN000;; set invalid syntax flag.
	  MOV	 LOOP_COUNT,ERROR_COND		 ;AN000;; set error flag to exit parse.
;***CNS
	  MOV	ERR_PART,INVALID_SWITCH
	  PUSH AX				 ;AN003;Save environment
	  MOV AX,CUR_PTR			 ;AN003;Set advancing ptr to end of argument
	  MOV OLD_PTR,AX			 ;AN003;after saving the beginning the string
	  MOV CUR_PTR,SI
	  POP AX				 ;AN003;Restore the environment

;***CNS
	.ELSE near					 ;AN000;;
	  .IF <RESULT_SYN_PTR NE 0>		 ;AN000;; was the switch found?
	    MOV    AX,WORD PTR RESULT_VAL+2	 ;AN000;; is it valid?
	    OR	   AX,AX			 ;AN000;;
	    .IF NZ OR				 ;AN000;;
	    MOV    AX,WORD PTR RESULT_VAL	 ;AN000;;
	    .IF <AX A MAX_ID>			 ;AN000;;
	      MOV    [BP].RET_CODE_1,ID_INVALID  ;AN000;; no...invalid id.
	      MOV    [BP].RET_CODE_3,INVALID_SYNTAX ;AN000;; syntax error.
	      MOV    LOOP_COUNT,ERROR_COND	 ;AN000;; set flag to exit parse
	      mov    bad_id,1			 ;AN000;;
;***CNS

	  PUSH AX				 ;AN003;Save environment
	  MOV AX,CUR_PTR			 ;AN003;Set advancing ptr to end of argument
	  MOV OLD_PTR,AX			 ;AN003;after saving the beginning the string
	  MOV CUR_PTR,SI
	  POP AX				 ;AN003;Restore the environment

;***CNS
	    .ELSE				 ;AN000;;
	      MOV    [BP].RET_CODE_4,ID_VALID	 ;AN000;; yes...set return code 4.
	      MOV    [BP].ID_PARM,AX		 ;AN000;;
	      mov    fourth_parm,1		 ;AN000;;
	      mov    fth_parmid,1		 ;AN000;;
	    .ENDIF				 ;AN000;;
	  .ELSE 				 ;AN000;;
	    INC    LOOP_COUNT			 ;AN000;; positional encountered...
	    .SELECT				 ;AN000;;
	    .WHEN <LOOP_COUNT EQ 1>		 ;AN000;; check for language
	      CALL   PROCESS_1ST_PARM		 ;AN000;;

;***CNS

	  PUSH AX				 ;AN003;Save environment
	  MOV AX,CUR_PTR			 ;AN003;Set advancing ptr to end of argument
	  MOV OLD_PTR,AX			 ;AN003;after saving the beginning the string
	  MOV CUR_PTR,SI
	  POP AX				 ;AN003;Restore the environment
;***CNS


	    .WHEN <LOOP_COUNT EQ 2>		 ;AN000;; check for code page
	      CALL   PROCESS_2ND_PARM		 ;AN000;;
;***CNS

	  PUSH AX				 ;AN003;Save environment
	  MOV AX,CUR_PTR			 ;AN003;Set advancing ptr to end of argument
	  MOV OLD_PTR,AX			 ;AN003;after saving the beginning the string
	  MOV CUR_PTR,SI
	  POP AX				 ;AN003;Restore the environment
;***CNS
	    .WHEN <LOOP_COUNT EQ 3>		 ;AN000;; check for file name
	      CALL   PROCESS_3RD_PARM		 ;AN000;;
;***CNS

	  PUSH AX				 ;AN003;Save environment
	  MOV AX,CUR_PTR			 ;AN003;Set advancing ptr to end of argument
	  MOV OLD_PTR,AX			 ;AN003;after saving the beginning the string
	  MOV CUR_PTR,SI
	  POP AX				 ;AN003;Restore the environment
;***CNS
	    .OTHERWISE				 ;AN000;;
	      MOV    [BP].RET_CODE_3,INVALID_SYNTAX ;AN000;; too many parms
;***CNS

	  PUSH AX				 ;AN003;Save environment
	  MOV AX,CUR_PTR			 ;AN003;Set advancing ptr to end of argument
	  MOV OLD_PTR,AX			 ;AN003;after saving the beginning the string
	  MOV CUR_PTR,SI
	  POP AX				 ;AN003;Restore the environment
;***CNS
	  MOV	ERR_PART,TOO_MANY
	      MOV    LOOP_COUNT,ERROR_COND	 ;AN000;; set error flag to exit parse.
	    .ENDSELECT				 ;AN000;;
	  .ENDIF				 ;AN000;;
	  MOV	 RESULT_TYPE,0			 ;AN000;; reset result block.
	  CALL	 SYSPARSE			 ;AN000;; parse next parameter.
	.ENDIF					 ;AN000;;
      .ENDWHILE 				 ;AN000;;
      .IF <[BP].RET_CODE_4 EQ ID_VALID> AND	 ;AN000;; ensure that if the switch
      .IF <[BP].RET_CODE_1 NE LANGUAGE_VALID>	 ;AN000;; was used..that a valid keyboard
	MOV	[BP].RET_CODE_3,INVALID_SYNTAX	 ;AN000;; code was used..
;***CNS

	  PUSH AX				 ;AN003;Save environment
	  MOV AX,CUR_PTR			 ;AN003;Set advancing ptr to end of argument
	  MOV OLD_PTR,AX			 ;AN003;after saving the beginning the string
	  MOV CUR_PTR,SI
	  POP AX				 ;AN003;Restore the environment
	  MOV	ERR_PART,VALUE_DISALLOW
;***CNS
      .ENDIF					 ;AN000;;
      RET					 ;AN000;;
PARSE_PARAMETERS       ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PROCESS_1ST_PARM
;
; FUNCTION:
; THIS PROCEDURE PROCESSES THE FIRST POSITIONAL PARAMETER. THIS SHOULD
; BE THE LANGUAGE ID OR THE KEYBOARD ID.
;
; AT ENTRY: PARSE RESULT BLOCK CONTAINS VALUES IF AX HAS NO ERROR.
;
; AT EXIT:
;    PARAMETER CONTROL BLOCK UPDATED FOR LANGUAGE ID.
;
; AUTHOR: WGR
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PROCESS_1ST_PARM       PROC    NEAR
       .IF <AX GT RC_NO_ERROR>			 ;AN000;; error on parse?
	 MOV	[BP].RET_CODE_1,LANGUAGE_INVALID ;AN000;; yes...set invalid language
	 MOV	[BP].RET_CODE_3,INVALID_SYNTAX	 ;AN000;; and syntax error..
	 MOV	LOOP_COUNT,ERROR_COND		 ;AN000;; set flag to exit parse.
      MOV    ERR_PART,AX			 ;AN003;;
       .ELSE near				 ;AN000;;

	 .IF <RESULT_TYPE EQ NUMBER>		 ;AN000;; was this a number (id)?
	   MOV	  AX,WORD PTR RESULT_VAL+2	 ;AN000;; yes...check to see if
	   OR	  AX,AX 			 ;AN000;; within range.
	   .IF NZ OR				 ;AN000;;
	   MOV	  AX,WORD PTR RESULT_VAL	 ;AN000;;
	   .IF <AX A MAX_ID>			 ;AN000;;
	     MOV    [BP].RET_CODE_1,ID_INVALID	 ;AN000;; no...invalid id.
	     MOV    [BP].RET_CODE_3,INVALID_SYNTAX ;AN000;; syntax error.
	     MOV    LOOP_COUNT,ERROR_COND	 ;AN000;; set flag to exit parse
	     mov    bad_id,1			 ;AN000;;
	   .ELSE				 ;AN000;;
	     MOV    [BP].RET_CODE_1,ID_VALID	 ;AN000;; valid id...set
	     MOV    [BP].RET_CODE_4,ID_VALID	 ;AN000;; valid id...set
	     MOV    [BP].ID_PARM,AX		 ;AN000;; and value moved into block
	     MOV    LOOP_COUNT,4		 ;AN000;; there should be no more parms
	     mov    one_parmid,1		 ;AN000;;
	   .ENDIF				 ;AN000;;
	 .ELSEIF <RESULT_TYPE EQ STRING>	 ;AN000;; must be a string then..
	   PUSH   SI				 ;AN000;;
	   PUSH   DI				 ;AN000;;
	   PUSH   CX				 ;AN000;;
	   PUSH   DS				 ;AN000;;
	   LDS	  SI,RESULT_VAL 		 ;AN000;; get ptr to string
	   MOV	  DI,BP 			 ;AN000;;
	   ADD	  DI,LANGUAGE_PARM		 ;AN000;; point to block for copy.
	   MOV	  CX,LANG_LENGTH		 ;AN000;; maximum length = 2
	   LODSB				 ;AN000;; load AL with 1st char..
	   .WHILE <CX NE 0> AND 		 ;AN000;; do twice....unless
	   .WHILE <AL NE 0>			 ;AN000;; there is only 1 character.
	     STOSB				 ;AN000;; store
	     DEC    CX				 ;AN000;; dec count
	     LODSB				 ;AN000;; load
	   .ENDWHILE				 ;AN000;;
	   .IF <CX NE 0> OR			 ;AN000;; if there was less than 2 or..
	   .IF <AL NE 0>			 ;AN000;; greater than 2 characters then..
	     MOV    [BP].RET_CODE_1,LANGUAGE_INVALID ;AN000;; invalid.
	     MOV    [BP].RET_CODE_3,INVALID_SYNTAX ;AN000;; syntax error
	  MOV	ERR_PART,INVALID_PARAM
	     MOV    LOOP_COUNT,ERROR_COND	 ;AN000;; set flag to exit parse.
	   .ELSE				 ;AN000;;
	     MOV    [BP].RET_CODE_1,LANGUAGE_VALID ;AN000;; valid language has been copied
	     MOV    ALPHA,1			 ;AN000;; language found
	   .ENDIF				 ;AN000;;
	   POP	  DS				 ;AN000;;
	   POP	  CX				 ;AN000;;
	   POP	  DI				 ;AN000;;
	   POP	  SI				 ;AN000;;
	 .ELSE					 ;AN000;; ommited parameter...
	   MOV	  [BP].RET_CODE_3,INVALID_SYNTAX ;AN000;; invalid since further parameters.
	 .ENDIF 				 ;AN000;;
       .ENDIF					 ;AN000;;
       RET					 ;AN000;;
PROCESS_1ST_PARM       ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PROCESS_2ND_PARM
;
; FUNCTION:
; THIS PROCEDURE PROCESSES THE 2ND POSITIONAL PARAMETER. THIS SHOULD
; BE THE CODE PAGE, IF REQUESTED.
;
; AT ENTRY: PARSE RESULT BLOCK CONTAINS VALUES IF AX HAS NO ERROR.
;
; AT EXIT:
;    PARAMETER CONTROL BLOCK UPDATED FOR CODE PAGE.
;
; AUTHOR: WGR
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PROCESS_2ND_PARM       PROC    NEAR
       .IF <AX GT RC_NO_ERROR>			   ;AN000;; if parse error..
	 MOV	[BP].RET_CODE_2,CODE_PAGE_INVALID  ;AN000;; mark invalid..
	 MOV	[BP].RET_CODE_3,INVALID_SYNTAX	   ;AN000;; syntax error
	 MOV	LOOP_COUNT,ERROR_COND		   ;AN000;; set flag to exit parse
      MOV    ERR_PART,AX			 ;AN003;;
       .ELSE					   ;AN000;;
	 .IF <RESULT_TYPE EQ NUMBER>		   ;AN000;; was parameter specified?
	   MOV	  AX,WORD PTR RESULT_VAL+2	   ;AN000;; yes..if code page not..
	   OR	  AX,AX 			   ;AN000;;
	   .IF NZ OR				   ;AN000;;
	   MOV	  AX,WORD PTR RESULT_VAL	   ;AN000;; valid..then
	   .IF <AX A MAX_ID>			   ;AN000;;
	     MOV    [BP].RET_CODE_2,CODE_PAGE_INVALID ;AN000;; mark invalid..
	     MOV    [BP].RET_CODE_3,INVALID_SYNTAX ;AN000;; syntax error
	     MOV    LOOP_COUNT,ERROR_COND	   ;AN000;; set flag to exit parse
	   .ELSE				   ;AN000;;
	     MOV    [BP].RET_CODE_2,CODE_PAGE_VALID;AN000;; else...valid code page
	     MOV    [BP].CODE_PAGE_PARM,AX	   ;AN000;; move into parm
	   .ENDIF				   ;AN000;;
	 .ELSE					   ;AN000;;
	   MOV	    [BP].RET_CODE_2,NO_CODE_PAGE   ;AN000;; mark as not specified.
	 .ENDIF 				   ;AN000;;
       .ENDIF					   ;AN000;;
       RET					   ;AN000;;
PROCESS_2ND_PARM      ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PROCESS_3RD_PARM
;
; FUNCTION:
; THIS PROCEDURE PROCESSES THE 3RD POSITIONAL PARAMETER. THIS SHOULD
; BE THE KEYBOARD DEFINITION FILE PATH, IF SPECIFIED.
;
; AT ENTRY: PARSE RESULT BLOCK CONTAINS VALUES IF AX HAS NO ERROR.
;
; AT EXIT:
;    PARAMETER CONTROL BLOCK UPDATED FOR FILE NAME.
;
; AUTHOR: WGR
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PROCESS_3RD_PARM       PROC    NEAR
       .IF <AX GT RC_NO_ERROR>		     ;AN000;; if parse error then..
	 MOV	[BP].RET_CODE_3,INVALID_SYNTAX ;AN000;; syntax error.
	 MOV	LOOP_COUNT,ERROR_COND	     ;AN000;; set flag to exit parse
      MOV    ERR_PART,AX			 ;AN003;;
       .ELSE				     ;AN000;;
	 .IF <RESULT_TYPE EQ FILE_SPEC>      ;AN000;;
	   PUSH   DS			     ;AN000;;
	   PUSH   SI			     ;AN000;;
	   PUSH   DI			     ;AN000;;
	   PUSH   CX			     ;AN000;;
	   LDS	  SI,RESULT_VAL 	     ;AN000;; load offset of file name
	   LEA	  DI,TEMP_FILE_NAME	     ;AN000;;
	   MOV	  [BP].PATH_OFFSET,DI	     ;AN000;; copy to parameter block
	   XOR	  CX,CX 		     ;AN000;;
	   LODSB			     ;AN000;; count the length of the path.
	   .WHILE <AL NE 0>		     ;AN000;;
	     STOSB			     ;AN000;;
	     LODSB			     ;AN000;;
	     INC    CX			     ;AN000;;
	   .ENDWHILE			     ;AN000;;
	   MOV	  [BP].PATH_LENGTH,CX	     ;AN000;; copy to parameter block
	   POP	  CX			     ;AN000;;
	   POP	  DI			     ;AN000;;
	   POP	  SI			     ;AN000;;
	   POP	  DS			     ;AN000;;
	 .ENDIF 			     ;AN000;;
       .ENDIF				     ;AN000;;
       RET				     ;AN000;;
PROCESS_3RD_PARM       ENDP
CODE	      ENDS
	      END
