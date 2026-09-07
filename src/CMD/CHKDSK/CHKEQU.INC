;fsexec  equ	 true			     ;				     ;	 ;an038;bgb  ;
FCB	EQU	5CH

String_Done equ 0
No_Error equ	0
chk_Error   equ     1
Stderr	equ	2

FALSE	EQU	0
TRUE	EQU	(NOT FALSE) AND 0FFFFh	; JWASM: mask NOT to 16 bits (jwasm leaves NOT wide -> != DOSSYM 0FFFFh -> A2143)

; NOTE WARNING DANGER.
; THIS EQU DEFINES AN OFFSET INTO THE SEARCH FCB OF THE LASTENT VALUE.
; ITS LOCATION MAY CHANGE FROM DOS VERSION TO DOS VERSION.
;2.0/2.1 value
;THISENT EQU	 17H			 ;Relative entry number of current entry
;3.0 value
THISENT EQU	14H				;Relative entry number of current entry


;Attribute bits

RDONLY	EQU	1
HIDDN	EQU	2
SYSTM	EQU	4
VOLIDA	EQU	8
ISDIR	EQU	10H
DRVCHAR EQU	":"
;
;*****************************************************************************
; Equates
;*****************************************************************************
;

Multiplex equ	2Fh				;
Set_Append_X equ 0B707h 			;				;AN000;;
Append_X equ	0B706h				;				;AN000;;
Append_X_Set equ 1				;
Append_Off equ	0				;
Append_ON equ	1				;


Disk_Error	equ	80h			;INT 24h bit clear if disk error

NO	equ	0
YES	equ	not NO

Year_Mask	equ	0FE00h
Month_Mask	equ	01E0h
Day_Mask	equ	001Fh
Hour_Mask	equ	0F800h
Minute_Mask	equ	07E0h

Not_Include	equ	0
Do_Include	equ	1


YES_Found equ	1
NO_Found equ	0

ON	equ	1
OFF	equ	0

No_Ext_Attrib	equ	0
No_Entry	equ	0
XA_Chain	equ	84h			;Mark head of XA chain

ifdef	fsexec
Len_FS_String_Buffer	equ	13
FAT12_File_System equ 01h
FAT16_File_System equ 04h
New_File_System equ 06h
endif

Bad_Exit	equ	0FFh			;Errorlevel = 0FFh

Net_Check equ	1200h
Assign_Check equ 8000h

Found_Yes equ	1
Found_No equ	0

Asciiz_End equ	0

Dir_Attribute	equ	10h
Vol_Attribute	equ	08h

Dir_Entries_Per_Sector	equ	512/32


Critical_Error_Fail	equ	3
Write_Protect	equ	0
Drive_Not_Ready equ	2

Blank	equ	" "

Head_Mask	equ	7Fh			;Mask to turn off head bit


;Limits
BIG_FAT_THRESHOLD equ 4086



;-------------------------------------------------------------------------------
; These are the data structures which we will need
;****************************************************************************
; Structures
;****************************************************************************
ifdef	fsexec
Exec_Block_Parms struc
Segment_Env dw	0
Offset_Command dw 0
Segment_Command dw 0
Offset_FCB1 dw	0
Segment_FCB1 dw 0
Offset_FCB2 dw	0
Segment_FCB2 dw 0
Exec_Block_Parms ends

Media_ID struc
Media_ID_Info_Level dw 0
Media_ID_Serial_Number dd 0
Media_ID_Volume_Label db 11 dup(" ")
Media_ID_File_System db 8  dup(" ")
Media_ID ends
endif

Sublist_Struc struc
Sublist_Size	db	?			;
Sublist_Rsv	db	?			;
Sublist_Offset	dw	?			;
Sublist_Segment dw	?			;
Sublist_Number	db	?			;
Sublist_Type	db	?			;
Sublist_Max	db	?			;
Sublist_Min	db	?			;
Sublist_Char	db	?			;
Sublist_Struc ends

Chk_DeviceParameters	struc

SpecialFunctions	db	?    ;1  0
DeviceType		db	?    ;1  1
DeviceAttributes	dw	?    ;2  2
NumberOfCylinders	dw	?    ;2  4
MediaType		db	?    ;1  6
BytePerSector		dw	?    ;2  7
SectorsPerCluster	db	?    ;
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
ReservedArea		db	6 dup(?)

Chk_DeviceParameters	ends




Relative_Sector_Buffer	struc			;

Start_Sector_Low	dw	?		;Low word of RBA sector
Start_Sector_High	dw	?		;High word of RBA sector
Number_Sectors		dw	?		;Number of sectors
Buffer_Offset		dw	?		;Address of data buffer
Buffer_Segment		dw	?		;

Relative_Sector_Buffer ends			;


XAL	struc

XAL_Tsize	dw	?
XAL_TCount	dw	?
XAL_LSize	dw	?
XAL_LCount	dw	?
XAL_Data	db	512-8 dup(?)

XAL	ends

DIRENT	STRUC
	DB	7 DUP (?)		;Ext FCB junk
	DB	?			;Drive
DIRNAM	DB	11 DUP (?)			;
DIRATT	DB	?				;
DIRCP	DW	?				;
DIR_XA	DW	?				;
DIRATT2 db	?				;
DIRRES	DB	5 DUP (?)			;
DIRTIM	DW	?				;
DIRDAT	DW	?				;
DIRCLUS DW	?				;
DIRESIZ DD	?				;
DIRENT	ENDS					;
ENTSIZ	EQU	SIZE DIRENT

;-------------------------------------------------------------------------------

