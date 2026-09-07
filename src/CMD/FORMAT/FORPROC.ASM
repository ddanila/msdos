;
.xlist
.xcref
BREAK	MACRO	subtitle
	SUBTTL	subtitle
	PAGE
ENDM

	INCLUDE FORCHNG.INC
	INCLUDE SYSCALL.INC
	INCLUDE FOREQU.INC
	INCLUDE FORMACRO.INC
	INCLUDE FORSWTCH.INC
	INCLUDE IOCTL.INC
.cref
.list
data	segment public para 'DATA'
data	ends

code	segment public para 'CODE'
	assume	cs:code,ds:data

	PUBLIC	FormatAnother?,Yes?,REPORT,USER_STRING
	public	fdsksiz,badsiz,syssiz,datasiz,biosiz
	public	AllocSize,AllocNum

	extrn	std_printf:near,crlf:near,PrintString:near
	extrn	Multiply_32_Bits:near
	extrn	AddToSystemSize:near

data	segment public	para	'DATA'
	extrn	driveLetter:byte
	extrn	msgInsertDisk:byte
	extrn	msgFormatAnother?:byte
	extrn	msgTotalDiskSpace:byte
	extrn	msgSystemSpace:byte
	extrn	msgBadSpace:byte
	extrn	msgDataSpace:byte
	extrn	Read_Write_Relative:byte
	extrn	msgAllocSize:byte
	extrn	MsgAllocNum:Byte
	extrn	deviceParameters:byte
	extrn	bios:byte
	extrn	dos:byte
	extrn	command:byte
	extrn	Serial_Num_Low:Word
	extrn	Serial_Num_High:Word
	extrn	msgSerialNumber:Byte
	extrn	SwitchMap:Word


	extrn	inbuff:byte

fdsksiz dd	0

syssiz	dd	0
biosiz	dd	0

badsiz	dd	0

datasiz dd	0

AllocSize dd	0				;
AllocNum dw	0				;
	dw	offset driveLetter
data	ends

FormatAnother? proc near
; Wait for key. If yes return carry clear, else no. Insures
;   explicit Y or N answer.
	Message msgFormatAnother?		;
	CALL	Yes?
	JNC	WAIT20
	JZ	WAIT20
	CALL	CRLF
	JMP	SHORT FormatAnother?
WAIT20: 					;
	RET					;
FormatAnother? endp

;*****************************************************************************
;Routine name:Yes?
;*****************************************************************************
;
;Description: Validate that input is valid Y/N for the country dependent info
;	      Wait for key. If YES return carry clear,else carry set.
;	      If carry is set, Z is set if explicit NO, else key was not Yes or No.
;
;Called Procedures: Message (macro)
;		    User_String
;
;Input: None
;
;Output: CY = 0 Yes is entered
;	 CY = 1, Z = No
;	 CY = 1, NZ = other
;
;Psuedocode
;----------
;
;	Get input (CALL USER STRING)
;	IF got character
;	   Check for country dependent Y/N (INT 21h, AX=6523h Get Ext Country)
;	   IF Yes
;	      clc
;	   ELSE (No)
;	      IF No
;		 stc
;		 Set Zero flag
;	      ELSE (Other)
;		 stc
;		 Set NZ
;	      ENDIF
;	   ENDIF
;	ELSE  (nothing entered)
;	   stc
;	   Set NZ flag
;	ENDIF
;	ret
;*****************************************************************************

Procedure YES?					;

	call	User_String			;Get character			;     ;
;	$IF	NZ				;Got one if returned NZ
	JZ $$IF1
	   mov	   al,23h			;See if it is Y/N
	   mov	   dl,[InBuff+2]		;Get character
	   DOS_Call GetExtCntry 		;Get country info call
	   cmp	   ax,Found_Yes 		;Which one?
;	   $IF	   E				;Got a Yes
	   JNE $$IF2
	      clc				;Clear CY for return
;	   $ELSE				;Not a Yes
	   JMP SHORT $$EN2
$$IF2:
	      cmp     ax,Found_No		;Is it No?
;	      $IF     E 			;Yep
	      JNE $$IF4
		 stc				;Set CY for return
;	      $ELSE				;Something else we don't want
	      JMP SHORT $$EN4
$$IF4:
		 xor	 al,al			;Set NZ flag for ret
		 cmp	 al,1			; " "	 " "
		 stc				;And CY flag for good measure
;	      $ENDIF				;
$$EN4:
;	   $ENDIF				;
$$EN2:
;	$ELSE					;No char found at all
	JMP SHORT $$EN1
$$IF1:
	   xor	   al,al			;Set NZ flag for ret
	   cmp	   al,1 			; " "	 " "
	   stc					;And CY flag for good measure
;	$ENDIF					;
$$EN1:
	ret					;				;     ;

Yes?	endp					;


USER_STRING:
; Get a string from user. Z is set if user typed no chars (imm CR)
;  We need to flush a second time to get rid of incoming Kanji characters also.
	MOV	AX,(STD_CON_INPUT_FLUSH SHL 8) + 0 ; Clean out input
	INT	21H
	MOV	DX,OFFSET INBUFF
	MOV	AH,STD_CON_STRING_INPUT
	INT	21H
	MOV	AX,(STD_CON_INPUT_FLUSH SHL 8) + 0 ; Clean out input
	INT	21H
	CMP	BYTE PTR [INBUFF+1],0
	RET

;*********************************************
; Make a status report including the following information:
; Total disk capacity
; Total system area used
; Total bad space allocated
; Total data space available
; Number of allocation units
; Size of allocation units

REPORT:
	call	crlf

	call	Calc_System_Space		;an013; dms;calc system space
	call	Calc_Total_Addressible_Space	;an013; dms;calc total space

	Message msgTotalDiskSpace		;
						;call	 std_printf
	cmp	WORD PTR SYSSIZ,0
	JNZ	SHOWSYS
	cmp	WORD PTR SYSSIZ+2,0
	JZ	CHKBAD
SHOWSYS:
	Message msgSystemSpace			;
						;CALL	 std_printf		 ;Report space used by system
CHKBAD:
	cmp	WORD PTR BADSIZ,0
	JNZ	SHOWBAD
	cmp	WORD PTR BADSIZ+2,0
	JZ	SHOWDATA
SHOWBAD:
	Message msgBadSpace			;
						;call	 std_printf
SHOWDATA:


	MOV	CX,WORD PTR Fdsksiz
	MOV	BX,WORD PTR Fdsksiz+2
	SUB	CX,WORD PTR BADSIZ
	SBB	BX,WORD PTR BADSIZ+2
	SUB	CX,WORD PTR SYSSIZ
	SBB	BX,WORD PTR SYSSIZ+2
	MOV	word ptr datasiz,CX
	MOV	word ptr datasiz+2,BX
	Message msgDataSpace			;
						;call	 std_printf

	call	crlf				;
	mov	ax,deviceParameters.DP_BPB.BPB_BytesPerSector ;
	mov	cl,deviceParameters.DP_BPB.BPB_SectorsPerCluster ;
	xor	ch,ch				;
	mul	cx				;Get bytes per alloc

	mov	word ptr AllocSize,ax		;Save allocation size
	mov	word ptr AllocSize+2,dx 	; for message
	Message msgAllocSize			;Print size of cluster
	call	Get_Free_Space			;an013; dms;get disk space

	mov	word ptr AllocNum,bx		;Put result in msg
	Message msgAllocNum			; = cluster/disk
	call	crlf				;
	test	switchmap, SWITCH_8		;If 8 tracks, don't display
	jnz	NOSERIALNUMBER			;serial number
	Message msgSerialNumber 		;Spit out serial number
	call	crlf				;
NOSERIALNUMBER:
	RET					;

;*****************************************************************************
;Routine name: Read_Disk
;*****************************************************************************
;
;description: Read in data using Generic IOCtl
;
;Called Procedures: None
;
;
;Change History: Created	5/13/87 	MT
;
;Input: AL = Drive number (0=A)
;	DS:BX = Transfer address
;	CX = Number of sectors
;	Read_Write_Relative.Start_Sector_High = Number of sectors high
;	DX = logical sector number low
;
;Output: CY if error
;	 AH = INT 25h error code
;
;Psuedocode
;----------
;	Save registers
;	Setup structure for function call
;	Read the disk (AX=440Dh, CL = 6Fh)
;	Restore registers
;	ret
;*****************************************************************************

Procedure Read_Disk				;

						;This is setup for INT 25h right
						;Change it to Read relative sect
	push	bx				;Save registers
	push	cx				;
	push	dx				;
	push	si				;
	push	di				;
	push	bp				;
	push	es				;
	push	ds				;
	mov	si,data 			;
	mov	es,si				;

	assume	es:data,ds:nothing		;

	mov	es:Read_Write_Relative.Buffer_Offset,bx ;Get transfer buffer add
	mov	bx,ds				;
	mov	es:Read_Write_Relative.Buffer_Segment,bx ;Get segment
	mov	bx,data 			;Point DS at parameter list
	mov	ds,bx				;

	assume	ds:data,es:data

	mov	Read_Write_Relative.Number_Sectors,cx ;Number of sec to read
	mov	Read_Write_Relative.Start_Sector_Low,dx ;Start sector
	mov	bx,offset Read_Write_Relative	;
	mov	cx,0FFFFh			;Read relative sector
	INT	25h				;Do the read
	pop	dx				;Throw away flags on stack
	pop	ds				;
	pop	es				;
	pop	bp				;
	pop	di				;
	pop	si				;
	pop	dx				;Restore registers
	pop	cx				;
	pop	bx				;
	ret					;


Read_Disk endp					;

;*****************************************************************************
;Routine name: Write_Disk
;*****************************************************************************
;
;description: Write Data using Generic IOCtl
;
;Called Procedures: None
;
;
;Change History: Created	5/13/87 	MT
;
;Input: AL = Drive number (0=A)
;	DS:BX = Transfer address
;	CX = Number of sectors
;	Read_Write_Relative.Start_Sector_High = Number of sectors high
;	DX = logical sector number low
;
;Output: CY if error
;	 AH = INT 26h error code
;
;Psuedocode
;----------
;	Save registers
;	Setup structure for function call
;	Write to disk (AX=440Dh, CL = 4Fh)
;	Restore registers
;	ret
;*****************************************************************************

Procedure Write_Disk				;


						;This is setup for INT 26h right
						;Change it to Read relative sect

	push	bx				;Save registers
	push	cx				;
	push	dx				;
	push	si				;
	push	di				;
	push	bp				;
	push	es				;
	push	ds				;
	mov	si,data 			;
	mov	es,si				;

	assume	es:data,ds:nothing		;

	mov	es:Read_Write_Relative.Buffer_Offset,bx ;Get transfer buffer add
	mov	bx,ds				;
	mov	es:Read_Write_Relative.Buffer_Segment,bx ;Get segment
	mov	bx,data 			;Point DS at parameter list
	mov	ds,bx				;

	assume	ds:data,es:data

	mov	Read_Write_Relative.Number_Sectors,cx ;Number of sec to write
	mov	Read_Write_Relative.Start_Sector_Low,dx ;Start sector
	mov	bx,offset Read_Write_Relative	;
	mov	cx,0FFFFh			;Write relative sector
	INT	26h				;Do the write
	pop	dx				;Throw away flags on stack
	pop	ds				;
	pop	es				;
	pop	bp				;
	pop	di				;
	pop	si				;
	pop	dx				;Restore registers
	pop	cx				;
	pop	bx				;
	ret					;

Write_Disk endp 				;

;=========================================================================
; Calc_Total_Addressible_Space	: Calculate the total space that is
;				  addressible on the the disk by DOS.
;
;	Inputs	: none
;
;	Outputs : Fdsksiz - Size in bytes of the disk
;=========================================================================

Procedure Calc_Total_Addressible_Space

	push	ax				;an013; dms;save affected regs
	push	dx
	push	bx

	call	Get_Free_Space			;an013; dms;get free disk space

	push	bx				;an013; dms;save avail. cluster
	push	dx				;an013; dms;save total. cluster

	mov	ax,dx				;an013; dms;get total clusters

	xor	bx,bx				;an013; dms;clear bx
	xor	cx,cx				;an013; dms;clear cx
	mov	cl,DeviceParameters.DP_BPB.BPB_SectorsPerCluster  ;an013; dms;get total sectors
	call	Multiply_32_Bits		;an013; dms;multiply

	xor	cx,cx				;an013; dms;clear cx
	mov	cx,DeviceParameters.DP_BPB.BPB_BytesPerSector  ;an013; dms;get total bytes
	call	Multiply_32_Bits		;an013; dms; multiply

	mov	word ptr Fdsksiz,ax		;an013; dms;save high word
	mov	word ptr Fdsksiz+2,bx		;an013; dms;save low word

	pop	dx				;an000; dms;get total clusters
	pop	bx				;an000; dms;get avail clusters

	mov	ax,dx				;an013; dms;get total clusters
	sub	ax,bx				;an013; dms;get bad clusters

	xor	bx,bx				;an013; dms;clear bx
	xor	cx,cx				;an013; dms;clear cx
	mov	cl,DeviceParameters.DP_BPB.BPB_SectorsPerCluster  ;an013; dms;get total sectors
	call	Multiply_32_Bits		;an013; dms;multiply

	xor	cx,cx				;an013; dms;clear cx
	mov	cx,DeviceParameters.DP_BPB.BPB_BytesPerSector  ;an013; dms;get total bytes
	call	Multiply_32_Bits		;an013; dms; multiply

	sub	ax,word ptr syssiz		;an013; dms;account for system
	sbb	bx,word ptr syssiz+2		;an013; dms;size

	mov	word ptr Badsiz,ax		;an013; dms;save high word
	mov	word ptr Badsiz+2,bx		;an013; dms;save low word

	pop	bx
	pop	dx				;an013; dms;restore regs
	pop	ax

	ret

Calc_Total_Addressible_Space	endp


;=========================================================================
; Get_Free_Space	: Get the free space on the disk.
;
;	Inputs	: none
;
;	Outputs : BX - Available space in clusters
;		  DX - Total space in clusters
;=========================================================================

Procedure Get_Free_Space

	xor	ax,ax				;an013; dms;clear ax
	mov	ah,36h				;an013; dms;Get disk free space
	mov	dl,driveletter			;an013; dms;get drive letter
	sub	dl,"A"				;an013; dms;get 0 based number
	inc	dl				;an013; dms;make it 1 based
	int	21h
	ret

Get_Free_Space	endp

;=========================================================================
; Calc_System_Space	: This routine calculates the space occupied by
;			  the system on the disk.
;
;	Inputs	: DOS.FileSizeInBytes
;		  BIOS.FileSizeInBytes
;		  Command.FileSizeInBytes
;
;	Outputs : SysSiz			- Size of the system
;=========================================================================

Procedure Calc_System_Space

	push	ax								;an013; dms;save regs
	push	dx

	mov	word ptr SysSiz+0,00h						;an013; dms;clear variable
	mov	word ptr SysSiz+2,00h

	mov	ax,word ptr [DOS.FileSizeInBytes+0]				;an013; dms;get low word
	mov	dx,word ptr [DOS.FileSizeInBytes+2]				;an013; dms;get high word
	call	AddToSystemSize 						;an013; dms;add in values

	mov	ax,word ptr [BIOS.FileSizeInBytes+0]				;an013; dms;get bios size
	mov	dx,word ptr [BIOS.FileSizeInBytes+2]
	call	AddToSystemSize 						;an013; dms;add in values

	mov	ax,word ptr [COMMAND.FileSizeInBytes+0] 			;an013; dms;get command size
	mov	dx,word ptr [COMMAND.FileSizeInBytes+2]
	call	AddToSystemSize 						;an013; dms;add in values

	pop	dx								;an013; dms;restore regs
	pop	ax

	ret

Calc_System_Space	endp



code	ends
	end
