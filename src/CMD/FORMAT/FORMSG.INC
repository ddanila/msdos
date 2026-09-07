;

;
;*****************************************************************************
; Macro's
;*****************************************************************************
;


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
; External data declarations
;*****************************************************************************
;

	Extrn	DriveLetter:Byte
	Extrn	SystemDriveLetter:Byte
	Extrn	CurrentHead:Byte
	Extrn	CurrentCylinder:Word
	Extrn	FdskSiz:Word
	Extrn	SysSiz:Word
	Extrn	BadSiz:Word
	Extrn	DataSiz:Word
	Extrn	Drive_Letter_Msg:Byte
	Extrn	PercentComplete:Byte
	Extrn	AllocSize:Dword
	Extrn	AllocNum:Word
	Extrn	Serial_Num_Low:Word
	Extrn	Serial_Num_High:Word
	Extrn	Command_Old_Ptr:Word
	Extrn	Msg_Allocation_Unit_Val:Dword

;
;*****************************************************************************
; Publics
;*****************************************************************************
;



;
;*****************************************************************************
; Message Retriever equates
;*****************************************************************************
;

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




data	segment public	para	'DATA'
	assume	ds:data


;
;*****************************************************************************
; Message Sublist Tables
;*****************************************************************************
;
;The  following  control  blocks  are	used   for   messages  with
;replaceable  paramaters.  These  control  blocks  are	used by  the
;SysDispMsg routine.
;

;---------------------------			;
Sublist_msgCurrentTrack label dword		;
						;
	db		Sublist_Length		;
	db		Reserved		;
	dw		offset PercentComplete	;
	dw		data			;
	db		1			;
	db		Right_Align+Unsgn_Bin_Word ;
	db		3			;Max % is 100
	db		3			;Min % is 0
	db		Blank			;
;---------------------------			;
Sublist_msgInsertDisk	label dword		;
Sublist_msgReInsertDisk label dword		;
Sublist_MsgHardDiskWarning label dword		;
Sublist_msgFormatNotSupported label dword	;

	db		Sublist_Length		;
	db		Reserved		;
	dw		offset DriveLetter	;
	dw		data			;
	db		1			;
	db		Left_Align+Char_Field_Char ;
	db		1			;
	db		1			;
	db		Blank			;
;---------------------------			;
Sublist_msgInsertDOSDisk label dword		;
						;
	db		Sublist_Length		;
	db		Reserved		;
	dw		offset SystemDriveLetter;
	dw		data			;
	db		1			;
	db		Left_Align+Char_Field_Char ;
	db		1			;
	db		1			;
	db		Blank			;
;---------------------------			;
Sublist_msgTotalDiskSpace label dword		;
						;
	db		Sublist_Length		;
	db		Reserved		;
	dw		offset FdskSiz		;
	dw		data			;
	db		1			;
	db		Right_Align+Unsgn_Bin_Dword ;
	db		10			;
	db		10			;4,000,000,000 limit
	db		Blank			;
;---------------------------			;
Sublist_msgSystemSpace	label dword		;
						;
	db		Sublist_Length		;
	db		Reserved		;
	dw		offset SysSiz		;
	dw		data			;
	db		1			;
	db		Right_Align+Unsgn_Bin_DWord ;
	db		10			;
	db		10			;64k*3 max
	db		Blank			;
;---------------------------			;
Sublist_msgBadSpace	label dword		;
						;
	db		Sublist_Length		;
	db		Reserved		;
	dw		offset BadSiz		;
	dw		data			;
	db		1			;
	db		Right_Align+Unsgn_Bin_DWord ;
	db		10			;
	db		10			;4,000,000,000 max
	db		Blank			;
;---------------------------			;
Sublist_msgDataSpace	label dword		;
						;
	db		Sublist_Length		;
	db		Reserved		;
	dw		Offset DataSiz		;
	dw		data			;
	db		1			;
	db		Right_Align+Unsgn_Bin_DWord ;
	db		10			;
	db		10			;4,000,000,000 max
	db		Blank			;
;---------------------------			;
Sublist_msgWhatIsVolumeId?  label dword 	;
						;
	db		Sublist_Length		;
	db		Reserved		;
	dw		offset DriveLetter	;
	dw		data			;
	db		1			;
	db		Left_Align+Char_Field_Char ;
	db		1			;
	db		1			;
	db		Blank			;
;---------------------------			;
Sublist_msgEXECFailure	label dword		;
						;
	db		Sublist_Length		;
	db		Reserved		;
	dw		Drive_Letter_Msg	;
	dw		data			;
	db		1			;
	db		Left_Align+Char_Field_ASCIIZ ;
	db		2			;
	db		2			;
	db		Blank			;
;---------------------------			;
Sublist_msgAllocNum	label dword		;
						;
	db		Sublist_Length		;
	db		Reserved		;
	dw		offset AllocNum 	;
	dw		data			;
	db		1			;
	db		Right_Align+Unsgn_Bin_Word ;
	db		10			;
	db		10			;
	db		Blank			;
;---------------------------			;
Sublist_msgAllocSize	label dword		;
						;
	db		Sublist_Length		;
	db		Reserved		;
	dw		offset AllocSize	;
	dw		data			;
	db		1			;
	db		Right_Align+Unsgn_Bin_DWord ;
	db		10			;
	db		10			;
	db		Blank			;
;---------------------------			;
Sublist_msgSerialNumber label dword		;
						;
	db		Sublist_Length		;
	db		Reserved		;
	dw		offset Serial_Num_Low	;
	dw		data			;
	db		1			;
	db		Right_Align+Bin_Hex_Word ;
	db		4			;
	db		4			;
	db		'0'                     ;Display leading 0's
	db		Sublist_Length		;
	db		Reserved		;
	dw		offset Serial_Num_High	;
	dw		data			;
	db		2			;
	db		Right_Align+Bin_hex_Word ;
	db		4			;
	db		4			;
	db		'0'                     ;

Public	Sublist_MsgParse_Error
Sublist_msgParse_Error	      label dword	;

	db		Sublist_Length		;
	db		Reserved		;
	dw		0			;
	dw		Data			;
	db		0			;
	db		Left_Align+Char_Field_ASCIIZ ;
	db		20			;
	db		01			;
	db		Blank			;
;---------------------------			;
Sublist_MsgVerify	label dword		;
						;
	db		Sublist_Length		;
	db		Reserved		;
	dw		offset Msg_Allocation_Unit_Val;
	dw		data			;
	db		1			;
	db		Right_Align+Unsgn_Bin_DWord;
	db		8			;
	db		8			;
	db		Blank
;
;*****************************************************************************
; Message Description Tables
;*****************************************************************************
;

;---------------------- 			;
Message_Number	= 1				;
Handle		= No_Handle			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Input			;
Input		= N_A				;
	Define_Msg	msgBadDOSVersion	;
;---------------------- 			;
Message_Number	= 2				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_msgCurrentTrack>	;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Input			;
Input		= N_A				;
	Define_Msg	msgCurrentTrack 	;
;---------------------- 			;
Message_Number	= 3				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_msgDataSpace>		;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgDataSpace		;
;---------------------- 			;
Message_Number	= 4				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Input			;
Input		= N_A				;
	Define_Msg	msgFormatComplete	;
;---------------------- 			;
Message_Number	= 5				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_msgBadSpace>		;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgBadSpace		;
;---------------------- 			;
Message_Number	= 6				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_msgTotalDiskSpace>	;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgTotalDiskSpace	;
;---------------------- 			;
Message_Number	= 7				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_msgInsertDisk> 	;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgInsertDisk		;
;---------------------- 			;
Message_Number	= 8				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_msgSystemSpace>	;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgSystemSpace		;
;---------------------- 			;
Message_Number	= 9				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_msgReInsertDisk>	;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg   msgReInsertDisk		;
;---------------------- 			;
Message_Number	= 10				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgLabelPrompt		;
;---------------------- 			;
Message_Number	= 11				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_msgFormatNotSupported> ;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgFormatNotSupported	;
;---------------------- 			;
Message_Number	= 12				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgInvalidDeviceParameters;
;---------------------- 			;
Message_Number	= 13				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgErrorInIOCTL 	;
;---------------------- 			;
Message_Number	= 14				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgNotBlockDevice	;
;---------------------- 			;
Message_Number	= 15				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgFATwriteError	;
;---------------------- 			;
Message_Number	= 16				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgDirectoryWriteError	;
;---------------------- 			;
Message_Number	= 17				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgAssignedDrive	;
;---------------------- 			;
Message_Number	= 18				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgNoSystemFiles	;
;---------------------- 			;
Message_Number	= 19				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgNetDrive		;
;---------------------- 			;
Message_Number	= 20				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgBadCharacters	;
;---------------------- 			;
Message_Number	= 21				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgParametersNotSupported ;
;---------------------- 			;
Message_Number	= 22				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgFormatFailure	;
;---------------------- 			;
Message_Number	= 23				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgNotSystemDisk	;
;---------------------- 			;
Message_Number	= 24				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgDiskUnusable 	;
;---------------------- 			;
Message_Number	= 25				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgBootWriteError	;
;---------------------- 			;
Message_Number	= 26				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgDirectoryReadError	;
;---------------------- 			;
Message_Number	= 27				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgNeedDrive		;
;---------------------- 			;
Message_Number	= 28				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	ContinueMsg		;
;---------------------- 			;
Message_Number	= 29				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgBadVolumeId		;
;---------------------- 			;
Message_Number	= 30				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Input			;
Input		= N_A				;
	Define_Msg	msgSystemTransfered	;
;---------------------- 			;
Message_Number	= 31				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_msgWhatIsVolumeId?>	;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgWhatIsVolumeId?	;
;---------------------- 			;
Message_Number	= 32				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgIncompatibleParametersForHardDisk ;
;---------------------- 			;

Message_Number	= 33				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgWriteProtected	;
;---------------------- 			;
Message_Number	= 34				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgNotReady		;
;---------------------- 			;

Message_Number	= 35				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgPartitionTableReadErr ;
;---------------------- 			;
Message_Number	= 36				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_msgSerialNumber>	;
Count		= 2				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgSerialNumber 	;
;---------------------- 			;
Message_Number	= 37				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgFormatBroken 	;
;---------------------- 			;
Message_Number	= 38				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_msgEXECFailure>	;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgEXECFailure		;
;---------------------- 			;
Message_Number	= 39				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	NO_SYS_MESS		;
;---------------------- 			;
Message_Number	= 40				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgbadpartitiontable	;
;---------------------- 			;
Message_Number	= 41				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgParametersNotSupportedByDrive ;
;---------------------- 			;
Message_Number	= 42				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgCRLF 		;
;---------------------- 			;
Message_Number	= 43				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgInterrupt		;
;---------------------- 			;
Message_Number	= 44				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_MsgInsertDOSDisk>	;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgInsertDOSDisk	;
;---------------------- 			;
Message_Number	= 45				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_MsgHardDiskWarning>	;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgHardDiskWarning	;
;---------------------- 			;
Message_Number	= 46				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgFormatAnother?	;
;---------------------- 			;
Message_Number	= 47				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgPartitionTableReadError ;
;---------------------- 			;
Message_Number	= 48				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgPartitionTableWriteError ;
;---------------------- 			;
Message_Number	= 49				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgIncompatibleParameters ;
;---------------------- 			;
Message_Number	= 50				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_MsgAllocNum>		;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgAllocNum		;
;---------------------- 			;
Message_Number	= 51				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_MsgAllocSize>		;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgAllocSize		;
;---------------------- 			;
Message_Number	= 52				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgPartitionTableWriteErr ;
;---------------------- 			;
Message_Number	= 53				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgSameSwitch		;
;---------------------- 			;
Message_Number	= 54				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	msgBad_T_N		;
;---------------------- 			;
Message_Number	= 55				;
Handle		= STDOUT			;
Sublist 	EQU <Sublist_MsgVerify>		;
Count		= 1				;
Class		= Utility_Msg_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	MsgVerify		;
;---------------------- 			;
Message_Number	= 0				;
Handle		= STDERR			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Ext_Err_Class 		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	Extended_Error_Msg	;
;----------------------
Message_Number	= 0				;
Handle		= STDERR			;
Sublist 	EQU <Sublist_MsgParse_Error>	;
Count		= 1				;
Class		= Parse_Err_Class		;
Function	= No_Function			;
Input		= N_A				;
	Define_Msg	Parse_Error_Msg 	;
;-----------------------



;
;These need to be coded as extended an parse errors, but left here to link.
;



Message_Number	= 70				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Input			;
Input		= N_A				;
	Define_Msg	msgOutOfMemory		;
;---------------------- 			;
Message_Number	= 71				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Input			;
Input		= N_A				;
	Define_Msg	msgBadDrive		;
;---------------------- 			;
Message_Number	= 10				;
Handle		= StdErr			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Parse_Err_Class		;
Function	= No_Input			;
Input		= N_A				;
	Define_Msg	msgInvalidParameter	;
;---------------------- 			;
Message_Number	= 73				;
Handle		= STDOUT			;
Sublist 	EQU <No_Replace>			;
Count		= N_A				;
Class		= Utility_Msg_Class		;
Function	= No_Input			;
Input		= N_A				;
	Define_Msg	msgLoadFailure		;









data ends


