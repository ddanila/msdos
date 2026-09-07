;fsexec equ true
const	segment public para 'const'
Len_FS_ID_String equ 8			; length of fat_12 and fat_16 strings
Command_Line_Length equ 128		; length of command line area
Len_FS_String_End equ 8 		; length of rec.exe + 0H
FALSE	EQU	0
;TRUE	 EQU	 -1

bdos	equ	21h
boot	equ	20h
aread	equ	25h
awrite	equ	26h


;IBMVER	EQU	false ; not for single drive system
;KANJI	EQU	true  ; set this to true for assembling jap version
tab	equ	09h
aread	equ	25h
awrite	equ	26h
fcb	equ	5ch
FCB1	equ	5Ch
FCB2	equ	6Ch
FCB_Filename_Length	equ	11

NO			equ	0
YES			equ	not NO


Not_Include		equ	0
Do_Include		equ	1

No_Ext_Attrib		equ	0
No_Entry		equ	0


FAT12_File_System	equ 01h
FAT16_File_System	equ 04h
New_File_System 	equ 06h

Bad_Exit		equ	0FFh			;Errorlevel = 0FFh

Net_Check		equ   1200h
Assign_Check		equ 8000h

DBCS_Lead		equ	81h
DBCS_Blank		equ  40h
DBCS_Vector_Size	equ 2
End_Of_Vector		equ 0
Blank			equ	" "

Found_Yes		equ   1
Found_No		equ    0

Asciiz_End		equ  0

Dir_Attribute		equ	10h
Vol_Attribute		equ	08h

Dir_Entries_Per_Sector	equ	512/32


Critical_Error_Fail	equ	3
Write_Protect		equ	0
Drive_Not_Ready 	equ	2


Len_FS_String_Buffer	equ	13

;Limits
BIG_FAT_THRESHOLD	equ 4086

; equates from recinit
;***********************************************
Multiplex		equ   2Fh			      ;
Set_Append_X		equ 0B707h			   ;			;AN000;;
Append_X		equ    0B706h			       ;		;AN000;;
Append_X_Set		equ 1				   ;
Append_Off		equ  0				     ;
Append_ON		equ   1 			      ;
fcb1			equ	05ch		;

String_Done equ 0
No_Error equ	0
rec_error   equ     1
Stderr	equ	2
Len_FS_String_Buffer equ 13



;-------------------------------------------------------------------------------
; DATA STRUCTURES
;-------------------------------------------------------------------------------

Exec_Block_Parms struc
Segment_Env	dw  0
Offset_Command	dw  0
Segment_Command dw  0
Offset_FCB1	dw  0
Segment_FCB1	dw  0
Offset_FCB2	dw  0
Segment_FCB2	dw  0

Exec_Block_Parms ends



;-------------------------------------------------------------------------------
; media id
;-------------------------------------------------------------------------------
Media_ID struc
Media_ID_Info_Level dw 0
Media_ID_Serial_Number dd 0
Media_ID_Volume_Label db 11 dup(" ")
Media_ID_File_System db 8  dup(" ")
Media_ID ends

;-------------------------------------------------------------------------------
; device parameters
;-------------------------------------------------------------------------------
A_DeviceParameters	struc

SpecialFunctions	db	?
DeviceType		db	?
DeviceAttributes	dw	?
NumberOfCylinders	dw	?
MediaType		db	?
BytePerSector		dw	?
SectorsPerCluster	db	?
ReservedSectors 	dw	?
NumberOfFATs		db	?
RootEntries		dw	?
TotalSectors		dw	?
MediaDescriptor 	db	?
SectorsPerFAT		dw	?
SectorsPerTrack 	dw	?
Heads			dw	?
HiddenSectors		dd	?
Ext_Total_Sectors	dd	?
Reserved_Area		db	6 dup(?)

A_DeviceParameters	ends




;-------------------------------------------------------------------------------
; relative sector buffer
;-------------------------------------------------------------------------------
Relative_Sector_Buffer	struc			;

Start_Sector_Low	dw	?		;Low word of RBA sector
Start_Sector_High	dw	?		;High word of RBA sector
Number_Sectors		dw	?		;Number of sectors
Buffer_Offset		dw	?		;Address of data buffer
Buffer_Segment		dw	?		;

Relative_Sector_Buffer ends			;


;-------------------------------------------------------------------------------
; xal ????
;-------------------------------------------------------------------------------
XAL	struc

XAL_Tsize	dw	?
XAL_TCount	dw	?
XAL_LSize	dw	?
XAL_LCount	dw	?
XAL_Data	db	512-8 dup(?)

XAL	ends

;-------------------------------------------------------------------------------
const	ends
