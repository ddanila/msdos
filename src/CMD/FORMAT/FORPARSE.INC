;



data	segment public para 'DATA'

;
;*****************************************************************************
; Publics
;*****************************************************************************
;

	Public	Drive_Letter_Buffer
	Public	Switch_Buffer
	Public	Switch_Num_Buffer
	Public	Switch_String_Buffer


;
;***************************************************************************
; Equates
;***************************************************************************
;

;Match Flags

Numeric_Value		equ	8000h		;
Signed_Numeric_Value	equ	4000h		;
Simple_String		equ	2000h		;
Date_String		equ	1000h		;
Time_String		equ	0800h		;
Complex_List		equ	0400h		;
Filespec		equ	0200h		;
Drive_Only		equ	0100h		;
Quoted_String		equ	0080h		;
Ignore_Colon		equ	0010h		;
Repeats_Allowed 	equ	0002h		;
Optional		equ	0001h		;

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

;
;*****************************************************************************
; Parse Structures
;*****************************************************************************
;

Control 	 struc

Match_Flags	dw	?
Function_Flags	dw	?
Result		dw	?
Values		dw	?
Num_Keywords	db	?
Keyword 	db	?

Control 	ends

Drive_Letter_Return	struc			;

Drive_Type	db	0			;
Drive_Item_Tag	db	0			;
Drive_Pointer	dw	0			;
Drive_Number	db	0			;A=1, B=2, C=3
Drive_debug	db	8 dup(0)

Drive_Letter_Return	ends			;

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
Switch_Number_Low   dw	    0		    ;
Switch_Number_High  dw	    0		    ;

Switch_Num_Return    ends			;

Switch_String_Return   struc			;

Switch_String_Type     db      0		       ;
Switch_String_Item_Tag db      0		       ;
Switch_String_Pointer  dw      0		       ;
Switch_String_Off	dw	0		;
Switch_String_Seg	dw	0		;

Switch_String_Return ends			;


;
;**************************************************************************
; Parse tables
;**************************************************************************
;

IF FSExec					;conditionally assemble /FS:

Switch_FS_Table       label byte		;

	dw	Drive_Control_Definition	;Point to next level
	db	0				;

ENDIF						;end conditional assembly /FS:

Command_Line_Table label byte			;

	dw	Command_Control 		;Point to next level
	db	0				;

;
;**************************************************************************
;Define Positionals, Switches and Keywords
;**************************************************************************
;


IF FSExec					;conditionally assemble /FS:

Drive_Control_Definition label byte		;

	db	1,1				;Only drive letter posistional
	dw	Positional_Control		;Pointer to control table
	db	1				;1 switch
	dw	Switch_FS_Control		;
	db	None				;No Keywords (maxk)

ENDIF						;end conditional assembly /FS:

Command_Control label byte			;

	db	1,1				;Only drive letter posistional
	dw	Positional_Control		;Pointer to control table
IF ShipDisk
	db	16				;if /Z switch needed
ELSE
	db	15				;
ENDIF
	dw	Switch_V_Control		;Without quotes 		AN000;
	dw	Switch_S_Control		;
	dw	Switch_Q_Control
	dw	Switch_U_Control
	dw	Switch_C_Control
	dw	Switch_4_Control		;
	dw	Switch_1_Control		;
	dw	Switch_8_Control		;
	dw	Switch_B_Control		;
	dw	Switch_T_Control		;
	dw	Switch_N_Control		;
	dw	Switch_Select_Control		;
	dw	Switch_Backup_Control		;
	dw	Switch_Autotest_Control 	;
	dw	Switch_F_Control		;
IF ShipDisk
	dw	Switch_Z_Control		;1 sector/cluster switch
ENDIF
	db	None				;No Keywords (maxk)

;
;**************************************************************************
;Control Tables
;**************************************************************************
;

Positional_Control label byte			;

	dw	Drive_Only			;Match_Flag
	dw	None				;No function flags
	dw	Drive_Letter_Buffer		;Where it will be returned
	dw	No_Value			;No value ranges defined
	db	None				;No defined switches/keywords

IF FSExec					;conditionally assemble /FS:

Switch_FS_Control label byte
	dw	Simple_String			;/FS:xxxxx
	dw	File_Table_Capitalize		;Make it uppercase
	dw	Switch_String_Buffer		;
	dw	No_Value			;
	db	1				;
	db	"/FS",0                         ;

ENDIF						;end conditional assembly /FS:

Switch_V_Control label byte			;

	dw	Simple_String+Quoted_String+Optional ;/v:xxxxxxxx
	dw	File_Table_Capitalize		;
	dw	Switch_String_Buffer		;
	dw	No_Value			;
	db	1				;
	db	"/V",0                          ;

Switch_S_Control label byte			;

	dw	None				;
	dw	None				;
	dw	Switch_Buffer			;
	dw	No_Value			;
	db	1				;
	db	"/S",0                          ;

Switch_Q_Control label byte
	dw	None
	dw	None
	dw	Switch_Buffer
	dw	No_Value
	db	1
	db	"/Q",0

Switch_U_Control label byte
	dw	None
	dw	None
	dw	Switch_Buffer
	dw	No_Value
	db	1
	db	"/U",0

Switch_C_Control label byte
	dw	None
	dw	None
	dw	Switch_Buffer
	dw	No_Value
	db	1
	db	"/C",0

Switch_4_Control label byte			;

	dw	None				;
	dw	None				;
	dw	Switch_Buffer			;
	dw	No_Value			;
	db	1				;
	db	"/4",0                          ;

Switch_1_Control label byte			;

	dw	None				;
	dw	None				;
	dw	Switch_Buffer			;
	dw	No_Value			;
	db	1				;
	db	"/1",0                          ;

Switch_8_Control label byte			;

	dw	None				;
	dw	None				;
	dw	Switch_Buffer			;
	dw	No_Value			;
	db	1				;
	db	"/8",0                          ;

Switch_B_Control label byte			;

	dw	None				;
	dw	None				;
	dw	Switch_Buffer			;
	dw	No_Value			;
	db	1				;
	db	"/B",0                          ;

Switch_T_Control label byte			;

	dw	Numeric_Value			;
	dw	None				;
	dw	Switch_Num_Buffer		;
	dw	Switch_T_Value			;
	db	1				;
	db	"/T",0                          ;

Switch_N_Control label byte			;

	dw	Numeric_Value			;
	dw	None				;
	dw	Switch_Num_Buffer		;
	dw	Switch_N_Value			;
	db	1				;
	db	"/N",0                          ;

Switch_Select_Control label byte		;

	dw	None				;
	dw	None				;
	dw	Switch_Buffer			;
	dw	No_Value			;
	db	1				;
	db	"/SELECT",0                     ;

Switch_Backup_Control label byte		;

	dw	None				;
	dw	None				;
	dw	Switch_Buffer			;
	dw	No_Value			;
	db	1				;
	db	"/BACKUP",0                     ;

Switch_Autotest_Control label byte		;

	dw	None				;
	dw	None				;
	dw	Switch_Buffer			;
	dw	No_Value			;
	db	1				;
	db	"/AUTOTEST",0                   ;

Switch_F_Control label byte			;
	dw	Simple_String			;/F:xxxxx
	dw	File_Table_Capitalize		;Make it uppercase
	dw	Switch_String_Buffer		;
	dw	Switch_Size_Value		;
	db	1				;
	db	"/F",0                          ;

IF ShipDisk

Switch_Z_Control label	byte			;control structure for /Z
	dw	None				;
	dw	None				;
	dw	Switch_Buffer			;
	dw	No_Value			;
	db	1				;
	db	"/Z",0                          ;

ENDIF

;
;************************************************************************
; PARSE Value Lists
;************************************************************************
;

Switch_T_Value label byte			;

	db	1				;Range only			;ANOOO;
	db	1				;1 range			;ANOOO;
	db	Range_OK			;Item_Tag			;ANOOO;
	dd	1				;1 is low bound 		;ANOOO;
	dd	1024				;2**10 is max

Switch_N_Value label byte			;

	db	1				;Range only			;ANOOO;
	db	1				;1 range			;ANOOO;
	db	Range_OK			;Item_Tag			;ANOOO;
	dd	1				;1 is low bound 		;ANOOO;
	dd	64				;2**6  is max

Switch_Size_Value	label	byte		;

	db	3				;Look for strings
	db	0				;No ranges
	db	0				;No numerics
	db	33				;33 possible strings
	db	Size_160			;
	dw	String_160k_1			;/F:160
	db	Size_160			;
	dw	String_160k_2			;/F:160K
	db	Size_160			;
	dw	String_160k_3			;/F:160KB
	db	Size_180			;
	dw	String_180k_1			;/F:180
	db	Size_180			;
	dw	String_180k_2			;/F:180K
	db	Size_180			;
	dw	String_180k_3			;/F:180KB
	db	Size_320			;
	dw	String_320k_1			;/F:320
	db	Size_320			;
	dw	String_320k_2			;/F:320K
	db	Size_320			;
	dw	String_320k_3			;/F:320KB
	db	Size_360			;
	dw	String_360k_1			;/F:360
	db	Size_360			;
	dw	String_360k_2			;/F:360K
	db	Size_360			;
	dw	String_360k_3			;/F:360KB
	db	Size_720			;
	dw	String_720k_1			;/F:720
	db	Size_720			;
	dw	String_720k_2			;/F:720K
	db	Size_720			;
	dw	String_720k_3			;/F:720KB
	db	Size_1200			;
	dw	String_1200k_1			;/F:1200
	db	Size_1200			;
	dw	String_1200k_2			;/F:1200K
	db	Size_1200			;
	dw	String_1200k_3			;/F:1200KB
	db	Size_1200			;
	dw	String_1200k_4			;/F:1.2
	db	Size_1200			;
	dw	String_1200k_5			;/F:1.2M
	db	Size_1200			;
	dw	String_1200k_6			;/F:1.2MB
	db	Size_1440			;
	dw	String_1440k_1			;/F:1440
	db	Size_1440			;
	dw	String_1440k_2			;/F:1440K
	db	Size_1440			;
	dw	String_1440k_3			;/F:1440KB
	db	Size_1440			;
	dw	String_1440k_4			;/F:1.44
	db	Size_1440			;
	dw	String_1440k_5			;/F:1.44M
	db	Size_1440			;
	dw	String_1440k_6			;/F:1.44MB
	db	Size_2880
	dw	String_2880k_1			;/F:2880
	db	Size_2880
	dw	String_2880k_2			;/F:2880K
	db	Size_2880
	dw	String_2880k_3			;/F:2880KB
	db	Size_2880
	dw	String_2880k_4			;/F:2.88
	db	Size_2880
	dw	String_2880k_5			;/F:2.88M
	db	Size_2880
	dw	String_2880k_6			;/F:2.88MB


No_Value	label	byte			;
	db	0				;

;
;*****************************************************************************
; Data Area for value lists
;*****************************************************************************
;

;
;The following are a list of the allowed strings for the /F:xxxxx switch.
;

String_160k_1	db	"160"  ,Asciiz_End      ;
String_160k_2	db	"160K" ,Asciiz_End      ;
String_160k_3	db	"160KB" ,Asciiz_End      ;
String_180k_1	db	"180"  ,Asciiz_End      ;
String_180k_2	db	"180K" ,Asciiz_End      ;
String_180k_3	db	"180KB" ,Asciiz_End      ;
String_320k_1	db	"320"  ,Asciiz_End      ;
String_320k_2	db	"320K" ,Asciiz_End      ;
String_320k_3	db	"320KB" ,Asciiz_End      ;
String_360k_1	db	"360"  ,Asciiz_End      ;
String_360k_2	db	"360K" ,Asciiz_End      ;
String_360k_3	db	"360KB" ,Asciiz_End      ;
String_720k_1	db	"720"  ,Asciiz_End      ;
String_720k_2	db	"720K" ,Asciiz_End      ;
String_720k_3	db	"720KB" ,Asciiz_End      ;
String_1200k_1	db	"1200" ,Asciiz_End      ;
String_1200k_2	db	"1200K",Asciiz_End      ;
String_1200k_3	db	"1200KB",Asciiz_End      ;
String_1200k_4	db	"1.2" ,Asciiz_End      ;
String_1200k_5	db	"1.2M" ,Asciiz_End      ;
String_1200k_6	db	"1.2MB" ,Asciiz_End      ;
String_1440k_1	db	"1440" ,Asciiz_End      ;
String_1440k_2	db	"1440K",Asciiz_End      ;
String_1440k_3	db	"1440KB",Asciiz_End      ;
String_1440k_4	db	"1.44",Asciiz_End      ;
String_1440k_5	db	"1.44M",Asciiz_End      ;
String_1440k_6	db	"1.44MB",Asciiz_End      ;
String_2880k_1	db	"2880",Asciiz_End
String_2880k_2	db	"2880K",Asciiz_End
String_2880k_3	db	"2880KB",Asciiz_End
String_2880k_4	db	"2.88",Asciiz_End
String_2880k_5	db	"2.88M",Asciiz_End
String_2880k_6	db	"2.88MB",Asciiz_End

;
;************************************************************************
; PARSE Return Buffers
;************************************************************************
;

Drive_Letter_Buffer	Drive_Letter_Return	<> ;Example of structure
Switch_Buffer		Switch_Return		<> ;
Switch_Num_Buffer	Switch_Num_Return	<> ;
Switch_String_Buffer	Switch_String_Return	<> ;

data	ends

;
;*****************************************************************************
; SysParse Routines
;*****************************************************************************
;


code	segment public	para 'CODE'
	assume cs:code,ds:Data

FarSW	equ	Not_Include
DateSW	equ	Not_Include			;
TimeSW	equ	Not_Include			;
FileSW	equ	Do_Include			;
CAPSW	equ	Do_Include			;
CmpxSW	equ	Not_Include			;
NumSW	equ	Do_Include			;
KeySW	equ	Not_Include			;
SwSW	equ	Do_Include			;
Val1SW	equ	DO_Include			;
Val2SW	equ	Not_Include			;
Val3SW	equ	Do_Include			;
DrvSW	equ	Do_Include			;
QusSW	equ	Do_Include			;

INCLUDE PARSE.ASM				;


code	ends
