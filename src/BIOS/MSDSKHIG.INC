; Disk-service body selected for the BIOS high-memory split.
; Default: original CODE segment. BIOS_SERVICE_ISOLATED: standalone BIOSHIGH
; segment with explicit low imports. Neither object mode activates relocation.
; Keep READ_SECTOR through DOINT together while converting low-data and gateway
; contracts. MSIOCTL.INC is part of this body; declarations stay in MSDISK.ASM.

PUBLIC BIOS_SERVICE_START, BIOS_SERVICE_END
BIOS_SERVICE_START LABEL BYTE

; READ A SINGLE SECTOR INTO THE TEMP BUFFER.
; PERFORM THREE RETRIES IN CASE OF ERROR.
;   INPUTS:	DRIVE HAS PHYSICAL DRIVE TO USE
;		CX HAS SECTOR AND CYLINDER
;		DH HAS HEAD
;   OUTPUTS:	CARRY CLEAR
;		    LOW BIOS DATA SEGMENT:BX POINTS TO SECTOR (CS IN LOW LAYOUT)
;		CARRY SET
;		    AX HAS ROM ERROR CODE
; REGISTERS ES AND BP ARE PRESERVED.

READ_SECTOR PROC NEAR
	PUBLIC READ_SECTOR

	PUSH	BP
	MOV	BP,3		; MAKE 3 ATTEMPTS
	PUSH	ES
;SB33015*****************************************************************
	mov	DL, byte ptr ds:[di].DriveNum			       ;SB;3.30*
	mov	BX, offset DiskSector	; Get ES:BX to point to buffer ;SB;3.30*
	BIOS_PUSH_DATA_SEG			;    get the segment right     ;SB;3.30*
	pop	ES			; now ES:BX is correct	       ;SB;3.30*
;SB33015*****************************************************************
RD_RET:
;SB33016*****************************************************************
	mov	AX, 0201h		; number of sectors to 1 (AL=1);SB;3.30*
	BIOS_ROM_INT13			; call rom-bios disk routines  ;SB;3.30*

;SB33016*****************************************************************
	JNC	OKRET2
Rd_rty:
	CALL	AGAIN		; RESET DISK, DECREMENT BP, PRESERVE AX
	jz	Err_RD_RET
	test	word ptr ds:[di].flags,fNon_Removable
	JNZ	RD_RET
	BIOS_LOW_MEM CMP,<[Media_Set_For_Format]>,0,DS
	jne	Rd_Skip1_DPT	;AN012;
	push	ds		;J.K. 11/7/86 For retry, set the head settle time
	push	ax		;to 0Fh. PTM845.
	BIOS_LOW_READ LDS,SI,<DPT>,ES
	mov	al, ds:[si].disk_head_sttl
	BIOS_LOW_MEM MOV,<[save_head_sttl]>,AL,DS
	mov	byte ptr ds:[si].disk_head_sttl, NormSettle
	pop	ax
	pop	ds
Rd_Skip1_DPT:			;AN012;
;SB33017*****************************************************************
					; SET CMD TO READ (AH=2) AND  ;SB ;3.30
	MOV	AX, 0201h		; NUM OF SECTORS TO 1 (AL=1)  ;SB ;3.30
	BIOS_ROM_INT13			; CALL ROM-BIOS DISK ROUTINES ;SB ;3.30
;SB33017*****************************************************************
	pushf			;AN012;
	BIOS_LOW_MEM CMP,<[Media_Set_For_Format]>,0,DS
	jne	Rd_Skip2_DPT	       ;AN012;
	push	ds
	push	ax
	BIOS_LOW_READ LDS,SI,<DPT>,ES
	BIOS_LOW_READ MOV,AL,<[save_head_sttl]>,DS
	mov	byte ptr ds:[si].disk_head_sttl, al
	pop	ax
	pop	ds
Rd_Skip2_DPT:			;AN012;
	popf			;AN012;
	jnc	OKRET2
	jmp	Rd_rty
ERR_RD_RET:
	MOV	DL,-1		; MAKE SURE WE ASK ROM IF MEDIA HAS CHANGED
	STC			; RETURN ERROR
; UPDATE INFORMATION PERTAINING TO LAST DRIVE ACCESSED, TIME OF ACCESS, LAST
; TRACK ACCESSED IN THAT DRIVE.
OKRET2:
	BIOS_LOW_MEM MOV,<[STEP_DRV]>,DL,DS
	BIOS_LOW_MEM MOV,<[TIM_DRV]>,DL,DS
	MOV	BYTE PTR [DI].TRACK,CH	; SAVE LAST TRACK ACCESSED ON THIS DRIVE
	PUSHF				; PRESERVE FLAGS IN CASE ERROR OCCURRED
	CALL	SET_TIM
	POPF				; RESTORE FLAGS
	POP	ES
	POP	BP
	RET
READ_SECTOR ENDP

;-----------------------------------------------------------
;
;		DISK REMOVABLE ROUTINE ARR 2.41
;

DSK$REM PROC	NEAR			;ARR 2.41
	PUBLIC	DSK$REM

	MESSAGE FTESTDISK,<"DISK REMOVABLE ">
	MNUM	FTESTDISK,AX
	MESSAGE FTESTDISK,<CR,LF>
; AL IS UNIT #
	CALL	SETDRIVE		; GET BDS FOR THIS DRIVE
	TEST	WORD PTR [DI].FLAGS,FNON_REMOVABLE
	JNZ	NON_REM
	BIOS_JUMP_LOW EXIT,BIOS_LOW_EXIT_ENTRY

NON_REM:
	BIOS_JUMP_LOW BUS$EXIT,BIOS_LOW_BUSY_ENTRY
DSK$REM ENDP

; SETDRIVE SCANS THROUGH THE DATA STRUCTURE OF BDSS, AND RETURNS A POINTER TO
; THE ONE THAT BELONGS TO THE DRIVE SPECIFIED. CARRY IS SET IF NONE EXISTS FOR
; THE DRIVE.
; SETDRIVE accepts the logical drive number in AL. SETDRIVE_PHYSICAL accepts
; the physical INT 13h drive number in AL.
; ON EXIT, DS:DI POINTS TO CORRECT BDS FOR THE DRIVE IF CARRY CLEAR.

	PUBLIC SETDRIVE
SETDRIVE PROC	NEAR
	MESSAGE FTESTDISK,<"SETDRIVE",CR,LF>
	PUSH	BX
	MOV	BL,DRIVELET
	JMP	SHORT SETDRIVE_FIELD
SETDRIVE_PHYSICAL:
	PUSH	BX
	MOV	BL,DRIVENUM
SETDRIVE_FIELD:
	XOR	BH,BH
	BIOS_PUSH_DATA_SEG
	POP	DS
	ASSUME	DS:CODE

; ASSUME FIRST BDS IS IN THIS SEGMENT
	MOV	DI,WORD PTR START_BDS
SCAN_LOOP:
	CMP	BYTE PTR [BX+DI],AL
	JE	SETDRV
GET_NXT_BDS:
	PUSH	WORD PTR [DI].LINK+2     ; GO TO NEXT BDS
	MOV	DI,WORD PTR [DI].LINK
	POP	DS
	ASSUME	DS:NOTHING

	CMP	DI,-1
	JNZ	SCAN_LOOP
	STC
SETDRV:
	POP	BX
	RET
SETDRIVE ENDP

;-----------------------------------------------------------
;
;		DISK I/O ROUTINES
;

DSK$WRITV PROC	NEAR
	PUBLIC	DSK$WRITV

	MESSAGE FTESTDISK,<"DISK WRITE WITH VERIFY ">
	MNUM	FTESTDISK,AX
	MESSAGE FTESTDISK,<" ">
	MNUM	FTESTDISK,DX
	MESSAGE FTESTDISK,<" FOR ">
	MNUM	FTESTDISK,CX
	MESSAGE FTESTDISK,<CR,LF>
	BIOS_LOW_MEM MOV,<[WRTVERIFY]>,103H,DS
	JMP	SHORT DSK$CL

DSK$WRIT:
	PUBLIC	DSK$WRIT
	MESSAGE FTESTDISK,<"DISK WRITE ">
	MNUM	FTESTDISK,AX
	MESSAGE FTESTDISK,<" ">
	MNUM	FTESTDISK,DX
	MESSAGE FTESTDISK,<" FOR ">
	MNUM	FTESTDISK,CX
	MESSAGE FTESTDISK,<CR,LF>
	BIOS_LOW_MEM MOV,<[WRTVERIFY]>,ROMWRITE,DS

DSK$CL:
	CALL	DISKIO
DSK$IO:
	JC	DSKBAD
	BIOS_JUMP_LOW EXIT,BIOS_LOW_EXIT_ENTRY
DSKBAD:
	BIOS_JUMP_LOW ERR$CNT,BIOS_LOW_ERRCNT_ENTRY
DSK$WRITV ENDP

DSK$READ PROC	NEAR
	PUBLIC	DSK$READ
	MESSAGE FTESTDISK,<"DISK READ ">
	MNUM	FTESTDISK,AX
	MESSAGE FTESTDISK,<" ">
	MNUM	FTESTDISK,DX
	MESSAGE FTESTDISK,<" FOR ">
	MNUM	FTESTDISK,CX
	MESSAGE FTESTDISK,<CR,LF>
	CALL	DISKRD
	JMP	DSK$IO
DSK$READ ENDP

; MISCELLANEOUS ODD JUMP ROUTINES.  MOVED OUT OF MAINLINE FOR SPEED.


; IF WE HAVE A SYSTEM WHERE WE HAVE VIRTUAL DRIVES, WE NEED TO PROMPT THE
; USER TO PLACE THE CORRECT DISK IN THE DRIVE.

CHECKSINGLE PROC NEAR
	PUBLIC CHECKSINGLE

	PUSH	AX
	PUSH	BX
	MOV	BX,WORD PTR DS:[DI].FLAGS
 ; IF HARD DRIVE, CANNOT CHANGE DISK.
 ; IF CURRENT OWNER OF PHYSICAL DRIVE, NO NEED TO CHANGE DISKETTE.
	TEST	BL,FNON_REMOVABLE OR FI_OWN_PHYSICAL
	JNZ	SINGLERET
	TEST	BL,FI_AM_MULT		 ; IS THERE A DRIVE SHARING THIS
					 ;   PHYSICAL DRIVE?
	JZ	SINGLERET
; LOOK FOR THE PREVIOUS OWNER OF THIS PHYSICAL DRIVE AND RESET ITS OWNERSHIP
; FLAG.
	MOV	AL,DS:[DI].DRIVENUM	; GET PHYSICAL DRIVE NUMBER
	PUSH	DS			; PRESERVE POINTER TO CURRENT BDS
	PUSH	DI
	BIOS_PUSH_DATA_SEG
	POP	DS
	ASSUME	DS:CODE

	MOV	DI,OFFSET START_BDS
SCAN_LIST:
	MOV	BX,WORD PTR [DI].LINK+2     ; GO TO NEXT BDS
	MOV	DI,WORD PTR [DI].LINK
	MOV	DS,BX
	ASSUME	DS:NOTHING

	CMP	DI,-1			; END OF LIST?
	JZ	SINGLE_ERR_RET		; MUST BE ERROR
	CMP	BYTE PTR [DI].DRIVENUM,AL
	JNZ	SCAN_LIST

CHECK_OWN:
	MOV	BX,WORD PTR [DI].FLAGS
	TEST	BL,FI_OWN_PHYSICAL
	JZ	SCAN_LIST
	XOR	BL,FI_OWN_PHYSICAL	    ; RESET OWNERSHIP FLAG
	MOV	WORD PTR DS:[DI].FLAGS,BX
	POP	DI			    ; RESTORE POINTER TO CURRENT BDS
	POP	DS
	XOR	BX,BX
	OR	BL,FI_OWN_PHYSICAL	    ; ESTABLISH CURRENT BDS AS OWNER
	OR	WORD PTR [DI].FLAGS,BX

;
; WE EXAMINE THE FSETOWNER FLAG. IF IT IS SET, THEN WE ARE USING THE CODE IN
; CHECKSINGLE TO JUST SET THE OWNER OF A DRIVE. WE MUST NOT ISSUE THE PROMPT
; IN THIS CASE.
;
	BIOS_LOW_MEM CMP,<BYTE PTR [FSETOWNER]>,1,DS
	JZ	SINGLERET
; TO SUPPORT "BACKWARD" COMPATIBILITY WITH IBM'S "SINGLE DRIVE STATUS BYTE"
; WE NOW CHECK TO SEE IF WE ARE IN A SINGLE DRIVE SYSTEM AND THE APPLICATION
; HAS "CLEVERLY" DIDDLED THE SDSB
	BIOS_LOW_MEM CMP,<[SINGLE]>,2,DS		    ; IF (SINGLE_DRIVE_SYSTEM)
	JNE	SHORT IGNORE_SDSB

	SAVEREG <DS,DI,AX>		    ;	THEN
	MOV	AL,DS:[DI].DRIVELET	    ;	  IF (CURR_DRV == REQ_DRV)
	MOV	AH,AL
	XOR	DI,DI
	MOV	DS,DI
	XCHG	AL,DS:BYTE PTR LSTDRV	    ;	     THEN SWAP(CURR_DRV,REQ_DRV)
	CMP	AH,AL			    ;	     ELSE
	RESTOREREG <AX,DI,DS>		    ;		  SWAP(CURR_DRV,REQ_DRV)
	JE	SINGLERET		    ;		  ISSUE SWAP_DSK_MSG

IGNORE_SDSB:
	BIOS_CALL_LOW SWPDSK,BIOS_LOW_SWPDSK ; ASK USER FOR CORRECT DISK
SINGLERET:
	POP	BX
	POP	AX
	RET

SINGLE_ERR_RET:
	STC
	POP	DI			    ; RESTORE CURRENT BDS
	POP	DS
	JMP	SHORT SINGLERET

BADDRIVE:
	MOV	AL,8			;Sector not found
	jmp	short BadDrive_Ret	;AN004;AN005;AN006;
UnformattedDrive:			;AN004;AN005;AN006;
	mov	al,7			;AN004;Unknown media;AN005;AN006;
BadDrive_Ret:
	STC
IORET:	RET

BOGUSSETTLE:
	MOV	AL,NORMSETTLE		; SOMEONE HAS DIDDLED THE SETTLE
	JMP	GOTSLOWSETTLE
CHECKSINGLE ENDP
;------------------------------------------------------------
;
;	DISK I/O HANDLER
;
;	AL = DRIVE NUMBER (0-6)
;	AH = MEDIA DESCRIPTOR
;	CX = SECTOR COUNT
;	DX = FIRST SECTOR (low)
;	[Start_Sec_H] = FIRST SECTOR (high) ;J.K. 32 bit calculation.
;	DS = CS
;	ES:DI = TRANSFER ADDRESS
;	[RFLAG]=OPERATION (2=READ, 3=WRITE)
;	[VERIFY]=1 FOR VERIFY AFTER WRITE
;
;	IF SUCCESSFUL CARRY FLAG = 0
;	  ELSE CF=1 AND AL CONTAINS ERROR CODE
;
	PUBLIC DISKRD
DISKRD	PROC	NEAR
	BIOS_LOW_MEM MOV,<[RFLAG]>,ROMREAD,DS

DISKIO:
	MOV	BX,DI			; ES:BX = TRANSFER ADDRESS
	CALL	SETDRIVE		; MAP LOGICAL AND PHYSICAL
	MOV	AL,BYTE PTR DS:[DI].MEDIAD
	BIOS_LOW_MEM MOV,<MEDBYT>,AL,DS		; PRESERVE MEDIA BYTE FOR DRIVE FOR USE
					; IN DETERMINING MEDIA CHANGE.
	JCXZ	IORET
;SB34DISK006******************************************************************
;SB	See if the Media is formatted or not by checking the flags field in
;SB	in the BDS.  If it is unformatted we cannot allow I/O, so we should
;SB	go to the error exit at label UnformattedDrive.  2LOCS

	test	word ptr ds:[di].FLAGS, UNFORMATTED_MEDIA
	jnz	UnformattedDrive
;SB34DISK006******************************************************************
	BIOS_LOW_MEM MOV,<[SECCNT]>,CX,DS		;save sector count
	BIOS_LOW_SAVE_SP <[SPSAV]>

; ENSURE THAT WE ARE TRYING TO ACCESS VALID SECTORS ON THE DRIVE
;

	mov	ax,dx			;AN000; save DX to AX
	xor	si,si			;AN000;
	add	dx,cx			;AN000;
	adc	si,0			;AN000;
	cmp	[di].DrvLim, 0		;AN000; Is this drive > 32 bit sector ?
	je	Sanity32		;AN000;
	cmp	si,0			;AN000;
	jne	BADDRIVE		;AN000;
	cmp	dx, [di].DrvLim 	;AN000;
	ja	BADDRIVE		;AN000;
	jmp	short SanityOK		;AN000;
Sanity32:				;AN000;
	BIOS_LOW_READ ADD,si,<[Start_Sec_H]>,DS	;AN000;
	cmp	si, [di].DrvLim_H	;AN000;
	jb	SanityOK		;AN000;
	ja	BADDRIVE		;AN000;
	cmp	dx, [di].DrvLim_L	;AN000;
	ja	BADDRIVE		;AN000;
SanityOK:				;AN000;
	BIOS_LOW_READ MOV,dx,<[Start_Sec_H]>,DS	;AN000;
	add	ax,word ptr [di].HIDSEC_L    ;AN000;
	adc	dx,word ptr [di].Hidsec_H    ;AN000;
;J.K. Now DX;AX have the physical first sector.
;Since the following procedures is going to destroy AX, let's
;save it temporarily to SAVED_WORD.
	BIOS_LOW_MEM MOV,<[Saved_Word]>,ax,DS	;AN000; Save the sector number (low)

;	 MOV	 SI,DX
;	 ADD	 SI,CX
;	 ADD	 DX,WORD PTR [DI].HIDSEC ; ADD IN THE HIDDEN SECTORS
;	 CMP	 SI,WORD PTR [DI].DRVLIM ; COMPARE AGAINST DRIVE MAX
;	 JA	 BADDRIVE

; SET UP POINTER TO DISK BASE TABLE IN [DPT]. WE CANNOT ASSUME THAT IOSETUP
; WILL DO IT BECAUSE WE WILL SKIP THE SET UP STUFF WITH HARD DISKS.
	PUSH	DS
	XOR	AX,AX
	MOV	DS,AX
	LDS	SI,DWORD PTR DS:[DSKADR]; CURRENT DISK PARM TABLE
	BIOS_LOW_MEM MOV,<WORD PTR DPT>,SI,DS
	BIOS_LOW_MEM MOV,<WORD PTR DPT+2>,DS,ES
	POP	DS
	TEST	WORD PTR [DI].FLAGS,FNON_REMOVABLE
	JNZ	SKIP_SETUP
	CALL	CHECKSINGLE
;
; CHECK TO SEE IF WE HAVE PREVIOUSLY NOTED A CHANGE LINE.  THE ROUTINE
; RETURNS IF EVERYTHING IS OK.	OTHERWISE, IT POPS OFF THE STACK AND RETURNS
; THE PROPER ERROR CODE.
;
;----------------------------------------|
; WARNING: DO NOT CHANGE THE FOLLOWING. ;|
;	   IT GETS PATCHED IN MSINIT	;|
	PUBLIC DISKIO_PATCH		;|
DISKIO_PATCH:				;|
	IFDEF BIOS_SERVICE_SEPARATE_DATA
	BIOS_CALL_LOW BIOS_CHECKLATCH_RESULT,BIOS_LOW_CHECKLATCH_RESULT
	JNC DISKIO_CHECK_CONTINUE
	RET				; caller owns the error return, not the low helper
DISKIO_CHECK_CONTINUE:
	ELSE
	CALL	CHECKLATCHIO		;|
	ENDIF
	PUBLIC BIOS_DISKIO_PATCH_END
BIOS_DISKIO_PATCH_END LABEL BYTE
;----------------------------------------|
;
; SET UP TABLES AND VARIABLES FOR I/O
	CALL	IOSETUP
;
; NOW THE SETTLE VALUES ARE CORRECT FOR THE FOLLOWING CODE
;
SKIP_SETUP:
;J.K. 32 bit sector calculation.
; DX;[Saved_Word] = starting sector number.
	mov	ax,dx			;AN000;
	xor	dx,dx			;AN000;
	DIV	WORD PTR [DI].SECLIM	;DIVIDE BY SEC PER TRACK
	BIOS_LOW_MEM MOV,<[Temp_H]>,ax,DS		;AN000;
	BIOS_LOW_READ MOV,ax,<[Saved_Word]>,DS	;AN000; Restore the lower word
	div	word ptr [di].SecLim	;AN000;
;Now, [Temp_H],AX = track #, DX = sector
	INC	DL			;Sector number is 1 based.
	BIOS_LOW_MEM MOV,<[CURSEC]>,DL,DS		;SAVE CURRENT SECTOR
	MOV	CX,WORD PTR [DI].HDLIM	;GET NUMBER OF HEADS

	push	ax			;AN000;
	XOR	DX,DX			;DIVIDE TRACKS BY HEADS PER CYLINDER
	BIOS_LOW_READ MOV,ax,<[Temp_H]>,DS 	;AN000;
	DIV	CX
	BIOS_LOW_MEM MOV,<[Temp_H]>,ax,DS		;AN000;
	pop	ax			;AN000;
	div	cx			;AN000;
;Now, [Temp_H],AX = cyliner #, DX = head
	BIOS_LOW_MEM CMP,<[Temp_H]>,0,DS		;AN000;
	ja	BADDRIVE_brdg		;AN000;
	cmp	AX, 1024		;AN000; 2**10 currently maxium for track #.
	ja	BADDRIVE_brdg		;AN000;
	BIOS_LOW_MEM MOV,<[CURHD]>,DL,DS		;SAVE CURRENT HEAD
	BIOS_LOW_MEM MOV,<[CURTRK]>,AX,DS		;SAVE CURRENT TRACK

;
; WE ARE NOW SET UP FOR THE I/O.  NORMALLY, WE CONSIDER THE DMA BOUNDARY
; VIOLATIONS HERE.  NOT TRUE.  WE PERFORM THE OPERATION AS IF EVERYTHING IS
; SYMMETRIC; LET THE INT 13 HANDLER WORRY ABOUT THE DMA VIOLATIONS.
;
	BIOS_LOW_READ MOV,AX,<[SECCNT]>,DS
	CALL	BLOCK
	CALL	DONE
	RET
DISKRD	ENDP

;
BADDRIVE_Brdg:jmp Baddrive
;

; SET THE DRIVE-LAST-ACCESSED FLAG FOR DISKETTE ONLY.  WE KNOW THAT THE HARD
; DISK WILL NOT BE REMOVED.
; DS:DI -> CURRENT BDS.
; AX,CX,SI ARE DESTROYED.
;
	PUBLIC IOSETUP
IOSETUP PROC	NEAR
	MOV	AL,[DI].DRIVENUM
	BIOS_LOW_MEM MOV,<[TIM_DRV]>,AL,DS 	; SAVE DRIVE LETTER
;
; DETERMINE PROPER HEAD SETTLE VALUES
;
	BIOS_LOW_MEM CMP,<[Media_Set_For_Format]>,0,DS	;AN012;
	jne	Skip_DPT_Setting		;AN012;
	MOV	CX,DS
	BIOS_LOW_READ LDS,SI,<DWORD PTR [DPT]>,ES	; GET POINTER TO DISK BASE TABLE
	BIOS_LOW_READ MOV,AL,<[EOT]>,DS
	MOV	[SI].DISK_EOT,AL	; BUMP FOR US
	MOV	AL,[SI].DISK_MOTOR_STRT ; PRESERVE OLD MOTOR START TIME
	BIOS_LOW_MEM MOV,<MOTORSTARTUP>,AL,DS
;
; FOR 3.5" DRIVES, BOTH EXTERNAL AS WELL AS ON THE K09, WE NEED TO SET THE
; MOTOR START TIME TO 4. THIS CHECKING FOR EVERY I/O IS GOING TO AFFECT
; PERFORMANCE ACROSS THE BOARD, BUT IS NECESSARY!! - RS
;
	PUSH	ES
	MOV	ES,CX			; ES:DI -> TO CURRENT BDS
	CMP	BYTE PTR ES:[DI].FORMFACTOR,FFSMALL
	JNZ	MOTOR_START_OK
	MOV	AL,4
	XCHG	AL,[SI].DISK_MOTOR_STRT
MOTOR_START_OK:
	POP	ES
;
; DS:SI NOW POINTS TO DISK PARAMETER TABLE.  GET CURRENT SETTLE AND SET FAST
; SETTLE
;
	XOR	AL,AL
	INC	AL			; IBM WANTS FAST SETTLE TO BE 1 - RS.
	XCHG	AL,[SI].DISK_HEAD_STTL	; GET SETTLE AND SET UP FOR FAST
	BIOS_LOW_MEM MOV,<SETTLECURRENT>,AL,DS
	MOV	AL,NORMSETTLE		; SOMEONE HAS DIDDLED THE SETTLE
GOTSLOWSETTLE:
	MOV	DS,CX
	BIOS_LOW_MEM MOV,<SETTLESLOW>,AL,DS
Skip_DPT_Setting:			;AN012;
	RET
;
; SET TIME OF LAST ACCESS, AND RESET DEFAULT VALUES IN THE DPT.
;
DONE:
	TEST	WORD PTR [DI].FLAGS,FNON_REMOVABLE
	JNZ	RETZ			; DO NOT SET FOR NON-REMOVABLE MEDIA
	CALL	SET_TIM 		; SET TIME OF LAST ACCESS FOR DRIVE
;
; RESTORE HEAD SETTLE AND EOT VALUES
;
DIDDLEBACK:
	pushf					;AN013;Save flag
	BIOS_LOW_MEM CMP,<[Media_Set_For_Format]>,0,DS	;AN012;
	jne	NoDiddleBack			;AN012;
	PUSH	AX
	MOV	DX,DS
	BIOS_LOW_READ MOV,AL,<SETTLECURRENT>,DS
	BIOS_LOW_READ MOV,AH,<MOTORSTARTUP>,DS
	BIOS_LOW_READ LDS,SI,<DPT>,ES
;	 MOV	 [SI].DISK_EOT,9	 ;J.K. 4/25/86. Should not change the EOT value
					;of diskbase to 9.  This cause a problem
					;with 1.44M diskette in Polaris when the user
					;issue INT 13 with the default system
					;diskbase.
	mov	[si].DISK_EOT,9 	;J.K. 11/5/86. For compatibility reason, return
					;back to set it to 9 ( PTM826 ).
	MOV	[SI].DISK_HEAD_STTL,AL
	MOV	[SI].DISK_SECTOR_SIZ,2
	MOV	[SI].DISK_MOTOR_STRT,AH
	MOV	DS,DX
	POP	AX
NoDiddleBack:				;AN013;
	popf				;AN013;Restore flag
RETZ:
	RET

;READ THE NUMBER OF SECTORS SPECIFIED IN AX, HANDLING TRACK BOUNDARIES
;DS:DI -> BDS FOR THIS DRIVE
BLOCK:
	OR	AX,AX			;SEE IF ANY SECTORS TO READ
	JZ	RETZ
;Fixed disk will not be restricted to the track-by-track basis. -J.K.4/10/86
	test	word ptr [di].Flags, fNon_Removable  ;J.K. Fixed disk?
	jz	BLOCK_FLOPPY				;J.K.
;SB34DISK002*****************************************************************
;SB	Check to see if multi track operation is allowed.  If not
;SB	we have to go to the block_floppy below to break up the operation.
;SB		2 LOCS
	BIOS_LOW_MEM TEST,<word ptr MulTrk_Flag>,MulTrk_ON,DS
	jz	BLOCK_FLOPPY
;SB34DISK002*****************************************************************
	call	DISK					;J.K.
	xor	ax,ax
	RET						;J.K.
BLOCK_FLOPPY:						;J.K.4/10/86
;
; READ AT MOST 1 TRACK WORTH.  PERFORM MINIMIZATION AT SECTOR / TRACK
;
	MOV	CL,BYTE PTR [DI].SECLIM
	INC	CL
	BIOS_LOW_READ SUB,CL,<CURSEC>,DS		; LEEAC 3.20 ADD SEGMENT OVERRIDE
	XOR	CH,CH
	CMP	AX,CX
	JAE	GOTMIN
	MOV	CX,AX
GOTMIN:
;
; AX IS THE REQUESTED NUMBER OF SECTORS TO READ
; CX IS THE NUMBER THAT WE CAN DO ON THIS TRACK
;
	PUSH	AX
	PUSH	CX
	MOV	AX,CX			; AL IS NUMBER OF SECTORS TO READ
	CALL	DISK
	POP	CX
	POP	AX
;
; CX IS THE NUMBER OF SECTORS JUST TRANSFERRED
;
	SUB	AX,CX			; REDUCE SECTORS-REMAINING BY LAST I/O
	SHL	CL,1
	ADD	BH,CL			; ADJUST TRANSFER ADDRESS
	JMP	BLOCK
IOSETUP ENDP

DskErr_Brdg: jmp DskErr 		;AN003;

;
;PERFORM DISK I/O WITH RETRIES
; AL = NUMBER OF SECTORS (1-8, ALL ON ONE TRACK)
; DI POINT TO DRIVE PARAMETERS
; ES:BX = TRANSFER ADDRESS (MUST NOT CROSS A 64K PHYSICAL BOUNDARY)
; [RFLAG] = 2 IF READ, 3 IF WRITE
; [VERIFY] = 0 FOR NORMAL, 1 FOR VERIFY AFTER WRITE

	PUBLIC DISK
DISK	PROC	NEAR
	MOV	BP,MAXERR		; SET UP RETRY COUNT
	BIOS_LOW_MEM MOV,<VRetry_Cnt>,BP,DS	;AN003;Verify op. retry cnt for Write-Verify.
	BIOS_LOW_MEM MOV,<Soft_ECC_Cnt>,BP,DS	;AN003;Soft ECC error retry count.
	BIOS_LOW_READ MOV,AH,<RFLAG>,DS		;GET READ/WRITE INDICATOR

RETRY:
	PUSH	AX

	BIOS_LOW_READ MOV,DX,<[CURTRK]>,DS		;LOAD CURRENT CYLINDER

	test	word ptr [di].FLAGS, fNon_Removable ;Fixed disk? - J.K. 4/7/86
	jz	DISK_NOT_MINI		;no, skip this. - J.K. 4/7/86
	cmp	[di].IsMini, 1		;Is this a mini disk? - J.K. 4/7/86
	jnz	DISK_NOT_MINI		;No. continue to next.- J.K. 4/7/86
	add	dx, [di].Hidden_Trks	;else add hidden trks.- J.K. 4/7/86
DISK_NOT_MINI:				;J.K. 4/7/86
	ROR	DH,1
	ROR	DH,1

	BIOS_LOW_READ OR,DH,<[CURSEC]>,DS
	MOV	CX,DX
	XCHG	CH,CL			; CL = SECTOR, CH = CYLINDER
	BIOS_LOW_READ MOV,DH,<BYTE PTR [CURHD]>,DS	; LOAD CURRENT HEAD NUMBER AND
	MOV	DL,BYTE PTR [DI].DRIVENUM  ; PHYSICAL DRIVE NUMBER
	CMP	BYTE PTR [DI].FORMFACTOR,FFHARDFILE
	JZ	DO_FAST 		; HARD FILES USE FAST SPEED
; IF WE HAVE [STEP_DRV] SET TO -1, WE USE THE SLOW SETTLE TIME.
; THIS HELPS WHEN WE HAVE JUST DONE A RESED DISK OPERATION AND THE HEAD HAS
; BEEN MOVED TO ANOTHER CYLINDER - THE PROBLEM CROPS UP WITH 3.5" DRIVES.
	BIOS_LOW_MEM CMP,<[STEP_DRV]>,-1,DS
	JZ	DO_WRITEJ
	CMP	AH,ROMREAD		; ARR 2.20
	JE	DO_FAST
	CMP	AH, ROMVERIFY
	JE	DO_FAST
DO_WRITEJ:
; READS ALWAYS FAST, UNLESS WE HAVE JUST DONE A DISK RESET OPERATION
	JMP	DO_WRITE		; ARR 2.20 READS ALWAYS FAST
DO_FAST:				; ARR 2.20
	CALL	FASTSPEED		; MZ  2.21 CHANGE SETTLE MODE
TESTERR:				; MZ  2.21
	JC	DSKERR_brdg
; SET DRIVE AND TRACK OF LAST ACCESS
	BIOS_LOW_MEM MOV,<[STEP_DRV]>,DL,DS	; ARR 2.20 SET DRIVE
	MOV	BYTE PTR [DI].TRACK,CH	; ARR 2.20 SAVE TRACK
NO_SET:
	BIOS_LOW_MEM CMP,<WRTVERIFY>,103H,DS	; CHECK FOR WRITE AND VERIFY
	JZ	DOVERIFY
NOVERIFY:
	POP	AX

;SB34DISK003*****************************************************************
;SB	Check the flags word in the BDS to see if the drive is non removable
;SB	If not we needn't do anything special
;SB	If it is a hard disk then check to see if multi-track operation
;SB	is specified.  If specified we don't have to calculate for the next
;SB	track since we are already done.  So we can go to the exit of this 
;SB	routine.	5 LOCS

	test	word ptr [di].FLAGS, fNON_REMOVABLE
	jz	ITS_REMOVABLE
	BIOS_LOW_MEM TEST,<MulTrk_Flag>,MulTrk_ON,DS
	jnz	DISK_RET
ITS_REMOVABLE:
;SB34DISK003*****************************************************************
	AND	CL,03FH 		; ELIMINATE CYLINDER BITS FROM SECTOR
	XOR	AH,AH
	BIOS_LOW_MEM SUB,<[SECCNT]>,AX,DS		; REDUCE COUNT OF SECTORS TO GO
	ADD	CL,AL			; NEXT SECTOR
	BIOS_LOW_MEM MOV,<[CURSEC]>,CL,DS
	CMP	CL,BYTE PTR [DI].SECLIM ; SEE IF SECTOR/TRACK LIMIT REACHED
	JBE	DISK_RET
NEXTTRACK:
	BIOS_LOW_MEM MOV,<[CURSEC]>,1,DS		; START WITH FIRST SECTOR OF NEXT TRACK
	BIOS_LOW_READ MOV,DH,<[CURHD]>,DS
	INC	DH
	CMP	DH,BYTE PTR [DI].HDLIM
	JB	NOXOR
	XOR	DH,DH
	BIOS_LOW_UNARY INC,<[CURTRK]>
NOXOR:
	BIOS_LOW_MEM MOV,<[CURHD]>,DH,DS
DISK_RET:
	CLC				; LEEAC
	RET
DISK	ENDP


; THE REQUEST IS FOR WRITE.  DETERMINE IF WE ARE TALKING ABOUT THE SAME
; TRACK AND DRIVE.  IF SO, USE THE FAST SPEED.

DO_WRITE PROC	NEAR
	BIOS_LOW_READ CMP,DL,<[STEP_DRV]>,DS	; ARR 2.20
	JNZ	DO_NORM 		;  WE HAVE CHANGED DRIVES

	CMP	CH,BYTE PTR [DI].TRACK	; ARR 2.20
	JZ	DO_FAST 		; WE ARE STILL ON THE SAME TRACK

DO_NORM:
	CALL	NORMSPEED
	JMP	TESTERR		; allow the separated-data body to grow
DO_WRITE ENDP
;
; WE HAVE A VERIFY REQUEST ALSO.  GET STATE INFO AND GO VERIFY
;

DOVERIFY PROC	NEAR
	POP	AX			; RESTORE SECTOR COUNT
	PUSH	AX
	MOV	AH,ROMVERIFY		; REQUEST VERIFY
	CALL	FASTSPEED		; MZ  2.21 CHANGE SETTLE MODE
	JNC	NOVERIFY

;SB34DISK004**************************************************************
;SB	check the error returned in AH to see if it is a SOFT ECC error.
;SB	If it is not we needn't do anything special.  If it is a SOFT
;SB	ECC error then decrement the SOFT_ECC_CNT error retry count. If
;SB	this retry count becomes 0 then we just  ignore the error and go to
;SB	No_verify but if we can still try then we call the routine to reset
;SB	the disk and go to DSKerr1 to retry the operation.	6 LOCS

	cmp	ah,11h			;SOFT ECC error ?
	jnz	Not_SoftECC_Err
	BIOS_LOW_UNARY DEC,<Soft_ECC_Cnt>
	jz	NoVerify		;no more retry
	call	ResetDisk		;reset disk
	jmp	DskErr1			;retry

;SB34DISK004**************************************************************

Not_SoftECC_Err:			;AN003;Other error.
	call	ResetDisk		;AN003;
	BIOS_LOW_UNARY DEC,<VRetry_Cnt>
	jmp	DskErr0 		;AN003;
DOVERIFY ENDP
;
; NEED TO SPECIAL CASE THE CHANGE-LINE ERROR AH=06H.  IF WE GET THIS, WE
; NEED TO RETURN IT.
;
;----------------------------------------|
; WARNING: DO NOT CHANGE THE FOLLOWING. ;|
;	   IT GETS PATCHED IN MSINIT	;|
	PUBLIC DSKERR			;|
DSKERR	PROC	NEAR			;|
	IFDEF BIOS_SERVICE_SEPARATE_DATA
	BIOS_CALL_LOW BIOS_CHECKIO_RESULT,BIOS_LOW_CHECKIO_RESULT
	JNC DSKERR_CHECK_CONTINUE
	JMP HARDERR2			; mapped error; unwind SPSAV in the high caller
DSKERR_CHECK_CONTINUE:
	ELSE
	CALL	CHECKIO 		;|
	ENDIF
	PUBLIC BIOS_DSKERR_PATCH_END
BIOS_DSKERR_PATCH_END LABEL BYTE
;---------------------------------------;|

	BIOS_LOW_MEM CMP,<MultiTrk_Format_Flag>,1,DS ;AN007;Multi trk format request?
	jne	DoChkAgain		   ;AN007;
	mov	bp, 1			   ;AN007;No more retry.
	BIOS_LOW_MEM MOV,<MultiTrk_Format_Flag>,0,DS ;AN007;Clear the flag.
DoChkAgain:				   ;AN007;
	CALL	AGAIN
DskErr0:				;AN003;
	JZ	HARDERR
	test	word ptr [di].FLAGS, fNon_Removable	;AN009;
	jnz	Skip_TimeOut_Chk			;AN009;
	CMP	AH,80H			;TIMEOUT?
	JZ	HARDERR 		;***
Skip_TimeOut_Chk:			;AN009;
	cmp	ah, 0cch		;AN003;Write Fault error?
	jz	Write_Fault_Err 	;AN003; Then, don't retry.
	BIOS_LOW_MEM MOV,<Soft_ECC_Cnt>,MAXERR,DS ;AN003;Set Soft_ECC_Cnt back to MAXERR
DSKERR1:
	POP	AX			;RESTORE SECTOR COUNT
	JMP	RETRY

Write_Fault_Err:			;AN003;
	mov	bp, 1			;AN003;Just retry only once for Write Fault error.
	jmp	DskErr1 		;AN003;

HARDERR:
	PUBLIC	HARDERR

	CALL	MAPERROR

HARDERR2:			; FOR ROUTINES THAT CALL MAPERROR THEMSELVES
	PUBLIC	HARDERR2

	BIOS_LOW_MEM MOV,<[TIM_DRV]>,-1,DS 	;FORCE A MEDIA CHECK THROUGH ROM
	BIOS_LOW_READ MOV,CX,<SECCNT>,DS		;GET COUNT OF SECTORS TO GO
	BIOS_LOW_RESTORE_SP <[SPSAV]>
;
; SINCE WE ARE PERFORMING A NON-LOCAL GOTO, RESTORE THE DISK PARAMETERS
;
MEDBYT_OK:
	CALL	DIDDLEBACK
	RET				;AND RETURN
DSKERR	ENDP

;
; CHANGE SETTLE VALUE FROM SETTLECURRENT TO WHATEVER IS APPROPRIATE
; NOTE THAT THIS ROUTINE IS NEVER CALLED FOR A FIXED DISK.
;
NORMSPEED PROC	NEAR
	BIOS_LOW_MEM CMP,<[Media_Set_For_Format]>,0,DS	;AN012;
	jne	FASTSPEED			;AN012;
	PUSH	DS
	PUSH	AX
	BIOS_LOW_READ MOV,AL,<SETTLESLOW>,DS
	BIOS_LOW_READ LDS,SI,<DPT>,ES		; CURRENT DISK PARM TABLE
	MOV	[SI].DISK_HEAD_STTL,AL
	POP	AX
	POP	DS
	CALL	FASTSPEED
	PUSH	DS
	BIOS_LOW_READ LDS,SI,<DPT>,ES
	MOV	[SI].DISK_HEAD_STTL,1	; 1 IS FAST SETTLE VALUE
	POP	DS
	RET
NORMSPEED ENDP

FASTSPEED PROC	NEAR
;
; IF THE DRIVE HAS BEEN MARKED AS TOO BIG (I.E. STARTING SECTOR OF THE
; PARTITION IS > 16 BITS, THEN ALWAYS RETURN DRIVE NOT READY.
;
	TEST	BYTE PTR [DI].FATSIZ,FTOOBIG
 IF iTEST
	JZ	READY
	JMP	NOTREADY
READY:
 ELSE
	JNZ	NOTREADY
 ENDIF

	MESSAGE FTESTINIT,<"<">
	MNUM	FTESTINIT,AX
	MESSAGE FTESTINIT,<",">
	MNUM	FTESTINIT,ES
	MESSAGE FTESTINIT,<":">
	MNUM	FTESTINIT
	MESSAGE FTESTINIT,<",">
	MNUM	FTESTINIT,CX
	MESSAGE FTESTINIT,<",">
	MNUM	FTESTINIT,DX
	MESSAGE FTESTINIT,<">">
	BIOS_ROM_INT13
DEATH:
	RET
NOTREADY:
	STC
	MOV	AH,80H
	JMP	DEATH
FASTSPEED ENDP

; MAP ERROR RETURNED BY ROM IN AH INTO CORRESPONDING CODE TO BE RETURNED TO
; DOS IN AL.
;
MAPERROR PROC	NEAR
	PUBLIC	MAPERROR

	PUSH	CX			; SAVE CX
	BIOS_PUSH_DATA_SEG
	POP	ES			;MAKE ES THE LOCAL SEGMENT
	MOV	AL,AH			;PUT ERROR CODE IN AL
	BIOS_LOW_MEM MOV,<[LSTERR]>,AL,DS		;TERMINATE LIST WITH ERROR CODE
	MOV	CX,NUMERR		;NUMBER OF POSSIBLE ERROR CONDITIONS
	MOV	DI,OFFSET ERRIN      ;POINT TO ERROR CONDITIONS
	REPNE	SCASB
	BIOS_LOW_READ MOV,AL,<[DI + NUMERR - 1]>,DS ; low error translation
	POP	CX			; RESTORE CX
	STC				;FLAG ERROR CONDITION
	RET
MAPERROR ENDP

; SET THE TIME OF LAST ACCESS FOR THIS DRIVE. THIS IS DONE ONLY FOR REMOVABLE
; MEDIA.

	PUBLIC SET_TIM
SET_TIM PROC	NEAR
	PUSH	AX
;SB33018******************************************************************
	xor	AH, AH			; set command to get time      ;SB;3.30*
	BIOS_ROM_INT1A			; call rom-bios timer function ;SB;3.30*
;SB33018******************************************************************
	OR	AL,AL
	JZ	NOROLL3
	BIOS_LOW_UNARY INC,<[DAYCNT]>
NOROLL3:
; WE HAVE THE NEW TIME. IF WE SEE THAT THE TIME HAS PASSED, THEN WE RESET
; THE THRESHOLD COUNTER...
	CMP	DX,WORD PTR [DI].TIM_LO
	JNZ	SETACCESS
	CMP	CX,WORD PTR [DI].TIM_HI
	JZ	DONE_SET
SETACCESS:
	BIOS_LOW_MEM MOV,<BYTE PTR [ACCESSCOUNT]>,0,DS
	MOV	WORD PTR [DI].TIM_LO,DX 	    ;SAVE IT
	MOV	WORD PTR [DI].TIM_HI,CX
DONE_SET:
	CLC
	POP	AX
	RET
SET_TIM ENDP

	ASSUME	CS:BIOS_SERVICE_CS,DS:NOTHING,ES:NOTHING,SS:NOTHING

;
; THIS IS THE TRUE INT 13 HANDLER.  WE PARSE THE REQUEST TO SEE IF THERE IS
; A DMA VIOLATION.  IF SO, DEPENDING ON THE FUNCTION, WE:
;   READ/WRITE	BREAK THE REQUEST INTO THREE PIECES AND MOVE THE MIDDLE ONE
;	INTO OUR INTERNAL BUFFER.
;   FORMAT	COPY THE FORMAT TABLE INTO THE BUFFER
;   VERIFY	POINT THE TRANSFER ADDRESS INTO THE BUFFER
;
; THIS IS THE BIGGEST BOGOSITY OF ALL.	THE IBM CONTROLLER DOES NOT HANDLE
; OPERATIONS THAT CROSS PHYSICAL 64K BOUNDARIES.  IN THESE CASES, WE COPY
; THE OFFENDING SECTOR INTO THE BUFFER BELOW AND DO THE I/O FROM THERE.
;
INT13FRAME  STRUC
OLDBP	DW  ?
OLDAX	DW  ?
OLDBX	DW  ?
OLDCX	DW  ?
OLDDX	DW  ?
OLDDD	DD  ?
OLDF	DW  ?
INT13FRAME  ENDS

;   ENTRY CONDITIONS:
;	AH = FUNCTION
;	AL = NUMBER OF SECTORS
;	ES:BX = DMA ADDRESS
;	CX = PACKED TRACK AND SECTOR
;	DX = HEAD AND DRIVE
;   OUTPUT CONDITIONS:
;	NO DMA VIOLATION.
;
	PUBLIC BLOCK13
BLOCK13 PROC	FAR
;
; LET THE OPPERATION PROCEED.  IF THERE IS A DMA VIOLATION, THEN WE DO THINGS.
;
	BIOS_LOW_MEM MOV,<PREVOPER>,AX,DS		; SAVE REQUEST
	PUSHF
	CMP	AH,ROMFORMAT
	JNZ	NOT_FORMAT
; SET CHANGED BY FORMAT BIT FOR ALL LOGICAL DRIVES USING THIS PHYSICAL DRIVE
;---------------------------------------------------------|
; WARNING: DO NOT CHANGE THE FOLLOWING.
; IT GETS PATCHED IN AT INIT TIME			  |
	PUBLIC CHANGED_PATCH
CHANGED_PATCH:
	BIOS_LOW_MEM MOV,<WORD PTR [FLAGBITS]>,FCHANGED_BY_FORMAT+FCHANGED,DS
	BIOS_CALL_LOW SET_CHANGED_DL,BIOS_LOW_SET_CHANGED
	PUBLIC BIOS_CHANGED_PATCH_END
BIOS_CHANGED_PATCH_END LABEL BYTE
;							  |
;---------------------------------------------------------|
NOT_FORMAT:
	test	dl, 80h			; floppy or hard disk?
	jnz	not_floppy		; if hard, skip this nonsense
	BIOS_LOW_MEM CMP,<EC35_Flag>,0,DS		; any electrically compat. drives?
	jz	not_floppy		; no; proceed unhindered
	SAVEREG	<ax, bx, cx>
	mov	cl, dl			; turn drive number into bit map:
	mov	al, 1			;   assume drive 0
	shl	al, cl			;   shift over correct number of times
	BIOS_LOW_READ TEST,al,<EC35_Flag>,DS	; is THIS drive an electrically compatible 3.5 incher?
	jz	not_EC35		; no; don't change anything
	mov	bl, dl			; which drive was it?
	xor	bh, bh			; need only one byte of index
	push	es			; need a segment register
	mov	ax, 40h			; the machine state byte is in the...
	mov	es, ax			; ...segment at 40h
	mov	byte ptr es:[90h+bx], 93H	; establish drive type as: (360k disk in 360k drive, no double-stepping, 250 kbs transfer rate)
	pop	es			; fix up register again
not_EC35:
	RESTOREREG <cx, bx, ax>
not_floppy:
	BIOS_LOW_MEM CMP,<[model_byte]>,mdl_ps2_30,DS	; is this a ps2/30?
	jne	not_ps2_30		; if not, just do normal call
	cmp	ah, 8			;J.K. 1/30/87 Read Driver Parm ?
	je	ps2_30_Problem		;J.K. 1/30/87
	cmp	ah, 15h
	je	ps2_30_Problem
not_ps2_30:
	BIOS_ROM_ORIG13			; SIMULATE INT 13
	JC	GOTERR13_br		; ERROR?
	RET	2			; NO, RETURN AND CLEAR FLAGS

GOTERR13_br: jmp Goterr13

;J.K.1/30/87 ps2_30 machine has some problem with AH=8h(Read Drive Parm), Int 13h.
;This function does not reset the common buses after the execution.
;To solve this problem, when we detect AH=8h, then we will save the result and
;will issue AH=1 (Read Status) call to reset the buses.

ps2_30_Problem: 			;J.K. 1/30/87; ps2_30 = PS2 Model 30.
	BIOS_LOW_MEM MOV,<Prev_DX>,DX,DS		;save orignal drive number
	BIOS_ROM_ORIG13			;Do "Read drive parm"

	pushf
	push	ax
	push	bx
	push	cx
	push	dx
	push	di
	push	si
	push	bp
	push	ds
	push	es

	BIOS_LOW_READ MOV,dx,<Prev_DX>,DS		;restore orignal drive
	pushf
	mov	ah, 1			;Read Status.
	BIOS_ROM_ORIG13			;Reset the bus as a side effect of this call.

	pop	es			;restore first call's registers and flags
	pop	ds
	pop	bp
	pop	si
	pop	di
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	popf
	jc	GotErr13		;AH=8 had been an error?
	ret	2

;
; SOME KIND OF ERROR OCCURRED.	SEE IF IT IS DMA VIOLATION
;
GOTERR13:
	PUSHF
	cmp	ah, 09h 		;AN011; DMA error?
	je	Chk_ValidMedia_ERR13	;AN011;
	cmp	ah, 11h 		;AN011; ECC error?
	je	Chk_ValidMedia_ERR13	;AN011;
	jmp	Skip_Ecc_Check		;AN011; Other error.  Just return back.

Chk_ValidMedia_ERR13:			;AN011;If SetDrive fails, then just
	push	ds			;AN011;    return back to INT 13h caller,
	push	di			;AN011;      without performing ECC, DMA
	push	ax			;AN011; 	error handling.
	mov	al, dl			;AN011;
	call	SetDrive_Physical	;AN011;
	pop	ax			;AN011;
	pop	di			;AN011;
	pop	ds			;AN011;
	jc	Skip_Ecc_Check		;AN011;

; TEST OF BIT PATTERN 08H LET OTHER ERRORS BE PASSED AS DMA ERRORS - PTR 32D0519
;	TEST	AH,08H			; DMA BIT
	CMP	AH, 09H 		; DMA ERROR CODE
	JNZ	CHECK_ECC
	JMP	GOTDMAERR
CHECK_ECC:
;J.K. AN003; Soft ECC bug is only applied to PC1 and PC-XT. So, we will enforce
;this ECC error handler for them.   Also, since CMC hardfiles in PC AT also
;generate a lot of unnecessary ECC errors, we will still cover PC ATs as
;it is done in the earlier version of MSBIO.
;During Format/Verify operation, we are going to consider any Soft Ecc as a
;hard error.

;SB34DISK005*****************************************************************
;SB	See if the machine we are operating on is a PC, XT or AT by checking
;SB	the model byte.  The soft ECC bug is only on these machines and if
;SB	the machine we are operating on is not one of these three then we
;SB	needn't do anything special.  If we are operating one these however
;SB	we check to see if the error occured during format by checking
;SB	media_set_for_format.  If it did occur during format we cannot do
;SB	anything but if not during format then check to see if the error
;SB	returned in AH is the SOFT_ECC error and if so go to OK11 since
;SB	the error can be ignored.  6 LOCS

	BIOS_LOW_MEM CMP,<[Media_Set_For_Format]>,1,DS ; formatting?
	je	Skip_Ecc_Check
	BIOS_LOW_MEM CMP,<[Model_Byte]>,0FEh,DS	; PC or XT?
	jae	Go_Chk_Ecc
	BIOS_LOW_MEM CMP,<[Model_Byte]>,0FBh,DS	; XT?
	je	Go_Chk_Ecc
	BIOS_LOW_MEM CMP,<[Model_Byte]>,0FCh,DS
	jne	Skip_Ecc_Check
	BIOS_LOW_MEM CMP,<[Secondary_Model_Byte]>,2,DS ; AT?
	ja	Skip_Ecc_Check
Go_Chk_Ecc:				; for PC, XT, AT
	CMP	AH,11H
	JZ	OK11
Skip_Ecc_Check: 			;AN003; Just return back to INT 13h caller.

;SB34DISK005*****************************************************************

	POPF
	RET	2
;
; WE HAVE AN ERROR STATUS 11H.	THIS INDICATES AN ECC-CORRECTED ERROR.	NOTE
; THAT THIS INDICATES THAT THE DATA IS PROBABLY CORRECT BUT NOT CERTAINLY
; CORRECT. THE ROMS ON PC-1S AND PC_XTS HAVE A 'BUG' IN THAT IF AN ECC ERROR
; OCCURS FOR A MULTI-SECTOR READ, ONLY THE SECTORS UP TO THE ONE WHERE THE
; ERROR OCCURRED ARE READ IN. WE HAVE NO WAY OF KNOWING HOW MANY WERE READ IN
; THIS CASE, SO WE REDO THE OPERATION, READING ONE SECTOR AT A TIME. IF WE
; GET AN ECC ERROR ON READING ONE SECTOR, WE IGNORE THE ERROR BECAUSE THE
; SECTOR HAS BEEN READ IN.
;
	PUBLIC OK11
OK11:
;	 POPF
;J.K. 8/29/86 Here, it is better reset the system. So, we are going to
;call Orig13 again

	xor	ah, ah
	BIOS_ROM_ORIG13			;reset. Don't care about the result

	BIOS_LOW_READ MOV,AX,<[PREVOPER]>,DS	; RETRIEVE REQUEST
;
; THIS WILL PROVIDE A TERMINATION POINT.
;
	CMP	AL,1			; IF REQUEST FOR ONE SECTOR, ASSUME OK
	JNZ	ECC_ERR_HANDLE
	XOR	AH,AH			; CLEAR CARRY TOO!
	RET	2

	PUBLIC ECC_ERR_HANDLE
ECC_ERR_HANDLE:
	SAVEREG <BX,CX,DX>
	BIOS_LOW_MEM MOV,<[NUMBER_OF_SEC]>,AL,DS
LOOP_ECC:
	BIOS_LOW_READ MOV,AX,<[PREVOPER]>,DS
	MOV	AL,1			; REQUEST FOR ONE SECTOR ONLY
;
; WE DO READS ONE SECTOR AT A TIME. THIS ENSURES THAT WE WILL EVENTUALLY
; FINISH THE REQUEST SINCE ECC ERRORS ON ONE SECTOR DO READ IN THAT SECTOR.
;
; WE NEED TO PUT IN SOME "INTELLIGENCE" INTO THE ECC HANDLER TO HANDLE READS
; THAT ATTEMPT TO READ MORE SECTORS THAN ARE AVAILABLE ON A PARTICULAR
; TRACK.
; WE CALL CHECK_WRAP TO SET UP THE SECTOR #, HEAD # AND CYLINDER # FOR
; THIS REQUEST.
; AT THIS POINT, ALL REGISTERS ARE SET UP FOR THE CALL TO ORIG13, EXCEPT
; THAT THERE MAY BE A STARTING SECTOR NUMBER THAT IS BIGGER THAN THE NUMBER
; OF SECTORS ON A TRACK.
;
	CALL	CHECK_WRAP		; GET CORRECT PARAMETERS FOR INT 13
	PUSHF
	BIOS_ROM_ORIG13
	JNC	OK11_OP
	CMP	AH,11H			; ONLY ALLOW ECC ERRORS
	JNZ	OK11_EXIT_err		;J.K. 8/26/86 Other error?
	mov	ah, 0			;J.K. ECC error. Reset the system again.
	pushf
	BIOS_ROM_ORIG13
	xor	ax, ax			; clear the error code so that if this 
					; was the last sector, no error code 
					; will be returned for the corrected 
					; read. (clear carry too.)
OK11_OP:
	BIOS_LOW_UNARY DEC,<[NUMBER_OF_SEC]>
	JZ	OK11_EXIT		; ALL DONE?
	INC	CL			; ADVANCE SECTOR NUMBER
	INC	BH			; ADD 200H TO ADDRESS
	INC	BH
	JMP	SHORT LOOP_ECC
OK11_EXIT_err:
	stc				;J.K. 8/28/86 Set carry bit again.
OK11_EXIT:
	RESTOREREG <DX,CX,BX>
	RET	2
;
; WE TRULY HAVE A DMA VIOLATION.  RESTORE REGISTER AX AND RETRY THE
; OPERATION AS BEST WE CAN.
;
GOTDMAERR:
	POP	AX			; CLEAN UP STACK
	BIOS_LOW_READ MOV,AX,<PREVOPER>,DS
	STI
	CMP	AH,ROMREAD		; SAVE USER FLAGS
	JB	INTDONE
	CMP	AH,ROMVERIFY
	JZ	INTVERIFY
	CMP	AH,ROMFORMAT
	JZ	INTFORMAT
	JA	INTDONE
;
; WE ARE DOING A READ/WRITE CALL.  CHECK FOR DMA PROBLEMS
;
	SAVEREG <DX,CX,BX,AX>
	PUSH	BP
	MOV	BP,SP
	MOV	DX,ES			; CHECK FOR 64K BOUNDARY ERROR

	SHL	DX,1
	SHL	DX,1
	SHL	DX,1
	SHL	DX,1			; SEGMENT CONVERTED TO ABSOLUTE ADDRESS

	ADD	DX,BX			; COMBINE WITH OFFSET
	ADD	DX,511			; SIMULATE A TRANSFER
;
; IF CARRY IS SET, THEN WE ARE WITHIN 512 BYTES OF THE END OF THE SEGMENT.
; WE SKIP THE FIRST TRANSFER AND PERFORM THE REMAINING BUFFERING AND TRANSFER
;
	JNC	NO_SKIP_FIRST
	MOV	DH,BYTE PTR [BP.OLDDX+1]	; SET UP HEAD NUMBER
	JMP	BUFFER			;J.K. 4/10/86
;	JMP	SHORT BUFFER
;
; DX IS THE PHYSICAL 16 BITS OF START OF TRANSFER.  COMPUTE REMAINING
; SECTORS IN SEGMENT.
;
NO_SKIP_FIRST:
	SHR	DH,1			; DH = NUMBER OF SECTORS BEFORE ADDRESS
	MOV	AH,128			; AH = MAX NUMBER OF SECTORS IN SEGMENT
	SUB	AH,DH
;
; AH IS NOW THE NUMBER OF SECTORS THAT WE CAN SUCCESSFULLY WRITE IN THIS
; SEGMENT.  IF THIS NUMBER IS ABOVE OR EQUAL TO THE REQUESTED NUMBER, THEN WE
; CONTINUE THE OPERATION AS NORMAL.  OTHERWISE, WE BREAK IT INTO PIECES.
;
	CMP	AH,AL			; CAN WE FIT IT IN?
	JB	DOBLOCK 		; NO, PERFORM BLOCKING.
;
; YES, THE REQUEST FITS.  LET IT HAPPEN
;
	MOV	DH,BYTE PTR [BP.OLDDX+1]	; SET UP HEAD NUMBER
	CALL	DOINT
	JMP	BAD13
;
; VERIFY THE GIVEN SECTORS.  PLACE THE BUFFER POINTER INTO OUR SPACE.
;
INTVERIFY:
	SAVEREG <ES,BX>
	BIOS_PUSH_DATA_SEG
	POP	ES
DOSIMPLE:
	MOV	BX,OFFSET DISKSECTOR
	PUSHF
	BIOS_ROM_ORIG13
	RESTOREREG  <BX,ES>
	RET	2

;
; FORMAT OPERATION.  COPY THE PARAMETER TABLE INTO MEMORY
;
INTFORMAT:
	SAVEREG <ES,BX>
	SAVEREG <SI,DI,DS>
	PUSH	ES
	BIOS_PUSH_DATA_SEG
	POP	ES
	POP	DS
	MOV	SI,BX
	MOV	DI,OFFSET DISKSECTOR
	CALL	MOVE
	RESTOREREG  <DS,DI,SI>
	JMP	DOSIMPLE
;
; INLINE CONTINUATION OF OPERATION
;
INTDONE:
	BIOS_CHAIN_VECTOR ORIG13,BIOS_SERVICE_ORIG13_OFFSET

;
; We can't fit the request into the entire block.  Perform the operation on
; the first block.
;
; DoBlock is modified to correctly handle multi-sector disk I/O. -J.K. 4/10/86
; Old DoBlock had added the number of sectors I/Oed (Ah in Old DoBlock) after
; the DoInt call to CL.  Observing only the lower 6 bits of CL(=max. 64) can
; represent a starting sector, if AH was big, then CL would be clobbered.
; By the way, we still are going to use CL for this purpose since Checkwrap
; routine will use it as an input.  To prevent CL from being clobbered, a
; safe number of sectors should be calculated like "63 - # of sectors/track".
; DoBlock will handle the first block of requested sectors within the
; boundary of this safe value. - J.K. 2/28/86

DoBlock:
;Try to get the # of sectors/track from BDS via Rom drive number.
;For any mini disks installed, here we have to pray that they have the
;same # of sector/track as the main DOS partition disk drive.

	Message ftestDisk,<"!!!DMA DoBlock!!!">

	mov	dx, word ptr [bp.olddx] ;set head #
	push	di
	push	ds
	push	ax			;AH - # of sectors before DMA boundary
					;AL - User requeseted # of sectors for I/O.
	mov	al, dl
	call	SetDrive_Physical	;get BDS pointer for this DISK.
	pop	ax
	test	word ptr [DI].Flags, fNon_Removable	;don't have to worry
	jnz	DoBlockHard		;about floppies. They are track by track operation.
	mov	al, ah			;set al = ah for floppies
	jmp	short DoBlockCont
DoBlockHard:
	push	cx
	xor	cx, cx
	mov	cx, [DI].SecLim 	;# of sectors/track
	mov	ch, 63
	sub	ch, cl
	mov	al, ch
	xchg	ah, al			;now ah - safe # of sectors
					;al - # of sectors before DMA boundary
	pop	cx
DoBlockCont:
	pop	ds
	pop	di
DoBlockContinue:
	Message ftestDisk,<"%%DMA DoBlock Loop%%">
	cmp	ah, al			;if safe_# >= #_of_sectors_to_go_before DMA,
	jae	DoBlocklast		;then #_of_sectors_to_go as it is for DoInt.
	push	ax			;save AH, AL
	mov	al, ah			;Otherwise, set al to ah to operate.
	jmp	short DoBlockDoInt	;DoInt will set AH to a proper function in [BP.Oldax]
DoBlocklast:
	mov	ah, al
	push	ax			;save AH
DoBlockDoInt:				;let AH = AL = # of sectors for this shot
	CALL	DoInt
	JC	BAD13			;something happened, bye!
	pop	ax
	SUB	BYTE PTR [BP.oldax], AH ;decrement by the successful operation
	ADD	CL,AH			;advance sector number. Safety gauranteed.
	ADD	BH,AH			;advance DMA address
	ADD	BH,AH			;twice for 512 byte sectors.
	cmp	ah, al			;check the previous value
	je	Buffer			;if #_of_sectors_to_go < safe_#, then we are done already.
	sub	al, ah			;otherwise, #_sector_to_go = #_of_sector_to_go - safe_#
	call	Check_Wrap		;get new CX, DH for the next operation.
	jmp	short DoBlockContinue	;handles next sectors left.
;End of modificaion of DoBlock	- J.K. 2/28/86
;The following is the original one.
;	 PUSH	 AX
;	 MOV	 AL,AH			 ; get max to operate on
;	 MOV	 AH,BYTE PTR [BP.oldax+1]; get function
;	 mov	 dh,byte ptr [BP.olddx+1]	 ; set up head number
;	 CALL	 DoInt
;	 JC	 Bad13			 ; something happened, bye!
;	 POP	 AX
;	 SUB	 BYTE PTR [BP.oldax],AH  ; decrement by the successful operation
;	 ADD	 CL,AH			 ; advance sector number
;	 ADD	 BH,AH			 ; advance DMA address
;	 ADD	 BH,AH			 ; twice for 512 byte sectors.

;
; THE NEXT REQUEST WILL WRAP THE 64K BOUNDARY.	IF WE ARE WRITING, THEN COPY
; THE OFFENDING SECTOR INTO OUR SPACE.
;
;   ES:BX POINTS TO THE SECTOR
;   CX,DX CONTAIN THE CORRECT TRACK/SECTOR/HEAD/DRIVE INFO
;   [BP.OLDAX] HAS CORRECT FUNCTION CODE
;
BUFFER:
	PUSH	BX
	MOV	AH,BYTE PTR [BP.OLDAX+1]
	CMP	AH,ROMWRITE
	JNZ	DOREAD
;
; COPY THE OFFENDING SECTOR INTO LOCAL BUFFER
;
	SAVEREG <DS,ES,SI,DI>
	BIOS_PUSH_DATA_SEG			; EXCHANGE SEGMENT REGISTERS
	PUSH	ES
	POP	DS
	POP	ES
	MOV	DI,OFFSET DISKSECTOR	; WHERE TO MOVE
	PUSH	DI			; SAVE IT
	MOV	SI,BX			; SOURCE
	CALL	MOVE
	POP	BX			; NEW TRANSFER ADDRESS
	RESTOREREG  <DI,SI>
	MOV	AL,1
; SEE IF WE ARE WRAPPING AROUND A TRACK OR HEAD
	MOV	DL,BYTE PTR [BP.OLDDX]	; GET DRIVE NUMBER
	CALL	CHECK_WRAP		; SETS UP REGISTERS IF WRAP-AROUND
;
;   AH IS FUNCTION
;   AL IS 1 FOR SINGLE SECTOR TRANSFER
;   ES:BX IS LOCAL TRANSFER ADDRES
;   CX IS TRACK/SECTOR NUMBER
;   DX IS HEAD/DRIVE NUMBER
;   SI,DI UNCHANGED
;
	CALL	DOINT
	RESTOREREG  <ES,DS>
	JC	BAD13			; GO CLEAN UP
	JMP	SHORT DOTAIL
;
; READING A SECTOR.  DO INT FIRST, THEN MOVE THINGS AROUND
;
DOREAD:
	SAVEREG <ES,BX>
	BIOS_PUSH_DATA_SEG
	POP	ES
	MOV	BX,OFFSET DISKSECTOR
	MOV	AL,1
; SEE IF OUR REQUEST WILL WRAP A TRACK OR HEAD BOUNDARY
	MOV	DL,BYTE PTR [BP.OLDDX]	; GET DRIVE NUMBER
	CALL	CHECK_WRAP		; SETS UP REGISTERS IF WRAP-AROUND
;
;   AH = FUNCTION
;   AL = 1 FOR SINGLE SECTOR
;   ES:BX POINTS TO LOCAL BUFFER
;   CX, DX ARE TRACK/SECTOR, HEAD/DRIVE
;
	CALL	DOINT
	RESTOREREG  <BX,ES>
	JC	BAD13			; ERROR => CLEAN UP
	SAVEREG <DS,SI,DI>
	BIOS_PUSH_DATA_SEG
	POP	DS
	MOV	DI,BX
	MOV	SI,OFFSET DISKSECTOR
	CALL	MOVE
	RESTOREREG  <DI,SI,DS>
;
; NOTE THE FACT THAT WE'VE DONE 1 MORE SECTOR
;
DOTAIL:
	POP	BX			; RETRIEVE NEW DMA AREA
	ADD	BH,2			; ADVANCE OVER SECTOR
	INC	CX
	MOV	AL,BYTE PTR [BP.OLDAX]
	CLC
	DEC	AL
	JZ	BAD13			; NO MORE I/O
; SEE IF WE WRAP AROUND A TRACK OR HEAD BOUNDARY WITH STARTING SECTOR
; WE ALREADY HAVE THE CORRECT HEAD NUMBER TO PASS TO CHECK_WRAP
	MOV	DL,BYTE PTR [BP.OLDDX]	; GET DRIVE NUMBER
	CALL	CHECK_WRAP		; SETS UP REGISTERS IF WRAP-AROUND
	CALL	DOINT
;
; WE ARE DONE.	AX HAS THE FINAL CODE; WE THROW AWAY WHAT WE GOT BEFORE
;
BAD13:
	MOV	SP,BP
	RESTOREREG  <BP,BX,BX,CX,DX>
	RET	2
BLOCK13 ENDP
	PAGE
	INCLUDE MSIOCTL.INC
	PAGE
; CHECK_WRAP IS A ROUTINE THAT ADJUSTS THE STARTING SECTOR, STARTING HEAD
; AND STARTING CYLINDER FOR AN INT 13 REQUEST THAT REQUESTS I/O OF A LOT
; OF SECTORS. IT ONLY DOES THIS FOR FIXED DISKS. IT IS USED IN THE SECTIONS
; OF CODE THAT HANDLE ECC ERRORS AND DMA ERRORS. IT IS NECESSARY, BECAUSE
; ORDINARILY THE ROM WOULD TAKE CARE OF WRAPS AROUND HEADS AND CYLINDERS,
; BUT WE BREAK DOWN A REQUEST WHEN WE GET AN ECC OR DMA ERROR INTO SEVERAL
; I/O OF ONE OR MORE SECTORS. IN THIS CASE, WE MAY ALREADY BE BEYOND THE
; NUMBER OF SECTORS ON A TRACK ON THE MEDIUM, AND THE REQUEST WOULD FAIL.
;
; INPUT CONDITIONS:
;	ALL REGISTERS SET UP FOR AN INT 13 REQUEST.
;
; OUTPUT:
;	DH - CONTAINS STARTING HEAD NUMBER FOR REQUEST
;	CX - CONTAINS STARTING SECTOR AND CYLINDER NUMBERS
;	(THE ABOVE MAY OR MAY NOT HAVE BEEN CHANGED, AND ARE 0-BASED)
;	ALL OTHER REGISTERS PRESERVED.
;
	PUBLIC CHECK_WRAP
CHECK_WRAP:
	Message ftestDisk,<"Entering Check_Wrap...",cr,lf>
	SAVEREG <AX,BX,DS,DI>
	MOV	AL,DL			; AL HAS PHYSICAL DRIVE NUMBER
	CALL	SETDRIVE_PHYSICAL	; GET POINTER TO BDS FOR DRIVE
	JC	NO_WRAP 		; DO NOTHING IF WRONG PHYSICAL DRIVE
	TEST	WORD PTR [DI].FLAGS,FNON_REMOVABLE
	JZ	NO_WRAP 		; NO WRAPPING FOR REMOVABLE MEDIA
	MOV	BX,[DI].SECLIM
	MOV	AX,CX
	AND	AX,003FH		; EXTRACT SECTOR NUMBER
	CMP	AX,BX			; ARE WE GOING TO WRAP?
	JBE	NO_WRAP
	DEC	AX			; CONVERT TO ZERO-BASED SECTOR
	DIV	BL			; AH=zero-based sector, AL=head wraps
	INC	AH			; RESTORE ONE-BASED BIOS SECTOR
	AND	CL,0C0H 		; ZERO OUT SECTOR #
	OR	CL,AH			; OR IN NEW SECTOR #
	XOR	AH,AH			; AX = # OF HEAD WRAPS
	ADD	AL,DH			; ADD ZERO-BASED STARTING HEAD #
	ADC	AH,0			; CATCH ANY CARRY
	MOV	BX,[DI].HDLIM		; NUMBER OF HEADS
	CMP	AX,BX			; ARE WE GOING TO WRAP AROUND A HEAD?
	JB	NO_WRAP_HEAD		; NO: AX IS THE NEW ZERO-BASED HEAD
	PUSH	DX			; PRESERVE DRIVE NUMBER AND HEAD NUMBER
	XOR	DX,DX
	DIV	BX			; DX=zero-based head, AX=cylinder wraps
	MOV	BH,DL			; BH HAS NEW HEAD NUMBER
	POP	DX			; RESTORE DRIVE NUMBER AND HEAD NUMBER
	MOV	DH,BH			; SET UP NEW HEAD NUMBER IN DH
	MOV	BH,CL
	AND	BH,3FH			; PRESERVE SECTOR NUMBER
	MOV	BL,6
	XCHG	CL,BL
	SHR	BL,CL			; GET MS CYLINDER BITS TO LS END
	ADD	CH,AL			; ADD IN CYLINDER WRAP
	ADC	BL,AH			; ADD IN HIGH BYTE
	SHL	BL,CL			; MOVE UP TO MS END
	XCHG	BL,CL			; RESTORE CYLINDER BITS INTO CL
	OR	CL,BH			; OR IN SECTOR NUMBER

NO_WRAP_HEAD:
	MOV	DH,AL			; AX HOLDS THE NEW ZERO-BASED HEAD
NO_WRAP:
	CLC				; RESET CARRY
	RESTOREREG <DI,DS,BX,AX>
	RET

;
; INT_2F_13:
;		THIS CODE IS CHAINED INTO THE INT_2F INTERRUPT DURING BIOS
;	INITIALIZATION.  IT ALLOWS THE USER TO CHANGE THE ORIG13 INT_13 VECTOR
;	AFTER BOOTING.	THIS ALLOWS TESTING AND IMPLEMENTATION OF CUSTOM INT_13
;	HANDLERS, WITHOUT GIVING UP MS-DOS ERROR RECOVERY
;
;	ENTRY CONDITIONS
;		AH	== RESET_INT_13  (13H)
;		DS:DX	== ADDRESS OF NEW INT_13 HANDLER
;		ES:BX	== ADDRESS OF NEW INT_13 VECTOR USED BY WARM BOOT
;								(INT 19)
;
;	EXIT CONDITIONS
;		ORIG13	== ADDRESS OF NEW INT_13 HANDLER
;		DS:DX	== OLD ORIG13 VALUE
;		ES:BX	== OLD OLD13  VALUE

	ASSUME CS:BIOS_SERVICE_CS,DS:NOTHING,ES:NOTHING,SS:NOTHING

	PUBLIC INT_2F_13
INT_2F_13	PROC	FAR

	CMP	AH,13H			; IF (INTERRUPT_VALUE != RESET_INT_13)
	JE	CHG_ORIG13
	BIOS_CHAIN_VECTOR NEXT2F_13,BIOS_SERVICE_NEXT2F_OFFSET

CHG_ORIG13:				;	ELSE
	BIOS_LOW_READ XCHG,DX,<WORD PTR [ORIG13]>,DS	; install new runtime offset and
	PUSH	AX			; return the old pointer in DS:DX
	MOV	AX,DS
	BIOS_LOW_READ XCHG,AX,<WORD PTR [ORIG13+2]>,DS
	MOV	DS,AX

	BIOS_LOW_READ XCHG,BX,<WORD PTR [OLD13]>,DS	; install new warm-boot offset and
	MOV	AX,ES			; return the old pointer in ES:BX
	BIOS_LOW_READ XCHG,AX,<WORD PTR [OLD13+2]>,DS
	MOV	ES,AX
	POP	AX

	IRET				;	END ELSE

INT_2F_13	ENDP

MOVE	PROC	NEAR
	CLD
	PUSH	CX
	MOV	CX,512/2
;J.K. Warning!!! Do not change the position of this label.
;     The following three bytes will be NOPed out by MSINIT if the system
;     does not support the DOUBLE WORD MOV instruction, i.e., (if
;     not 386 base machine.)
;----------------------------------------------------------------------------
	public	DoubleWordMov
DoubleWordMov:			;AN002;
	shr	cx, 1		;AN002;Make it a double word.
	db	66h		;AN002;Machine code for double word mov
	PUBLIC BIOS_DWORD_PATCH_END
BIOS_DWORD_PATCH_END LABEL BYTE
;----------------------------------------------------------------------------
	REP	MOVSW
	POP	CX
	RET
MOVE ENDP

DOINT	PROC	NEAR
	MOV	DL,BYTE PTR [BP.OLDDX]		; GET PHYSICAL DRIVE NUMBER
	XOR	AH,AH
	OR	AL,AL
	JZ	DOINTDONE
	MOV	AH,BYTE PTR [BP.OLDAX+1]	; GET REQUEST CODE
	PUSH	[BP.OLDF]
	BIOS_ROM_ORIG13
	PUSHF
	POP	[BP.OLDF]
DOINTDONE:
	RET
DOINT	ENDP
BIOS_SERVICE_END LABEL BYTE
