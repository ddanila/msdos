PAGE	    ,132
TITLE	    PARSE CODE AND CONTROL BLOCKS FOR DISPLAY.SYS

;****************** START OF SPECIFICATIONS **************************
;
;  MODULE NAME: PARSER.ASM
;
;  DESCRIPTIVE NAME: PARSES THE DEVICE= STATEMENT IN CONFIG.SYS FOR
;		     DISPLAY.SYS
;
;  FUNCTION: THE COMMAND LINE PASSED TO DISPLAY.SYS IN THE CONFIG.SYS
;	     STATEMENT IS PARSED TO CHECK FOR CORRECT SYNTAX. A TABLE
;	     IS SETUP CONTAINING THE VALUES FOUND.
;
;  ENTRY POINT: PARSER
;
;  INPUT: ES:DI POINTS TO REQUEST HEADER
;
;  AT EXIT:
;     NORMAL: TABLE SET UP WITH VALUES FOUND.
;
;     ERROR: 0 RETURNED IN FIRST WORD OF TABLE.
;
;  INTERNAL REFERENCES:
;
;     ROUTINES: SYSPARSE - PARSING CODE
;
;     DATA AREAS: PARMSx - PARSE CONTROL BLOCK FOR SYSPARSE
;		  TABLE - TO CONTAIN VALUES FOUND IN DEVICE= LINE
;
;  EXTERNAL REFERENCES:
;
;     ROUTINES: N/A
;
;     DATA AREAS: N/A
;
;  NOTES:
;
;      Label: "The DOS DISPLAY.SYS Device Driver"
;	      "Version 4.00 (C) Copyright 1988 Microsoft
;	      "Licensed Material - Program Property of Microsoft"
;
;****************** END OF SPECIFICATIONS ****************************
;
; The following is the table structure of the parser.	All fields are
; two bytes field (accept for the device and id name)
;
; TABLE HEADER :
; ÍÍÍÍÍÍÍÍÍÍÍÍÍÍ
;    ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;    ³ N = Number of devices.	  ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´
;    ³	 Device  # 1  offset	 ÄÅÄÄÄÄÄÄÄÄÄÄÄÄÄÄ>ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´		  ³			     ³
;    ³	 Device  # 2  offset	  ³		  ³	 Table_1  (a)	     ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´		  ³			     ³
;    ³	 Device  # 3  offset	  ³		  ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´
;    ³	 Device  # 4  offset	  ³
;    ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;
;
; N = 1,2,3 or 4.  A two bytes number indicating the number of device specified.
; DEVICE # N OFFSET : a two bytes offset address to table_1. (ie. Device #1 offset
; is a pointer to table_1 (a). Device #2 offset is a pointer to table_1
; (b)...etc.).	 If an error was detected in the command N is set to zero.
;
;
;
; TABLE_1 :
; ÍÍÍÍÍÍÍÍÍ
;
;    ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿	      ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;    ³ N = Number of Offsets.	  ³	      ³ 			 ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´    ÚÄÄÄÄÄÄ³      Table_2  (a)	 ³
;    ³	 Device Name  offset	 ÄÅÄÄÄÄÙ      ³ 			 ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´	      ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;    ³	 Device  Id   offset	 ÄÅÄÄÄÄÄÄ¿
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´	 ³    ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;    ³	 Device  HWCP offset	 ÄÅÄÄÄÄ¿ ³    ³ 			 ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´    ³ ÀÄÄÄÄ³      Table_3  (a)	 ³
;    ³	 Device  Desg offset	 ÄÅÄÄ¿ ³      ³ 			 ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´  ³ ³      ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;    ³	    "Reserved"            ³  ³ ³
;    ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ  ³ ³      ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;				     ³ ³      ³ 			 ³
;				     ³ ÀÄÄÄÄÄÄ³      Table_4  (a)	 ³
;				     ³	      ³ 			 ³
;				     ³	      ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;				     ³	      ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;				     ³	      ³ 			 ³
;				     ÀÄÄÄÄÄÄÄÄ³      Table_5  (a)	 ³
;					      ³ 			 ³
;					      ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;
;
;  N=Length of table_1, or the number of offsets contained in table_1.
;  The offsets are pointers (two bytes) to the parameters value of the device.
;  "Reserved" : a two byte memory reserved for future use of the "PARMS" option.
;
;
; TABLE_2 :
; ÍÍÍÍÍÍÍÍÍ
;
;    ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;    ³ N = Length of devices name ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´
;    ³	  Device   name 	  ³
;    ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;
; N = Length of device name.  Device length is always 8 byte long.
; Device Name : the name of the device (eg. LPT1, CON, PRN).  The name
; is paded with spaces to make up the rest of the 8 characters.
;
;
;
; TABLE_3 :
; ÍÍÍÍÍÍÍÍÍ
;
;    ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;    ³ N = Length of Id name.	  ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´
;    ³	   Id	Name		  ³
;    ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;
; N = Length of id name.  Id name length is always 8 byte long.
; Id Name : the name of the id (eg. EGA, VGA).	The name
; is paded with spaces to make up the rest of the 8 character.
;
;
;
; TABLE_4 :
; ÍÍÍÍÍÍÍÍÍ
;
;    ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;    ³ N = Length of table.	  ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´
;    ³	  HWCP	#  1		  ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´
;    ³	  HWCP	#  2		  ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´
;    ³		.		  ³
;    ³		.		  ³
;    ³		.		  ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´
;    ³	  HWCP	#  10		  ³
;    ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;
;
; N = Length of table in words. Or the number of HWCP's.
; HWCP # N : a hardware code page number converted to binary.  The maximum
; number of pages allowed is 10.
;
;
;
; TABLE_5 :
; ÍÍÍÍÍÍÍÍÍ
;
;    ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;    ³ N = Length of table.	  ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´
;    ³	  Designate		  ³
;    ÃÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ´
;    ³	  Font			  ³
;    ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;
; N = Lenght of table.	0 - nothing was specified
;			1 - Only a designate was specified.
;			2 - Designate and font were given.  If the Desg field
;			    was left empty in the DEVICE command then the
;			    Designate field is filled with 0FFFFH.
; Designate, Font : Are the Desg. and Font binary numbers.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

INCLUDE     DEF-EQU.INC      ; structures and equates

.XLIST
INCLUDE     STRUC.INC	     ; Structured macros
.LIST

PUBLIC	    PARSER	     ; near procedure for parsing DEVICE= statement
PUBLIC	    TABLE	     ; table for variable storage used by INIT module.
PUBLIC	    GET_DEVICE_ID    ; procedure to determine device adapter

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Set assemble switches for parse code
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

DateSW	      EQU     0
DrvSW	      EQU     0
SwSW	      EQU     0
Val1SW	      EQU     0
Val2SW	      EQU     0
Val3SW	      EQU     0


CODE	      SEGMENT  PUBLIC BYTE 'CODE'
	      ASSUME CS:CODE


.XLIST
INCLUDE     PARSE.ASM	    ; Parsing code
.LIST


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PARM control block for DISPLAY.SYS - DEVICE= command statement.
; Command line looks like:
;
;   DEVICE=[d:][path]DISPLAY.SYS CON[:]=(type[,[hwcp][,n]])
;     or
;   DEVICE=[d:][path]DISPLAY.SYS CON[:]=(type[,[hwcp][,(n,m)]])
;     or, for compatibility with DOS 3.3; PTM P1895
;   DEVICE=[d:][path]DISPLAY.SYS CON[:]=(type[,[(hwcp)][,n|(n,m)]])
;
; The command line will be parsed from left to right, taking care of the
; nesting of complex lists as they occur.
;
; The first level of control blocks is shown below.
; Complex list control blocks follow.
; Null VALUE LIST and RESULT BUFFER are placed after all other PARSE control
; blocks.
;
; d:\path\DISPLAY.SYS CON=(complex list)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARMS1	       LABEL WORD
	       DW	PARMSX1
	       DB	0		   ; no extra delimeters or EOLs.

PARMSX1        LABEL BYTE
	       DB	1,1		   ; min,max positional operands
	       DW	D_NAME		   ; pointer to control block
	       DB	0		   ; no switches
	       DB	1		   ; 1 keywords
	       DW	DSP_LIST	   ; pointer to control block

D_NAME	       LABEL WORD
	       DW	0200H		   ; file spec
	       DW	0001H		   ; cap result by file table
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; no value checking done
	       DB	0		   ; no keyword/switch synonyms

DSP_LIST       LABEL WORD
	       DW	0400H		   ; complex list, ignore colon
	       DW	0012H		   ; cap result by char table
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; no value checking done
	       DB	2		   ; 1 keyword
	       DB	"CON=",0           ;GHG CON[:]= keyword
	       DB	"CON:=",0          ;GHG

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PARM control block for second level of nesting.
; ie. complex list from first level of nesting
;
; (type, hwcp, n or complex list)
;or,
; (type, (hwcp), n or complex list)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARMS2	       LABEL WORD
	       DW	PARMSX2
	       DB	0		   ; no extra delimeters or EOLs.

PARMSX2        LABEL BYTE
	       DB	0,3		   ; min,max positional operands
	       DW	DSP_TYPE	   ; pointer to control block
	       DW	HWCP		   ; pointer to control block
	       DW	CP_PREPS	   ; pointer to control block
	       DB	0		   ; no switches
	       DB	0		   ; no keywords

DSP_TYPE       LABEL BYTE
	       DW	2001H		   ; sstring (optional)
	       DW	0002H		   ; cap by char table
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; value list
	       DB	0		   ; no keyword/switch synonyms


HWCP	       LABEL BYTE
	       DW	8401H		   ;AN002; numeric or complex list (optional)
	       DW	0		   ; no functions
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; no value checking done
	       DB	0		   ; no keyword/switch synonyms

CP_PREPS       LABEL BYTE
	       DW	8401H		   ; numeric or complex list (optional)
	       DW	0		   ; no functions
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; value list
	       DB	0		   ; no keyword/switch synonyms


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PARM control block for third level of nesting.
; ie. complex list from second nesting level
;
; (hwcp)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARMS3_X       LABEL WORD
	       DW	PARMSX3_X
	       DB	0		   ;AN002; no extra delimeters or EOLs.

PARMSX3_X      LABEL BYTE
	       DB	1,1		   ;AN002; min,max positional operands
	       DW	PREPS		   ;AN002; pointer to control block
	       DB	0		   ;AN002; no switches
	       DB	0		   ;AN002; no keywords

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PARM control block for third level of nesting.
; ie. complex list from second nesting level
;
; (n,m)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARMS3	       LABEL WORD
	       DW	PARMSX3
	       DB	0		   ; no extra delimeters or EOLs.

PARMSX3        LABEL BYTE
	       DB	1,2		   ; min,max positional operands
	       DW	PREPS		   ; pointer to control block
	       DW	SUBFONTS	   ; pointer to control block
	       DB	0		   ; no switches
	       DB	0		   ; no keywords

PREPS	       LABEL BYTE
	       DW	8000H		   ; numeric
	       DW	0		   ; no functions
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; value list
	       DB	0		   ; no keyword/switch synonyms

SUBFONTS       LABEL BYTE
	       DW	8001H		   ; numeric (optional)
	       DW	0		   ; no functions
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; no value checking done
	       DB	0		   ; no keyword/switch synonyms

; Null VALUE LIST and RESULT BUFFER for all PARSE control blocks

NOVALS	       LABEL BYTE
	       DB	0		   ; no value checking done

RESULT_BUF     LABEL BYTE
RESULT_TYPE    DB	?		   ; type returned (number, string, etc.)
	       DB	?		   ; matched item tag (if applicable)
	       DW	?		   ; synonym ptr (if applicable)
RESULT_VAL     DD	?		   ; value

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; TABLE STRUCTURE FOR RETURNING VALUES TO THE INIT MODULE
;  (ADAPTED FROM VERSION 1.0 DISPLAY.SYS)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

TABLE	       LABEL	BYTE		   ; table header
DEVICE_NUM     DW	ONE		   ; should only be one device
TABLE2_PTR     DW	TABLE2		   ; pointer to table 2

TABLE2	       LABEL	WORD
OFFSET_NUM     DW	FOUR		   ; 4 pointer follow
TABLE3_PTR     DW	TABLE3		   ; pointer to table 3 (device name)
TABLE4_PTR     DW	TABLE4		   ; pointer to table 4 (device id)
TABLE5_PTR     DW	TABLE5		   ; pointer to table 5 (hwcp's)
TABLE6_PTR     DW	TABLE6		   ; pointer to table 6 (num desg's and fonts)

TABLE3	       LABEL	WORD		   ; device name (ie. CON)
T3_LENGTH      DW	EIGHT		   ; length
T3_NAME        DB	"CON     "         ; value

TABLE4	       LABEL	WORD		   ; device id. (eg. EGA,MONO...)
T4_LENGTH      DW	ZERO		   ; length
T4_NAME        DB	"        "         ; value

TABLE5	       LABEL	WORD		   ; hardware code pages
T5_NUM	       DW	ZERO		   ; only 1 for CON
T5_VALUE       DW	?		   ; value

TABLE6	       LABEL	WORD		   ; Designates and fonts
T6_NUM	       DW	ZERO		   ; values given (0 - 2 valid)
T6_DESG        DW	?		   ; n value
T6_FONT        DW	?		   ; m value


OK_FLAG        DB	ON		   ; FLAG INDICATING PARSE STATUS
LOOP1	       DB	ZERO
LOOP2	       DB	ZERO

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PARSER
;
; FUNCTION:
; THIS PROCEDURE PARSES THE DEVICE= PARAMETERS FROM THE INIT REQUEST
; BLOCK.
;
; AT ENTRY: ES:DI POINTS TO REQUEST HEADER
;
; AT EXIT:
;    NORMAL: TABLE SET UP WITH VALUES FOUND
;
;    ERROR: 0 LOADED IN FIRST WORD OF TABLE
;
; AUTHOR: WGR
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARSER	PROC	 NEAR
	PUSH	 ES
	PUSH	 BX
	PUSH	 DS			  ;
	PUSH	 SI			  ;
	LDS	 SI,RH.RH0_BPBA 	  ;
	PUSH	 CS			  ; establish ES ..
	POP	 ES			  ; addressability to data
	LEA	 DI,PARMS1		  ; point to PARMS control block
	XOR	 CX,CX			  ; clear both CX and DX for
	XOR	 DX,DX			  ;  SYSPARSE
	CALL	 SYSPARSE		  ; move pointer past file spec
	CALL	 SYSPARSE		  ; do first parse
	.WHILE <AX NE RC_EOL> AND	  ; EOL?...then end parse...and..
	.WHILE <OK_FLAG EQ ON>		  ; make sure that flag still ok..
	  .IF <AX NE RC_NO_ERROR>	  ; parse error?
	    MOV     OK_FLAG,OFF 	  ; yes...reset flag
	  .ELSE 			  ; no...process..
	    .SELECT			  ;
	    .WHEN <RESULT_TYPE EQ COMPLEX> ; complex string found?
	      INC    LOOP1		  ; increment count
	      .IF <LOOP1 GT ONE>	  ; more than one?
		MOV    OK_FLAG,OFF	  ; yes....we have an error
	      .ELSE			  ; no ..
		CALL   PARSE_MAIN	  ; process complex string..
	      .ENDIF			  ;
	    .OTHERWISE			  ; not a complex string so..
	      MOV    OK_FLAG,OFF	  ; we have a problem...reset flag
	    .ENDSELECT			  ;
	    CALL   SYSPARSE		  ; continue parsing..
	  .ENDIF			  ;
	.ENDWHILE			  ;
	.IF <OK_FLAG EQ OFF> OR 	  ; flag indicating error?
	.IF <LOOP1 EQ ZERO>		  ; or no parameters specified?
	  MOV	DEVICE_NUM,ZERO 	  ; yes...set device number to 0
	  STC				  ;
	.ELSE				  ;
	  CLC				  ;
	.ENDIF				  ;
	POP    SI			  ;
	POP    DS			  ;
	POP    BX			  ;
	POP    ES			  ;
	RET				  ;
PARSER	ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PARSE_MAIN
;
; FUNCTION:
; THIS PROCEDURE PARSES THE CON=(    ) COMPLEX LIST DEVICE= LINE FOUND
; IN CONFIG.SYS
;
; AT ENTRY: RESULT BUFFER CONTAINS POINTER TO COMPLEX STRING
;
; AT EXIT:
;    NORMAL: TABLE SET UP WITH VALUES FOUND
;
;    ERROR: OK_FLAG = 0
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARSE_MAIN  PROC   NEAR
	    PUSH   DI			  ; setup to parse the nested..
	    PUSH   DS			  ; complex string...but save..
	    PUSH   SI			  ; current parsing status.
	    PUSH   CX			  ;
	    XOR    CX,CX		  ;
	    LEA    DI,PARMS2		  ; next control block..
	    LDS    SI,RESULT_VAL	  ; point to stored string
	    CALL   SYSPARSE		  ;
	    .WHILE <AX NE RC_EOL> AND	  ; not EOL?   and..
	    .WHILE <OK_FLAG EQ ON>	  ; error flag still ok?
	      .IF <AX NE RC_NO_ERROR>	  ; check for parse errors
		MOV    OK_FLAG,OFF	  ; yes....reset error flag
	      .ELSE			  ; no...process
		INC    LOOP2		  ;
		.SELECT 		  ;
		.WHEN <RESULT_TYPE EQ STRING> ; simple string
		  CALL	 PARSE_STR	  ; yes...process
		.WHEN <RESULT_TYPE EQ NUMBER> ; number?..
		  CALL	 PARSE_NUM	  ; yes...process
		.WHEN <RESULT_TYPE EQ COMPLEX> ; complex string?
		  CALL	 PARSE_COMPLEX
		.OTHERWISE		  ; anything else is..
		  MOV	 OK_FLAG,OFF	  ; an error...reset flag.
		.ENDSELECT		  ;
		CALL   SYSPARSE 	  ; continue parsing
	      .ENDIF			  ;
	    .ENDWHILE			  ;
	    POP    CX			  ; restore original parse..
	    POP    SI			  ; registers.
	    POP    DS			  ;
	    POP    DI			  ;
	    RET 			  ;
PARSE_MAIN  ENDP

;
PARSE_COMPLEX	PROC
	.IF  <LOOP2 EQ TWO>	 ;AN002; Should be for HWCP
	     CALL  PARSE_COMP_X  ;AN002; for (hwcp)
	.ELSE
	     CALL   PARSE_COMP	 ; yes...process for (n,m)
	.ENDIF
	ret
PARSE_COMPLEX	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PARSE_COMP_X
;
; FUNCTION:
; THIS PROCEDURE PARSES A COMPLEX LIST FOUND WITHIN THE CON=(	)
; COMPLEX LIST for (hwcp).
;
; AT ENTRY: RESULT BUFFER CONTAINS POINTER TO COMPLEX STRING
;
; AT EXIT:
;    NORMAL: TABLE SET UP WITH VALUES FOUND
;
;    ERROR: OK_FLAG = 0
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARSE_COMP_X PROC   NEAR
	     PUSH   DI			  ;AN002; setup ro parse the nested..
	     PUSH   DS			  ;AN002; complex string..saving the..
	     PUSH   SI			  ;AN002; current parse status.
	     PUSH   CX
	     XOR    CX,CX
	     LEA    DI,PARMS3_X 	  ;AN002; next control block
	     LDS    SI,RESULT_VAL	  ;AN002; point to stored string.
	     CALL   SYSPARSE
	     .WHILE <AX NE RC_EOL> AND	  ;AN002; not EOL?...and..
	     .WHILE <OK_FLAG EQ ON>	  ;AN002; error flag still okay?
	       .IF <AX NE RC_NO_ERROR> OR ;AN002; parse error?...or..
	       .IF <RESULT_TYPE NE NUMBER> ;AN002; something other than a number..
		 MOV	OK_FLAG,OFF	  ;AN002; found?....yes..reset flag.
	       .ELSE			  ;AN002; no...process..
		 INC	T5_NUM		  ;AN002; increment counter
		 MOV	AX,WORD PTR RESULT_VAL ;AN002; get numeric value into word
		 MOV	T5_VALUE,AX	  ;AN002; yes...number of designates.
		 CALL	SYSPARSE	  ;AN002; continue parsing
	       .ENDIF
	     .ENDWHILE
	     POP    CX			  ;AN002; restore previous parse..
	     POP    SI			  ;AN002; registers.
	     POP    DS
	     POP    DI
	     RET
PARSE_COMP_X ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PARSE_COMP
;
; FUNCTION:
; THIS PROCEDURE PARSES A COMPLEX LIST FOUND WITHIN THE CON=(	)
; COMPLEX LIST for (n,m).
;
; AT ENTRY: RESULT BUFFER CONTAINS POINTER TO COMPLEX STRING
;
; AT EXIT:
;    NORMAL: TABLE SET UP WITH VALUES FOUND
;
;    ERROR: OK_FLAG = 0
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARSE_COMP   PROC   NEAR
	     PUSH   DI			  ; setup ro parse the nested..
	     PUSH   DS			  ; complex string..saving the..
	     PUSH   SI			  ; current parse status.
	     PUSH   CX			  ;
	     XOR    CX,CX		  ;
	     LEA    DI,PARMS3		  ; next control block
	     LDS    SI,RESULT_VAL	  ; point to stored string.
	     CALL   SYSPARSE		  ;
	     .WHILE <AX NE RC_EOL> AND	  ; not EOL?...and..
	     .WHILE <OK_FLAG EQ ON>	  ; error flag still okay?
	       .IF <AX NE RC_NO_ERROR> OR ; parse error?...or..
	       .IF <RESULT_TYPE NE NUMBER> ; something other than a number..
		 MOV	OK_FLAG,OFF	  ; found?....yes..reset flag.
	       .ELSE			  ; no...process..
		 INC	T6_NUM		  ; increment counter
		 MOV	AX,WORD PTR RESULT_VAL ; get numeric value into word
		 .IF <T6_NUM EQ ONE>	  ; first value found?
		   MOV	  T6_DESG,AX	  ; yes...number of designates.
		 .ELSE			  ; else..
		   MOV	  T6_FONT,AX	  ; second number...number of fonts.
		 .ENDIF 		  ;
		 CALL	SYSPARSE	  ; continue parsing
	       .ENDIF			  ;
	     .ENDWHILE			  ;
	     POP    CX			  ; restore previous parse..
	     POP    SI			  ; registers.
	     POP    DS			  ;
	     POP    DI			  ;
	     RET			  ;
PARSE_COMP   ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PARSE_STR
;
; FUNCTION:
; THIS PROCEDURE PARSES A STRING FOUND WITHIN THE CON=(   ) STATEMENT
;
; AT ENTRY: RESULT BUFFER POINTS TO ASCIIZ STRING
;
; AT EXIT:
;    NORMAL: TABLE SET UP WITH VALUES FOUND
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARSE_STR    PROC   NEAR
	     PUSH   DI			  ; get source and..
	     PUSH   DS			  ; destination registers..
	     PUSH   SI			  ; setup.
	     LDS    SI,RESULT_VAL	  ;
	     .IF <<BYTE PTR DS:[SI]> NE ZERO> ; check for null string
	       LEA    DI,T4_NAME	  ;
	       LODSB			  ; load first character.
	       .WHILE <AL NE ZERO>	  ; while not at end of ASCIIZ do..
		 STOSB			  ; store..
		 LODSB			  ; load next character..
	       .ENDWHILE		  ;
	       MOV    T4_LENGTH,EIGHT	  ; value found.
	     .ENDIF			  ;
	     POP    SI			  ; restore registers.
	     POP    DS			  ;
	     POP    DI			  ;
	     RET
PARSE_STR    ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PARSE_NUM
;
; FUNCTION:
; THIS PROCEDURE PARSES NUMBERS FOUND IN THE CON=(   ) STATEMENT
; BLOCK.
;
; AT ENTRY: RESULT BUFFER CONTAINS A DWORD NUMBER VALUE
;
; AT EXIT:
;    NORMAL: TABLE SET UP WITH VALUES FOUND
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARSE_NUM    PROC   NEAR
	     MOV    AX,WORD PTR RESULT_VAL   ; get value into word form
	     .IF <LOOP2 EQ TWO> 	     ; if this is the code page then..
		MOV   T5_VALUE,AX	     ; load that value.
		INC   T5_NUM		     ;
	     .ELSEIF <LOOP2 EQ THREE>	     ;
		MOV   T6_DESG,AX	     ; must be number of designates..
		INC   T6_NUM		     ; load and increment count
	     .ENDIF			     ;
	     RET			     ;
PARSE_NUM    ENDP


	     ASSUME CS:CODE,DS:CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: GET_DEVICE_ID
;
; FUNCTION:
; THIS PROCEDURE RETURNS THE DISPLAY DEVICE TO THE INIT ROUTINE WHEN
; A DEVICE ID IS NOT SUPPLIED.
;
; AT ENTRY: N/A
;
; AT EXIT:
;    NORMAL: DEVICE ID PLACED WITHIN THE TABLE. (EGA OR LCD)
;	     CARRY IS CLEARED.
;
;    ERROR:  DEVICE ID IS MONO OR CGA
;	     CARRY IS SET.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

FUNC_INFO	  INFO_BLOCK <>

DEVICE_N_LENGTH   EQU	EIGHT

DEVICE_TYPES	  DB	"EGA     "
		  DB	"LCD     "

NUM_DEVICE_TYPES  EQU ($-DEVICE_TYPES)/DEVICE_N_LENGTH

DEVICE_FLAG	  DB	00000000B


GET_DEVICE_ID  PROC   NEAR
	       PUSH   AX
	       PUSH   BX			  ;
	       PUSH   CX			  ; s
	       PUSH   DX			  ;  a	 r
	       PUSH   DI			  ;   v   e
	       PUSH   SI			  ;    e   g
	       PUSH   ES			  ;	    i
	       PUSH   DS			  ;	     s
	       PUSH   CS			  ;	      t
	       POP    DS			  ;	       e
	       PUSH   CS			  ;		r
	       POP    ES			  ;		 s
	       XOR    AX,AX			  ;
	       MOV    AH,FUNC_CALL		  ;
	       LEA    DI,FUNC_INFO		  ;
	       XOR    BX,BX			  ;
	       INT    10H			  ; try VGA functionality call
	       .IF <AL EQ FUNC_CALL>		  ; worked?....then
		 OR	DEVICE_FLAG,VGA_FOUND	  ; VGA found.
	       .ELSE				  ; no VGA...try EGA
		 MOV	AH,ALT_SELECT		  ;
		 MOV	BL,EGA_INFO_CALL	  ;
		 INT	10H			  ;
		 .IF <BL NE EGA_INFO_CALL>	  ; if changed then EGA present..
		   OR	  DEVICE_FLAG,EGA_FOUND   ; mark as found.
		 .ELSE				  ; no EGA...try LCD.
		   MOV	  AH,GET_SYS_ID 	  ; get system id..
		   INT	  15H			  ; yup....its a convertible..so
		   .IF <ES:[BX].MODEL_BYTE EQ LCD_MODEL> AND
		   MOV	  AH,GET_STATUS 	  ; check for LCD..
		   INT	  15H			  ;
		   .IF <BIT AL NAND ON> 	  ; yes....bit says LCD..so..
		     OR     DEVICE_FLAG,LCD_FOUND ; mark as LCD.
		   .ENDIF			  ;
		 .ENDIF 			  ;
	       .ENDIF				  ;
	       .IF <DEVICE_FLAG NE ZERO>	  ; nothing found?..then exit (eg. MONO)
		 LEA	SI,DEVICE_TYPES 	  ; start of new id's
		 SAR	DEVICE_FLAG,ONE 	  ; shift flag into carry bit
		 .WHILE NC			  ; carry not set yet..
		   ADD	  SI,DEVICE_N_LENGTH	  ; next id
		   SAR	  DEVICE_FLAG,ONE	  ; next flag...
		 .ENDWHILE			  ;
		 PUSH	CS			  ; found....transfer id..
		 POP	ES			  ; into the table..
		 LEA	DI,T4_NAME		  ;
		 MOV	CX,DEVICE_N_LENGTH	  ;
		 REP	MOVSB			  ;
		 MOV	T4_LENGTH,EIGHT 	  ;
		 CLC				  ; clear error flag
	       .ELSE				  ;
		 STC				  ; set error (ie. MONO or CGA found)
	       .ENDIF				  ;
	       POP    DS			  ; r
	       POP    ES			  ;  e	  r
	       POP    SI			  ;   s    e
	       POP    DI			  ;    t    g
	       POP    DX			  ;	o    i
	       POP    CX			  ;	 r    s
	       POP    BX			  ;	  e    t
	       POP    AX			  ;		e
	       RET				  ;		 r
GET_DEVICE_ID  ENDP				  ;		  s



CODE	      ENDS
	      END
