PAGE	    ,132
TITLE	    PARSE CODE AND CONTROL BLOCKS FOR PRINTER.SYS

;****************** START OF SPECIFICATIONS **************************
;
;  MODULE NAME: PARSER.ASM
;
;  DESCRIPTIVE NAME: PARSES THE DEVICE= STATEMENT IN CONFIG.SYS FOR
;		     PRINTER.SYS
;
;  FUNCTION: THE COMMAND LINE PASSED TO PRINTER.SYS IN THE CONFIG.SYS
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
;
;  EXTERNAL REFERENCES:
;
;     ROUTINES: N/A
;
;     DATA AREAS: TABLE - TO CONTAIN VALUES FOUND IN DEVICE= LINE
;
;  NOTES:
;
;      Label: "DOS DISPLAY.SYS Device Driver"
;	      "Version 4.00 (C) Copyright 1988 Microsoft
;	      "Licensed Material - Program Property of Microsoft"
;
;
;****************** END OF SPECIFICATIONS ****************************

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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


.XLIST
INCLUDE     STRUC.INC	     ; Structured macros
.LIST

INCLUDE     CPSPEQU.INC

PUBLIC	    PARSER	     ; near procedure for parsing DEVICE= statement

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Set assemble switches for parse code
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

DateSW	      EQU     0
DrvSW	      EQU     0
SwSW	      EQU     0
Val1SW	      EQU     1     ;
Val2SW	      EQU     0
Val3SW	      EQU     0


CSEG	      SEGMENT  PARA PUBLIC 'CODE'
	      ASSUME CS:CSEG,DS:NOTHING,ES:NOTHING


EXTRN	    TABLE:WORD	     ; table for variable storage used by INIT module.
EXTRN	    DEVICE_NUM:WORD

.XLIST
INCLUDE     PARSE.ASM	    ; Parsing code
.LIST


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PARM control block for parsing PRINTER.SYS - DEVICE= command statement.
; Command line looks like:
;
;   DEVICE=[d:][path]PRINTER.SYS LPT#[:]=(type[,[hwcp][,n]])
;     or
;   DEVICE=[d:][path]PRINTER.SYS LPT#[:]=(type[,[(hwcp1,hwcp2,...)][,n]])
;
; The command line will be parsed from left to right, taking care of the
; nesting of complex lists as they occur.
;
; The first level of control blocks is shown below.
; Complex list control blocks follow.
; Null VALUE LIST and RESULT BUFFER are placed after all other PARSE control
; blocks.
;
; d:\path\PRINTER.SYS lpt#=(complex list)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARMS1	       LABEL WORD
	       DW	PARMSX1
	       DB	0		   ; no extra delimeters or EOLs.

PARMSX1        LABEL BYTE
	       DB	1,1		   ; min,max positional operands
	       DW	D_NAME		   ; pointer to control block
	       DB	0		   ; no switches
	       DB	1		   ; 1 or more keywords
	       DW	PRT_LIST	   ; pointer to control block

D_NAME	       LABEL WORD
	       DW	0200H		   ; file spec
	       DW	0001H		   ; cap result by file table
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; no value checking done
	       DB	0		   ; no keyword/switch synonyms

PRT_LIST       LABEL WORD
	       DW	0402H		   ; complex list,  repeats allowed
	       DW	0002H		   ; cap result by char table
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; no value checking done
	       DB	8		   ; 4 keywords
	       DB	"PRN=",0           ;GHG Ä¿
	       DB	"LPT1=",0          ;GHG  ³ 4 possible keywords
	       DB	"LPT2=",0          ;GHG  ³
	       DB	"LPT3=",0          ;GHG ÄÙ
	       DB	"PRN:=",0          ;GHG Ä¿
	       DB	"LPT1:=",0         ;GHG  ³ 4 possible keywords
	       DB	"LPT2:=",0         ;GHG  ³   with colon
	       DB	"LPT3:=",0         ;GHG ÄÙ

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PARM control block for second level of nesting.
; ie. complex list from first level of nesting
;
; (type, hwcp or complex list, n)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARMS2	       LABEL WORD
	       DW	PARMSX2
	       DB	0		   ; no extra delimeters or EOLs.

PARMSX2        LABEL BYTE
	       DB	1,3		   ; min,max positional operands
	       DW	PRT_TYPE	   ; pointer to control block
	       DW	HWCP		   ; pointer to control block
	       DW	CP_PREPS	   ; pointer to control block
	       DB	0		   ; no switches
	       DB	0		   ; no keywords

PRT_TYPE       LABEL BYTE
	       DW	2000H		   ; sstring
	       DW	0002H		   ; cap by char table
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; value list
	       DB	0		   ; no keyword/switch synonyms

HWCP	       LABEL BYTE
	       DW	8401H		   ; numeric or complex list (optional)
	       DW	0		   ; no functions
	       DW	RESULT_BUF	   ; result
	       DW	NOVALS		   ; no value checking done
	       DB	0		   ; no keyword/switch synonyms

CP_PREPS       LABEL BYTE
	       DW	8001H		   ; numeric (optional)
	       DW	0		   ; no functions
	       DW	RESULT_BUF	   ; result
	       DW	N_Val_Range	   ;AN002; value list
	       DB	0		   ; no keyword/switch synonyms


N_Val_Range    label   byte
	       db      1		   ;AN002; Range defintion
	       db      1		   ;AN002; Number of ranges
	       db      1		   ;AN002; item tag
	       dd      0, 12		   ;AN002; 0 - 12

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PARM control block for third level of nesting.
; ie. complex list from second nesting level
;
; (hwcp1,hwcp2,...)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARMS3	       LABEL WORD
	       DW	PARMSX3
	       DB	0		   ; no extra delimeters or EOLs.

PARMSX3        LABEL BYTE
	       DB	1,1		   ; min,max positional operands
	       DW	HWCPS		   ; pointer to control block
	       DB	0		   ; no switches
	       DB	0		   ; no keywords

HWCPS	       LABEL BYTE
	       DW	8003H		   ; numeric, repeats allowed
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
SYN_PTR        DW	?		   ; synonym ptr (if applicable)
RESULT_VAL     DD	?		   ; value


OK_FLAG        DB	ON		   ; FLAG INDICATING PARSE STATUS
NUM_LOOP       DB	ZERO


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
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARSER	PROC	 NEAR
	PUSH	 DX
	PUSH	 DI
	PUSH	 ES
	PUSH	 BX
	PUSH	 DS			  ;
	PUSH	 SI			  ;
	CLD				  ;
	LDS	 SI,RH.RH0_BPBA 	  ;
	PUSH	 CS			  ; establish ES ..
	POP	 ES			  ; addressability to data
	LEA	 DI,PARMS1		  ; point to PARMS control block
	XOR	 CX,CX			  ; clear both CX and DX for
	XOR	 DX,DX			  ;  SYSPARSE
	CALL	 SYSPARSE		  ; move pointer past file spec
	CALL	 SYSPARSE		  ; do first parse
	LEA	 BX,TABLE		  ;
	.WHILE <AX NE RC_EOL> AND	  ; EOL?...then end parse...and..
	.WHILE <OK_FLAG EQ ON>		  ; make sure that flag still ok..
	  .IF <AX NE RC_NO_ERROR>	  ; parse error?
	    MOV     OK_FLAG,OFF 	  ; yes...reset flag
	  .ELSE 			  ;
	    .SELECT			  ;
	    .WHEN <RESULT_TYPE EQ COMPLEX>; complex string found?
	      INC    DEVICE_NUM 	  ; increment count
	      INC    BX 		  ; point to next device table
	      INC    BX 		  ;
	      .IF <DEVICE_NUM GT FOUR>	  ; more than one?
		MOV    OK_FLAG,OFF	  ; yes....we have an error
	      .ELSE			  ; no ..
		PUSH   BX		  ;
		MOV    BX,CS:[BX]	  ;
		CALL   COPY_NAME	  ;
		MOV    NUM_LOOP,ZERO	  ;
		CALL   PARSE_MAIN	  ; process complex string..
		POP    BX		  ;
	      .ENDIF			  ;
	    .OTHERWISE			  ; not a complex string so..
	      MOV    OK_FLAG,OFF	  ; we have a problem...reset flag
	    .ENDSELECT			  ;
	  .ENDIF			  ;
	  PUSH	 BX			  ;
	  CALL	 SYSPARSE		  ; continue parsing..
	  POP	 BX			  ;
	.ENDWHILE			  ;
	.IF <OK_FLAG EQ OFF>		  ; flag indicating error?
	  MOV	DEVICE_NUM,ZERO 	  ; yes...set device number to 0
	  STC				  ;
	.ELSE				  ;
	  CLC				  ;
	.ENDIF				  ;
	POP    SI			  ;
	POP    DS			  ;
	POP    BX			  ;
	POP    ES			  ;
	POP    DI			  ;
	POP    DX			  ;
	RET				  ;
PARSER	ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PARSE_MAIN
;
; FUNCTION:
; THIS PROCEDURE PARSES THE LPT=(    ) COMPLEX LIST DEVICE= LINE FOUND
; IN CONFIG.SYS
;
; AT ENTRY: RESULT BUFFER CONTAINS POINTER TO COMPLEX STRING
;
; AT EXIT:
;    NORMAL: TABLE SET UP WITH VALUES FOUND
;
;    ERROR: OK_FLAG = 0
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARSE_MAIN  PROC   NEAR
	    PUSH   BX			  ;
	    PUSH   DI			  ; setup to parse the nested..
	    PUSH   DS			  ; complex string...but save..
	    PUSH   SI			  ; current parsing status.
	    PUSH   CX			  ;
	    XOR    CX,CX		  ;
	    LEA    DI,PARMS2		  ; next control block..
	    LDS    SI,RESULT_VAL	  ; point to stored string
	    PUSH   BX			  ;
	    CALL   SYSPARSE		  ;
	    POP    BX			  ;
	    .WHILE <AX NE RC_EOL> AND	  ; not EOL?   and..
	    .WHILE <OK_FLAG EQ ON>	  ; error flag still ok?
	      INC    NUM_LOOP		  ;
	      .IF <AX NE RC_NO_ERROR>	  ; check for parse errors
		MOV    OK_FLAG,OFF	  ; yes....reset error flag
	      .ELSE			  ; no...process
		PUSH   BX		  ;
		.SELECT 		  ;
		.WHEN <RESULT_TYPE EQ STRING> ; simple string
		  MOV	 BX,CS:[BX].DI_OFFSET ;
		  CALL	 PARSE_STR	  ; yes...process
		.WHEN <RESULT_TYPE EQ NUMBER> ; number?..
		  .IF <NUM_LOOP EQ TWO>   ;
		    MOV    BX,CS:[BX].DCP_OFFSET
		  .ELSE 		  ;
		    MOV    BX,CS:[BX].DD_OFFSET
		  .ENDIF		  ;
		   MOV	  AX,WORD PTR RESULT_VAL ; get value into word form
		   .IF <AX NE ZERO>
		     INC    WORD PTR CS:[BX] ;
		     MOV    WORD PTR CS:[BX+2],AX ; load that value.
		   .ENDIF
		.WHEN <RESULT_TYPE EQ COMPLEX> ; complex string?
		  MOV	 BX,CS:[BX].DCP_OFFSET ;
		  CALL	 PARSE_COMP	  ; yes...process
		.OTHERWISE		  ; anything else is..
		  MOV	 OK_FLAG,OFF	  ; an error...reset flag.
		.ENDSELECT		  ;
		CALL   SYSPARSE 	  ; continue parsing
		POP    BX		  ;
	      .ENDIF			  ;
	    .ENDWHILE			  ;
	    POP    CX			  ; restore original parse..
	    POP    SI			  ; registers.
	    POP    DS			  ;
	    POP    DI			  ;
	    POP    BX			  ;
	    RET 			  ;
PARSE_MAIN  ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: PARSE_COMP
;
; FUNCTION:
; THIS PROCEDURE PARSES A COMPLEX LIST FOUND WITHIN THE LPT=(	)
; COMPLEX LIST.
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
	     MOV    DI,BX		  ;
	     PUSH   DI			  ;
	     XOR    CX,CX		  ;
	     LEA    DI,PARMS3		  ; next control block
	     LDS    SI,RESULT_VAL	  ; point to stored string.
	     PUSH   BX			  ;
	     CALL   SYSPARSE		  ;
	     POP    BX			  ;
	     .WHILE <AX NE RC_EOL> AND	  ; not EOL?...and..
	     .WHILE <OK_FLAG EQ ON> AND   ; error flag still okay?
	     .WHILE <AX NE RC_OP_MISSING> ;
	       .IF <AX NE RC_NO_ERROR>	  ; parse error?...or..
		 MOV	OK_FLAG,OFF	  ; found?....yes..reset flag.
	       .ELSE			  ; no...process..
		 INC	WORD PTR CS:[BX]  ; increment counter
		 .IF <<WORD PTR CS:[BX]> LE TEN>
		   POP	  DI		  ;
		   MOV	  AX,WORD PTR RESULT_VAL ; get numeric value into word
		   MOV	  WORD PTR CS:[DI+2],AX ;
		   INC	  DI		  ;
		   INC	  DI		  ;
		   PUSH   DI		  ;
		   PUSH   BX		  ;
		   LEA	  DI,PARMS3	  ;
		   CALL   SYSPARSE	  ; continue parsing
		   POP	  BX		  ;
		 .ELSE			  ;
		   MOV	  OK_FLAG,OFF	  ;
		 .ENDIF 		  ;
	       .ENDIF			  ;
	     .ENDWHILE			  ;
	     POP    DI			  ;
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
; THIS PROCEDURE PARSES A STRING FOUND WITHIN THE LPT=(   ) STATEMENT
;
; AT ENTRY: RESULT BUFFER POINTS TO ASCIIZ STRING
;
; AT EXIT:
;    NORMAL: TABLE SET UP WITH VALUES FOUND
;
;    ERROR: STRING > 8 - OK_FLAG SET OFF
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PARSE_STR    PROC   NEAR
	     PUSH   DI			  ; get source and..
	     PUSH   DS			  ; destination registers..
	     PUSH   SI			  ; setup.
	     PUSH   CX			  ;
	     LDS    SI,RESULT_VAL	  ;
	     MOV    DI,BX		  ;
	     MOV    CS:[DI].N_LENGTH,EIGHT ;
	     INC    DI			  ;
	     INC    DI			  ;
	     MOV    CX,EIGHT		  ;
	     LODSB			  ; load first character.
	     .WHILE <AL NE ZERO> AND	  ; while not at end of ASCIIZ do..
	     .WHILE <CX NE ZERO>	  ;
	       STOSB			  ; store..
	       LODSB			  ; load next character..
	       DEC    CX		  ;
	     .ENDWHILE			  ;
	     .IF <CX EQ ZERO>
	       MOV    OK_FLAG,OFF
	     .ENDIF
	     POP    CX			  ; value found.
	     POP    SI			  ; restore registers.
	     POP    DS			  ;
	     POP    DI			  ;
	     RET
PARSE_STR    ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: COPY_NAME
;
; FUNCTION:
; THIS PROCEDURE COPIES THE FOUND STRING VALUE INTO THE TABLE.
;
; AT ENTRY: N/A
;
; AT EXIT:
;    NORMAL: TABLE UPDATED
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

COPY_NAME    PROC   NEAR
	     PUSH   DI			  ; get source and..
	     PUSH   DS			  ; destination registers..
	     PUSH   SI			  ; setup.
	     PUSH   CS			  ;
	     POP    DS			  ;
	     MOV    SI,SYN_PTR		  ;
	     MOV    DI,CS:[BX].DN_OFFSET  ;
	     MOV    CS:[DI].N_LENGTH,EIGHT ;
	     INC    DI			  ;
	     INC    DI			  ;
	     LODSB			  ; load first character.
	     .WHILE <AL NE ZERO>	  ; while not at end of ASCIIZ do..
	       .IF <AL NE ':'> AND        ;ignore colon
	       .IF <AL NE '='>            ; or =
		 STOSB			  ; store..
	       .ENDIF			  ;
	       LODSB			  ; load next character..
	     .ENDWHILE			  ;
	     POP    SI			  ; restore registers.
	     POP    DS			  ;
	     POP    DI			  ;
	     RET
COPY_NAME    ENDP

CSEG	      ENDS
	      END
