data	segment PUBLIC para 'DATA'
;
;*****************************************************************************
; Macro's
;*****************************************************************************
Define_Msg macro Message_Name			;
						;
Create_Msg Message_Name,Message_Number,Handle,Sublist,Count,Class,Function,Input
						;
	endm					;

;-----------------------------------------------------------------------------

Create_Msg macro Parm1,Parm2,Parm3,Parm4,Parm5,Parm6,Parm7,Parm8;

Public	Parm1
Parm1	label	word				;
	dw	Parm2				;
	dw	Parm3				;
	dw	Parm4				;
	dw	Parm5				;
	db	Parm6				;
	db	Parm7				;
	dw	Parm8				;
	endm					;

;
;*****************************************************************************
; Message Retriever equates
;*****************************************************************************

Format_Msg		equ	'C'

N_A			equ	0
Sublist_Length		equ	11
None			equ	0

Blank			equ	" "
No_Function		equ	0
No_Replace		equ	0

Msg_Ser_Class		equ	0
Ext_Err_Class		equ	1
Parse_Err_Class 	equ	2
Utility_Msg_Class	equ	0FFh

Reserved		equ	0

;
;*****************************************************************************
; Message Sublist Tables
;*****************************************************************************
;
;The  following  control  blocks  are	used   for   messages  with
;replaceable  paramters.  These  control  blocks  are  used by	the
;SysDispMsg routine.
;

;---------------------------			;
Sublist_opnerr		label	byte
						;
	db		Sublist_Length
	db		Reserved
	dw		dg:fname_buffer
	dw		Dg
	db		0
	db		Left_Align+Char_Field_ASCIIZ
	db		14
	db		1
	db		Blank
;---------------------------			;
Sublist_Baddrv		label	byte
						;
	db		Sublist_Length
	db		Reserved
	dw		dg:Drive_Letter_Msg
	dw		Dg
	db		0
	db		Left_Align+Char_Field_ASCIIZ
	db		4
	db		4
	db		Blank
;---------------------------			;
ifdef	fsexec
Sublist_msg_EXECFailure label	byte
	db		Sublist_Length
	db		Reserved
	dw		dg:Drive_Letter_Msg
	dw		Dg
	db		1
	db		Left_Align+Char_Field_ASCIIZ
	db		2
	db		2
	db		Blank
endif
;---------------------------			;
Sublist_msg_recmsg	label	byte
						;
	db		Sublist_Length
	db		Reserved
	dw		dg:rec_num
	dw		Dg
	db		1
	db		Left_Align+Unsgn_Bin_Word
	db		5
	db		1
	db		Blank
;---------------------------			;
Sublist_msg_ofmsg	label	byte
						;
	db		Sublist_Length
	db		Reserved
	dw		dg:x_value_lo
	dw		Dg
	db		1
	db		Left_Align+Unsgn_Bin_DWord
	db		10
	db		1
	db		Blank
	db		Sublist_Length
	db		Reserved
	dw		y_value_lo
	dw		Dg
	db		2
	db		Left_Align+Unsgn_Bin_DWord
	db		10
	db		1
	db		Blank
;-----------------------------------------------------------------------
Drive_sublist label byte

    db	11		   ; sublist size
    db	0		   ;reserved
    dw	dg:driveletter ;offset of data
    dw	dg		   ;seg of data
    db	1		   ; 1st replaceable parm
    db	char_field_asciiz  ; type = char
    db	2		   ; max field width
    db	2		   ; min field width
    db	' '                ; pad char (unused)
;---------------------------			;
Sublist_msg_parserr	label	dword		;
	db		Sublist_Length		;11
	db		Reserved		;0
public movsi
movsi	dw		dg:command_line_buffer	;off
	dw		dg			;seg
	db		0			;USE PERCENT ZERO
	db		Left_Align+Char_Field_ASCIIZ ;type of data
	db		128			;max width
	db		1			;min width
	db		Blank			;pad char
;---------------------------			;



;
;*****************************************************************************
; Message Description Tables
;*****************************************************************************
;

;---------------------- 			;
Message_Number	= 2
Handle		= STDERR
Sublist 	EQU <Sublist_Opnerr>
Count		= N_A
Class		= EXT_ERR_CLASS
Function	= NO_INPUT
Input		= N_A
	Define_Msg   opnerr			; AN000;SM File not found - xxxxxx
;---------------------- 			;
Message_Number	= 3
Handle		= STDERR
Sublist 	EQU <None>
Count		= N_A
Class		= Utility_Msg_Class
Function	= NO_INPUT
Input		= N_A
	Define_Msg   Substerr			; AN000;SM Can not recover SUBST or ASSIGNED drive
;---------------------- 			;
Message_Number	= 4
Handle		= STDERR
Sublist 	EQU <sublist_baddrv>
Count		= N_A
Class		= UTILITY_MSG_CLASS
Function	= NO_INPUT
Input		= N_A
	Define_Msg   baddrv			; AN000;SM Invalid drive or file name
;---------------------- 			;
Message_Number	= 5
Handle		= STDERR
Sublist 	EQU <None>
Count		= N_A
Class		= UTILITY_MSG_CLASS
Function	= NO_INPUT
Input		= N_A
	Define_Msg   dirmsg			; AN000;SM Warning - directory full
;---------------------- 			;
Message_Number	= 6
Handle		= STDERR
Sublist 	EQU <None>
Count		= N_A
Class		= UTILITY_MSG_CLASS
Function	= NO_INPUT
Input		= N_A
	Define_Msg   NotNetM			; AN000;SM Cannot recover a Network drive
;---------------------- 			;
ifdef fsexec
 Message_Number  = 7				 ;
 Handle 	 = STDERR			 ;
 Sublist	 = Sublist_msg_EXECFailure	 ;
 Count		 = 1				 ;
 Class		 = UTILITY_MSG_CLASS		 ;
 Function	 = NO_INPUT			 ;
 Input		 = N_A				 ;
	 Define_Msg   MsgEXECFailure		 ;RECOVER not avail. on drive %1
endif
;---------------------- 			;
Message_Number	= 8
Handle		= STDout
Sublist 	EQU <Sublist_msg_recmsg>
Count		= 1
Class		= UTILITY_MSG_CLASS
Function	= NO_INPUT
Input		= N_A
	Define_Msg   recmsg			; AN000;SM %1 file(s) recovered
;---------------------- 			;
Message_Number	= 9
Handle		= STDout
Sublist 	EQU <Sublist_msg_ofmsg>
Count		= 2
Class		= UTILITY_MSG_CLASS
Function	= NO_INPUT
Input		= N_A
	Define_Msg   ofmsg_ptr			; AN000;SM %1 of %2 bytes recovered
;---------------------- 			;
Message_Number	=  10
Handle		= STDout
Sublist 	EQU <drive_sublist>
Count		= 1
Class		= UTILITY_MSG_CLASS
Function	= NO_INPUT
Input		= N_A
	Define_Msg   askmsg			; AN000;SM Press any key...
;---------------------- 			;
Message_Number	= 11
Handle		= STDERR
Sublist 	EQU <None>
Count		= N_A
Class		= Utility_Msg_Class
Function	= NO_INPUT
Input		= N_A
	Define_Msg   FATerrRead 		; AN000;SM Can not read File allocation table(s)
;---------------------- 			;
Message_Number	= 12
Handle		= STDERR
Sublist 	EQU <None>
Count		= N_A
Class		= Utility_Msg_Class
Function	= NO_INPUT
Input		= N_A
	Define_Msg   FATerrWrite		; AN000;SM Can not write file allocation table(s)
;---------------------- 			;
Message_Number	= 13				; AN000;MT
Handle		= STDout			; AN000;MT
Sublist 	EQU <None>				; AN000;MT
Count		= N_A				; AN000;MT
Class		= Utility_Msg_Class		; AN000;MT
Function	= NO_INPUT			; AN000;MT
Input		= N_A				; AN000;MT
	Define_Msg   CRLF_Ptr			; AN000;MT CR,LF
;---------------------------			;
Message_Number	= 0				;
Handle		= STDERR			;
Sublist 	EQU <None>				;
Count		= N_A				;
Class		= Ext_Err_Class 		;
Function	= No_Input			;
Input		=N_A				;
	Define_Msg  Extended_Error_Msg		;
;---------------------------			;
;-----------------------
Message_Number	= 0				;
Handle		= STDERR			;
Sublist 	EQU <dg:sublist_msg_parserr>	;				;an031;bgbbgb000;
Count		= 1				;
Class		= Parse_Err_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	Parse_Error_Msg 	;
;---------------------- 			;
Message_Number	= 14
Handle		= STDERR
Sublist 	EQU <None>
Count		= None
Class		= utility_msg_class
Function	= NO_INPUT
Input		= N_A
	Define_Msg   no_mem_arg 		; AN013;bgb insufficient memory


Data ends
;	extrn	Drive_Letter_Msg:Byte
;	extrn	FName_Buffer:Byte
