	 PAGE	 ,132				; 
TITLE	IFSFUNC HANDLE ROUTINES - Routines for FS dispatch
NAME	IFSHANDLE
;******************************************************************************
;
; HANDLE (SFT) related FS calls
;
;
;   IFS_CLOSE
;   IFS_COMMIT
;   IFS_LSEEK
;   IFS_READ
;   IFS_WRITE
;   IFS_LOCK
;   IFS_XATTR
;
;******************************************************************************
.xlist
.xcref
INCLUDE IFSSYM.INC
INCLUDE IFSFSYM.INC
INCLUDE DOSSYM.INC
INCLUDE DEVSYM.INC
.cref
.list
AsmVars <IBM, Installed, DEBUG>
; define the base code segment of the network support first
IFSSEG	SEGMENT BYTE PUBLIC 'IFSSEG'
IFSSEG	ENDS
; include THE REST of the segment definitions for normal MSDOS
include dosseg.asm
DATA		SEGMENT WORD PUBLIC 'DATA'
	;DOSGROUP Data
	Extrn	THISSFT:DWORD
	Extrn	DMAADD:DWORD
	Extrn	CurrentPDB:WORD
	Extrn	SAVE_BX:WORD
	Extrn	SAVE_CX:WORD
	Extrn	SAVE_DS:WORD
	Extrn	SAVE_SI:WORD
	Extrn	SAVE_ES:WORD
	Extrn	SAVE_DI:WORD
DATA		ENDS
; define our own code segment
IFSSEG	SEGMENT BYTE PUBLIC 'IFSSEG'
	ASSUME	SS:DOSGROUP,CS:IFSSEG
	;IFS Data
	Extrn	THISDFL:DWORD
	Extrn	THISIFS:DWORD
	Extrn	IFSPROC_FLAGS:WORD
	Extrn	IFSR:WORD
	Extrn	DEVICE_CB@_OFFSET:WORD
BREAK <IFS_CLOSE Close a FS SFT>
;******************************************************************************
; IFS_CLOSE - see IFS_COMMIT for details
;******************************************************************************
	procedure   IFS_CLOSE,NEAR
ASSUME	DS:DOSGROUP,ES:NOTHING
	ifsr_fcn_def  EXECAPI			; define ifsr for close
	ifsr_api_def  CLOSEFILE
	TEST	ES:[DI.SF_FLAGS],devid_file_clean + sf_close_nodate
	JNZ	C_05
	CallInstall DATE16,MultDOS,13		; set sf date/time on close
	MOV	ES:[DI.SF_DATE],AX
	MOV	ES:[DI.SF_TIME],DX
C_05:

	SaveReg <ES,DI> 			; save SFT ptr
	CallInstall FREE_SFT,MultDOS,8		; set SFT busy
	PUSH	AX				; save old ref count
	TEST	ES:[DI.SF_MODE],SF_ISFCB	; always close fcb
	JNZ	C_10				; only do real close when
	CMP	AX,1				; sft being freed
	JE	C_10
	JMP	C_80
C_10:
	MOV	CS:IFSPROC_FLAGS,ISCLOSE + SETDEVICECB
						; 2nd flag causes sft_to_sff to
						; set device cb@
	JMP	C_20				; cont. in ifs_commit
EndProc IFS_CLOSE
BREAK <IFS_COMMIT Commit a FS SFT>
;******************************************************************************
; IFS_COMMIT
; Called by:	   IFSFUNC dispatcher
; Routines called: CALL_IFS	DRIVE_FROM_SFT
;		   SFT_TO_SFF
;		   SFF_TO_SFT
; Inputs:
;	[THISSFT] set to the SFT for the file being used
;	ES:DI = [THISSFT] (date time are NOT correct)
;		SFT must never be for an FCB on commit (error not detected)
; Outputs:
;	sf_ref_count decremented on close unless FAIL
;		(AX has old value for COMMIT)
;	ES:DI point to SFT
;	Carry set if error (file deleted or disk changed)
; DS preserved, others destroyed
;******************************************************************************
	procedure   IFS_COMMIT,NEAR
ASSUME	DS:DOSGROUP,ES:NOTHING
	ifsr_fcn_def  EXECAPI
	ifsr_api_def  CLOSEFILE
	MOV	CS:IFSPROC_FLAGS,SETDEVICECB	; set ifsproc_flags
C_20:						; (welcome ifs_close)
	invoke	DRIVE_FROM_SFT			; set IFSDRV for possible criter
	invoke	PREP_IFSR			; clear ifsrh
	MOV	DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	invoke	SFT_TO_SFF			; sets: [THISIFS]
						;	ES:BX -> IFSRH
						;	IFSR_OPEN_CB@
						;	ds - IFSSEG
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_CLOSEFILE	; prep IFSRH
	MOV	ES:[BX.IFSR_FUNCTION],IFSEXECAPI
	MOV	ES:[BX.IFSR_APIFUNC],IFSCLOSEFILE
	XOR	AL,AL
	TEST	IFSPROC_FLAGS,ISCLOSE
	JNZ	C_40
	INC	AL
C_40:
	MOV	ES:[BX.IFSR_FUNC],AL
	invoke	CALL_IFS			; *** call fs with close request
	JNC	C_60
	TEST	IFSPROC_FLAGS,ISCLOSE		; ifs error
	JZ	C_980				; return w/carry, if close
	RestoreReg <CX,DI,ES>			; old ref count & sft
	CMP	CX,1
	JNE	C_980
	MOV	ES:[DI.sf_ref_count],0		; If freeing, need to zap
	JMP	C_980
C_60:
	invoke	SFF_TO_SFT
	TEST	IFSPROC_FLAGS,ISCLOSE
	JZ	C_990				; finished w/commit
C_80:
	RestoreReg <AX,DI,ES>			; old ref count & sft
	CMP	AX,1
	JNE	C_990
	MOV	ES:[DI.sf_ref_count],0		; If freeing, need to zap
	JMP	C_990				; busy mark
C_980:						; Return area
	STC
	JMP	C_1000
C_990:
	CLC
C_1000: 					; preserve ds - dosgroup
	PUSH	SS
	POP	DS
	return
EndProc IFS_COMMIT
BREAK <IFS_LSEEK Seek on a NET SFT>
;******************************************************************************
; IFS_LSEEK
; Inputs:
;	ES:DI -> SFT
;	CX:DX = Input CX:DX to $Lseek (offset)
;	NOTE: THIS LSEEK IS ALWAYS ASSUMED TO BE A TYPE 2 (relative to EOF)
; Returns:
;	ES:DI -> SFT
;	Carry clear
;		DX:AX return as with local $Lseek
;	Carry Set
;		AX is error code
; All destroyed
;******************************************************************************
	procedure   IFS_LSEEK,NEAR
ASSUME	DS:Nothing,ES:NOTHING			; Initially DS is unknown
	ifsr_fcn_def  EXECAPI			; define ifsr for lseek
	ifsr_api_def  LSEEKFILE
	PUSH	SS				; Set DS to DOSGROUP
	POP	DS				;
ASSUME	DS:DOSGROUP				;

	MOV	CS:IFSPROC_FLAGS,SETDEVICECB	; init processing flags
	MOV	WORD PTR [THISSFT],DI
	MOV	WORD PTR [THISSFT+2],ES
	SaveReg <ES,DI> 			; save for later restore before leave

	invoke	PREP_IFSR
	invoke	DRIVE_FROM_SFT			; set IFSDRV for possible criter
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	invoke	SFT_TO_SFF			; sets: [THISIFS]
						;	ES:BX -> IFSRH
						;	IFSR_OPEN_CB@
						;	ds - IFSSEG
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_LSEEKFILE	; prep IFSRH
	MOV	ES:[BX.IFSR_FUNCTION],IFSEXECAPI
	MOV	ES:[BX.IFSR_APIFUNC],IFSLSEEKFILE
	MOV	ES:[BX.IFSR_MODE],MODE2
	MOV	WORD PTR ES:[BX.IFSR_POSITION],DX
	MOV	WORD PTR ES:[BX.IFSR_POSITION+2],CX
	invoke	CALL_IFS			; call fs with lseek request
	JC	LS_1000
	MOV	AX,WORD PTR ES:[BX.IFSR_POSITION]
	MOV	DX,WORD PTR ES:[BX.IFSR_POSITION+2]
	invoke	SFF_TO_SFT
	CLC
LS_1000:
	RestoreReg <DI,ES>			; restore sft ptr for ibmdos
	return
EndProc IFS_LSEEK

BREAK <IFS_READ Read from a NET SFT>
;******************************************************************************
; IFS_READ
; Called by:	   IFSFUNC dispatcher
; Routines called: CALL_IFS
;		   SFT_TO_SFF
;		   SFF_TO_SFT
; Inputs:
;	Outputs of SETUP:
;	    CX = byte count
;	    ES:DI Points to SFT
;	    [DMAADD] = transfer addr
;	SFT checked for access mode
; Outputs:
;    Carry clear
;	SFT Position updated
;	CX = No. of bytes read
;	ES:DI point to SFT
;	[DMAADD] filled with info read
;    Carry set
;	AX is error code
;	CX = 0
;	ES:DI point to SFT
; DS preserved, all other registers destroyed
;******************************************************************************
	procedure   IFS_READ,NEAR
ASSUME	DS:DOSGROUP,ES:NOTHING
	ifsr_fcn_def  EXECAPI			; define ifsr for read
	MOV	CS:IFSPROC_FLAGS,SetDeviceCB
	MOV	WORD PTR [THISSFT],DI		; set thissft
	MOV	WORD PTR [THISSFT+2],ES
R_20:						; (welcome lock/read)
	ifsr_api_def  READFILE
	invoke	PREP_IFSR			; zero out ifsr, es:bx -> ifsr
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_READFILE	; prep IFSRH
	MOV	ES:[BX.IFSR_APIFUNC],IFSREADFILE
	JMP	W_80				; cont. read/write common code
						;  in ifs_write below
EndProc IFS_READ
BREAK <IFS_WRITE Write to a NET SFT>
;******************************************************************************
; IFS_WRITE
; Called by:	   IFSFUNC dispatcher
; Routines called: CALL_IFS
;		   SFT_TO_SFF
;		   SFF_TO_SFT
; Inputs:
;	Outputs of SETUP:
;	    CX = byte count
;	    ES:DI Points to SFT
;	    [DMAADD] = transfer addr
;	SFT checked for access mode
; Outputs:
;    Carry clear
;	SFT Position updated
;	CX = No. of bytes written
;	ES:DI point to SFT
;    Carry set
;	AX is error code
;	CX = 0
;	ES:DI point to SFT
; DS preserved, all other registers destroyed
;******************************************************************************
	procedure   IFS_WRITE,NEAR
ASSUME	DS:DOSGROUP,ES:NOTHING
	ifsr_fcn_def  EXECAPI			; define ifsr for write
	MOV	CS:IFSPROC_FLAGS,SetDeviceCB	; init processing flags
	MOV	WORD PTR [THISSFT],DI		; set thissft
	MOV	WORD PTR [THISSFT+2],ES
W_20:						; (welcome write/unlock)
	ifsr_api_def  WRITEFILE
	invoke	PREP_IFSR
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_WRITEFILE	; prep IFSRH
	MOV	ES:[BX.IFSR_APIFUNC],IFSWRITEFILE
W_80:						; (welcome read)
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	MOV	ES:[BX.IFSR_FUNCTION],IFSEXECAPI
	MOV	ES:[BX.IFSR_COUNT],CX
	MOV	AX,WORD PTR [DMAADD]		; to access dmaadd
	MOV	WORD PTR ES:[BX.IFSR_BUFFER@],AX
	MOV	AX,WORD PTR [DMAADD+2]
	MOV	WORD PTR ES:[BX.IFSR_BUFFER@+2],AX
	invoke	DRIVE_FROM_SFT			; set IFSDRV for possible criter
	invoke	SFT_TO_SFF			; sets: [THISIFS]
						;	ES:BX -> IFSRH
						;	IFSR_OPEN_CB@
						;	ds - IFSSEG
	invoke	CALL_IFS			; *** call fs with read/write request
	JNC	W_100
	Context DS				; restore ds-dosgroup
	LES	DI,[THISSFT]			; restore esdi-sft
	transfer ifs_1000			; transfer to general ret as carry set
W_100:
	MOV	CX,ES:[BX.IFSR_COUNT]		; prep reg output
	invoke	SFF_TO_SFT

	Context DS				; restore ds-dosgroup
	LES	DI,[THISSFT]			; restore esdi-sft
	transfer ifs_990			; transfer to general good ret in util
EndProc IFS_WRITE

BREAK <IFS_XLOCK Lock a FS SFT>
;******************************************************************************
; IFS_XLOCK
; Called by:	     IFSFUNC dispatcher
; Routines called:   CALL_IFS		DRIVE_FROM_SFT
;		     SFT_TO_SFF
;		     SFF_TO_SFT
; Inputs:
;   BL = 0 to lock, 1 to unlock
;   ES:DI -> SFT
;   DS:DX -> one range: DWORD position followed by DWORD length
; Outputs:
;	AX set on error: Lock conflict
;			 Too many locks
;******************************************************************************
	procedure   IFS_XLOCK,NEAR
	ifsr_fcn_def  EXECAPI
	ifsr_api_def  LOCKFILE
	SaveReg <BX>				; save input bl
	MOV	CS:IFSPROC_FLAGS,SetDeviceCB
L_60:
	SaveReg <DS>				; save input ds (buffer ptr)
	Context DS				; ds-dosgroup to access thissft
	MOV	WORD PTR [THISSFT],DI		; set [THISSFT]
	MOV	WORD PTR [THISSFT+2],ES
	invoke	DRIVE_FROM_SFT			; set IFSDRV for possible criter
	invoke	PREP_IFSR			; clear ifsrh				 ;AM003;
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	invoke	SFT_TO_SFF			; sets: [THISIFS]
						;	ES:BX -> IFSRH
						;	IFSR_OPEN_CB@
						;	ds - IFSSEG
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_LOCKFILE	; prep IFSRH
	MOV	ES:[BX.IFSR_FUNCTION],IFSEXECAPI
	MOV	ES:[BX.IFSR_APIFUNC],IFSLOCKFILE
	RestoreReg <DS> 			; range segment, mode (input bl)
	RestoreReg <AX> 			; restore input bl into al
	MOV	ES:[BX.IFSR_FUNC],AL
	SaveReg <SI,DX>
	RestoreReg <SI>
	MOV	AX,WORD PTR DS:[SI]
	MOV	WORD PTR ES:[BX.IFSR_LK_POSITION],AX
	MOV	AX,WORD PTR DS:[SI+2]
	MOV	WORD PTR ES:[BX.IFSR_LK_POSITION+2],AX
	MOV	AX,WORD PTR DS:[SI+4]
	MOV	WORD PTR ES:[BX.IFSR_LK_LENGTH],AX
	MOV	AX,WORD PTR DS:[SI+6]
	MOV	WORD PTR ES:[BX.IFSR_LK_LENGTH+2],AX
	RestoreReg <SI>
	SaveReg <CS>				; set ds=ifsseg for ifs call
	RestoreReg <DS>

	invoke	CALL_IFS			; *** call fs with lock request
	JNC	L_100
	transfer ifs_1000			; go to general return	 (util)
L_100:
	invoke	SFF_TO_SFT
	transfer ifs_990			; go to general good ret (util)
EndProc IFS_XLOCK
BREAK <IFS_FILE_XATTRIBUTES Get/Set File Extended Attributes by handle>

; Extended-attribute compatibility stub. Set requests (BL=4) succeed without
; storing attributes. Get requests return an empty list; USER_CX reports 2
; when a count word was written, otherwise 0.
	procedure   IFS_FILE_XATTRIBUTES,NEAR
	CMP	BL,4				;
	JNE	XFA_40				;
	JMP	C_990				; just ret success if set
XFA_40:

	Context DS				; on get - set size to 2 and count=0
	MOV	AX,[SAVE_CX]			; if count < 2 than no buffer2
	CMP	AX,2
	JGE	XFA_120
	XOR	AX,AX
	JMP	SHORT XFA_140
XFA_120:
	PUSH	[SAVE_ES]
	POP	ES
	MOV	DI,[SAVE_DI]
	XOR	AX,AX
	STOSW					; count in buffer
	MOV	AX,2
XFA_140:
	SaveReg <AX>				; preserve future cx
	CallInstall Get_User_Stack,multDOS,24	; put size  in user cx
	RestoreReg <AX> 			; restore future cx
	MOV	DS:[SI.USER_CX],AX
	JMP	C_990				; go ret in close to get ds-dosgroup
EndProc IFS_FILE_XATTRIBUTES
IFSSEG	ENDS
    END
