TITLE	DISK3 - Disk utility routines
NAME	Disk3
; Low level Read and write routines for local SFT I/O on files and devs
;
;   DISKWRITE
;   WRTERR
;
.xlist
include dosseg.asm

CODE	SEGMENT BYTE PUBLIC  'CODE'
	ASSUME	SS:DOSGROUP,CS:DOSGROUP

.xcref
INCLUDE DOSSYM.INC
INCLUDE DEVSYM.INC
include version.inc
.cref
.list

Installed = TRUE

	i_need	THISSFT,DWORD
	i_need	DMAADD,DWORD
	i_need	SecClusPos,BYTE
	i_need	ClusNum,WORD
	i_need	Trans,BYTE
	i_need	BytPos,4
	i_need	SecPos,DWORD		  ;F.C. >32mb
	i_need	BytSecPos,WORD
	i_need	BytCnt1,WORD
	i_need	BytCnt2,WORD
	i_need	SecCnt,WORD
	i_need	ThisDPB,DWORD
	i_need	LastPos,WORD
	i_need	ValSec,WORD		  ;F.C. >32mb
	i_need	GrowCnt,DWORD
	i_need	ALLOWED,BYTE
	I_need	JShare,DWORD
	I_need	FSeek_drive,BYTE	  ; DOS 4.00
	I_need	FSeek_firclus,WORD	  ; DOS 4.00
	I_need	FSeek_logclus,WORD	  ; DOS 4.00
	I_need	HIGH_SECTOR,WORD	  ;F.C. >32mb
	I_need	HIGH_SECTOR_TEMP,WORD	  ;F.C. >32mb
	I_need	EXTERR,WORD			   ; DOS 4.00
	I_need	EXTERR_LOCUS,BYTE		   ; DOS 4.00
	I_need	EXTERR_ACTION,BYTE		   ; DOS 4.00
	I_need	EXTERR_CLASS,BYTE		   ; DOS 4.00
	I_need	EXITHOLD,DWORD			   ; DOS 4.00
	I_need	DISK_FULL,BYTE			   ; DOS 4.00
	I_need	SC_DRIVE,BYTE			   ; DOS 4.00
	I_need	SC_CACHE_COUNT,WORD		   ; DOS 4.00
	I_need	ThisDRV,BYTE			   ; DOS 4.00
	I_need	User_In_AX,WORD 		   ; DOS 4.00
	I_need	DOS34_FLAG,WORD 		   ; DOS 4.00
	I_need	FIRST_BUFF_ADDR,WORD		   ; DOS 4.00

IF	BUFFERFLAG
	EXTRN	SAVE_MAP:NEAR
	EXTRN	RESTORE_MAP:NEAR
	EXTRN	SAVE_USER_MAP:NEAR
	EXTRN	RESTORE_USER_MAP:NEAR
	i_need	BUF_EMS_SAFE_FLAG,BYTE
	i_need	BUF_EMS_MODE,BYTE
ENDIF

	

Break	<DISKWRITE -- PERFORM USER DISK WRITE>

; Inputs:
;	Outputs of SETUP
; Function:
;	Perform disk write
; Outputs:
;    Carry clear
;	CX = No. of bytes read
;	ES:DI point to SFT
;	SFT offset and cluster pointers updated
;    Carry set
;	CX = 0
;	ES:DI point to SFT
;	AX has error code

	procedure   DISKWRITE,NEAR
	DOSAssume   CS,<DS>,"DiskWrite"
	ASSUME	ES:NOTHING

	Assert	ISSFT,<ES,DI>,"DiskWrite"
	PUSH	ES:[DI.sf_firclus]	  ; set up 1st cluster # for FastSeek
	POP	[FSeek_firclus]

	invoke	CHECK_WRITE_LOCK	  ;IFS. check write lock
	JNC	WRITE_OK		  ;IFS. lock check ok
	return

WRTEOFJ:
	JMP	WRTEOF

WRITE_OK:
	AND	ES:[DI.sf_flags],NOT (sf_close_nodate OR devid_file_clean)
				; Mark file as dirty, clear no date on close
	LES	BP,[THISDPB]
	Assert	ISDPB,<ES,BP>,"DiskWrite/WriteOk"
	MOV	AL,ES:[BP.dpb_drive]   ; set up drive # for FastSeek
	MOV	[FSeek_drive],AL       ; 11/5/86 DOS 4.00

	invoke	BREAKDOWN
	MOV	AX,WORD PTR [BYTPOS]
	MOV	DX,WORD PTR [BYTPOS+2]
	JCXZ	WRTEOFJ 		;Make the file length = sf_position
	ADD	AX,CX
	ADC	DX,0			; AX:DX=byte after last byte accessed
;
; Make sure divide won't overflow
;
	MOV	BX,ES:[BP.dpb_sector_size]
;	CMP	DX,BX			;F.C. >32mb  16 bit sector check
;	JAE	WrtErr			;F.C. >32mb

	CALL	DIV32			;F.C. perform 32 bit divide
	MOV	BX,AX			; Save last full sector
	OR	DX,DX
	JNZ	CALCLUS
	SUB	AX,1			; AX must be zero base indexed
	SBB	[HIGH_SECTOR],0 	;F.C. >32mb
CALCLUS:
	PUSH	[HIGH_SECTOR]		;F.C. >32mb
	CALL	SHR32			;F.C. >32mb
	POP	[HIGH_SECTOR]		;F.C. >32mb

;	SHR	AX,CL			; Last cluster to be accessed
	PUSH	AX
	PUSH	DX			; Save the size of the "tail"
	PUSH	ES
	LES	DI,[THISSFT]
	Assert	ISSFT,<ES,DI>,"DiskWrite/CalClus"
	MOV	AX,WORD PTR ES:[DI.sf_size]
	MOV	DX,WORD PTR ES:[DI.sf_size+2]
	POP	ES



	PUSH	AX			;F.C. >32mb
	MOV	AX,DX			;F.C. >32mb
	XOR	DX,DX			;F.C. >32mb
	DIV	ES:[BP.dpb_sector_size] ;F.C. >32mb
	MOV	[HIGH_SECTOR_TEMP],AX	;F.C. >32mb
	POP	AX			;F.C. >32mb

	DIV	ES:[BP.dpb_sector_size]
	MOV	CX,AX		; Save last full sector of current file
	OR	DX,DX
	JZ	NORNDUP
	ADD	AX,1		; Round up if any remainder
	ADC	[HIGH_SECTOR_TEMP],0	;F.C. >32mb
NORNDUP:
	PUSH	[HIGH_SECTOR_TEMP]	;F.C. >32mb
	POP	WORD PTR [VALSEC+2]	;F.C. >32mb
	MOV	WORD PTR [VALSEC],AX  ;Number of sectors that have been written
	XOR	AX,AX
	MOV	WORD PTR [GROWCNT],AX
	MOV	WORD PTR [GROWCNT+2],AX
	POP	AX

	MOV	DI,[HIGH_SECTOR]	;F.C. >32mb
	CMP	DI,[HIGH_SECTOR_TEMP]	;F.C. >32mb
	JB	NOGROW			;F.C. >32mb
	JZ	lowsec			;F.C. >32mb
	SUB	BX,CX			;F.C. >32mb
	SBB	DI,[HIGH_SECTOR_TEMP]	;F.C. >32mb di:bx no. of sectors
	JMP	yesgrow 		;F.C. >32mb
lowsec:
	MOV	DI,0		;F.C. >32mb
	SUB	BX,CX		; Number of full sectors
	JB	NOGROW
	JZ	TESTTAIL
yesgrow:
	MOV	CX,DX
	XCHG	AX,BX
	MUL	ES:[BP.dpb_sector_size]  ; Bytes of full sector growth
	MOV	[HIGH_SECTOR],DX	 ;F.C. >32mb save dx
	MOV	[HIGH_SECTOR_TEMP],AX	 ;F.C. >32mb save ax
	MOV	AX,DI			 ;F.C. >32mb
	MUL	ES:[BP.dpb_sector_size]  ;F.C. >32mb do higher word multiply
	ADD	AX,[HIGH_SECTOR]	 ;F.C. >32mb add lower value
	MOV	DX,AX			 ;F.C. >32mb DX:AX is the result of
	MOV	AX,[HIGH_SECTOR_TEMP]	 ;F.C. >32mb a 32 bit multiply

	SUB	AX,CX		; Take off current "tail"
	SBB	DX,0		; 32-bit extension
	ADD	AX,BX		; Add on new "tail"
	ADC	DX,0		; ripple tim's head off
	JMP	SHORT SETGRW
HAVSTART:
;int 3
	MOV	CX,AX
	invoke	SKPCLP
	JCXZ	DOWRTJ
	MOV	[FSeek_logclus],DX   ; delete EOF (FFFFH)
	INC	[FSeek_logclus]
	invoke	FastSeek_Truncate    ;
	invoke	ALLOCATE
	JNC	DOWRTJ

	entry	WRTERR
	DOSAssume   CS,<DS>,"DiskWrite/WrtErr"
	ASSUME	ES:NOTHING

	MOV	AH,0FH				;MS. write/data/fail/abort
 entry WRTERR22
	MOV	AL,[THISDRV]			;MS.
	CALL	File_Handle_Fail_Error	;MS. issue disk full I24
	MOV	CX,0			;No bytes transferred
;	XOR	CX,CX			; will be deleted
	LES	DI,[THISSFT]
	Assert	ISSFT,<ES,DI>,"DiskWrite/WrtErr"
;	CLC
	return

DOWRTJ: JMP	DOWRT

ACC_ERRWJ:
	JMP	SET_ACC_ERRW

TESTTAIL:
	SUB	AX,DX
	JBE	NOGROW
	XOR	DX,DX
SETGRW:
	MOV	WORD PTR [GROWCNT],AX
	MOV	WORD PTR [GROWCNT+2],DX
NOGROW:
	POP	AX
	MOV	CX,[CLUSNUM]	; First cluster accessed
	invoke	FNDCLUS
	JC	ACC_ERRWJ
	MOV	[CLUSNUM],BX
	MOV	[LASTPOS],DX
	MOV	[FSeek_logclus],AX    ; set up last position
	SUB	AX,DX		; Last cluster minus current cluster
	JZ	DOWRT		; If we have last clus, we must have first
	JCXZ	HAVSTART	; See if no more data
	PUSH	CX		; No. of clusters short of first
	MOV	CX,AX

	CMP	[CLUSNUM],0	      ;FS. null file
	JZ	NULL_FILE	      ;FS. yes
	MOV	[FSeek_logclus],DX    ;FS. delete EOF (FFFFH)
	INC	[FSeek_logclus]       ;FS.
	invoke	FastSeek_Truncate     ;FS.
NULL_FILE:
	invoke	ALLOCATE
	POP	AX
	JC	WRTERR
	MOV	CX,AX
	MOV	DX,[LASTPOS]
	INC	DX
	DEC	CX
	JZ	NOSKIP
	MOV	[FSeek_logclus],DX    ;
	ADD	[FSeek_logclus],CX    ; set up last position
	invoke	SKPCLP
	JC	ACC_ERRWJ
NOSKIP:
	MOV	[CLUSNUM],BX
	MOV	[LASTPOS],DX
DOWRT:
	CMP	[BYTCNT1],0
	JZ	WRTMID
	MOV	BX,[CLUSNUM]
	invoke	BUFWRT
	JC	ACC_ERRWJ
WRTMID:
	MOV	AX,[SECCNT]
	OR	AX,AX
	JNZ	havemid
	JMP	WRTLAST
havemid:
	ADD	WORD PTR [SECPOS],AX
	ADC	WORD PTR [SECPOS+2],0	 ;F.C. >32mb
	invoke	NEXTSEC
	JNC	gotok
	JMP	ACC_ERRWJ
gotok:
	MOV	BYTE PTR [TRANS],1	 ; A transfer is taking place
	MOV	DL,[SECCLUSPOS]
	MOV	BX,[CLUSNUM]
	MOV	CX,[SECCNT]
WRTLP:
	invoke	OPTIMIZE
	JNC	wokok
	JMP	ACC_ERRWJ
wokok:
	PUSH	DI
	PUSH	AX
	PUSH	DX
	PUSH	BX
	Assert	ISDPB,<ES,BP>,"DiskWrite/WrtLp"
	MOV	AL,ES:[BP.dpb_drive]
	MOV	[SC_DRIVE],AL		  ;LB. save it for INVALIDATE_SC
	PUSH	CX			  ;LB.
	PUSH	[HIGH_SECTOR]		  ;LB.
SCANNEXT:				  ;LB.
	invoke	GETCURHEAD		  ;LB.
ASSUME	DS:NOTHING
NEXTBUFF:			; Search for buffers
	CMP	[SC_CACHE_COUNT],0	    ;LB. SC support ?
	JZ	nosc			    ;LB. no
	PUSH	AX			    ;LB. save reg
	PUSH	CX			    ;LB. save reg
	PUSH	DX			    ;LB. save reg
	invoke	INVALIDATE_SC		    ;LB. invalidate SC
	POP	DX			    ;LB. save reg
	POP	CX			    ;LB. save reg
	POP	AX			    ;LB. save reg
nosc:
	CALL	BUFF_RANGE_CHECK	    ;F.C. >32mb
	JNC	inrange2		    ;F.C. >32mb
	mov	DI,[DI.buf_next]	    ;LB. get next buffer 1/19/88
	JMP	DONEXTBUFF		    ;LB.
inrange2:
	TEST	[DI.buf_flags],buf_dirty    ;LB. if dirty
	JZ	not_dirty		    ;LB.
	invoke	DEC_DIRTY_COUNT 	    ;LB. then decrement dirty count
not_dirty:
	MOV	WORD PTR [DI.buf_ID],(buf_visit SHL 8) OR 0FFH	  ; Free the buffer, it is being over written
	invoke	SCANPLACE
DONEXTBUFF:
	CMP	DI,[FIRST_BUFF_ADDR]	  ;LB. end of chain
	JNZ	NEXTBUFF		  ;LB. no
	ADD	DX,1			  ;LB. next sector number
	ADC	[HIGH_SECTOR],0 	  ;LB.
	LOOP	SCANNEXT		  ;LB. check again
	POP	[HIGH_SECTOR]		  ;LB.
	POP	CX			  ;LB. get count back

	POP	BX
	POP	DX
	MOV	DS,WORD PTR [DMAADD+2]
	MOV	[ALLOWED],allowed_RETRY + allowed_FAIL + allowed_IGNORE

IF	BUFFERFLAG
	pushf
	cmp	[BUF_EMS_MODE], -1
	je	safe_write	
	call	save_map
	call	restore_user_map
safe_write:
	popf
ENDIF	

	invoke	DWRITE

IF	BUFFERFLAG
	pushf
	cmp	[BUF_EMS_MODE], -1
	je	safe_map	
	call	save_user_map
	call	restore_map
safe_map:
	popf
ENDIF

	POP	CX
	POP	BX
	Context DS
	JC	SET_ACC_ERRW
	JCXZ	WRTLAST
	MOV	DL,0
	INC	[LASTPOS]	; We'll be using next cluster
	JMP	WRTLP

WRTLAST:
	MOV	AX,[BYTCNT2]
	OR	AX,AX
	JZ	FINWRT
	MOV	[BYTCNT1],AX
	invoke	NEXTSEC
	JC	SET_ACC_ERRW
	MOV	[BYTSECPOS],0
	invoke	BUFWRT
	JC	SET_ACC_ERRW
FINWRT:
	LES	DI,[THISSFT]
	Assert	ISSFT,<ES,DI>,"DiskWrite/FinWrt"
	MOV	AX,WORD PTR [GROWCNT]
	MOV	CX,WORD PTR [GROWCNT+2]
	OR	AX,AX
	JNZ	UPDATE_size
	JCXZ	SAMSIZ
Update_size:
	ADD	WORD PTR ES:[DI.sf_size],AX
	ADC	WORD PTR ES:[DI.sf_size+2],CX
;
; Make sure that all other SFT's see this growth also.
;
	MOV	AX,1
if installed
	Context DS
	call	DWORD PTR SS:[JShare + 14 * 4]
else
	Call	ShSU
endif
SAMSIZ:
	transfer SETCLUS		  ; ES:DI already points to SFT

SET_ACC_ERRW:
	transfer SET_ACC_ERR_DS

WRTEOF:
	MOV	CX,AX
	OR	CX,DX
	JZ	KILLFIL
	SUB	AX,1
	SBB	DX,0

	PUSH	BX
	MOV	BX,ES:[BP.dpb_sector_size]    ;F.C. >32mb
	CALL	DIV32			      ;F.C. >32mb
	POP	BX			      ;F.C. >32mb
	CALL	SHR32			      ;F.C. >32mb


;	SHR	AX,CL
	MOV	CX,AX
	invoke	FNDCLUS
SET_ACC_ERRWJ2:
	JC	SET_ACC_ERRW
	MOV	[FSeek_logclus],DX    ; truncate clusters starting from DX
	invoke	FastSeek_Truncate
	JCXZ	RELFILE
	invoke	ALLOCATE
	JC	WRTERRJ 	     ;;;;;;;;; disk full
UPDATE:
	LES	DI,[THISSFT]
	Assert	ISSFT,<ES,DI>,"DiskWrite/update"
	MOV	AX,WORD PTR [BYTPOS]
	MOV	WORD PTR ES:[DI.sf_size],AX
	MOV	AX,WORD PTR [BYTPOS+2]
	MOV	WORD PTR ES:[DI.sf_size+2],AX
;
; Make sure that all other SFT's see this growth also.
;
	MOV	AX,2
if installed
	Context DS
	Call	DWORD PTR SS:[JShare + 14 * 4]
else
	Call	ShSU
endif
	XOR	CX,CX
	transfer ADDREC

WRTERRJ: JMP	 WRTERR
RELFILE:
	MOV	DX,0FFFFH
	invoke	RELBLKS
Set_Acc_ERRWJJ:
	JC	SET_ACC_ERRWJ2
	JMP	SHORT UPDATE

KILLFIL:
	XOR	BX,BX
	PUSH	ES
	LES	DI,[THISSFT]
	Assert	ISSFT,<ES,DI>,"DiskWrite/KillFil"
	MOV	ES:[DI.sf_cluspos],BX
	MOV	ES:[DI.sf_lstclus],BX
	XCHG	BX,ES:[DI.sf_firclus]
	POP	ES
	invoke	Delete_FSeek   ; delete fastseek entry

	OR	BX,BX
	JZ	UPDATEJ
	PUSH	ES		; since first cluster # is 0
	PUSH	BP		; we must delete the old cache entry
	PUSH	AX
	PUSH	CX
	PUSH	DX
	LES	BP,[THISDPB]		 ; get current DPB
	MOV	DL,ES:[BP.dpb_drive]	 ; get current drive
	MOV	CX,BX			 ; first cluster #
	MOV	AH,2			 ; delete cache entry by drive:firclus
	invoke	FastOpen_Update 	 ; call fastopen
	POP	DX
	POP	CX
	POP	AX
	POP	BP
	POP	ES
	invoke	RELEASE
	JC	SET_ACC_ERRWJJ
UpDateJ:
	JMP	UPDATE
EndProc DISKWRITE



Break	<DIV32 -- PERFORM 32 BIT DIVIDE>

; Inputs:
;	DX:AX = 32 bit dividend   BX= divisor
; Function:
;	Perform 32 bit division
; Outputs:
;	[HIGH_SECTOR]:AX = quotiend , DX= remainder

	procedure   DIV32,NEAR
	ASSUME	DS:NOTHING,ES:NOTHING


	PUSH	AX			;F.C. >32mb
	MOV	AX,DX			;F.C. >32mb
	XOR	DX,DX			;F.C. >32mb
	DIV	BX			;F.C. >32mb
	MOV	[HIGH_SECTOR],AX	;F.C. >32mb
	POP	AX			;F.C. >32mb


	DIV	BX			; AX=last sector accessed
	return

EndProc DIV32

Break	<SHR32 -- PERFORM 32 BIT SHIFT RIGHT>

; Inputs:
;	[HIGH_SECTOR]:AX = 32 bit sector number
; Function:
;	Perform 32 bit shift right
; Outputs:
;	AX= cluster number

	procedure   SHR32,NEAR
	ASSUME	DS:NOTHING,ES:NOTHING


	MOV	CL,ES:[BP.dpb_cluster_shift]
	XOR	CH,CH
entry ROTASHFT				;F.C. >32mb
	OR	CX,CX			;F.C. >32mb
	JZ	norota			;F.C. >32mb
ROTASHFT2:
	CLC				;F.C. >32mb
	RCR	[HIGH_SECTOR],1 	;F.C. >32mb
	RCR	AX,1			;F.C. >32mb
	LOOP	ROTASHFT2		;F.C. >32mb:
norota:
	return

EndProc SHR32


; Issue File Handle Fail INT 24 Critical Error
; Input: Disk_Full=0  ok
;		   1  disk full or EOF
; Function: issue critical error for disk full or EOF error
;
; OutPut: carry clear , no I24
;	  carry set, fail from I24

procedure File_Handle_Fail_Error,NEAR
	ASSUME	ES:NOTHING,DS:NOTHING
	CMP	[DISK_FULL],0	 ;MS. disk full or EOF
	JZ	Fexit		 ;MS. no
	TEST	[DOS34_FLAG],Disable_EOF_I24   ;MS. check input status ?
	JNZ	Fexit		 ;MS. yes
	LES	DI,[THISSFT]	 ;MS. get current SFT
;	LES	DI,ES:[DI.sf_DEVPTR];MS. get device header
	TEST	ES:[DI.sf_flags],Handle_Fail_I24  ;MS. gen I24 ?
	JZ	Fexit		 ;MS. no
	PUSH	DS		 ;MS. save DS
	TEST	AH,1				;MS. READ ?
	JZ	readeof 			;MS. yes
	MOV	[EXTERR],error_Handle_Disk_Full ;MS. set extended error
	JMP	SHORT errset			;MS. set extended error
readeof:
	MOV	[EXTERR],error_Handle_EOF	;MS. set extended error
errset:
	MOV	[EXTERR_CLASS],errCLASS_OutRes	;MS. set class
	MOV	[EXTERR_ACTION],errACT_Abort	;MS. set action
	MOV	[EXTERR_LOCUS],errLOC_Unk	;MS. set locus
	MOV	word ptr [EXITHOLD + 2],ES	;MS. save es:bp in exithold
	MOV	word ptr [EXITHOLD],BP		;MS.
	TEST	ES:[DI.sf_flags],devid_device	  ;MS. device  ?
	JNZ	chardev2			  ;MS. yes
	LDS	SI,ES:[DI.sf_DEVPTR]		  ;MS. get dpb
	LDS	SI,[SI.dpb_driver_addr] 	  ;MS. get drive device haeder
	JMP	SHORT doi24			  ;MS. gen I24 ?
chardev2:
	LDS	SI,ES:[DI.sf_DEVPTR]		  ;MS. get chr dev header
doi24:
	MOV	BP,DS				  ;MS. bp:si -> device header
	MOV	DI,error_I24_gen_failure	;MS. general error
	invoke	NET_I24_ENTRY			;MS. issue I24
	STC					;MS. must be fail
	POP	DS				;MS. restore DS
	MOV	AX,[EXTERR]			;MS. set error
	JMP	SHORT Fend			;MS. exit
Fexit:
	CLC					;MS. clear carry
Fend:
	return					;MS.
EndProc File_Handle_Fail_Error


Break	<BUFF_RANGE_CHECK- buffer range checkink>

; Inputs:
;	DS:DI -> buffer. AL= drive #
;	[HIGH_SECTOR]:DX = sector #
; Function:
;	check if sector is in the buffer
; Outputs:
;	carry clear= in the range
;	      set  = not in the range

	procedure   BUFF_RANGE_CHECK,NEAR
	ASSUME	DS:NOTHING,ES:NOTHING

	CMP	WORD PTR [DI.buf_sector],DX
	JNZ	DONEXTBUFF2	; not this sector	   ;F.C. >32mb
	MOV	SI,[HIGH_SECTOR]			   ;F.C. >32mb
	CMP	WORD PTR [DI.buf_sector+2],SI		   ;F.C. >32mb
	JNZ	DONEXTBUFF2	; Not for this drive
	CMP	AL,[DI.buf_ID]
	JZ	secfound	; Buffer has the sector
DONEXTBUFF2:
	STC
secfound:
	return

EndProc BUFF_RANGE_CHECK

CODE	ENDS
    END

