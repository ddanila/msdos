
const	segment public para 'const'
;***************************************************************************
; Equates
;***************************************************************************
;
;Match Flags
Numeric_Value		equ	8000h
Signed_Numeric_Value	equ	4000h
Simple_String		equ	2000h
Date_String		equ	1000h
Time_String		equ	0800h
Complex_List		equ	0400h
Filespec		equ	0200h
Drive_Only		equ	0100h
Quoted_String		equ	0080h
Ignore_Colon		equ	0010h
Repeats_Allowed 	equ	0002h
Optional		equ	0001h

;Function_Flags

File_Table_Capitalize	equ	1
Char_Table_Capitalize	equ	2
Remove_Colon		equ	10h

;Extra delimeters and EOL

No_Extra_Delimiters	equ	00h
Delimiters_Only 	equ	1
EOL_Or_Delimiters	equ	2

Semi_Colon		equ	";"
Tab			equ	09h
Colon			equ	":"


;Parse Errors

No_Error		equ	0
Too_Many_Operands	equ	1
Operand_Missing 	equ	2
Not_In_Switch_List	equ	3
Not_In_Keyword_List	equ	4
Out_Of_Range		equ	6
Not_In_Value_List	equ	7
Not_In_String_List	equ	8
Syntax_Error		equ	9
End_Of_Parse		equ	-1

;Return types

Type_Reserved		equ	0		;
Type_Number		equ	1		;
Type_List_Index 	equ	2		;
Type_String		equ	3		;
Type_Complex		equ	4		;
Type_Filespec		equ	5		;
Type_Drive		equ	6		;
Type_Date		equ	7		;
Type_Time		equ	8		;
Type_Quoted_String	equ	9		;


;Other

None			equ	0
No_Error		equ	0
Switch_Found		equ	0FFFFh
Range_Ok		equ	1
Command_Line_Parms	equ	81h
const	ends

data	segment public para 'DATA'
;*****************************************************************************
;*****************************************************************************
; Parse Tables
;*****************************************************************************
;*****************************************************************************
;The following parse control block can be used for any command which
;needs only one optional file specification an operand.  Returns a
;pointer to the unverified string in PARSE1_OUTPUT.  Currently used
;for the RECOVER command.
;*****************************************************************************
;;;;db 'PARSE TABLE AREA'
 public parms_input_block, parms_ext_block, control_block, value_list_block
 public results_block, parse_type, parse_code, parse_addr
;*****************************************************************************
; This is the parms input block pointed to by es:di before calling sysparse.
; it is the top level table.
parms_input_block LABEL   BYTE
		DW	dg:parms_ext_block	  ; addr of parms extension block
		DB	0			; no delimiters or eol chars
;*****************************************************************************
; This is the parms extension block pointed to by the parms input block.
; it defines the number and type of parameters allowed in the command line.
parms_ext_block LABEL	BYTE
		DB	1,1			; only one positional parm
		DW	dg:control_block       ; addr of positional control block
		DB	0			;	 no switches
		DB	0			;	 no keywords
;PARSE control block for an optional file specification (upper cased)
;or drive number
;*****************************************************************************
; This is the control block for either drive letter "c:", or filename.ext, or
; both "c:filename.ext" entered in the command line. it is pointed to by the
; parms extension block.
control_block	LABEL	BYTE
		Dw	$p_file_spc+$p_drv_only ; allowable return values
						; 0200 = filespec
						; 0100 = drive only
		DW	1			; capitalize - file table
		DW	dg:results_block	   ; points to reults block
		DW	dg:value_list_block	   ; point to valu list block
		DB	0			; no keyword synonyms
;Indicates no value list for PARSE.
;*****************************************************************************
; This is the value list block pointed to by the control block.  This table is
; used to define the type of numeric or string parameters expected.  Since no
; parameters with numerics or strings are used, this block is set to zero.
value_list_block DW	 0			 ;AN000;  no values
;Common output blocks for PARSE number, complex, or string values.
;*****************************************************************************
; This is the results block pointed to by the control block.
; both "c:filename.ext" entered in the command line. it is pointed to by the
; parms extension block.
results_block	LABEL	BYTE
PARSE_TYPE     DB      0		       ; type of parm returned
PARSE_CODE     DB      0		       ; matched item tag / return valu
PARSE_SYN      DW      0		       ;	es offset of synonym
PARSE_ADDR     DD      0		       ; either a numeric value, or
	       dd      0 ;parser puts in too many;the offset of string value

;;;;DB 'PARSE AREA ENDS'
data	ends
code	segment PUBLIC para 'CODE'
;*****************************************************************************
; SysParse Routines
;*****************************************************************************
FarSW	equ	Not_Include			;
DateSW	equ	Not_Include			;
TimeSW	equ	Not_Include			;
FileSW	equ	Do_Include			;
CAPSW	equ	Not_Include			;
CmpxSW	equ	Not_Include			;
NumSW	equ	Not_Include			;
KeySW	equ	Not_Include			;
SwSW	equ	Not_Include			;
Val1SW	equ	Not_Include			;
Val2SW	equ	Not_Include			;
Val3SW	equ	Not_Include			;
DrvSW	equ	Do_Include			;
QusSW	equ	Not_Include			;
basesw	equ	1 ;use ds as the default register
incsw	equ	0 ;include psdata myself
code	ends
data	segment PUBLIC para 'DATA'
include psdata.inc
data	ends
code	segment PUBLIC para 'CODE'
pathlabl parser
INCLUDE PARSE.ASM
pathlabl parser
code	ends
