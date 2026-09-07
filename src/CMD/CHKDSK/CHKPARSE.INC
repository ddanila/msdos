data	segment public para 'DATA'
;*****************************************************************************
; Publics
;*****************************************************************************
;	Public	Drive_Letter_Buffer
	Public	SwBuffer
	Public	Switch_F_Buffer
;	Public	FileSpec_Buffer
	public	buffer
	public	sw_v, sw_f
;***************************************************************************
; Equates
;***************************************************************************
;Match Flags
Numeric_Value		equ	8000h		;
Signed_Numeric_Value	equ	4000h		;
Simple_String		equ	2000h		;
Date_String		equ	1000h		;
Time_String		equ	0800h		;
Complex_List		equ	0400h		;
Quoted_String		equ	0080h		;
Ignore_Colon		equ	0010h		;
Repeats_Allowed 	equ	0002h		;
Optional		equ	0001h		;
Filespec		equ	0200h		;
Drive_Only		equ	0100h		;
;Function_Flags
File_Table_Capitalize	equ	1		;
Char_Table_Capitalize	equ	2		;
Remove_Colon		equ	10h		;
;Extra delimeters and EOL
Delimiters_Only 	equ	1		;
EOL_Or_Delimiters	equ	2		;
Semi_Colon		equ	";"             ;
Tab			equ	09h		;
Colon			equ	":"             ;
;Parse Errors
No_Error		equ	0		;
Too_Many_Operands	equ	1		;
Operand_Missing 	equ	2		;
Not_In_Switch_List	equ	3		;
Not_In_Keyword_List	equ	4		;
Out_Of_Range		equ	6		;
Not_In_Value_List	equ	7		;
Not_In_String_List	equ	8		;
Syntax_Error		equ	9		;
End_Of_Parse		equ	-1		;
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
None			equ	0		;
No_Error		equ	0		;
Switch_Found		equ	0FFFFh		;
Range_Ok		equ	1		;
Command_Line_Parms	equ	81h		;
;*****************************************************************************
; Parse Structures
;*****************************************************************************
Control 	 struc
Match_Flags	dw	?
Function_Flags	dw	?
Result		dw	?
Values		dw	?
Num_Keywords	db	?
Keyword 	db	?
Control 	ends
;Drive_Letter_Return	 struc			 ;
;Drive_Type		 db	 0			 ;
;Drive_Item_Tag 	 db	 0			 ;
;Drive_Pointer		 dw	 0			 ;
;Drive_Number		 db	 0			 ;A=1, B=2, C=3
;Drive_debug		 db	 8 dup(0)
;Drive_Letter_Return	 ends			 ;
;Filespec_Return struc
;Filespec_Type		 db	 0
;FileSpec_Item		 db	 0
;FileSpec_Pointer	 dw	 0
;Filespec_String_Off	 dw	 0
;FileSpec_String_Seg	 dw	 0
;FileSpec_Return ends
single_Return struc
dftype		  db	  0
Item		  db	  0
Pointer 	  dw	  0
drnum_stroff	  dw	  0
return_strseg		 dw	 0
single_return	ends
Switch_Return	 struc				;
Switch_Type	db	0			;
Switch_Item_Tag db	0			;
Switch_Pointer	dw	0			;
Switch_Debug	db	4 dup(0)
Switch_Return	 ends				;
Switch_Num_Return    struc			;
Switch_Num_Type     db	    0			    ;
Switch_Num_Item_Tag db	    0			    ;
Switch_Num_Pointer  dw	    0			    ;
Switch_Number_Low   dw	    0		    ;				    ;AN0;an000;bgb00;
Switch_Number_High  dw	    0		    ;				    ;AN0;an000;bgb00;
Switch_Num_Return    ends			;
Switch_String_Return   struc			;
Switch_String_Type     db      0		       ;
Switch_String_Item_Tag db      0		       ;
Switch_String_Pointer  dw      0		       ;
Switch_String_Off	dw	0		;
Switch_String_Seg	dw	0		;
Switch_String_Return ends			;
;**************************************************************************
; Parse tables
;**************************************************************************
Public	input_Table
input_Table	 label	 byte		 ;
	dw	offset dg:ext_table		;Point to next level	      ;A;an000;bgbN000;
	db	Delimiters_Only 		;
	db	1				;
	db	Semi_Colon			;
Drive_Table		label	byte
	dw	offset dg:Drive_Control_Definition ;Point to next level
	db	Delimiters_Only 		;
	db	1				;
	db	Semi_Colon			;
;**************************************************************************
;Define Positionals, Switches and Keywords
;**************************************************************************
Public	ext_table
ext_table		   label   byte 	;
	db	0,1			;up to one parm, either drive or file
	dw	dg:dfcontrol			     ;Pointer to control table
	db	1				;1 switch  def
	dw	dg:SwControl		;switch control block
	db	None				;No Keywords (maxk)
Drive_Control_Definition  label   byte		;
	db	0,1				;Only drive letter positional
	dw	dg:dfControl		    ;Pointer to control table	    ;AN0;an000;bgb00;
	db	None				;0 switches
	db	None				;No Keywords (maxk)
;**************************************************************************
; Define Positionals, Switches and Keywords
;**************************************************************************
;this is the new control block for both drive letters and filespecs
Public	dfControl
dfControl	 label	 byte		 ;
	dw	drive_only+FileSpec+Optional		   ;
	dw	None				;
	dw	dg:Buffer	       ;
	dw	dg:No_Value			;
	db	None				;
Public	SwControl							   ;an02;an000;bgb0;bgb
SwControl	 label	 byte		 ;				 ;AN020;;an000;bgbbgb
	dw	None				;
	dw	None				;
	dw	dg:SwBuffer		 ;
	dw	dg:No_Value
	db	2				;
sw_v	db	"/V",0                          ;
sw_f	db	"/F",0                          ;
;*****************************************************************************
; Value lists
;*****************************************************************************
No_Value	db	0			 ;
;************************************************************************
; PARSE Return Buffers
;************************************************************************
; these buffers were replaced by a single buffer due to the parser bug
;Drive_Letter_Buffer	 Drive_Letter_Return	 <>  ;Example of structure
;FileSpec_Buffer	 FileSpec_Return	 <>  ;
SwBuffer		Switch_Return		<>  ;
Switch_F_Buffer 	Switch_Return		<>  ;
buffer			single_return		<>  ; new results buffer
data	ends					;
;*****************************************************************************
; SysParse Routines
;*****************************************************************************
code	segment public	para 'CODE'
FarSW	equ	Not_Include			;
DateSW	equ	Not_Include			;
TimeSW	equ	Not_Include			;
FileSW	equ	Do_Include			;
CAPSW	equ	Not_Include			;
CmpxSW	equ	Not_Include			;
NumSW	equ	Not_Include			;
KeySW	equ	Not_Include			;
SwSW	equ	Do_Include			;
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
