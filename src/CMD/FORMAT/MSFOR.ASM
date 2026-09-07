; e forproc.sal= @(#)ibmfor.asm 1.28 85/10/15
	name	OemFormatRoutines
INCLUDE FORCHNG.INC
debug	equ	0
;-------------------------------------------------------------------------------
; Public for debugging only

	public	CheckSwitches
	public	LastChanceToSaveIt
	public	WriteBootSector
	public	OemDone
	public	WriteBogusDos
	public	ConvertToOldDirectoryFormat
	public	SetPartitionTable
	public	ReadSector
	public	WriteSector
	public	SectorIO
	public	GetVolumeId

	public	customBPBs
	public	NotSlashB
	public	NotSingleSided
	public	EndSwitchCheck
	public	WeCanNotIgnoreThisError
	public	HardDisk?
	public	BogusDos
	public	sys_mess_loop
	public	end_sys_loop
	public	DirectoryRead
	public	wrtdir
	public	DirectoryWritten
	public	FCBforVolumeIdSearch
	public	CopyVolumeId
	public	CompareVolumeIds
	public	BadVolumeId

	public	boot2
	public	boot
	public	scratchBuffer
	public	biosFilename
	public	dosFilename
	public	oldDrive
	public	oldVolumeId
	public	Read_Write_Relative
	public	Serial_Num_Low
	public	Serial_Num_High
	public	SizeMap

	public	ptr_msgWhatIsVolumeId?

	public	trackReadWritePacket

	public	BPB81
	public	BPB82
	public	BPB91
	public	BPB92

;-------------------------------------------------------------------------------

data	segment public para 'DATA'
data	ends

code	segment public para 'CODE'
	assume	cs:code,ds:data
	extrn	AddToSystemSize:near

	Public	AccessDisk
	public	CheckSwitches
	public	LastChanceToSaveIt
	public	OemDone
	public	BiosFile
	public	DosFile

data	segment public	para	'DATA'
	extrn	currentCylinder:word
	extrn	currentHead:word
	extrn	deviceParameters:byte
	extrn	drive:byte
	extrn	driveLetter:byte
	extrn	fBigFAT:byte
	extrn	inbuff:byte
	extrn	switchmap:word
	extrn	Old_Dir:byte
	extrn	fLastChance:byte
	extrn	Fatal_Error:Byte
	extrn	Bios:Byte
	extrn	Dos:Byte
	extrn	Command:Byte

	extrn	msgBad_T_N:byte
	extrn	msgBadVolumeId:byte
	extrn	msgBadPartitionTable:byte
	extrn	msgBootWriteError:byte
	extrn	msgDirectoryReadError:byte
	extrn	msgDirectoryWriteError:byte
	extrn	msgInvalidParameter:byte
	extrn	msgIncompatibleParameters:byte
	extrn	msgIncompatibleParametersForHardDisk:byte
	extrn	msgParametersNotSupportedByDrive:byte
	extrn	msgPartitionTableReadError:byte
	extrn	msgPartitionTableWriteError:byte
	extrn	msgWhatIsVolumeId?:byte
	extrn	NumSectors:word, TrackCnt:word

IF	DEBUG
	extrn	msgFormatBroken:byte
ENDIF

data	ends

	extrn	PrintString:near
	extrn	std_printf:near
	extrn	crlf:near
	extrn	user_string:near
	extrn	Read_Disk:near
	extrn	Write_Disk:near


;-------------------------------------------------------------------------------
; Constants

.xlist
INCLUDE DOSMAC.INC
INCLUDE FORMACRO.INC
INCLUDE FOREQU.INC
INCLUDE FORSWTCH.INC

; This defines all the int 21H system calls
INCLUDE SYSCALL.INC

; Limits

INCLUDE filesize.inc

;-------------------------------------------------------------------------------
; These are the data structures which we will need

INCLUDE DIRENT.INC
INCLUDE ioctl.INC
INCLUDE version.inc

.list

;-------------------------------------------------------------------------------
; And this is the actual data
data	segment public	para	'DATA'

Read_Write_Relative Relative_Sector_Buffer <>	;


	IF IBMCOPYRIGHT
BiosFile db	"x:\IBMBIO.COM", 0
DosFile db	"x:\IBMDOS.COM", 0
	ELSE
BiosFile db	"x:\IO.SYS", 0
DosFile db	"x:\MSDOS.SYS", 0
	ENDIF

Dummy_Label db	"NO NAME    "
Dummy_Label_Size dw  11

Serial_Num_Low dw 0				;
Serial_Num_High dw 0				;

SizeMap db	0				;

trackReadWritePacket a_TrackReadWritePacket <>


; BIOS parameter blocks for various media
customBPBs label byte
BPB92	a_BPB	<512, 2, 1, 2, 112, 2*9*40, 0fdH, 2, 9, 2, 0, 0, 0, 0>
BPB91	a_BPB	<512, 1, 1, 2,	64, 1*9*40, 0fcH, 2, 9, 1, 0, 0, 0, 0>
BPB82	a_BPB	<512, 2, 1, 2, 112, 2*8*40, 0ffH, 1, 8, 2, 0, 0, 0, 0>
BPB81	a_BPB	<512, 1, 1, 2,	64, 1*8*40, 0feH, 1, 8, 1, 0, 0, 0, 0>
BPB720	a_BPB	<512, 2, 1, 2, 112, 2*9*80, 0F9h, 3, 9, 2, 0, 0, 0, 0>
BPB2880	a_BPB	<512, 2, 1, 2, 240, 5760, 0F0h, 9, 36, 2, 0, 0, 0, 0>



boot2	db	0,0,0, "Boot 1.x"
	db	512 - 11 dup(?)

REORG2	LABEL	BYTE
	ORG	BOOT2
	INCLUDE BOOT11.INC
	ORG	REORG2



INCLUDE BOOTFORM.INC


BOOT	LABEL	BYTE
	INCLUDE BOOT.INC

scratchBuffer db 512 dup(?)

ptr_msgWhatIsVolumeId? dw offset msgWhatIsVolumeId?
	dw	offset driveLetter


FAT12_String db "FAT12   "
FAT16_String db "FAT16   "

Media_ID_Buffer Media_ID <>


data	ends
;-------------------------------------------------------------------------------
; AccessDisk:
;    Called whenever a different disk is about to be accessed
;
;    Input:
;	al - drive letter (0=A, 1=B, ...)
;
;    Output:
;	none
AccessDisk proc near

	push	ax				; save drive letter
	mov	bl,al				; Set up GENERIC IOCTL REQUEST preamble
	inc	bl
	mov	ax,(IOCTL SHL 8) + Set_Drv_Owner ; IOCTL function
	int	21h
	pop	ax
	return

AccessDisk endp

;-------------------------------------------------------------------------------
;    CheckSwitches:
;	Check switches against device parameters
;	Use switches to modify device parameters
;
;    Input:
;	deviceParameters
;
;    Output:
;	deviceParameters may be modified
;	Carry set if error
;
;
;  /B <> /S
;  /B/8 <> /V
;  /1 or /8 <> /T/N
;


Public	CHeckSwitches
CheckSwitches proc near

CheckExcl:

	test	SwitchMap,Switch_F		;Specify size?
;	$IF	NZ				;Yes
	JZ $$IF1
	   test    SwitchMap,(Switch_1+Switch_8+Switch_4+Switch_N+Switch_T)
;	   $IF	   NZ				;/F replaces above switches
	   JZ $$IF2
	      Message msgIncompatibleParameters ;Print error
	      mov     Fatal_Error,Yes		;Force exit
;	   $ELSE				;
	   JMP SHORT $$EN2
$$IF2:
	      call    Size_To_Switch		;Go set switches based
;	   $ENDIF				; on the size
$$EN2:
;	$ENDIF					;
$$IF1:
	cmp	Fatal_Error,NO			;
;	$IF	E				;
	JNE $$IF6
	   call    Check_Switch_8_B		;
	   call    Check_T_N
;	$ENDIF					;
$$IF6:
	cmp	Fatal_Error,Yes 		;
	jne	ExclChkDone			;
	stc					;
	ret					;

ExclChkDone:
; Patch the boot sector so that the boot strap loader knows what disk to
; boot from
;	 mov	 Boot.Boot_PhyDrv, 00H
	mov	Boot.EXT_PHYDRV, 00H		;AN00?;

	cmp	deviceParameters.DP_DeviceType, DEV_HARDDISK
	jne	CheckFor5InchDrives

; Formatting a hard disk so we must repatch the boot sector
;	 mov	 Boot.Boot_PhyDrv, 80H
	mov	Boot.EXT_PHYDRV, 80H		;AN00?;
	test	switchmap, not (SWITCH_S or SWITCH_V or SWITCH_Q or SWITCH_U or SWITCH_C or SWITCH_Select or SWITCH_AUTOTEST or Switch_B)
	jz	SwitchesOkForHardDisk

	Message msgIncompatibleParametersForHardDisk ;
	stc
	ret

; Before checking the Volume Id we need to verify that a valid one exists
; We assume that unless a valid boot sector exists on the target disk, no
; valid Volume Id can exist.

SwitchesOkForHardDisk:
	SaveReg <ax,bx,cx,dx,ds>
	mov	al,drive
	mov	cx,LogBootSect
	xor	dx,dx
	lea	bx,scratchBuffer		; ScratchBuffer := Absolute_Read_Disk(
						;INT	 25h				 ;		      Logical_sec_1 )

						;Assume Dir for vol ID exists in 1st 32mb of partition

	mov	Read_Write_Relative.Start_Sector_High,0
	call	Read_Disk			;
						;	on the stack. We throw them away

	jnc	CheckSignature
	stc
	RestoreReg <ds,dx,cx,bx,ax>
	ret

CheckSignature: 				; IF (Boot.Boot_Signature != aa55)

	mov	ax, word ptr ScratchBuffer.Boot_Signature
	cmp	ax, 0aa55h			;Find a valid boot record?
	RestoreReg <ds,dx,cx,bx,ax>
	clc					;No, so no need to check label
;	$IF	Z				;No further checking needed
	JNZ $$IF8
	   test    SwitchMap,(SWITCH_Select or SWITCH_AUTOTEST) ;Should we prompt for vol label?
;	   $IF	   Z				;Yes, if /Select not entered
	   JNZ $$IF9
	      call    CheckVolumeId		;Go ask user for vol label	;     ;
;	   $ELSE				;/Select entered
	   JMP SHORT $$EN9
$$IF9:
	      clc				;CLC indicates passed label test
;	   $ENDIF				; for the return
$$EN9:
;	$ENDIF
$$IF8:
	return

Incomp_Message: 				;an000; fix PTM 809

	Message msgIncompatibleParameters	;an000; print incompatible parms
	stc					;an000; signal error
	return					;an000; return to caller

Print_And_Return:
						;call	 PrintString			 ;
	stc
	return


CheckFor5InchDrives:

						;If drive type is anything other than 48 or 96, then only /V/S/H/N/T allowed
	cmp	byte ptr deviceParameters.DP_DeviceType,DEV_5INCH96TPI
	je	Got96

	cmp	byte ptr deviceParameters.DP_DeviceType,DEV_5INCH
	je	Got48

	xor	ax,ax								;an000; dms;clear reg
	or	ax,(Switch_V or Switch_S or Switch_Q or Switch_U or Switch_C or Switch_N or Switch_T or Switch_B) ;an000; dms;set up switch mask
	or	ax,(Switch_Backup or Switch_Select or Switch_Autotest)
IF ShipDisk
	or	ax,Switch_Z
ENDIF
	not	ax
	test	switchmap,ax							;an000; dms;invalid switch?
	jz	Goto_Got_BPB1							;an000;dms;continue format
	Message msgParametersNotSupportedByDrive ;
	jmp	short Print_And_Return

Goto_Got_BPB1:
	jmp	Goto_Got_BPB
						; We have a 96tpi floppy drive
						; /4 allows just about all switches however, /1 requires /4
Got96:
;;;DMS;;test	switchmap, SWITCH_8		;an000; If /8 we have an error
;;;DMS;;jnz	Incomp_message			;an000; tell user error

	test	switchmap, SWITCH_4
	jnz	CheckForInterestingSwitches	;If /4 check /N/T/V/S

	test	switchmap, SWITCH_1		;If /1 and /4 check others
	jz	Got48

						;If only /1 with no /4, see if /N/T
	test	SwitchMap,(Switch_N or Switch_T)
	jnz	CheckForInterestingSwitches

	jmp	Incomp_message			;an000; tell user error occurred

Got48:
						;Ignore /4 for non-96tpi 5 1/4" drives
	and	switchmap, not SWITCH_4

						;Ignore /1 if drive has only one head and not /8
	cmp	word ptr deviceParameters.DP_BPB.BPB_Heads, 1
	ja	CheckForInterestingSwitches
	test	switchmap, SWITCH_8
	jz	CheckForInterestingSwitches
	and	switchmap, not SWITCH_1

						;Are any interesting switches set?
CheckForInterestingSwitches:
	test	switchmap, not (SWITCH_V or SWITCH_S or SWITCH_Q or SWITCH_U or SWITCH_C or Switch_Backup or SWITCH_SELECT or SWITCH_AUTOTEST or Switch_B)
	jz	Goto_EndSwitchCheck		;No, everything ok

						;At this point there are switches other than /v/s/h
	test	SwitchMap,(SWITCH_N or SWITCH_T)
	jz	Use_48tpi			;Not /n/t, so must be /b/1/8/4

						;We've got /N/T, see if there are others
	test	SwitchMap, not (SWITCH_N or SWITCH_T or SWITCH_V or SWITCH_S or SWITCH_Q or SWITCH_U or SWITCH_C or Switch_Backup or SWITCH_SELECT or SWITCH_AUTOTEST)
	jz	NT_Compatible			;Nope, all is well

						;If 96tpi drive and /1 exists with /N/T, then okay, otherwise error
	cmp	byte ptr deviceParameters.DP_DeviceType,DEV_5INCH96TPI
	jne	Bad_NT_Combo

	test	SwitchMap, not (SWITCH_1 or SWITCH_N or SWITCH_T or SWITCH_V)
	jnz	Bad_NT_Combo
	test	SwitchMap, not (SWITCH_S or SWITCH_Q or SWITCH_U or SWITCH_C or Switch_Backup or SWITCH_SELECT or Switch_Autotest)
	jz	Goto_Got_BPB

Bad_NT_Combo:
	Message msgIncompatibleParameters	;
	jmp	Print_And_Return

Goto_Got_BPB:
	jmp	Got_BPB_Ok			;Sleazy, but je won't reach it

Goto_EndSwitchCheck:
	jmp	EndSwitchCheck
						;There is a problem with /N/T in that IBMBIO will default to a BPB with the
						;media byte set to F0 (other) if the /N/T combo is used for the format. This
						;will cause problems if we are creating a media that has an assigned media
						;byte, i.e. 160,180,320,360, or 720k media using /N/T. To avoid this problem,
						;if we detect a /N/T combo that would correspond to one of these medias, then
						; we will set things up using the /4/1/8 switches instead of the /N/T
						; MT - 7/17/86 PTR 33D0110

						; Combo's that we look for - 96tpi drive @ /T:40, /N:9
						;			     96tpi drive @ /T:40, /N:8
						;
						; Look for this combo after we set everything up with the /T/N routine
						;			     1.44 drive  @ /T:80, /N:9

NT_Compatible:
	cmp	byte ptr deviceParameters.DP_DeviceType,DEV_5INCH96TPI
	jne	Goto_Got_BPB

	cmp	TrackCnt,40			;Look for 40 tracks
	jne	Got_BPB_Ok

	cmp	NumSectors,9			;9 sectors?
	je	Found_48tpi_Type

	cmp	NumSectors,8			;8 sectors?
	jne	Goto_Got_BPB			;Nope, different type, let it go thru

	or	SwitchMap,SWITCH_8		;Yes, turn on /8 switch

Found_48tpi_Type:
	and	SwitchMap,not (SWITCH_N or SWITCH_T) ;Turn off /T/N

;******End PTR fix

; if we have a 96 tpi drive then we will be using it in 48 tpi mode
Use_48tpi:
	cmp	byte ptr deviceParameters.DP_DeviceType, DEV_5INCH96TPI
	jne	Not96tpi

	mov	byte ptr deviceParameters.DP_MediaType, 1
	mov	word ptr deviceParameters.DP_Cylinders, 40
Not96tpi:

; Since we know we are formatting in 48 tpi mode turn on /4 switch
; (We use this info in LastChanceToSaveIt)
	or	switchmap, SWITCH_4

; At this point we know that we will require a special BPB
; It will be one of:
;    0) 9 track 2 sides - if no switches
;    1) 9 track 1 side	- if only /1 specified
;    2) 8 track 2 sides - if only /8 specified
;    3) 8 track 1 side	- if /8 and /1 specified
;
Get_BPBs:
; ax is used to keep track of which of the above BPB's we want
	xor	ax, ax

NotSlashB:

	test	switchmap, SWITCH_1
	jz	NotSingleSided
	add	ax, 1
NotSingleSided:

	test	switchmap, SWITCH_8
	jz	Not8SectorsPerTrack
	add	ax, 2
; /8 implies Old_Dir = TRUE
	mov	Old_Dir,(TRUE) AND 0FFh
Not8SectorsPerTrack:

; Ok now we know which BPB to use so lets move it to the device parameters

	mov	bx, size a_BPB
	mul	bx
	lea	si, CustomBPBs
	add	si, ax
	lea	di, deviceParameters.DP_BPB
	mov	cx, size a_BPB
	push	ds
	pop	es
	rep	movsb

;*****************************************************************
;*  /N/T DCR stuff.  Possible flaw exists if we are dealing with a
;*  HardDisk. If they support the  "custom format" features for
;*  Harddisks too, then CheckForInterestingSwitches should
;*  consider /n/t UNinteresting, and instead of returning
;*  after setting up the custom BPB we fall through and do our
;*  Harddisk Check.
Got_BPB_OK:
	test	switchmap,SWITCH_N+SWITCH_T
	jnz	Setup_Stuff
	jmp	EndSwitchCheck
Setup_Stuff:
; Set up NumSectors and SectorsPerTrack entries correctly
	test	switchmap,SWITCH_N
	jz	No_Custom_Seclim
	mov	ax,word ptr NumSectors
	mov	DeviceParameters.DP_BPB.BPB_SectorsPerTrack,ax
	jmp	short Handle_Cyln
No_Custom_Seclim:
	mov	ax,deviceParameters.DP_BPB.BPB_SectorsPerTrack
	mov	NumSectors,ax

Handle_Cyln:
	test	switchmap,SWITCH_T
	jz	No_Custom_Cyln
; Set up TrackCnt and Cylinders entries correctly
	mov	ax,TrackCnt
	mov	DeviceParameters.DP_Cylinders,ax
	jmp	short Check_720
No_Custom_Cyln:
	mov	ax,DeviceParameters.DP_Cylinders
	mov	TrackCnt,ax

;****PTM P868  - Always making 3 1/2 media byte 0F0h. If 720, then set to
;		 0F9h and use the DOS 3.20 BPB. Should check all drives
;		 at this point (Make sure not 5 inch just for future
;		 protection)
;		 We will use the known BPB info for 720 3 1/2 diskettes for
;		 this special case. All other new diskette media will use the
;		 calculations that follow Calc_Total for BPB info.
; Fix MT  11/12/86

Check_720:

	cmp	TrackCnt,80
	jne	Check_720_Legacy
	cmp	NumSectors,36
	jne	Check_720_Legacy

; DOS 5 standard 2.88 MB FAT12 layout.
	SaveReg <ds,es,si,di,cx>
	mov	cx,seg data
	mov	ds,cx
	mov	es,cx
	mov	si,offset BPB2880
	mov	di,offset deviceParameters.DP_BPB
	mov	cx,size a_BPB
	rep	movsb
	RestoreReg <cx,di,si,es,ds>
	jmp	EndSwitchCheck

Check_720_Legacy:

	cmp	byte ptr deviceParameters.DP_DeviceType,DEV_5INCH96TPI
	je	Calc_Total

	cmp	byte ptr deviceParameters.DP_DeviceType,DEV_5INCH
	je	Calc_Total

	cmp	TrackCnt,80
	jne	Calc_Total

	cmp	NumSectors,9
	jne	Calc_Total

; At this point we know we have a 3 1/2 720kb diskette to format. Use the
; built in BPB rather than the one handed to us by DOS, because the DOS one
; will be based on the default for that drive, and it can be different from
; what we used in DOS 3.20 for the 720's. Short sighted on our part to use
; 0F9h as the media byte, should have use 0F0h (OTHER) and then we wouldn't
; have this problem.

	SaveReg <ds,es,si,di,cx>


	mov	cx,seg data			;Setup seg regs, just in case they ain't!
	mov	ds,cx
	mov	es,cx

	mov	si,offset BPB720		;Copy the BPB!
	mov	di,offset deviceParameters.DP_BPB
	mov	cx,size a_BPB
	rep	movsb
	RestoreReg <cx,di,si,es,ds>
	jmp	EndSwitchCheck

;End PTM P868 fix ****************************************

Calc_Total:
	mov	ax,NumSectors
	mov	bx,DeviceParameters.DP_BPB.BPB_Heads
	mul	bl				; AX = # of sectors * # of heads
	mul	TrackCnt			; DX:AX = Total Sectors
	or	dx,dx
	jnz	Got_BigTotalSectors
	mov	DeviceParameters.DP_BPB.BPB_TotalSectors,ax
	jmp	short Set_BPB
Got_BigTotalSectors:
	mov	DeviceParameters.DP_BPB.BPB_BigTotalSectors,ax
	mov	DeviceParameters.DP_BPB.BPB_BigTotalSectors+2,dx
	push	dx				; preserve dx for further use
	xor	dx,dx
	mov	DeviceParameters.DP_BPB.BPB_TotalSectors,dx
	pop	dx

Set_BPB:
; We calculate the number of sectors required in a FAT. This is done as:
; # of FAT Sectors = TotalSectors / SectorsPerCluster * # of bytes in FAT to
; represent one cluster (i.e. 3/2) / BytesPerSector (i.e. 512)
	xor	bx,bx
	mov	bl,DeviceParameters.DP_BPB.BPB_SectorsPerCluster
	div	bx				; DX:AX contains # of clusters
; now multiply by 3/2
	mov	bx,3
	mul	bx
	mov	bx,2
	div	bx
	xor	dx,dx				; throw away modulo
; now divide by 512
	mov	bx,512
	div	bx
; dx:ax contains number of FAT sectors necessary
	inc	ax				; Go one higher
	mov	DeviceParameters.DP_BPB.BPB_SectorsPerFAT,ax
	mov	DeviceParameters.DP_MediaType,0
	mov	DeviceParameters.DP_BPB.BPB_MediaDescriptor,Custom_Media


EndSwitchCheck:
	clc
	return

CheckSwitches endp

;*****************************************************************************
;Routine name: Size_To_Switch
;*****************************************************************************
;
;Description: Given the SizeMap field as input indicating the SIZE= value
;	      entered, validate that the specified size is valid for the
;	      drive, and if so, turn on the appropriate data fields and
;	      switches that would be turned on by the equivilent command line
;	      using only switchs. All defined DOS 4.00 sizes are hardcoded,
;	      in case a drive type of other is encountered that doesn't
;	      qualify as a DOS 4.00 defined drive. Exit with error message if
;	      unsupported drive. The switches will be setup for the CheckSwitches
;	      routine to sort out, using existing switch matrix logic.
;
;Called Procedures: Low_Density_Drive
;		    High_Capacity_Drive
;		    720k_Drives
;		    Other_Drives
;
;
;Input: SizeMap
;	Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;	 SwitchMap = appropriate Switch_?? values turned on
;	 TrackCnt, NumSectors set if Switch_T,Switch_N turned on
;*****************************************************************************


Procedure Size_To_Switch

	cmp	SizeMap,0			;Are there sizes entered?
;	$IF	NE				;Yes
	JE $$IF13
	   cmp	   deviceParameters.DP_DeviceType,DEV_HARDDISK
;	   $IF	   E				;No size for fixed disk
	   JNE $$IF14
	      Message msgIncompatibleParametersForHardDisk ;
;	   $ELSE				;Diskette, see what type
	   JMP SHORT $$EN14
$$IF14:
	      cmp     byte ptr deviceParameters.DP_DeviceType,DEV_5INCH ;
;	      $IF     E 			;Found 180/360k drive
	      JNE $$IF16
		 call	 Low_Density_Drive	;Go set switches
;	      $ELSE				;Check for 96TPI
	      JMP SHORT $$EN16
$$IF16:
		 cmp	 byte ptr deviceParameters.DP_DeviceType,DEV_5INCH96TPI ;AN001; ;
;		 $IF	 E			;Found it
		 JNE $$IF18
		    call    High_Capacity_Drive ;
;		 $ELSE				;
		 JMP SHORT $$EN18
$$IF18:
		    cmp     byte ptr deviceParameters.DP_DeviceType,DEV_3INCH720KB ;AN0001;
;		    $IF     E			;Found 720k drive
		    JNE $$IF20
		       call    Small_Drives	;
;		    $ELSE			;
		    JMP SHORT $$EN20
$$IF20:
		       cmp     byte ptr deviceParameters.DP_DeviceType,DEV_OTHER
;		       $IF     E		;Must be 1.44mb
		       JE $$IF21_OTHER
		       cmp     byte ptr deviceParameters.DP_DeviceType,DEV_3INCH2880KB
		       JNE $$IF22
$$IF21_OTHER:
			  call	  Other_Drives	;
;		       $ELSE			;
		       JMP SHORT $$EN22
$$IF22:
			  Message msgParametersNotSupportedByDrive ;
			  mov	  Fatal_Error,Yes ;
;		       $ENDIF			;
$$EN22:
;		    $ENDIF			;
$$EN20:
;		 $ENDIF 			;
$$EN18:
;	      $ENDIF				;
$$EN16:
;	   $ENDIF				;
$$EN14:
;	$ENDIF					;
$$IF13:
	cmp	Fatal_Error,Yes 		;
;	$IF	E				;
	JNE $$IF30
	   Message msgIncompatibleParameters	;
;	$ENDIF					;
$$IF30:

	cmp	deviceParameters.DP_DeviceType,DEV_HARDDISK
;	$if	e
	JNE $$IF32
		mov	Fatal_Error,Yes
;	$endif
$$IF32:

	and	SwitchMap,not Switch_F		;Turn off /F so doesn't effect
	ret					; following logic

Size_To_Switch endp

;*****************************************************************************
;Routine name: High_Capacity_Drive
;*****************************************************************************
;
;Description: See if 1.2mb diskette, or one of the other 5 1/4 sizes. Turn
;	      on /4 if 360k or lower
;
;Called Procedures: Low_Density_Drive
;
;
;Input: SizeMap
;	Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;	 SwitchMap = Switch_4 if 360k or lowere
;*****************************************************************************

Procedure High_Capacity_Drive			;

	test	SizeMap,Size_1200		;1.2mb diskette?
;	$IF	Z				;Nope
	JNZ $$IF34
	   call    Low_Density_Drive		;Check for /4 valid types
	   cmp	   Fatal_Error, No		;Find 160/180/320/360k?
;	   $IF	   E				;Yes
	   JNE $$IF35
	      or      SwitchMap,Switch_4	;Turn on /4 switch
;	   $ELSE				;Did not find valid size
	   JMP SHORT $$EN35
$$IF35:
	      mov     Fatal_Error,Yes		;Indicate invalid device
;	   $ENDIF				;
$$EN35:
;	$ENDIF					;
$$IF34:
	ret					;

High_Capacity_Drive endp

;*****************************************************************************
;Routine name: Low_Density_Drive
;*****************************************************************************
;
;Description: See if 360k diskete or one of the other 5 1/4 sizes. Turn
;	      on the /1/8 switch to match sizes
;
;Called Procedures: Low_Density_Drive
;
;
;Input: SizeMap
;	Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;	 SwitchMap = Switch_1, Switch_8 to define size
;
;	360k = No switch
;	320k = Switch_8
;	180k = Switch_1
;	160k = Switch_1 + Switch_8
;*****************************************************************************


Procedure Low_Density_Drive			;
						;
	test	SizeMap,Size_160		;
;	$IF	NZ				;
	JZ $$IF39
	   or	   SwitchMap,Switch_1+Switch_8	;
;	$ELSE					;
	JMP SHORT $$EN39
$$IF39:
	   test    SizeMap,Size_180		;
;	   $IF	   NZ				;
	   JZ $$IF41
	      or      SwitchMap,Switch_1	;
;	   $ELSE				;
	   JMP SHORT $$EN41
$$IF41:
	      test    SizeMap,Size_320		;
;	      $IF     NZ			;
	      JZ $$IF43
		 or	 SwitchMap,Switch_8	;
;	      $ELSE				;
	      JMP SHORT $$EN43
$$IF43:
		 test	 SizeMap,Size_360	;
;		 $IF	 Z			;None of the above, not valid
		 JNZ $$IF45
		    mov     Fatal_Error,Yes	;
;		 $ENDIF 			;
$$IF45:
;	      $ENDIF				;
$$EN43:
;	   $ENDIF				;
$$EN41:
;	$ENDIF					;
$$EN39:
	ret					;

Low_Density_Drive endp

;*****************************************************************************
;Routine name: Small_Drives
;*****************************************************************************
;
;Description: See if 720k media in 720 drive, set up /T/N if so, otherwise
;	      error
;
;Called Procedures: None
;
;
;Input: SizeMap
;	Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;	 SwitchMap
;	 TrackCnt
;	 NumSectors
;	720k = /T:80 /N:9
;*****************************************************************************

Procedure Small_Drives				;

	test	SizeMap,Size_720		;Ask for 720k?
;	$IF	Z				;Nope, thats all drive can do
	JNZ $$IF50
	   mov	   Fatal_Error,Yes		;Indicate error
;	$ENDIF					;
$$IF50:
	ret					;

Small_Drives endp


;*****************************************************************************
;Routine name: Other_Drives
;*****************************************************************************
;
;Description: See if 1.44 media or 720k media, setup /t/n, otherwise error
;
;Called Procedures: Small_Drives
;
;
;Input: SizeMap
;	Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;	 SwitchMap
;	 TrackCnt
;	 NumSectors
;	720k = /T:80 /N:9
;*****************************************************************************

Procedure Other_Drives				;

	test	SizeMap,Size_2880		;Ask for 2.88mb diskette?
	jz	Check_Other_1440
	or	SwitchMap,Switch_T+Switch_N	;2.88 MB is 80 tracks, 36 sectors
	mov	TrackCnt,80
	mov	NumSectors,36
	ret

Check_Other_1440:
	test	SizeMap,Size_1440		;Ask for 1.44mb diskette?
;	$IF	Z				;Nope
	JNZ $$IF52
	   call    Small_Drives 		;See if 720k
	   cmp	   Fatal_Error,No		;Fatal_error=Yes if not
;	   $IF	   E				;Got 720k
	   JNE $$IF53
	      or      SwitchMap,Switch_T+Switch_N ;Turn on /T:80 /N:9
	      mov     TrackCnt,80		;
	      mov     NumSectors,9		;
;	   $ENDIF				;
$$IF53:
;	$ELSE					;Asked for 1.44mb
	JMP SHORT $$EN52
$$IF52:
	   or	   SwitchMap,Switch_T+Switch_N	;Turn on /T:80 /N:18;
	   mov	   TrackCnt,80			;This will protect SIZE=1440
	   mov	   NumSectors,18		; from non-standard drives with
;	$ENDIF					; type of 'other'
$$EN52:
	ret					;

Other_Drives endp


;*****************************************************************************
;Routine name:Check_T_N
;*****************************************************************************
;
;Description: Make sure than if /T is entered, /N is also entered
;
;Called Procedures:  None
;
;
;Input: SizeMap
;	Fatal_Error = NO
;
;Output: Fatal_Error = YES/NO
;*****************************************************************************

Procedure Check_T_N

	test	SwitchMap,Switch_N		;Make sure /T entered if /N
;	$IF	NZ,AND				;
	JZ $$IF57
	test	SwitchMap,Switch_T		;
;	$IF	Z				;
	JNZ $$IF57
	   Message msgBad_T_N			;It wasn't, so barf
	   mov	   Fatal_Error,Yes		;Indicate error
;	$ELSE					;
	JMP SHORT $$EN57
$$IF57:
	   test    SwitchMap,Switch_T		;Make sure /N entered if /T
;	   $IF	   NZ,AND			;
	   JZ $$IF59
	   test    SwitchMap,Switch_N		;
;	   $IF	   Z				;It wasn't, so also barf
	   JNZ $$IF59
	      Message msgBad_T_N		;
	      mov     Fatal_Error,Yes		;Indicate error
;	   $ENDIF				;
$$IF59:
;	$ENDIF					;
$$EN57:
	ret

Check_T_N endp



;-------------------------------------------------------------------------------
;    LastChanceToSaveIt:
;	This routine is called when an error is detected in DiskFormat.
;	If it returns with carry not set then DiskFormat is restarted.
;	It gives the oem one last chance to try formatting differently.
;	fLastChance gets set Then to prevent multiple prompts from being
;	issued for the same diskette.
;
;	Algorithm:
;		IF (error_loc == Track_0_Head_1) &
;			  ( Device_type < 96TPI )
;		   THEN
;			fLastChance  := TRUE
;			try formatting 48TPI_Single_Sided
;		   ELSE return ERROR
;
LastChanceToSaveIt proc near

	cmp	currentCylinder, 0
	jne	WeCanNotIgnoreThisError
	cmp	currentHead, 1
	jne	WeCanNotIgnoreThisError

	cmp	deviceParameters.DP_DeviceType, DEV_5INCH
	ja	WeCanNotIgnoreThisError

	mov	fLastChance, (TRUE) AND 0FFh

	or	switchmap, SWITCH_1
	call	CheckSwitches
	clc
	ret

WeCanNotIgnoreThisError:
	stc
	ret

LastChanceToSaveIt endp

;-------------------------------------------------------------------------------


;*****************************************************************************
;Routine name WriteBootSector
;*****************************************************************************
;
;DescriptioN: Copy EBPB information to boot record provided by Get recommended
;	      BPB, write out boot record, error
;	      if can write it, then fill in new fields (id, etc..). The volume
;	      label will not be added at this time, but will be set by the
;	      create volume label call later.
;
;Called Procedures: Message (macro)
;
;
;Input: DeviceParameters.DP_BPB
;
;Output: CY clear if ok
;	 CY set if error writing boot or media_id info
;
;Psuedocode
;----------
;
;	Copy recommended EBPB information to canned boot record
;	Write boot record out (INT 26h)
;	IF error
;	   Display boot error message
;	   stc
;	ELSE
;	   Compute serial id and put into field (CALL Create_Serial_ID)
;	   Point at 'FAT_12' string for file system type
;	   IF fBIGFat	 ;16 bit FAT
;	      Point at 'FAT_16' for file system type
;	   ENDIF
;	   Copy file system string into media_id field
;	   Write info to boot (INT 21h AX=440Dh, CX=0843h SET MEDIA_ID)
;	   IF error (CY set)
;	      Display boot error message
;	      stc
;	   ELSE
;	      clc
;	   ENDIF
;	ENDIF
;	ret
;*****************************************************************************

Procedure WriteBootSector			;

	lea	si, deviceParameters.DP_BPB	;Copy EBPB to the boot record	;
	lea	di, Boot.EXT_BOOT_BPB		;  "  " 	"  "		;AC000:
	mov	cx, size EXT_BPB_INFO		;  "  " 	"  "		;AC000:
	push	ds				;Set ES=DS (data segment)	;     ;
	pop	es				;  "  " 	"  "		;     ;
	rep	movsb				;Do the copy			;     ;
						;Write out the boot record	;     ;
	mov	al, drive			;Get drive letter		;     ;
	mov	cx, 1				;Specify 1 sector		;     ;
	xor	dx, dx				;Logical sector 0		;     ;
	lea	bx, boot			;Point at boot record		;     ;
;Boot record in 1st 32mb of partition
	mov	Read_Write_Relative.Start_Sector_High,0 ;
	call	Write_Disk			;
;	$IF	C				;Error on write
	JNC $$IF62
	   Message msgBootWriteError		;Print error			;     ;
	   stc					;CY=1 means error		;     ;
;	$ELSE					;Good write of boot record!
	JMP SHORT $$EN62
$$IF62:
	   mov	   cx,Dummy_Label_Size		;Put in dummy volume label size
	   lea	   si,Dummy_Label		;  "  "       "  "
	   lea	   di,Media_ID_Buffer.Media_ID_Volume_Label  ;	"  "	   "  "
	   rep	   movsb			;  "  "       "  "
	   call    Create_Serial_ID		;Go create unique ID number
	   lea	   si,FAT12_String		;Assume 12 bit FAT
	   cmp	   fBigFAT,(TRUE) AND 0FFh 		;Is it?
;	   $IF	   E				;Not if fBigFat is set....
	   JNE $$IF64
	      lea     si,FAT16_String		;Got 16 bit FAT
;	   $ENDIF				;
$$IF64:
						;Copy file system string	;     ;
	   mov	   cx,8 			; to buffer
	   lea	   di,Media_ID_Buffer.Media_ID_File_System ;	 "  "
	   rep   movsb			;    "   "	  "  "
	   mov	   al,Generic_IOCtl		;Generic IOCtl call
	   mov	   bl,Drive			;Get drive
	   inc	   bl				;Make it 1 based
	   xor	   bh,bh			;Set bh=0
	   mov	   ch,RawIO			;Set Media ID call
	   mov	   cl,Set_Media_ID
	   mov	   dx,offset Media_ID_Buffer	;Point at buffer
	   DOS_Call IOCtl			;Do function call
;	   $IF	   C				;Error ? (Write or old boot rec)
	   JNC $$IF66
	      Message msgBootWriteError 	;Indicate we couldn't write it
	      stc				;CY=1 for error return
;	   $ELSE				;Set Media ID okay
	   JMP SHORT $$EN66
$$IF66:
	      clc				;CY=0 for good return
;	   $ENDIF				;
$$EN66:
;	$ENDIF					;
$$EN62:
	ret					;

WriteBootSector endp				;


;*****************************************************************************
;Routine name Create_Serial_ID
;*****************************************************************************
;
;DescriptioN&gml Create unique 32 bit serial number by getting current date and
;	      time and then scrambling it around.
;
;Called Procedures: Message (macro)
;
;
;Input&gml None
;
;Output&gml Media_ID_Buffer.Serial_Number = set
;	    AX,CX,DX destroyed
;	    Serial_Num_Low/High = Serial number generated
;
;Psuedocode
;----------
;
;	Get date (INT 21h, AH=2Bh)
;	Get time (INT 21h, AH=2Ch)
;	Serial_ID+0 = DX reg date + DX reg time
;	Serial_ID+2 = CX reg date + CX reg time
;	Serial_Num_Low = Serial_ID+2
;	Serial_Num_High = Serial_ID+0
;	ret
;*****************************************************************************

Procedure Create_Serial_ID			;

	DOS_Call Get_Date			;Get date from DOS
	push	cx				;Save results
	push	dx				;
	DOS_Call Get_Time			;Get_Time
	mov	ax,dx				;Scramble it
	pop	dx				;
	add	ax,dx				;
	mov	word ptr Media_ID_Buffer.Media_ID_Serial_Number+2,ax ;
	mov	Serial_Num_Low,ax		;
	mov	ax,cx				;
	pop	cx				;
	add	ax,cx				;
	mov	word ptr Media_ID_Buffer.Media_ID_Serial_Number,ax ;
	mov	Serial_Num_High,ax		;
	ret					;

Create_Serial_ID endp				;

;-------------------------------------------------------------------------------

; OemDone:
;
OemDone proc	near

; if /b write out a fake dos & bios
	test	switchmap, SWITCH_B
	jz	Switch8?
	call	WriteBogusDos
	retc

Switch8?:
	test	switchmap, SWITCH_8
	jz	HardDisk?
	call	ConvertToOldDirectoryFormat
	retc

HardDisk?:
	cmp	deviceParameters.DP_DeviceType, DEV_HARDDISK
	clc
	retnz
	call	SetPartitionTable

	return

OemDone endp

;------------------------------------------------------------------------------

data	segment public	para	'DATA'

	if IBMCOPYRIGHT
biosFilename db "x:\ibmbio.com",0
dosFilename db	"x:\ibmdos.com",0
	else
biosFilename db "x:\io.sys",0
dosFilename db	"x:\msdos.sys",0
	endif

data	ends

; simple code to stuff bogus dos in old-style diskette.

BogusDos:
	push	cs
	pop	ds
	mov	al,20h
	out	20h,al				; turn on the timer so the disk motor
	mov	si,mesofs			; shuts off
sys_mess_loop:
	lodsb
if ibmcopyright
end_sys_loop:
endif
	or	al,al
	jz	end_sys_loop
	mov	ah,14
	mov	bx,7
	int	16
	jmp	sys_mess_loop
if not ibmcopyright
end_sys_loop:
	xor	ah, ah				; get next char function
	int	16h				; call keyboard services
	int	19h				; reboot
endif

	include BOOT.CL1
mesofs	equ	sysmsg - BogusDos

WriteBogusDos proc near

	mov	al,driveLetter
	mov	biosFilename,al
	mov	dosFilename,al
	mov	cx, ATTR_HIDDEN or ATTR_SYSTEM
	lea	dx, biosFilename
	mov	ah,CREAT
	int	21h
	mov	bx,ax
	mov	cx, BIOS_SIZE
	push	ds
	push	cs
	pop	ds
	assume	ds:code
	lea	dx, BogusDos
	mov	ah,WRITE
	int	21h
	pop	ds
	assume	ds:data
	mov	ah,CLOSE
	int	21h
	mov	cx, ATTR_HIDDEN or ATTR_SYSTEM
	lea	dx, dosFilename
	mov	ah,CREAT
	int	21h
	mov	bx,ax
	mov	cx, DOS_SIZE
	lea	dx, BogusDos
	mov	ah,WRITE
	int	21h
	mov	ah,CLOSE
	int	21h
; Comunicate system size to the main format program
	mov	word ptr DOS.FileSizeInBytes,DOS_SIZE				;an000; dms;get size of DOS
	mov	word ptr DOS.FileSizeInBytes+2,00h

	xor	dx,dx
	mov	ax,DOS_SIZE
	call	AddToSystemSize

	mov	word ptr Bios.FileSizeInBytes,BIOS_SIZE 			;an000; dms;get size of BIOS
	mov	word ptr Bios.FileSizeInBytes+2,00h

	xor	dx,dx
	mov	ax,BIOS_SIZE
	call	AddToSystemSize

	clc
	return

WriteBogusDos endp

;-------------------------------------------------------------------------------

ConvertToOldDirectoryFormat proc near

;
; convert to 1.1 directory
;
	mov	al,drive			; Get 1st sector of directory
	mov	cx,1				; 1.1 directory always starts on
	mov	dx,3				; sector 3
	lea	bx,scratchBuffer
;Root Directory always in 1st 32mb of partition
	mov	Read_Write_Relative.Start_Sector_High,0 ;
	call	Read_Disk			;
	jnc	DirectoryRead
	Message msgDirectoryReadError		;
	stc
	ret
DirectoryRead:

; fix attribute of ibmbio and ibmdos
	lea	bx,scratchBuffer
	mov	byte ptr [bx].dir_attr, ATTR_HIDDEN or ATTR_SYSTEM
	add	bx, size dir_entry
	mov	byte ptr [bx].dir_attr, ATTR_HIDDEN or ATTR_SYSTEM

wrtdir:
	mov	al,[drive]			; write out the directory
	cbw
	mov	cx,1
	mov	dx,3
	lea	bx,scratchBuffer
;Root Directory always in 1st 32mb of partition
	mov	Read_Write_Relative.Start_Sector_High,0 ;
	call	Write_Disk			;
	jnc	DirectoryWritten
	Message msgDirectoryWriteError		;
	stc
	ret
DirectoryWritten:

	test	switchmap, SWITCH_S		; Was system requested?
	retnz					; yes, don't write old boot sector
	mov	al,drive
	cbw
	mov	bx,offset boot2 		; no,  write old boot sector
	cmp	deviceParameters.DP_BPB.BPB_Heads, 1
	je	bootset8
	mov	word ptr [bx+3],0103h		; start address for double sided drives
bootset8:
	mov	cx,1
	xor	dx,dx
;Boot record in 1st 32mb of partition
	mov	Read_Write_Relative.Start_Sector_High,0 ;
	call	Write_Disk			;
	retnc

	Message msgBootWriteError		;
	stc
	ret

ConvertToOldDirectoryFormat endp

;-------------------------------------------------------------------------------

a_PartitionTableEntry struc
BootInd db	?
BegHead db	?
BegSector db	?
BegCylinder db	?
SysInd	db	?
EndHead db	?
EndSector db	?
EndCylinder db	?
RelSec	dd	?
CSec	dd	?
a_PartitionTableEntry ends

; structure of the IBM hard disk boot sector:
IBMBoot STRUC
	db	512 - (4*size a_PartitionTableEntry + 2) dup(?)
PartitionTable db 4*size a_PartitionTableEntry dup(?)
Signature dw	?
IBMBoot ENDS


;*****************************************************************************
;Routine name: SetPartitionTable
;*****************************************************************************
;
;Description: Find location for DOS partition in partition table, get the
;	      correct system indicator byte, and write it out. If can not
;	      read/write boot record or can't find DOS partition, display
;	      error
;
;Called Procedures: Message (macro)
;		    Determine_Partition_Type
;		    ReadSector
;		    WriteSector
;
;
;Input: None
;
;Output: CY set if error
;
;Psuedocode
;----------
;
;	Read the partition table (Call ReadSector)
;	IF ok
;	   IF boot signature of 55AAh
;	       Point at system partition table
;	       SEARCH
;		  Assume DOS found
;		  IF System_Indicator <> 1,AND
;		  IF System_Indicator <> 4,AND
;		  IF System_Indicator <> 6
;		    STC   (DOS not found)
;		  ELSE
;		    CLC
;		  ENDIF
;	       EXITIF DOS found (CLC)
;		  CALL Determine_Partition_Type
;		  Write the partition table (CALL WriteSector)
;		  IF error
;		     Display boot write error message
;		     stc
;		  ELSE
;		     clc
;		  ENDIF
;	       ORELSE
;		  Point at next partition entry (add 16 to partition table ptr)
;	       ENDLOOP if checked all 4 partition entries
;		  Display Bad partition table message
;		  stc
;	       ENDSRCH
;	   ELSE invalid boot record
;	      Display Bad partition table message
;	      stc
;	   ENDIF
;	ELSE error
;	   Display Partition table error
;	   stc
;	ENDIF
;	ret
;*****************************************************************************

Procedure SetPartitionTable			;

	xor	ax, ax				;Head
	xor	bx, bx				;Cylinder
	xor	cx, cx				;Sector
	lea	dx, boot2			;Never use 1.x boot on hardfile,;     ;
	call	ReadSector			;this will use space as buffer	;     ;
;	$IF	NC				;If read okay
	JC $$IF70
	   cmp	   Boot2.Boot_Signature,Boot_ID ;
;	   $IF	   E				;Does signature match?
	   JNE $$IF71
	      lea     bx, boot2.PartitionTable	;Yes, point at partition table
;	      $SEARCH				;Look for DOS partition
$$DO72:
		 cmp	 [bx].sysind,FAT12_File_System ;
;		 $IF	 NE,AND 		;
		 JE $$IF73
		 cmp	 [bx].sysind,FAT16_File_System ;
;		 $IF	 NE,AND 		;
		 JE $$IF73
		 cmp	 [bx].sysind,New_File_System ;
;		 $IF	 NE			;
		 JE $$IF73
		    stc 			;We didn't find partition
;		 $ELSE				;
		 JMP SHORT $$EN73
$$IF73:
		    clc 			;Indicate found partition
;		 $ENDIF 			;
$$EN73:
;	      $EXITIF NC			;Get correct id for it
	      JC $$IF72
		 CALL	 Determine_Partition_Type ;
		 mov	 ax, 0			;Head				;     ;
		 mov	 bx, 0			;Cylinder			;     ;
		 mov	 cx, 0			;Sector 			;     ;
		 lea	 dx, boot2		;				;     ;
		 call	 WriteSector		;Write out partition table	;     ;
;		 $IF	 C			;Error writing boot record
		 JNC $$IF77
		    MESSAGE msgPartitionTableWriteError ;
		    stc 			;Set CY to indicate error	;     ;
;		 $ELSE				;
		 JMP SHORT $$EN77
$$IF77:
		    clc 			;No error means no CY		;     ;
;		 $ENDIF 			;
$$EN77:
;	      $ORELSE				;
	      JMP SHORT $$SR72
$$IF72:
		 add	 bx,size a_PartitionTableEntry ;			;     ;
		 cmp	 bx,(offset Boot2.PartitionTable)+4*size a_PartitionTableEntry ;     ;
;	      $ENDLOOP				;Checked all 4 partition entries
	      JMP SHORT $$DO72
		 MESSAGE msgBadPartitionTable	;Tell user bad table
		 stc				;Set CY for exit		;     ;
;	      $ENDSRCH				;
$$SR72:
;	   $ELSE				;Invalid boot record
	   JMP SHORT $$EN71
$$IF71:
	      MESSAGE msgBadPartitionTable	;
	      stc				;Set CY for error return	;     ;
;	   $ENDIF				;
$$EN71:
;	$ELSE					;Couldn't read boot record
	JMP SHORT $$EN70
$$IF70:
	   MESSAGE msgPartitionTableReadError	;
	   stc					;Set CY for error return	;     ;
;	$ENDIF					;
$$EN70:
	ret					;				;     ;

SetPartitionTable endp				;

;*****************************************************************************
;Routine name: Determine_Partition_Type
;*****************************************************************************
;
;DescriptioN: Set the system indicator field to its correct value as
;	      determined by the following rules:
;
;	     - Set SysInd = 01h if partition or logical drive size is < 10mb
;	       and completely contained within the first 32mb of DASD.
;	     - Set SysInd = 04h if partition or logical drive size is >10mb,
;	       <32mb, and completely contained within the first 32mb of DASD
;	     - Set SysInd to 06h if partition or logical drive size is > 32mb,
;
;Called Procedures: Message (macro)
;
;
;Input: BX has offset of partition table entry
;	fBigFAT = TRUE if 16bit FAT
;
;Output: BX.SysInd = correct partition system indicator value (1,4,6)
;
;Psuedocode
;----------
;	Add partition start location to length of partition
;	IF end > 32mb
;	   BX.SysInd = 6
;	ELSE
;	   IF fBigFat
;	      BX.SysInd = 4
;	   ELSE
;	      BX.SysInd = 1
;	   ENDIF
;	ret
;*****************************************************************************

Procedure Determine_Partition_Type

	mov	dx,word ptr [bx].Csec+2 					;an000; dms;Get high word of sector count
	cmp	dx,0								;AN000;    ;> 32Mb?
;	$IF	NE								;AN000;    ;yes
	JE $$IF87
		mov	[BX].SysInd,New_File_System				;AN000;    ;type 6
;	$ELSE
	JMP SHORT $$EN87
$$IF87:
		call	Calc_Total_Sectors_For_Partition			;an000; dms;returns DX:AX total sectors
		cmp	DeviceParameters.DP_BPB.BPB_HiddenSectors[+2],0 	;an000; dms;> 32Mb?
;		$if	ne							;an000; dms;yes
		JE $$IF89
			mov	[bx].SysInd,New_File_System			;an000; dms; type 6
;		$else
		JMP SHORT $$EN89
$$IF89:
			cmp	dx,0						;an000; dms; partition > 32 Mb?
;			$if	ne						;an000; dms; yes
			JE $$IF91
				mov  [bx].SysInd,New_File_System		;an000; dms; type 6
;			$else							;an000; dms; < 32 Mb partition
			JMP SHORT $$EN91
$$IF91:
				cmp	fBigFat,(True) AND 0FFh				;an000;    ;16 bit FAT
;				$IF	E					;AC000;    ;yes
				JNE $$IF93
					mov	[BX].SysInd,FAT16_File_System	;an000;    ;type 4
;				$ELSE						;an000;    ;12 bit FAT
				JMP SHORT $$EN93
$$IF93:
					mov	[bx].SysInd,FAT12_File_System	;an000;    ;type 1
;				$ENDIF
$$EN93:
;			$ENDIF
$$EN91:
;		$ENDIF
$$EN89:
;	$endif
$$EN87:
	ret

Determine_Partition_Type endp			;


;=========================================================================
; Calc_Total_Sectors_For_Partition	: This routine determines the
;					  total number of sectors within
;					  this partition.
;
;	Inputs	: DeviceParameters
;
;	Outputs : DX:AX - Double word partition size
;=========================================================================

Procedure Calc_Total_Sectors_For_Partition

	mov	ax,word ptr DeviceParameters.DP_BPB.BPB_HiddenSectors[+0]	;an000; dms; low word
	mov	dx,word ptr DeviceParameters.DP_BPB.BPB_HiddenSectors[+2]	;an000; dms; high word
	cmp	DeviceParameters.DP_BPB.BPB_TotalSectors,0			;an000; dms; extended BPB?
;	$if	e								;an000; dms; yes
	JNE $$IF99
		add	ax,word ptr DeviceParameters.DP_BPB.BPB_BigTotalSectors[+0]   ;an000; dms; add in low word
		adc	dx,0							;an000; dms; pick up carry if any
		add	dx,word ptr DeviceParameters.DP_BPB.BPB_BigTotalSectors[+2]   ;an000; dms; add in high word
;	$else									;an000; dms; standard BPB
	JMP SHORT $$EN99
$$IF99:
		add	ax,word ptr DeviceParameters.DP_BPB.BPB_TotalSectors	;an000; dms; add in total sector count
		adc	dx,0							;an000; dms; pick up carry if any
;	$endif
$$EN99:

	ret

Calc_Total_Sectors_For_Partition	endp


;-------------------------------------------------------------------------------
; ReadSector:
;    Read one sector
;
;    Input:
;	ax - head
;	bx - cylinder
;	cx - sector
;	dx - transfer address

ReadSector proc near

	mov	TrackReadWritePacket.TRWP_FirstSector, cx
	mov	cx,(RAWIO shl 8) or READ_TRACK
	call	SectorIO
	return

ReadSector endp

;-------------------------------------------------------------------------------
; WriteSector:
;    Write one sector
;
;    Input:
;	ax - head
;	bx - cylinder
;	cx - sector
;	dx - transfer address

WriteSector proc near

	mov	TrackReadWritePacket.TRWP_FirstSector, cx
	mov	cx,(RAWIO shl 8) or WRITE_TRACK
	call	SectorIO
	return

WriteSector endp

;-------------------------------------------------------------------------------
; SectorIO:
;    Read/Write one sector
;
;    Input:
;	ax - head
;	bx - cylinder
;	cx - (RAWIO shl 8) or READ_TRACK
;	   - (RAWIO shl 8) or WRITE_TRACK
;	dx - transfer address

SectorIO proc	near

	mov	TrackReadWritePacket.TRWP_Head, ax
	mov	TrackReadWritePacket.TRWP_Cylinder, bx
	mov	WORD PTR TrackReadWritePacket.TRWP_TransferAddress, dx
	mov	WORD PTR TrackReadWritePacket.TRWP_TransferAddress + 2, ds
	mov	TrackReadWritePacket.TRWP_SectorsToReadWrite, 1

	mov	bl, drive
	inc	bl
	mov	ax, (IOCTL shl 8) or GENERIC_IOCTL
	lea	dx, trackReadWritePacket
	int	21H
	return

SectorIO endp

;-------------------------------------------------------------------------------

data	segment public	para	'DATA'

oldDrive db	?

FCBforVolumeIdSearch db 0ffH
	db	5 dup(0)
	db	08H
	db	0
	db	"???????????"
	db	40 DUP(0)

data	ends

GetVolumeId proc near
; Input:
;    dl = drive
;    di = name buffer

; Save current drive
	mov	ah,19H
	int	21H
	mov	oldDrive, al

; Change current drive to the drive that has the volume id we want
	mov	ah, 0eH
	int	21H

; Search for the volume id
	mov	ah, 11H
	lea	dx, FCBforVolumeIdSearch
	int	21H
	push	ax

; Restore current drive
	mov	ah, 0eH
	mov	dl,oldDrive
	int	21H

; Did the search succeed?
	pop	ax
	or	al,al
	jz	CopyVolumeId
	stc
	ret

CopyVolumeId:
; Find out where the FCB for the located volume id was put
	mov	ah,2fH
	int	21H

; Copy the Volume Id
	mov	si, bx
	add	si, 8
	push	es
	push	ds
	pop	es
	pop	ds
	mov	cx, 11
	rep	movsb
	push	es
	pop	ds

	clc
	ret

GetVolumeId endp

data	segment public	para	'DATA'
oldVolumeId db	11 dup(0)
data	ends

CheckVolumeId proc near

; Get the volume id that's on the disk
	lea	di, oldVolumeId
	mov	dl, drive
	call	GetVolumeId
	jnc	Ask_User			;Did we find one?
	clc					;No, return with no error
	ret

; Ask the user to enter the volume id that he/she thinks is on the disk
; (first blank out the input buffer)
Ask_User:

	Message msgWhatIsVolumeId?		;
						;lea	 dx, ptr_msgWhatIsVolumeId?
						;call	 std_printf
	call	user_string
	call	crlf

; If the user just pressed ENTER, then there must be no label
	cmp	inbuff+1, 0
	jne	CompareVolumeIds
	cmp	oldVolumeId, 0
	jne	BadVolumeId
	ret

CompareVolumeIds:
; pad the reponse with blanks
; The buffer is big enough so just add 11 blanks to what the user typed in
	push	ds
	pop	es
	mov	cx, Label_Length
	xor	bx,bx
	mov	bl, inbuff + 1
	lea	di, inbuff + 2
	add	di, bx
	mov	al, ' '
	rep	stosb
; Make the reply all uppercase
	mov	byte ptr Inbuff+2+Label_Length,ASCIIZ_End ;Make string ASCIIZ
	mov	dx, offset inbuff + 2		;Start of buffer
	mov	al,22h				;Capitalize asciiz
	DOS_Call GetExtCntry			;Do it

; Now compare what the user specified with what is really out there
	mov	cx, Label_Length		;
	lea	si, inbuff + 2
	lea	di, oldVolumeId
	repe	cmpsb
	jne	BadVolumeId
	ret

BadVolumeId:
	Message msgBadVolumeID			;
	stc
	ret

CheckVolumeId endp


Check_Switch_8_B	proc	near

	   test    SwitchMap, SWITCH_B		;/8/B <> /V because
;	   $IF	   NZ,AND			; old directory type
	   JZ $$IF102
	   test    SwitchMap, Switch_8		; used which didn't support
;	   $IF	   NZ,AND			; volume labels.
	   JZ $$IF102
	   test    SwitchMap, SWITCH_V		;
;	   $IF	   NZ				;
	   JZ $$IF102
	      Message msgIncompatibleParameters ;Tell user
	      mov     Fatal_Error,Yes		;Bad stuff
;	   $ELSE				;No problem so far
	   JMP SHORT $$EN102
$$IF102:
	      test    SwitchMap, Switch_B	;Can't reserve space and
;	      $IF     NZ,AND			; install sys files at the
	      JZ $$IF104
	      test    SwitchMap, Switch_S	; same time.
;	      $IF     NZ			; No /S/B
	      JZ $$IF104
		 Message msgIncompatibleParameters ;Tell user
		 mov	 Fatal_Error,Yes	;Bad stuff
;	       $ELSE				 ;Still okay
	       JMP SHORT $$EN104
$$IF104:
		  test	  SwitchMap,Switch_1	 ;/1/8/4 not okay with /N/T
;		  $IF	  NZ,OR 		 ;
		  JNZ $$LL106
		  test	  SwitchMap,Switch_8	 ;
;		  $IF	  NZ,OR 		 ;
		  JNZ $$LL106
		  test	  SwitchMap,Switch_4	 ;
;		  $IF	  NZ			 ;
		  JZ $$IF106
$$LL106:
		     test    SwitchMap,(Switch_T or Switch_N) ;
;		     $IF     NZ 		 ;Found /T/N <> /1/8
		     JZ $$IF107
			Message msgIncompatibleParameters ;Tell user
			mov	Fatal_Error,Yes  ;Bad stuff
;		     $ELSE			 ;
		     JMP SHORT $$EN107
$$IF107:
			test	SwitchMap,Switch_V
;			$IF	NZ,AND
			JZ $$IF109
			test	SwitchMap,Switch_8
;			$IF	NZ
			JZ $$IF109
				Message msgIncompatibleParameters
				mov	Fatal_Error,Yes
;			$ENDIF
$$IF109:
;		     $ENDIF			 ;
$$EN107:
;		  $ENDIF			 ;
$$IF106:
;	       $ENDIF				 ;
$$EN104:
;	    $ENDIF				 ;
$$EN102:
	    ret

Check_Switch_8_B	endp


code	ends
	end

