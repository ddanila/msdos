	PAGE	,132				; 
TITLE	IFSFUNC UTILITY ROUTINES - Routines for IFSFUNC
NAME	IFSUTIL
;************************************************************************************
; Miscellaneous routines
;   IFSFlushBuf
;   IFS_UPDATE_CB	(Part II)
;   SERVER_DOSCALL_CLOSEFILES_FOR_UID
;   SERVER_IFSFUNC_DATA_AREA
;   DRIVE_FROM_CDS
;   DRIVE_FROM_SFT
;   PREP_IFSR
;   CALL_IFS
;   CREATE_DFL_ENTRY
;;;alias ENTER_NAMES_LIST
;   DELETE_DFL_ENTRY
;;;alias EXIT_NAMES_LIST
;   DFL_MATCH
;   DFL_SINGLE_FILE_CHECK
;;;alias PROCESS_ALIAS
;   CDS_TO_CD
;   CD_TO_CDS
;   DFL_TO_DF
;   DF_TO_DFL
;   SFT_TO_SFF
;   SF_TO_SFT
;   XCHGP
;   CONSIST_SFT
;   CONSIST_DFL
;   PRN_CHECK
;   IFSDrvFromCDS
;   SET_THISIFS_UNC
;   SET_CATEGORY
;   SET_DEPIOCTL_IFSR
;   GET_UNC_FS_NAME
;   MOVE_DRIVER_NAME
;   CONVERT_NAME_ASCIIZ
;   CHECK_SEQ
;   CHECK_REAL_DEVICE
;   NET_TRANS
;   STRIP_WFP_START
;   CHECK_IFS_ATTRIBUTE
;   CHECK_IFS_SUPPORT
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
; include the rest of the segment definitions for normal MSDOS
include dosseg.asm
DATA		SEGMENT WORD PUBLIC 'DATA'
	;DOSGROUP Data
	Extrn	sft_addr:DWORD
	Extrn	sftFCB:DWORD
	Extrn	WFP_START:WORD
	Extrn	THISCDS:DWORD
	Extrn	THISSFT:DWORD
	Extrn	CDSADDR:DWORD
	Extrn	CDSCOUNT:BYTE
	Extrn	CurrentPDB:WORD
	Extrn	RetryCount:WORD
	Extrn	SysInitTable:BYTE
	Extrn	CurrentPDB:WORD
	Extrn	IFS_HEADER:DWORD
	Extrn	NULDEV:DWORD
	Extrn	SWAP_AREA_TABLE:BYTE
	Extrn	EXTERR:WORD
	Extrn	EXTERR_ACTION:BYTE
	Extrn	EXTERR_CLASS:BYTE
	Extrn	EXTERR_LOCUS:BYTE
	Extrn	ALLOWED:BYTE
	Extrn	ErrMap24End:BYTE
	Extrn	ErrMap24:BYTE
if debug
	Extrn	BugLev:WORD
	Extrn	BugTyp:WORD
	include bugtyp.asm
endif
DATA		ENDS
; define our own code segment
IFSSEG	SEGMENT BYTE PUBLIC 'IFSSEG'
	ASSUME	SS:DOSGROUP,CS:IFSSEG
	;IFS Data
	Extrn	IFSPROC_FLAGS:WORD
	Extrn	IFSFUNC_FLAGS:WORD
;;;aliasExtrn	NLAddr:DWORD
	Extrn	TEMPBUF:BYTE
	Extrn	DFLAddr:DWORD
	Extrn	DFLCount:BYTE
	Extrn	UNC_FS_HDR:DWORD
	Extrn	THISIFS:DWORD
	Extrn	THISDFL:DWORD
	Extrn	IFSR:WORD
	Extrn	CD1:WORD
	Extrn	DF1:WORD
	Extrn	SFF1:WORD
	Extrn	IFSDRV:BYTE
	Extrn	PHONEY_NAME:BYTE
	Extrn	DEVICE_CB@_OFFSET:WORD
	Extrn	SAVE_CB@:DWORD
	Extrn	IFSF_SWAP_START:BYTE
	Extrn	IFSF_SWAP_END:BYTE
	PUBLIC	LPT1_NAME
LPT1_NAME	DB	"LPT1",0
PRN_NAME	DB	"PRN",0
; The following buffer was created 1/88 to temporarily hold canonicalized
; path name for $Nametrans call for Redir
; Some area of TEMPBUF should be used instead for optimized storage space but
; I didn't have time to research the best way to use it as time was short to
; fix ptm
; This buffer should later be taken out when time permits to do this right
;
NET_TRANS_BUFFER DB	128 DUP (0)		; temporary buffer used for $Nametrans
						; storage of canonicalized pathname
BREAK <IFSFlushBuf -- Flush all Net Cache Buffers>
;************************************************************************************
; IFSFlushBuf
; Called by:	   Dispatcher
; Routines called: CD_TO_CDS
;		   CDS_TO_CD
;		   CALL_IFS
; Input: AL = 0  Flush all Net buffers.
;	      -1     "    "       "   plus invalidate them.
; Function:
;	FOR I = 1 to # CDSs
;	  DO
;	    IF CURDIR_ISIFS = true THEN
;	       DO
;		 Prepare IFSRH:
;		 *  IFSR_LENGTH      DW     40	     ; Request length
;		 *  IFSR_FUNCTION    DB      4	     ; Execute API function
;		  + IFSR_RETCODE     DW      ?
;		  + IFSR_RETCLASS    DB      ?
;		    IFSR_RESV1	     DB     16 DUP(0)
;		 *  IFSR_APIFUNC     DB      1	     ; Drive Reset
;		  + IFSR_ERROR_CLASS DB      ?
;		  + IFSR_ERROR_ACTION DB     ?
;		  + IFSR_ERROR_LOCUS DB      ?
;		  + IFSR_ALLOWED     DB      ?
;		  + IFSR_I24_RETRY   DB      ?
;		  + IFSR_I24_RESP    DB      ?
;		    IFSR_RESV2	     DB      ?
;		 *+ IFSR_DEVICE_CB@  DD      ?	     ; Call CDS_TO_CD to convert
;						    ; CDS to CD and set this as
;						    ; pointer to it.
;		    IFSR_OPEN_CB@    DD      ?
;		 *  IFSR_FUNC	     DB      ?	     ; 0 IF AL=0.  1 IF AL=-1.
;		    IFSR_RESV2	     DB      0
;		 CALL routine, CALL_IFS, with pointer to CURDIR_IFSR_HDR
;	       ENDDO
;	    ENDIF
;	  ENDDO
; Output:  None
; Notes:   all destroyed
;************************************************************************************
	procedure   IFSFlushBuf,NEAR
ASSUME	DS:DOSGROUP,ES:NOTHING
	ifsr_fcn_def  EXECAPI
	ifsr_api_def  DRIVERESET
	MOV	CL,CDSCount			; CX = # CDS's
	MOV	DX,SIZE curdir_list		; DX = size CDS entry
	LDS	SI,[CDSAddr]			; Get addr 1st CDS
IFB_20:
	TEST	DS:[SI.curdir_flags],curdir_isnet
	JZ	IFB_60
						; Is IFS.  Send drive reset request
	invoke	PREP_IFSR			; sets es:bx -> ifsr (zeroed out)
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_DRIVERESET
	MOV	ES:[BX.IFSR_FUNCTION],IFSEXECAPI
	MOV	ES:[BX.IFSR_APIFUNC],IFSDRIVERESET
	SaveReg <DS,SI> 			; save cds ptr
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	invoke	CDS_TO_CD
	MOV	ES:[BX.IFSR_FUNC],AL
	SaveReg <CX>				; preserve loop count
	invoke	CALL_IFS			; Call IFS
	RestoreReg <CX> 			; retrieve loop count
	JNC	IFB_30
	RestoreReg <SI,DS>			; restore cds ptr
	JMP	SHORT IFB_60
IFB_30:
	RestoreReg <DI,ES>			; restore cds ptr into es:di
	CALL	CD_TO_CDS			; update CDS if retcode ok
	PUSH	ES				; get cds ptr into ds:si
	POP	DS
	MOV	SI,DI
IFB_60:
	ADD	SI,DX				; Skip to next CDS
	LOOP	IFB_20
	JMP	IFS_990
;***********************************************************************************
;						  ifs common return area
;***********************************************************************************
	entry  IFS_980
	STC
	return
	entry  IFS_990
	CLC
	entry  IFS_1000
	return
EndProc IFSFlushBuf
BREAK <IFS_UPDATE_CB  Update SFT entry>
;******************************************************************************
; IFS_UPDATE_CB
; Called by:  IFSFUNC Dispatcher  (Share)
; Routines called:
;		     SFT_TO_SFF
;		     SF_TO_SFT
;		     CALL_IFS
; Inputs:
;	DS:SI -> SFT
; Function:
;	Prep IFSRH:
;	*  IFS_LENGTH	   DW	  28	   ; Request length
;	*  IFS_FUNCTION    DB	   6	   ; Control Block Update
;	   IFS_RETCODE	   DW	   ?
;	   IFS_RETCLASS    DB	   ?
;	   IFS_RESV1	   DB	  16 DUP(0)
;	*  IFS_CB@	   DD	   ?	   ; Control Block Address
;	*  IFS_TYPE	   DB	   ?	   ; Control Block Type
;	     IFSOPEN	   EQU	   0	   ;  Open instnce (SFT) entry
;	     IFSCB	   EQU	  -1	   ;  See CB Type Field
;	   IFS_RESV2	   DB	   0
;	Call IFS specified in SFT
; Outputs:
;	Carry set on error.  Error code in AX.
; Regs:
; Programming notes:
;******************************************************************************
	procedure IFS_UPDATE_CB,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	ifsr_fcn_def	UPDATECB
						; Reset ifsfunc processing flags
	MOV	CS:IFSPROC_FLAGS,ISCTLFCN+ISSFT ; Set this so SFT_TO_SFF sets
						; ifsr_cb@ instead of ifsr_open_cb@
						; ISSFT set so sft_to_sff sets
						; thisifs
	invoke	PREP_IFSR			; sets es:bx -> ifsr (zeroed out)
	Context DS
	invoke	SFT_TO_SFF			; SFT: sets [THISIFS]
						;	    ES:BX -> IFSRH
						;	    IFSR_CB@
						;	    ds - IFSSEG
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_UPDATECB	; prep IFSRH
	MOV	ES:[BX.IFSR_FUNCTION],IFSUPDATECB
	MOV	ES:[BX.IFSR_TYPE],IFSOPEN
	invoke	CALL_IFS
	JC	ifs_1000			; cf already set
	invoke	SFF_TO_SFT
	JMP	ifs_990
EndProc IFS_UPDATE_CB
BREAK <SERVER_DOSCALL_CLOSEFILES_FOR_UID>
;************************************************************************************
; SERVER_DOSCALL_CLOSEFILES_FOR_UID
; Called by:	   IFSFUNC Dispatcher
; Routines called:
;	CALL_IFS
; Inputs:
;	[CurrentPDB] set to UID of user aborting
; Function:
;	Get address of IFS driver chain.
;	FOR I = 1 to last IFS driver
;	    Send request below to IFS driver
;	IFSRH:
;	*  IFSR_LENGTH	    DW	   40	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DW	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   16 DUP(0)
;	*  IFSR_APIFUNC     DB	   19	    ; End of Computer ID
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	 + IFSR_ALLOWED     DB	    ?
;	 + IFSR_I24_RETRY   DB	    ?
;	 + IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	   IFSR_DEVICE_CB@  DD	    ?	    ; CD
;	   IFSR_OPEN_CB@    DD	    ?
;	*  IFSR_UID	    DW	    ?
; Outputs: None
; Regs: All destroyed
;************************************************************************************
	procedure   SERVER_DOSCALL_CLOSEFILES_FOR_UID,NEAR
ASSUME	DS:DOSGROUP,ES:NOTHING
	ifsr_fcn_def EXECAPI
	ifsr_api_def EOCID
	LDS	SI,IFS_HEADER			; get 1st ifs driver
ASSUME	DS:NOTHING
SDC_20: 					; ** Loop here on ifs drivers
	MOV	CS:WORD PTR [THISIFS],SI	; Send end of process request
	MOV	CS:WORD PTR [THISIFS+2],DS	; to all fs drivers.
						; Set thisifs for call_ifs
	invoke	PREP_IFSR			; sets es:bx -> ifsr (zeroed out)
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_EOCID
	MOV	ES:[BX.IFSR_FUNCTION],IFSEXECAPI
	MOV	ES:[BX.IFSR_APIFUNC],IFSEOCID
	MOV	AX,[CurrentPDB]
	MOV	ES:[BX.IFSR_UID],AX
	SaveReg <DS,CS>
	RestoreReg <DS>
ASSUME	DS:IFSSEG				; ds - ifsseg
	invoke	CALL_IFS
	RestoreReg <DS> 			; ds - fs driver
	LDS	SI,[SI.IFS_NEXT]		; Do next fs driver
	CMP	SI,NULL_PTR			; if ptr null, no more
	JNE	SDC_20
	PUSH	DS
	POP	AX
	CMP	AX,NULL_PTR
	JNE	SDC_20
	jmp	ifs_1000			; go return
EndProc SERVER_DOSCALL_CLOSEFILES_FOR_UID
BREAK <SERVER_IFSFUNC_DATA_AREA - IFSFUNC swappable data area>
;************************************************************************************
; SERVER_IFSFUNC_DATA_AREA
; Called by:	    Dispatcher
; Routines called:  None
; Inputs:
;	DS - DOSGroup
; Function:
;	Put IFSFUNC swappable data area info in ibmdos's swap_area_table
; Outputs:
;	swap_area_table filled in:
;			dw	num areas - 3
;			dd	ibmdos swap indos area address
;			dw	ibmdos swap indos area length
;			dd	ibmdos swap always area address
;			dw	ibmdos swap always area length
;			dd	ifsfunc swap indos area address
;			dw	ifsfunc swap indos area length
; Regs: All preserved
;************************************************************************************
	procedure   SERVER_IFSFUNC_DATA_AREA,NEAR
ASSUME	DS:DOSGROUP,ES:NOTHING
	SaveReg <AX,ES,DI,DS,SI,DX,CS>
	RestoreReg <ES>
	MOV	DI,OFFSET CS:IFSF_SWAP_START
	MOV	DX,OFFSET CS:IFSF_SWAP_END
	SUB	DX,DI
	LEA	SI,SWAP_AREA_TABLE	; get offset address of swap area table

	MOV	WORD PTR DS:[SI],3	; number of data areas increased from 2 to 3
	ADD	SI,14			; skip to ifsfunc area
	MOV	WORD PTR DS:[SI],DI	; fill in ifsfunc data area address
	MOV	WORD PTR DS:[SI+2],ES
	MOV WORD PTR DS:[SI+4],DX	; fill in ifsfunc data area length
	RestoreReg <DX,SI,DS,DI,ES,AX>
	return
EndProc SERVER_IFSFUNC_DATA_AREA
BREAK <DRIVE_FROM_XXX -- Compute a drive index from a CDS or SFT>
	procedure DRIVE_FROM_CDS,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
;************************************************************************************
; DRIVE_FROM_CDS
; Inputs:
;	[THISCDS] Set
;	DS - DOSGROUP
; Function:
;	Compute drive letter from THISCDS
; Outputs:
;	[IFSDRV] = Drive # (0=A)
; No registers Revised
;************************************************************************************
	PUSH	BX
	PUSH	AX
	MOV	[IFSDRV],0FEH		; Default to ?, 0FEH + 'A' = '?'
	MOV	AX,WORD PTR [THISCDS]
	CMP	AX,-1
	JZ	DFC_20
	CALL	IFSDrvFromCDS
DFC_20:
	POP	AX
	POP	BX
	jmp	ifs_1000		; go return
EndProc DRIVE_FROM_CDS
;************************************************************************************
; DRIVE_FROM_SFT
; Inputs:
;	[THISSFT] Set	   DS-Dosgroup
; Function:
;	Compute drive letter from THISSFT
; Outputs:
;	[IFSDRV] = Drive # (0=A)
;	[IFSDRV] = -1 if printer
;		PHONEY_NAME
; No registers Revised
;************************************************************************************
	procedure DRIVE_FROM_SFT,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <DS,BX,CX>
	LDS	BX,[THISSFT]
	TEST	[BX.sf_flags],sf_net_spool
	JNZ	DFS_100
	MOV	BL,BYTE PTR [BX.sf_flags]
	AND	BL,devid_file_mask_drive
	CMP	BL,0FEH AND devid_file_mask_drive	; UNC ????
	JNZ	DFS_20			; No
	MOV	BL,0FEH 		; Restore lost bits if UNC
DFS_20:
	MOV	[IFSDRV],BL
	RestoreReg <CX,BX,DS>
	JMP	ifs_1000		; go return
DFS_100:
	SaveReg <ES,DI,SI>
	MOV	DI,OFFSET CS:[PHONEY_NAME]	; Set name for I24 handler
	PUSH	CS
	POP	ES
	MOV	SI,BX
	ADD	SI,SF_NAME
	MOV	CX,8
	REP	MOVSB
	RestoreReg <SI,DI,ES>
	MOV	BL,-1
	JMP	DFS_20
EndProc DRIVE_FROM_SFT
BREAK <PREP_IFSR -- zero out ifsr>
;************************************************************************************
; PREP_IFSR
; Called by:	all function routines
; Inputs: none
; Function:
;	set all ifsrh fields to zero
; Outputs:
;	ES:BX -> IFSRH
; Regs: all except ES,BX saved
;************************************************************************************
	procedure PREP_IFSR,NEAR
	SaveReg <DS,DI,AX,CX>			; save regs
	SaveReg <CS,CS> 			; get ds,es -> ifsseg
	RestoreReg <DS,ES>
ASSUME	DS:IFSSEG,ES:IFSSEG
	MOV	DI,OFFSET IFSR			; es:di -> ifsrh
	MOV	BX,DI				; es:bx -> ifsrh
	MOV	CX,SIZE IFSRH  /2
	XOR	AX,AX
	REP	STOSW				; fill ifsr w/zeros
	RestoreReg <CX,AX,DI,DS>		; restore regs
	return
EndProc PREP_IFSR
BREAK <CALL_IFS - call IFS Driver>
;************************************************************************************
; CALL_IFS
; Called by:	all function routines
; Inputs:
;	[THISIFS] set
;	ES:BX -> IFS request header
;	DS - IFSSEG
; Function:
;	Call file system function entry point
; Outputs:
;	Outputs of call
; Regs: none preserved
;************************************************************************************
	procedure CALL_IFS,NEAR
	CALL	CHECK_IFS_SUPPORT		; 1st check if this request ok for ifs
	PUSH	WORD PTR [THISIFS]		; save thisifs offset

	CALL	SET_CATEGORY			; do this to determine unc or ifs
	OR	CL,CL				; cl-1 for unc, 0 for ifs
	JNZ	CI_05
	invoke	EcritIFS			; enter ifs critical section
	JMP	SHORT CI_10
CI_05:
	invoke	EcritNET			; enter network critical section

CI_10:
	LDS	SI,[THISIFS]			; set thisifs=fs driver fcn entry pt
	MOV	AX,DS:[SI.IFS_CALL@]		; offset=contents of ifs_call@
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	MOV	WORD PTR [THISIFS],AX
	PUSH	CX				; save this for later unc vs. ifs check
;----------------------------------------------------------------------------
	CALL	[THISIFS]			; call fs driver with request
;----------------------------------------------------------------------------
	POP	CX				; unc or ifs result
	POP	WORD PTR [THISIFS]		; restore thisifs offset

	OR	CL,CL				; again, determine whether to exit ifs
	JNZ	CI_15				; or unc critical section
	invoke	LcritIFS			; leave ifs critical section
	JMP	SHORT CI_17
CI_15:
	invoke	LcritNET			; leave network critical section

CI_17:
	MOV	AL,ES:[BX.IFSR_RETCLASS]	; check for error (class)
	CMP	AL,IFSR_NO_ERROR		; (any err must have class set)
	JNE	CI_20
	JMP	ifs_990 			; no error, go ret no carry
;-----------------------------------------------; error processing
CI_20:
	TEST	IFSPROC_FLAGS,IsInit		; if in init code, skip error proc
	JZ	CI_22
	JMP	ifs_980 			; init error- just go stc and quit
CI_22:
	CMP	AL,IFSR_INT21H_CRITER		; critical error?
	JE	CI_23
	JMP	CI_30
CI_23:
	MOV	AX,ES:[BX.IFSR_RETCODE] 	; put retcode in al before condition


	CMP	AX,error_write_protect
	JB	NO_UNMAP
	CMP	AX,error_gen_failure
	JA	NO_UNMAP
	SUB	AX,error_write_protect	; BIAS old errors back down into 0-12 range
NO_UNMAP:
	PUSH	DS
	Context DS
ASSUME	DS:DOSGROUP
	MOV	DI,AX
	MOV	AX,OFFSET DOSGroup:ErrMap24End
	SUB	AX,OFFSET DOSGroup:ErrMap24
; AX is the index of the first unavailable error.  Do not translate if
; greater or equal to AX.
	CMP	DI,AX
	MOV	AX,DI
	JAE	NoTrans
	MOV	AL,ErrMap24[DI]
	XOR	AH,AH
NoTrans:
	POP	DS
	invoke	SET_EXTERR_INFO 		; yes - set error info

CI_25:
	SaveReg <DS,SI,ES,DI,CX,AX>		; temporarily save ifsr in tempbuf over
	SaveReg <ES>				; next call
	RestoreReg <DS> 			; Set dssi -> ifsr (current esbx)
	MOV	SI,BX
	MOV	CX,36				; half size of max ifsr
	MOV	DI,OFFSET TEMPBUF		; set esdi -> tempbuf
	CLD					; next instr auto-increment
	REP	MOVSW				; copy the ifsr over (word move)
	MOV	AX,CS:IFSPROC_FLAGS		; preserve ifsproc_flags
	STOSW
	RestoreReg <AX,CX,DI,ES,SI,DS>		; restore regs

	CMP	DI,error_I24_gen_failure
	JBE	CI_26
	MOV	DI,error_I24_gen_failure
CI_26:
	SaveReg <AX>				; preserve dos ext err
	invoke	IFS_I24 			;	do int 24h

	SaveReg <DS,SI,ES,DI,CX,AX>		; restore original ifsr (over criter one)
	SaveReg <CS,CS> 			; set dssi -> tempbuf
	RestoreReg <DS,ES>			; set esdi -> ifsr
	MOV	SI,OFFSET TEMPBUF		;
	MOV	DI,OFFSET IFSR			;
	MOV	CX,36				; half size of max ifsr
	CLD					; next instr auto-increment
	REP	MOVSW				; copy the ifsr over (word move)
	LODSW					; restore ifsproc_flags
	MOV	CS:IFSPROC_FLAGS,AX		;
	RestoreReg <AX,CX,DI,ES,SI,DS>		; restore regs

	CMP	AL,RETRY			;	if retry, restart request
	JE	CI_27				;	else, go ret w/carry
	RestoreReg <AX> 			; retrieve dos ext err			 ;AN021;;AM025;
	JMP	ifs_980
CI_27:
	ADD	SP,2				; restore stack (dos ext error #)
	JMP	CI_80
CI_30:						; not critical error:
	CMP	AL,IFSR_BAD_FORMAT		; map ifsr bad format error to general
	JNE	CI_32				; failure (12) critical error
	MOV	AL,12
	MOV	SS:[EXTERR],31			; set dos error variables for abort
	MOV	SS:[EXTERR_CLASS],4		; (Internal)
	MOV	SS:[EXTERR_ACTION],4		; (Abort)
	MOV	SS:[EXTERR_LOCUS],1		; (Unknown)
	MOV	SS:[ALLOWED],08H		; allow only fail
	MOV	DI,AX
	JMP	CI_25				; go back & treat as critical error
CI_32:
	CMP	AL,IFSR_DRIVER_ERROR
	JNE	CI_37
	MOV	AX,ES:[BX.IFSR_RETCODE] 	; *** driver error class ***
	CMP	AX,IFSR_NO_FCN_SUPPORT
	JG	CI_34
	MOV	AX,50				; request not supported by file system
	JMP	CI_100
CI_34:
	CMP	AX,IFSR_ACCESS_DENIED
	JNE	CI_35
	MOV	AX,65				; access denied by file system
	JMP	CI_100
CI_35:
	CMP	AX,IFSR_DEVICE_TYPE_MISMATCH
	JNE	CI_36
	MOV	AX,66				; file sytem device type incorrect
	JMP	CI_100
CI_36:
	MOV	AX,59				; fs experienced an unexpected error
	JMP	CI_100

CI_37:
	CMP	AL,IFSR_DEVICE_ERROR		; fs got device error
	JNE	CI_38
	MOV	AX,ES:[BX.IFSR_RETCODE]
	invoke	DEVICE2EXTERR			; convert device - ext error
	JMP	CI_100				; go set class/action/locus
CI_38:
	MOV	AX,ES:[BX.IFSR_RETCODE]
	CMP	AX,error_sharing_violation
	JNZ	CI_100
	SaveReg <DS>				;  save ifsseg
	Context DS				;     Share error
	invoke	PHONEY_DPB			;     Set phoney NET DPB for INT 24
	CMP	ES:[BX.IFSR_APIFUNC],IFSOPENFILE ; on open/create - share error,no int24
	JNE	CI_39
	CallInstall SHARE_ERROR,MultDOS,11
	JMP	SHORT  CI_39_20
CI_39:
	CallInstall SHARE_VIOLATION,MultDOS,10
CI_39_20:
	RestoreReg <DS>
	JNC	CI_40
	MOV	AX,error_sharing_violation	;      carry set - quit w/error
	invoke	SET_EXTERR_INFO
	JMP	ifs_980
CI_40:						;      carry clear - retry
	MOV	AL,RETRY

CI_80:
	INC	ES:[BX.IFSR_I24_COUNT]		;	retry: inc retry count
	MOV	ES:[BX.IFSR_I24_RESP],AL	;	     store i24 response
	MOV	ES:[BX.IFSR_RETCODE],0		;	     reset retcode and class
	MOV	ES:[BX.IFSR_RETCLASS],0
	MOV	ES:[BX.IFSR_ERROR_CLASS],0	;	     reset retcode and class
	MOV	ES:[BX.IFSR_ERROR_ACTION],0
	MOV	ES:[BX.IFSR_ERROR_LOCUS],0	;	     reset retcode and class
	MOV	ES:[BX.IFSR_ALLOWED],0
	SaveReg <CS>				;	       restore ds-ifsseg
	RestoreReg <DS>
ASSUME	DS:IFSSEG
	JMP	CALL_IFS
CI_100: 					;     non-critical error
	TEST	CS:IFSPROC_FLAGS,IsMsgRet	;     if msg ret call to int 2f-5 stack
	JNZ	CI_120				;     not dosgroup so can't call next
	CALL	SET_EXTERR_INFO 		;     set exterr info and
CI_120:
	JMP	ifs_980 			;     go ret w/carry
EndProc CALL_IFS
BREAK <CREATE_DFL_ENTRY - fill in DFL entry, add to names list if alias>
;************************************************************************************
; CREATE_DFL_ENTRY
; Routine called by:  ATTACH_START
;		      PROCESS_ALIAS
; Routines called:    DFL_TO_DF
;		      ENTER_NAMES_LIST
; Inputs:
;	[THISIFS] set
;	BL = macro type
;	CX = user word
;	DS:SI -> ASCIIZ device name
;	ES:DI -> Target driver to attach to and parms.
;			  DW ASCIIZ  -	FS name
;			  DW n	     -	number of parms
;			  DB ASCIIZ,... parms
; Function:
;	WHILE DFL entries
;	  IF entry not in use THEN
;	     DO
;	       Set in progress flag for this entry
;	       DFL_TYPE = BL
;	       DFL_DEV_NAME = name pointed to by DS:SI
;	       DFL_USER_WORD = CX
;	       IF alias, Call ENTER_NAMES_LIST
;	       DFL_IFS_HDR = [THISIFS]
;	       Set in use flag
;	       Reset in progress flag
;	       Set [THISDFL]
;	       Call DFL_TO_DF
;	       LEAVE WHILE
;	     ENDDO
;	  ELSE DO
;		 Get next DFL entry
;		 IF no entry THEN
;		    Set error_out_of_structures
;		 ENDIF
;	       ENDDO
;	ENDWHILE
; Outputs:
;    carry clear:
;	DFL entry created.  Names list addition if alias.
;	[THISDFL] set
;	DS:SI -> DFL
;	If not alias:
;	  DF loaded
;	  ES:BX -> IFSRH
;	  IFSR_DEVICE_CB@ -> DF
;    carry set on error, ax - error
; Regs: DS:SI -> DFL, all others destroyed
;************************************************************************************
	procedure CREATE_DFL_ENTRY,NEAR
	SaveReg <DS,SI> 			; save input DS:SI (devname)
	MOV	DX,CX				; save user word in dx
	LDS	SI,CS:[DFLAddr] 		; Set DS:SI -> 1st DFL entry
	MOV	CL,CS:DFLCount			; CX = # DFL entries
	OR	CL,CL				; check for available dfl structure
	JZ	CDE_30
	XOR	CH,CH
ASSUME	DS:NOTHING,ES:NOTHING
	CALL	CONSIST_DFL			; reset all in_prog flags
CDE_20:
	TEST	[SI.DFLL_FLAGS],DFL_INUSE	; look for unused DFL
	JZ	CDE_40				; entry
	ADD	SI,SIZE DFLL_LIST
	LOOP	CDE_20
CDE_30:
	MOV	AX,error_out_of_structures
	RestoreReg <SI,DS>			; restore stack
	JMP	ifs_980 			; go return w/carry
CDE_40:
	CALL	INIT_DFL			; zero out dfl entry
	OR	[SI.DFLL_FLAGS],DFL_INPROG	; Found DFL entry -
						; Set in progress flag
	MOV	[SI.DFLL_TYPE],BL		; Store DFL_TYPE
	MOV	[SI.DFLL_USER_WORD],DX		; store user word
	RestoreReg <DI,ES>			; get dev name ptr off stack
	CALL	XCHGP				; Set DS:SI -> devname
	PUSH	DI				;     ES:DI -> DFL
						; save dfl start offset
CDE_60:
	INC	DI				; mov di to dfl_dev_name
	INC	DI
	MOV	CX,8				; Devs max of 8 ch and ':', and a NUL
CDE_70: 					; dssi->source, esdi->dfl_dev_name
	LODSB					; just store 1st 8 padded to right
	CallInstall UCase,multDOS,19,<AX>,<BX>	; w/blanks				 ;AC030; ax chg to bx
	OR	AL,AL				; 0 . : signal end
	JZ	CDE_73
	CMP	AL,'.'
	JZ	CDE_73
	CMP	AL,':'
	JZ	CDE_73
	STOSB
	LOOP	CDE_70
	JMP	SHORT CDE_80
CDE_73:
	MOV	AL," "
CDE_76:
	STOSB
	LOOP	CDE_76
;;;aliasCMP	BL,TYPE_ALIAS
;;;;;;;;JNE	CDE_80
;;;;;;;;CALL	ENTER_NAMES_LIST			; Store alias index
;;;;;;;;JNC	CDE_120
;;;;;;;;POP	DI					; if error back out
;;;;;;;;AND	[SI.DFLL_FLAGS],NOT DFL_INPROG		; go exit with carry
;;;aliasJMP	ifs_980
CDE_80:
	ADD	DI,4					; skip alias index and user wd
;;;;	INC	DI									 ;AD004;
CDE_100:
	MOV	AX,WORD PTR [THISIFS]
	STOSW						; Set DFL_IFS_HDR to
	MOV	AX,WORD PTR [THISIFS+2] 		; [THISIFS]
	STOSW
CDE_120:
	POP	DI					; retrieve dfl start
	MOV	WORD PTR CS:[THISDFL],DI		; Set [thisdfl]
	MOV	WORD PTR CS:[THISDFL+2],ES
	PUSH	ES					; Set DS:SI -> DFL
	POP	DS
	MOV	SI,DI
	CALL	CHECK_REAL_DEVICE			; this will set dfl_dev_real
	OR	[SI.DFLL_FLAGS],DFL_INUSE
	AND	[SI.DFLL_FLAGS],NOT DFL_INPROG
;;;aliasCMP	BL,TYPE_ALIAS
;;;aliasJNE	CDE_140
;;;aliasJMP	ifs_990 			; go ret no carry
CDE_140:
	invoke	PREP_IFSR			; init req hdr
	invoke	DFL_TO_DF
	JMP	ifs_990
EndProc CREATE_DFL_ENTRY
BREAK <DELETE_DFL_ENTRY - Delete DFL entry, remove from names list if alias>
;************************************************************************************
; DELETE_DFL_ENTRY
; Routine called by:  IFS_ASSOPER
; Routines called:
; Inputs:
;	[THISDFL] set
; Function:
; Outputs:
;    carry clear:
;	DFL entry deleted.
;    carry set on error, ax - error
; Regs: everything preserved
;************************************************************************************
	procedure DELETE_DFL_ENTRY,NEAR
	LDS	SI,[THISDFL]			; simply reset in_use bit
	AND	DS:[SI.DFLL_FLAGS],NOT DFL_INUSE
;;;aliasCMP	DS:[SI.DFLL_TYPE],TYPE_ALIAS	; if alias, must remove name
;;;aliasJE	DDE_20				; from names list, and reset
	JMP	ifs_1000
;;;aliasDDE_20:
;;;aliasCALL	EXIT_NAMES_LIST 		; all alias indicies
;;;aliasJMP	ifs_1000
EndProc DELETE_DFL_ENTRY
;BREAK <ENTER_NAMES_LIST - add alias name to Names List>
;;;alias
;************************************************************************************
; ENTER_NAMES_LIST
; Routine called by:  CREATE_DFL_ENTRY
; Routines called:	DOS: DStrLen
; Inputs:
;	  DS:SI -> DFL
;	  ES:DI -> Target driver to attach to and parms.
;			  DW ASCIIZ  -	FS name
;			  DW n	     -	number of parms
;			  DB ASCIIZ,... parms
; Function:
;	Place one and only parameter (alias) into names list.
; Outputs:
;	carry clear: name added
;	carry set:   AX error
; Notes:  all preserved except AX
;************************************************************************************
;	procedure ENTER_NAMES_LIST
;SSUME	DS:IFSSEG,ES:IFSSEG
;	SaveReg <ES,DI,CX,DX,DS,SI>
;	PUSH	ES
;	POP	DS
;	MOV	SI,DI
;	ADD	SI,4				; ds:si -> alias name
;	CallInstall DStrlen,multDOS,37		; get size of alias name in cx
;	LES	DI,[NLAddr]			; get address of names list
;	MOV	DX,WORD PTR ES:[DI]		; DX=total size of names list
;	INC	DI
;	INC	DI
;	MOV	AX,WORD PTR ES:[DI]		; AX=used size of names list
;	PUSH	AX				; save used size for dfl_alias_index
;	ADD	AX,CX				; AX=hopefully new used size
;	CMP	DX,AX				; check that new string fits
;	JAE	ENL_20
;	MOV	AX,error_out_of_structures	; error - doesn't fit
;	JMP	ENL_980 			; ret w/carry
;NL_20: 					; ok - fits
;	STOSW					; store new used size
;	POP	AX				; get index from stack
;	PUSH	AX
;	INC	DI
;	INC	DI
;	ADD	DI,AX				; Space to spot in list to put name
;	REP	MOVSB
;	RestoreReg <SI,DS>			; Set dfl alias index to byte offset
;	POP	AX				; (+4) of name in list
;	MOV	DS:WORD PTR [SI.DFL_ALIAS_INDEX],AX
;	JMP	ENL_990 			; go ret no carry
;NL_980:					; Return area
;	STC					; error
;	RestoreReg <SI,DS,DX,CX,DI,ES>
;	return
;NL_990:
;	CLC					; no error
;	RestoreReg <DX,CX,DI,ES>
;NL_1000:
;	return
;ndProc ENTER_NAMES_LIST
;REAK <EXIT_NAMES_LIST - remove alias name from Names List>
;************************************************************************************
; EXIT_NAMES_LIST
; Routine called by:  DELETE_DFL_ENTRY
; Routines called:	DOS: StrLen
; Inputs:
;	  DS:SI -> DFL
; Function:
;	Remove alias name from Names List
; Outputs:
;	name removed
; Notes:  all preserved
;************************************************************************************
;	procedure EXIT_NAMES_LIST
;SSUME	DS:IFSSEG,ES:IFSSEG
;	MOV	DX,DS:[SI.DFL_ALIAS_INDEX]	; DX=index
;	LES	DI,[NLAddr]
;	MOV	AX,ES:WORD PTR [DI+2]		; AX=used size
;	SaveReg <ES,DI,AX>
;	ADD	DI,DX+4
;	CallInstall StrLen,multDOS,18		; CX=size of alias name
;	PUSH	ES
;	POP	DS
;	MOV	SI,DI
;	ADD	SI,CX
;	MOV	BX,CX
;	SUB	AX,SI				; CX= #bytes to move =
;	MOV	CX,AX				; used size - index of next name
;	REP	MOVSB				; move names up
;	RestoreReg <AX,DI,ES>			; adjust used size
;	SUB	AX,BX
;	MOV	ES:WORD PTR [DI+2],AX
;	LDS	SI,[DFLAddr]			; loop thru all dfl entries to
;	MOV	DI,SIZE DFL_LIST		; adjust alias indicies above
;	MOV	CL,[DFLCount]			; index removed
;	XOR	CH,CH
;XNL_20:					; ** Loop here on dfl entries
;	TEST	DS:[SI.DFLL_FLAGS],DFL_INUSE
;	JZ	EXNL_40
;	MOV	AX,DS:[SI.DFL_ALIAS_INDEX]	; 0 if not alias
;	CMP	AX,DX
;	JB	EXNL_40
;	SUB	AX,BX				; adjust by size of name deleted
;	MOV	DS:[SI.DFL_ALIAS_INDEX],AX
;XNL_40:
;	ADD	SI,DX
;	LOOP	EXNL_20
;	JMP	ifs_1000			; go return
;ndProc EXIT_NAMES_LIST
BREAK <DFL_SINGLE_FILE_CHECK - support single file check>
;************************************************************************************
; DFL_SINGLE_FILE_CHECK
; Routine called by:  IFS_FILE_ATTRIBUTES
; Inputs:
;	  [THISDFL]
;	  [WFP_START]
; Function:
;	IF [THISDFL] .NOT. NULL THEN
;	   DO
;	     Get IFS header from DFL_IFS_HDR
;	     IF IFSDEVICE true THEN
;		DO
;		  Call DFL_TO_DF
;		  Clear carry
;		ENDDO
;	     ELSE   Set error - device doesn't support single file fcn
;	     ENDIF
;	   ENDDO
;	ELSE DO
;	       CALL DFL_MATCH
;	       IF match found THEN
;		  DO
;		    Get IFS header from DFL_IFS_HDR
;		    IF IFSDEVICE true THEN
;		       DO
;			 Call DFL_TO_DF
;			 Clear carry
;		       ENDDO
;		    ELSE Set error - device doesn't support single file fcn
;		  ENDDO
;	       ELSE Set error - device not IFS
;	       ENDIF
;	     ENDDO
;	ENDIF
; Outputs:
;	no carry:		carry: error
;	  [THISIFS] set
;	  ES:BX -> IFSRH
;	  IFSR_DEVICE_CB@
;	  ds - IFSSEG
;************************************************************************************
	procedure DFL_SINGLE_FILE_CHECK
ASSUME	DS:IFSSEG,ES:IFSSEG
;; assume thisdfl aready set up here
;; don't want to write another parse routine
;;	CMP	WORD PTR [THISDFL],MINUS_ONE
;;	JNZ	DSFC_20
;;	CALL	DFL_MATCH			; check for dfl entry
;;	JNC	DSFC_20
;;	MOV	AX,error_not_ifs_device
;;	JMP	ifs_1000
DSFC_20:
	LES	DI,CS:[THISDFL]
	LES	DI,ES:[DI.DFLL_IFS_HDR]		; check that ifs device supports
	TEST	ES:[DI.IFS_ATTRIBUTE],IFSDEVICE ; single file function
	JNZ	DSFC_60
	MOV	AX,error_file_not_found 	; no - set error & go return w/carry
	JMP	ifs_980
DSFC_60:
	invoke	DFL_TO_DF
	JMP	ifs_990
EndProc DFL_SINGLE_FILE_CHECK
;BREAK <PROCESS_ALIAS -- add alias name>
;************************************************************************************
; PROCESS_ALIAS
; Called by: ATTACH_START
; Routines called:  DFL_MATCH
;		    CREATE_DFL_ENTRY
; Inputs:
;	    DS:SI -> ASCIIZ source name
;	    ES:DI -> ALIAS name
; Function:
; Regs:
;************************************************************************************
;	Procedure   PROCESS_ALIAS,NEAR
;SSUME	DS:NOTHING,ES:NOTHING
;	CALL	DFL_MATCH
;	JC	PA_20
;;;???	match found, error or override???
;A_20:
;	CALL	CREATE_DFL_ENTRY
;	JMP	ifs_1000
;ndProc PROCESS_ALIAS
BREAK <DFL_MATCH -- check for DFL entry>
;************************************************************************************
; DFL_MATCH
; Called by: ATTACH_START  CONSIST_SFT
;	     IFS_DELETE
; Routines called:
; Inputs:
;	    DS:SI -> Asciiz Device name
; Function:
;	Search DFL for match on name
;	If match found - set [THISDFL] and clear carry
;	Else set carry
; Output:
;	carry clear - match found, [THISDFL] set
;	carry set   - match not found
; Regs: all preserved
;************************************************************************************
	Procedure   DFL_MATCH
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <DS,SI,ES,DI,AX,CX,BX>		; save registers
	SaveReg    <CS> 			; store canonicalized version of
	RestoreReg <ES> 			; source asciiz dev name in
	MOV	DI,OFFSET TEMPBUF+10		; tempbuf+10
	MOV	CX,10				; devs max of 8 ch and : and nul
DM_20:
	LODSB
	CallInstall UCase,multDOS,19,<AX>,<BX>
	STOSB
	OR	AL,AL
	JZ	DM_60
	CMP	AL,"."
	JZ	DM_40
	LOOP	DM_20
DM_40:
	XOR	AL,AL
	MOV	BYTE PTR ES:[DI-1],AL
DM_60:
	CMP	BYTE PTR ES:[DI-2],":"
	JNZ	DM_80
	MOV	BYTE PTR ES:[DI-2],0
DM_80:
	XOR	AX,AX				; ax is counter through DFL entries
	LDS	SI,[DFLAddr]			; dssi -> dfl entry
DM_100: 					; <<<<< matching loop >>>>>
	CMP	AL,CS:[DFLCount]
	JAE	DM_980
	TEST	DS:[SI.DFLL_FLAGS],DFL_INUSE
	JZ	DM_160
	SaveReg <SI>				; dfl entry offset
	ADD	SI,DFL_DEV_NAME
	MOV	DI,OFFSET TEMPBUF
	CALL	CONVERT_NAME_ASCIIZ		; moves dev name into tempbuf
						; in asciiz form - di preserved
	MOV	SI,OFFSET TEMPBUF+10
	Call	PRN_CHECK			; if si->prn - chg si->lpt1
	CallInstall StrCmp,multDOS,30,<AX>,<AX> ; check for match
	RestoreReg <SI> 			; dfl entry offset
	JZ	DM_990
DM_160:
	ADD	SI,SIZE DFLL_LIST
	INC	AL
	JMP	SHORT DM_100			; go up & try next entry
DM_980:
	SaveReg <AX,CS> 			; set thisdfl null on error
	RestoreReg <DS>
	MOV	AX,NULL_PTR
	MOV	WORD PTR [THISDFL],AX
	MOV	WORD PTR [THISDFL+2],AX
	RestoreReg <AX>
	STC
	JMP	SHORT DM_1000
DM_990:
	TEST	DS:[SI.DFLL_FLAGS],dfl_paused	; if printer paused, no match
	JNZ	DM_980

	MOV	CS:WORD PTR [THISDFL],SI
	MOV	CS:WORD PTR [THISDFL+2],DS
	CLC					; es:di -> dfl on match
DM_1000:
	RestoreReg <BX,CX,AX,DI,ES,SI,DS>	; restore regs
	return
EndProc DFL_MATCH
BREAK <SFT_TO_SFF -- Convert SFT to SFF>
;************************************************************************************
; SFT_TO_SFF
; Inputs:
;	[THISSFT] set
;	DS - DOSGROUP
; Function:
;	Load SFF from SFT
;	  SFF_TYPE	=  0
;	  SFF_TYPE+1	=  0
;	  SFF_FLAGS	=  SF_FLAGS
;	  SFF_MODE	=  SF_MODE
;	  SFF_RESV1	=  0
;	  SFF_ATTR	=  SF_ATTR
;	  SFF_UID	=  SF_UID
;	  SFF_PID	=  SF_PID
;	  SFF_SIZE	=  SF_SIZE
;	  SFF_POSITION	=  SF_POSITION
;	  SFF_TIME	=  SF_TIME
;	  SFF_DATE	=  SF_DATE
;	  SFF_NAME	=  SF_NAME
;	  SFF_EXT	=  SF_NAME+8
;	  SFF_RESV2	=  0
;	  SFF_SF_ID	=  math on sft address
;	  SFF_FSDA	=  SF_CLUSPOS
;	  SFF_FSDA + 2	=  SF_DIRSEC
;	  SFF_FSDA + 4	=  SF_DIRSEC+2
;	  SFF_FSDA + 6	=  SF_LSTCLUS
; Outputs:
;	SF loaded
;	ES:BX -> IFSRH
;	IFSR_OPEN_CB@ set
;	If SetDeviceCB set then IFSR_DEVICE_CB@ set
;	DS - IFSSEG
; notes: all except ES,BX,DS preserved
;************************************************************************************
	procedure SFT_TO_SFF,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <DI,SI,AX,CX>			; save regs
	SaveReg <CS>
	RestoreReg <ES>
ASSUME	ES:IFSSEG
	MOV	DI,OFFSET SFF1			; DS:SI -> SFT
	LDS	SI,[THISSFT]			; ES:DI -> SFF
	SaveReg <DI>				; save SFF offset
	MOV	AH,CBTYPE_SFF			; sff_type
	XOR	AL,AL
	STOSW
	MOV	AX,WORD PTR [SI.SF_FLAGS]	; sff_flags
	STOSW
	MOV	AX,WORD PTR [SI.SF_MODE]	; sff_mode
;;;;;;;;PUSH	BX									 ;AD015;
;;;;;;;;AND	BX,8000H								 ;AD015;
;;;;;;;;OR	AX,BX									 ;AD015;
	STOSW
;;;;;;;;POP	AX									 ;AD015;
;;;;;;;;AND	AX,0EFFFH								 ;AD015;
;;;;;;;;STOSW										 ;AD015;
;;;;;;;;MOV	AX,WORD PTR [SI.SF_IOMODE]	; sff_iomode				 ;AD024;
	XOR	AX,AX				; just put zero in reserved area
	STOSW
	MOV	AL,BYTE PTR [SI.SF_ATTR]	; sff_attr
;;;;;;;;MOV	AH,BYTE PTR [SI.SF_ATTR_HI]	; sff_attr_hi  - no longer exists	 ;AD024;
	STOSW
	MOV	AX,WORD PTR [SI.SF_UID] 	; sff_uid
	STOSW
	MOV	AX,WORD PTR [SI.SF_PID] 	; sff_pid
	STOSW
	SaveReg <SI>
	ADD	SI,SF_SIZE
	MOV	CX,4
	REP	MOVSW				; sff_size & position
	RestoreReg <SI>
	MOV	AX,WORD PTR [SI.SF_TIME]	; sff_time
	STOSW
	MOV	AX,WORD PTR [SI.SF_DATE]	; sff_date
	STOSW
	SaveReg <SI>				; sff_name/ext/cp
	ADD	SI,SF_NAME
	MOV	CX,11				;   (name - 11, cp - 2 bytes) cp out
	REP	MOVSB
	XOR	AX,AX
	STOSW					; just put zero in reserved area

	RestoreReg <SI> 			; sff_sf_id
	SaveReg <SI,DS,DS>			;     calculate based on sft address
	RestoreReg <AX>
	MOV	CL,4
	SHL	AX,CL
	ADD	SI,AX
	RestoreReg <AX>
	AND	AX,0F000H
	ADD	AX,SI
	STOSW
	RestoreReg <SI>
	ADD	DI,SIZE SFF_RESV		; sff_fsda  1st word
	SaveReg <SI>				; save si for issft case
	ADD	SI,SF_CLUSPOS
	MOV	CX,3
	REP	MOVSW
;;;;;;;;ADD	SI,12									 ;AN017;;AD024;
;;;;;;;;MOVSW										 ;AN017;;AD024;
	RestoreReg <SI>
	MOV	AX,WORD PTR [SI.SF_LSTCLUS]	; manually put lstclus in fsda+6
	STOSW
	TEST	CS:[IFSPROC_FLAGS],ISSFT
	JZ	SFT_20
	MOV	AX,WORD PTR [SI.SF_IFS_HDR]	; Set [THISIFS] only if
	MOV	WORD PTR CS:[THISIFS],AX	;   no yet set by cds_to_cd or
	MOV	AX,WORD PTR [SI.SF_IFS_HDR+2]	;   dfl_to_df
	MOV	WORD PTR CS:[THISIFS+2],AX
SFT_20:
	RestoreReg <DI> 			; restore ES:DI -> start of SFF
	SaveReg    <ES> 			; set DS:DI -> SFF
	RestoreReg <DS>
ASSUME	DS:IFSSEG
	MOV	BX,OFFSET IFSR			 ; set ES:BX -> IFSRH
	TEST	CS:IFSPROC_FLAGS,ISCTLFCN
	JNZ	SFT_40					; API fcn -
	MOV	WORD PTR ES:[BX.IFSR_OPEN_CB@],DI	; set IFSR_OPEN_CB@
	MOV	WORD PTR ES:[BX.IFSR_OPEN_CB@+2],DS
	JMP	SFT_60
SFT_40: 					; Ctl fcn -
	MOV	WORD PTR ES:[BX.IFSR_CB@],DI	; set IFSR_CB@
	MOV	WORD PTR ES:[BX.IFSR_CB@+2],DS
SFT_60:
	TEST	IFSPROC_FLAGS,SetDeviceCB	; check whether to set
	JZ	SFT_1000			; device cb or not
	LDS	SI,[THISSFT]
	CMP	WORD PTR DS:[SI.SF_DEVPTR],NULL_PTR  ; null if seq
	JE	SFT_1000
	TEST	DS:[SI.SF_FLAGS],DEVID_DEVICE	; cds or dfl?				 ;AM007;
	LDS	SI,DS:[SI.SF_DEVPTR]		; get device ptr (cds/dfl)		 ;AM007;
	JNZ	SFT_100 			; jmp if dfl
	MOV	WORD PTR CS:SAVE_CB@,SI 	; CDS
	MOV	WORD PTR CS:SAVE_CB@+2,DS
	TEST	DS:[SI.CURDIR_FLAGS],CURDIR_ISIFS
	JZ	SFT_1000
	CALL	CDS_TO_CD
	JMP	SHORT SFT_1000
SFT_100:
	MOV	WORD PTR CS:[THISDFL],SI	; DFL
	MOV	WORD PTR CS:[THISDFL+2],DS	; set this cause dfl-df
	CALL	DFL_TO_DF			; expects it
SFT_1000:
	RestoreReg <CX,AX,SI,DI>		; restore regs
	SaveReg <CS>
	RestoreReg <DS> 			; set ds -ifsseg
	return
EndProc SFT_TO_SFF
BREAK <SFF_TO_SFT -- Convert SFF to SFT>
;************************************************************************************
; SFF_TO_SFT
; Inputs:
;	[THISSFT] set
; Function:
;	Update SFT with SFF
;	SF_FLAGS     =	SFF_FLAGS
;	SF_MODE      =	SFF_MODE
;	SF_ATTR      =	SFF_ATTR
;	SF_UID	     =	SFF_UID
;	SF_PID	     =	SFF_PID
;	SF_SIZE      =	SFF_SIZE
;	SF_POSITION  =	SFF_POSITION
;	SF_TIME      =	SFF_TIME
;	SF_DATE      =	SFF_DATE
;	SF_NAME      =	SFF_NAME
;	SF_NAME+8    =	SFF_EXT
;	SF_CLUSPOS   =	SFF_FSDA
;	SF_DIRSEC    =	SFF_FSDA + 2
;	SF_DIRSEC+2  =	SFF_FSDA + 4
;	SF_LSTCLUS   =	SFF_FSDA + 6
; Outputs:
;	SFT loaded
; notes: all regs preserved
;************************************************************************************
	procedure SFF_TO_SFT,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <ES,DI,DS,SI,AX,CX>		; save regs
	PUSH	SS
	POP	DS
ASSUME	DS:DOSGROUP
	LES	DI,[THISSFT]			; DS:SI -> SFF
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	MOV	SI,OFFSET SFF1			; ES:DI -> SFT
	INC	SI
	INC	SI
	LODSW					; sff_flags
;;;;;;;;AND	AX,0EFFFH			; (hi bit sft_flags - also mode       )  ;AD015;
	MOV	WORD PTR ES:[DI.SF_FLAGS],AX	; sft_flags
	LODSW
;;;;;;;;AND	AX,0EFFFH								 ;AD015;
	MOV	WORD PTR ES:[DI.SF_MODE],AX	; sft_mode
	LODSW
;;;;;;;;MOV	WORD PTR ES:[DI.SF_IOMODE],AX	; sft_iomode	...no longer exists	 ;AD024;
	LODSW
	MOV	BYTE PTR ES:[DI.SF_ATTR],AL	; sft_attr
;;;;;;;;MOV	BYTE PTR ES:[DI.SF_ATTR_HI],AH	;    no longer exists			 ;AD024;
	LODSW
	MOV	WORD PTR ES:[DI.SF_UID],AX	; sft_uid
	LODSW
	MOV	WORD PTR ES:[DI.SF_PID],AX	; sft_pid
	SaveReg <DI>
	ADD	DI,SF_SIZE
	MOV	CX,4
	REP	MOVSW				; sft_size & position
	RestoreReg <DI>
	LODSW
	MOV	WORD PTR ES:[DI.SF_TIME],AX	; sft_time
	LODSW
	MOV	WORD PTR ES:[DI.SF_DATE],AX	; sft_date
	PUSH	DI				; sft_name/ext/cp
	ADD	DI,SF_NAME
	MOV	CX,11				;   (name - 11, cp - 2 bytes)
	REP	MOVSB
	ADD	SI,SIZE SFF_RESV		; sft_fsda  1st word
	ADD	SI,4				; for sff_sf_id
	POP	DI
	SaveReg <DI>
	ADD	DI,SF_CLUSPOS
	MOV	CX,3
	REP	MOVSW
;;;;;;;;ADD	DI,12									 ;AN017;;AD024;
;;;;;;;;MOVSW										 ;AN017;;AD024;
	LODSW
	RestoreReg <DI> 								 ;AN003;;AM024;
	MOV	WORD PTR ES:[DI.SF_LSTCLUS],AX
	TEST	IFSPROC_FLAGS,SetDeviceCB	; check whether to update
	JZ	SFF_1000			; device cb or not
	TEST	IFSPROC_FLAGS,IsSeq
	JNZ	SFF_1000
	TEST	ES:[DI.SF_FLAGS],DEVID_DEVICE	; cds or dfl?				 ;AM007;
	PUSHF					;  save results of this test for later
	LES	DI,ES:[DI.SF_DEVPTR]		; get device ptr (cds/dfl)
	CMP	DI,NULL_PTR
	JNE	SFF_20
	POPF
	JMP	SFF_1000

SFF_20:
	POPF					; retrieve cd/df test results
	JNZ	SFF_100 			; jmp if dfl
	MOV	DI,WORD PTR CS:SAVE_CB@ 	; CDS
	PUSH	WORD PTR CS:SAVE_CB@+2
	POP	ES
	TEST	ES:[DI.CURDIR_FLAGS],CURDIR_ISIFS
	JZ	SFF_1000
	CALL	CD_TO_CDS
	JMP	SHORT SFF_1000
SFF_100:
	MOV	WORD PTR CS:[THISDFL],DI	; DFL
	MOV	WORD PTR CS:[THISDFL+2],ES	; set this cause DF_TO_DFL
	CALL	DF_TO_DFL			; expects it
SFF_1000:
	RestoreReg <CX,AX,SI,DS,DI,ES>		; restore regs
	return
EndProc SFF_TO_SFT
BREAK <CDS_TO_CD -- Convert CDS to CD>
;************************************************************************************
; CDS_TO_CD
; Inputs:
;	DS:SI -> CDS
; Function:
;	Load CD from CDS
;	  CD_TYPE   = 1
;	  CD_TYPE+1 = 0
;	  CD_END    = CURDIR_END
;	  CD_TEXT   = CURDIR_TEXT
;	  CD_FSDA   = CURDIR_ID
;	  CD_FSDA+2 = CURDIR_ID+2
;	  CD_FSDA+4 = CURDIR_USER_WORD
;	  CD_FSDA+6 = CURDIR_FSDA
; Outputs:
;	CD loaded
;	ES:BX -> IFSRH
;	IFSR_DEVICE_CB@ -> CD
;	[THISIFS] = CURDIR_IFS_HDR
;	DS - IFSSEG
; Regs: all except DS,ES,BX saved
;************************************************************************************
	procedure CDS_TO_CD,NEAR
	SaveReg <DI,SI,AX,CX>			; save regs
	PUSH	CS
	POP	ES				; DS:SI -> CDS
ASSUME	ES:IFSSEG				; ES:DI -> CD
	MOV	DI,OFFSET CS:CD1
	PUSH	DI				; save cd offset
	MOV	AL,CBTYPE_CD			; cd_type
	TEST	CS:IFSPROC_FLAGS,ISDUMMYCDS	;    check for dummy cd
	JZ	CCD_10
	MOV	AL,CBTYPE_DUMMYCD
CCD_10:
	XOR	AH,AH
	STOSW					; move di down thru cd during store
	MOV	AX,WORD PTR [SI.CURDIR_END]	; cd_end
	STOSW
	PUSH	SI				; cd_text
	MOV	CX,DIRSTRLEN
	REP	MOVSB
	POP	SI
	MOV	AX,WORD PTR [SI.CURDIR_ID]	; cd_fsda
	ADD	DI,SIZE CD_RESV
	STOSW
	MOV	AX,WORD PTR [SI.CURDIR_ID+2]
	STOSW
	MOV	AX,WORD PTR [SI.CURDIR_USER_WORD]
	STOSW
	MOV	AX,WORD PTR [SI.CURDIR_FSDA]
	STOSW
	TEST	CS:IFSPROC_FLAGS,THISIFS_SET
	JNZ	CCD_20
	MOV	AX,WORD PTR [SI.CURDIR_IFS_HDR] ; Set [THISIFS]
	MOV	WORD PTR CS:[THISIFS],AX
	MOV	AX,WORD PTR [SI.CURDIR_IFS_HDR+2]
	MOV	WORD PTR CS:[THISIFS+2],AX
CCD_20:
	POP	DI				; restore CD offset
	PUSH	CS				; get DS -> IFSSEG
	POP	DS
ASSUME	DS:IFSSEG
	MOV	BX,OFFSET IFSR			; ES:BX -> IFSRH
	SaveReg <BX>
	ADD	BX,DEVICE_CB@_OFFSET
	MOV	WORD PTR ES:[BX],DI		; set IFSR_DEVICE_CB@
	ADD	BX,2
	MOV	WORD PTR ES:[BX],ES
	RestoreReg <BX>
	RestoreReg <CX,AX,SI,DI>		; restore regs
	return
EndProc CDS_TO_CD
BREAK <CD_TO_CDS -- Convert CD to CDS>
;************************************************************************************
; CD_TO_CDS
; Inputs:
;	ES:DI -> CDS
;	DS    -> IFSSEG
; Function:
;	Update CDS with CD
;	  CURDIR_TEXT	   =	CD_TEXT
;	  CURDIR_ID	   =	CD_FSDA
;	  CURDIR_ID+2	   =	CD_FSDA+2
;	  CURDIR_USER_WORD =	CD_FSDA+4
;	  CURDIR_END	   =	CD_END
;	  CURDIR_FSDA	   =	CD_FSDA+6
; Outputs:
;	CDS updated
; notes: all regs preserved
;************************************************************************************
	procedure CD_TO_CDS,NEAR
ASSUME	DS:IFSSEG,ES:IFSSEG
	SaveReg <ES,DI,DS,SI,AX,CX>		; save regs
	MOV	SI,OFFSET CD1			; ES:DI -> CDS
						; DS:SI -> CD
	INC	SI
	INC	SI
	LODSW					; curdir_end
	MOV	ES:[DI.CURDIR_END],AX
	PUSH	DI
	MOV	CX,DIRSTRLEN
	REP	MOVSB
	POP	DI
	ADD	SI,SIZE CD_RESV 		; curdir_id
	LODSW
	MOV	WORD PTR ES:[DI.CURDIR_ID],AX
	LODSW
	MOV	WORD PTR ES:[DI.CURDIR_ID+2],AX
	LODSW					; curdir_user_word
	MOV	WORD PTR ES:[DI.CURDIR_USER_WORD],AX
	LODSW					; curdir_fsda
	MOV	WORD PTR ES:[DI.CURDIR_FSDA],AX
	RestoreReg <CX,AX,SI,DS,DI,ES>		; restore regs
	return
EndProc CD_TO_CDS
BREAK <DFL_TO_DF -- Convert DFL to DF>
;************************************************************************************
; DFL_TO_DF
; Inputs:
;	[THISDFL]
; Function:
;	Load DF from DFL
;	  DF_TYPE     = 2
;	  DF_TYPE + 1 = 0
;	  DF_DEV_NAME = DFL_DEV_NAME
;	  DF_FSDA     = DFL_FSDA
; Outputs:
;	DF loaded
;	ES:BX -> IFSRH
;	IFSR_DEVICE_CB@ -> DF
;	[THISIFS] = DFL_IFS_HDR
;	DS - IFSSEG
; notes: es,bx,ds Revised, others saved
;************************************************************************************
	procedure DFL_TO_DF,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <DI,SI,AX>			; save regs
	PUSH	CS
	POP	ES
ASSUME	ES:IFSSEG
	MOV	DI,OFFSET DF1			; es:di -> df
	MOV	BX,OFFSET IFSR			; set es:bx - ifsrh
	PUSH	BX				; fill in device cb@
	ADD	BX,CS:DEVICE_CB@_OFFSET
	MOV	WORD PTR ES:[BX],DI
	ADD	BX,2
	MOV	WORD PTR ES:[BX],ES
	POP	BX
	LDS	SI,[THISDFL]			; ds:si -> dfl
	MOV	AL,CBTYPE_DF			; df_type
	XOR	AH,AH
	STOSW
	PUSH	SI				; df_dev_name
	ADD	SI,DFL_DEV_NAME
	MOV	CX,8
	REP	MOVSB
	POP	SI
	PUSH	SI
	ADD	SI,DFL_FSDA			; df_fsda

	TEST	CS:IFSPROC_FLAGS,SetDeviceCB	; if this flag set, i24 already taken
	JNZ	DDF_20				; care of, otherwise take care of it
	SaveReg <DI,SI> 			; df, dfl dev name offsets
	MOV	DI,OFFSET CS:[PHONEY_NAME]	; set phoney name and ifsdrv
	MOV	CX,4
	REP	MOVSW
	MOV	CS:[IFSDRV],-1
	RestoreReg <SI,DI>			; dfl dev name, df offsets

DDF_20:
	MOV	CX,SIZE DFL_FSDA
	REP	MOVSB
	POP	SI
	MOV	AX,WORD PTR DS:[SI.DFLL_IFS_HDR] ; Set [THISIFS]
	MOV	WORD PTR [THISIFS],AX
	MOV	AX,WORD PTR DS:[SI.DFLL_IFS_HDR+2]
	MOV	WORD PTR [THISIFS+2],AX
	PUSH	CS				; set ds - ifsseg
	POP	DS
	RestoreReg <AX,SI,DI>			; restore regs
	return
EndProc DFL_TO_DF
BREAK <DF_TO_DFL -- Convert DF to DFL>
;************************************************************************************
; DF_TO_DFL
; Inputs:
;	[THISDFL] set
; Function:
;	Update DFL with DF
;	  DFL_DEV_NAME = DF_DEV_NAME
;	  DFL_FSDA     = DF_FSDA
; Outputs:
;	DFL updated
; notes: all regs preserved
;************************************************************************************
	procedure DF_TO_DFL,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <ES,DI,DS,SI>			; save regs
	LES	DI,[THISDFL]			; esdi -> dfl
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	MOV	SI,OFFSET DF1			; dssi -> df
	INC	SI				; space si,di to dev_name
	INC	SI
	PUSH	DI
	ADD	DI,DFL_DEV_NAME
	MOV	CX,8
	REP	MOVSB				; update dfl_dev_name for some reason
	POP	DI
	ADD	DI,DFL_FSDA
	MOV	CX,SIZE DFL_FSDA
	REP	MOVSB				; update dfl_fsda
	RestoreReg <SI,DS,DI,ES>		; restore regs
	return
EndProc DF_TO_DFL
BREAK <CONSIST_SFT -- Make SFT caches consistent with state of IFSFUNC>
;************************************************************************************
; CONSIST_SFT
; Inputs:
;	None
; Function:
;	Make sure all device SFTs are consistent with current IFSFUNC state
; Outputs:
;	None
; Regs: DS,ES,SI,DI preserved others destroyed
;************************************************************************************
	procedure CONSIST_SFT,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	CMP	CS:[DFLCount],0 	; if no dfl, forget it
	JE	CS_20
	SaveReg <DS,SI,ES,DI>
	CLI				; This scan of the SFT tables is
					;  a critical section we must protect
					;  with CLI and STI as CritNET must
					;  be disjoint from all other critical
					;  sections
	LDS	SI,[SFTFCB]
ASSUME	DS:NOTHING
	MOV	CX,[SI].sfCount
	LEA	SI,[SI].sfTable
	JCXZ	DONE_LOOK_FCB
	CALL	LOOK_FIX
DONE_LOOK_FCB:
	LDS	SI,[SFT_Addr]		; get pointer to beginning of table
ScanLoop:
	MOV	CX,[SI].SFCount
	PUSH	DS
	PUSH	SI
	LEA	SI,[SI].sfTable
	CALL	LOOK_FIX
	POP	SI
	POP	DS
	LDS	SI,[SI].SFLink		; get next table segment
	CMP	SI,-1			; end of tables?
	JNZ	ScanLoop		; no, try again
	STI
	RestoreReg <DI,ES,SI,DS>
CS_20:
	return
LOOK_FIX:
	CMP	[SI].sf_ref_count,0
	JZ	NEXT_SFT		; Ignore Free ones
	TEST	[SI].sf_flags,devid_device
	JZ	NEXT_SFT		; Only look at device SFTs
	TEST	[SI].sf_flags,sf_isnet
	PUSH	CX			; sft loop count
	PUSH	DS			; sft ptr
	PUSH	SI
	PUSHF				; Save result of above TEST
	ADD	SI,sf_name		; put asciiz form of sf_name in tempbuf
	PUSH	CS			; to call dfl_match with
	POP	ES
	MOV	DI,OFFSET TEMPBUF
	CALL	CONVERT_NAME_ASCIIZ
	PUSH	CS
	POP	DS
	MOV	SI,DI
	CALL	DFL_MATCH		; is this sft attached? cf1-no,cf0-yes
	JC	NOT_R_DEV
	PUSH	CS			; IS ATTACHED - recover test for sf_isnet
	CALL	PIRET
	JNZ	NOT_REDIR		; jmp if marked attached - ok
; [THISDFL] dfl entry
; (TOS+2):(TOS) -> SFT
; (TOS+4) = CX loop count
					; Not marked attached, but should & will be
	LES	DI,[THISDFL]
	POP	SI
	POP	DS			; DS:SI -> SFT
	MOV	AX,WORD PTR [SI.sf_devptr+2]	; save original devptr
	MOV	WORD PTR ES:[DI.DFLL_DEVPTR+2],AX
	MOV	AX,WORD PTR [SI.sf_devptr]
	MOV	WORD PTR ES:[DI.DFLL_DEVPTR],AX
	MOV	WORD PTR [SI.sf_devptr+2],ES
	MOV	WORD PTR [SI.sf_devptr],DI
	MOV	AX,WORD PTR ES:[DI.DFL_FSDA]	 ; put dfl fsda into sft fsda
	MOV	WORD PTR [SI.sf_cluspos],AX
	MOV	AX,WORD PTR ES:[DI.DFL_FSDA+2]
	MOV	WORD PTR [SI.sf_dirsec],AX
	MOV	AX,WORD PTR ES:[DI.DFL_FSDA+4]
	MOV	WORD PTR [SI.sf_dirsec+2],AX
	MOV	AX,WORD PTR ES:[DI.DFL_FSDA+6]
	MOV	WORD PTR [SI.sf_lstclus],AX
	OR	[SI.sf_flags],sf_isnet + sf_net_spool ; Turn on bits
	JMP	SHORT CLEAN_CX
PIRET:
	IRET
NOT_R_DEV:
	PUSH	CS			; NOT ATTACHED - recover test for sf_isnet
	CALL	PIRET
	JNZ	UNDO_BITS		; jmp if marked attached - problem
NOT_REDIR:
	POP	SI
	POP	DS
CLEAN_CX:
	POP	CX
NEXT_SFT:
	ADD	SI,size sf_entry
	LOOP	LOOK_FIX
	return
; [THISDFL] dfl entry
; (TOS+2):(TOS) -> SFT
; (TOS+4) = CX loop count
UNDO_BITS:				; device not attached, but marked so
	POP	SI			; unmark it, restore original devptr
	POP	DS			; DS:SI -> SFT
	AND	[SI.sf_flags],NOT (sf_isnet + sf_net_spool) ; Turn off bits
	MOV	ES,WORD PTR [SI.sf_devptr+2]	    ; set esdi -> dfl
	MOV	DI,WORD PTR [SI.sf_devptr]
	MOV	AX,WORD PTR ES:[DI.DFLL_DEVPTR+2]    ; restore original devptr
	MOV	WORD PTR [SI.sf_devptr+2],AX
	MOV	AX,WORD PTR ES:[DI.DFLL_DEVPTR]
	MOV	WORD PTR [SI.sf_devptr],AX
	JMP	SHORT CLEAN_CX
EndProc CONSIST_SFT
BREAK <CONSIST_DFL -- Reset all DFL in_prog flags>
;************************************************************************************
; CONSIST_DFL
; Inputs:
;	DS:SI -> 1st DFL entry
;	CX = DFLCount
; Function:
;	Set all dfl_inprog flags to zero
; Outputs:
;	dfl_inprog flags all zero
; notes: all regs preserved
;************************************************************************************
	procedure CONSIST_DFL,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <SI,DX,CX>
	MOV	DX,SIZE DFLL_LIST
CD_20:						; reset loop
	AND	BYTE PTR DS:[SI],NOT DFL_INPROG
	ADD	SI,DX
	LOOP	CD_20
	RestoreReg <CX,DX,SI>
	return
EndProc CONSIST_DFL


BREAK <PRN_CHECK -- change PRN to LPT1>

;************************************************************************************
;
; PRN_CHECK
;
; Inputs:
;	DS -> IFSSEG
;	SI -> asciiz canonicalized device name
; Function:
;	IF DSSI-> "PRN",0 THEN
;	   Set SI -> LPT1_NAME
;	ENDIF
; Outputs:
;	SI possibly Revised
;
; notes: all but si preserved
;
;************************************************************************************

	procedure PRN_CHECK,NEAR
ASSUME	DS:IFSSEG,ES:NOTHING

	SaveReg <ES,DI,AX,CS>
	RestoreReg <ES>
	MOV	DI,OFFSET PRN_NAME
	SaveReg <SI>
	CallInstall StrCmp,MultDOS,30
	RestoreReg <SI>
	JNZ	PC_20
	MOV	SI,OFFSET LPT1_NAME
PC_20:
	RestoreReg <AX,DI,ES>
	return

EndProc PRN_CHECK


BREAK <CHECK_REAL_DEVICE -- Match dfl_dev_name to real device>
;************************************************************************************
;
; CHECK_REAL_DEVICE
;
; Inputs:
;	DS:SI -> DFL entry
;
; Function:
;	Match device name to device driver chain names
;	IF match found
;	   set dfl_dev_real
;	IF device name = "prn" THEN
;	   set to "LPT1"
; Outputs:
;	dfl_dev_real set
;	device name changed to "LPT1" if "PRN"
;
; Regs: AX,CX destroyed.  All others preserved.
;
;************************************************************************************
	procedure CHECK_REAL_DEVICE,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <ES,DI,DS,SI,CS>
	RestoreReg <ES>
ASSUME	ES:IFSSEG
	MOV	DI,OFFSET TEMPBUF+10		; esdi-> tempbuf+10
	ADD	SI,DFL_DEV_NAME 		; dssi -> dfl_dev_name
	CALL	CONVERT_NAME_ASCIIZ		; asciiz form of dfl_dev_name
						; at tempbuf+10
						; Use this to match real devnames
	Context DS				; get addressability to dosgroup
						; to access device driver chain
	LDS	SI,NULDEV			; dssi -> real device driver chain
CRD_20: 					; <<< matching loop on dev drvrs >>>
	SaveReg <DS,SI>
	ADD	SI,SDEVNAME			; dssi -> real dev name
	MOV	DI,OFFSET TEMPBUF
	CALL	CONVERT_NAME_ASCIIZ
	SaveReg <ES>
	RestoreReg <DS>
	MOV	SI,DI				; dssi -> tempbuf    (real)
	ADD	DI,10				; esdi -> tempbuf+10 (dfl)
	CallInstall StrCmp,MultDOS,30		; compare (case insensitive)
	RestoreReg <SI,DS>			; device driver chain
	JZ	CRD_40
	LDS	SI,DS:[SI.SDEVNEXT]
	CMP	SI,NULL_PTR
	JNE	CRD_20
;;;;;;;;SaveReg <DS>				; only offset null			 ;AD022;
;	RestoreReg <AX> 								 ;AD022;
;	CMP	AX,NULL_PTR								 ;AD022;
;;;;;;;;JNE	CRD_20									 ;AD022;
	RestoreReg <SI,DS>			; dfl entry
	JMP	SHORT CRD_100			; go check "prn"
CRD_40: 					; match found
	RestoreReg <SI,DS>			; dfl entry
	OR	DS:[SI.DFLL_FLAGS],DFL_DEV_REAL
CRD_100:
	SaveReg <DS,SI> 			; dfl entry
	SaveReg <CS>
	RestoreReg <DS>
ASSUME	DS:IFSSEG
	MOV	SI,OFFSET PRN_NAME		; ds:si -> "prn",0
						; es:di -> tempbuf+10 (dfl)
	CallInstall StrCmp,MultDOS,30		; compare (case insensitive)
	RestoreReg <SI,DS>			; dfl entry
	JNZ	CRD_120
						; prn match
	CALL	XCHGP				; after call: ds ifsseg
						;	      esdi->dfl entry
ASSUME	DS:IFSSEG
	MOV	SI,OFFSET LPT1_NAME
	SaveReg <ES,DI> 			; dfl entry offset
	ADD	DI,DFL_DEV_NAME 		; make dfl_dev_name = "LPT1    "
	MOV	CX,4
	REP	MOVSB
	RestoreReg <SI,DS>			; dfl entry offset
	OR	DS:[SI.DFLL_FLAGS],DFL_DEV_REAL
CRD_120:
	RestoreReg <DI,ES>			; restore es,di
	return
EndProc CHECK_REAL_DEVICE
Break	<XCHGP - exchange source and destination pointers>
;************************************************************************************
; XCHGP
; Inputs:
;	DS:SI & ES:DI
; Function:
;	Swap ds:si with es:di
; Outputs:
;	ds<=>es, si<=>di
; notes: all preserved
;************************************************************************************
Procedure XCHGP,NEAR
	SaveReg <DS,ES>
	RestoreReg  <DS,ES>
	XCHG	SI,DI
	return
EndProc XCHGP
Break	<IFSDrvFromCDS - convert an offset to a CDS into the 0-based drive>
;************************************************************************************
;   IFSDrvFromCDS - convert an offset to a CDS into a 0-based drive number.
;   Sets IFSDrv also.
;   Inputs:	AX contains offset from the beginning of CDSAddr
;   Outputs:	AL contains the 0-based drive number
;		IFSDrv is set
;   Registers Revised: AH, BL
;************************************************************************************
Procedure   IFSDrvFromCDS,NEAR
	ASSUME	DS:NOTHING,ES:NOTHING
	SUB	AX,WORD PTR [CDSADDR]	; AX is offset of THISCDS
	MOV	BL,SIZE CurDir_list	; size in convenient spot
	DIV	BL			; get drive number
	MOV	CS:[IFSDRV],AL
	return
EndProc IFSDrvFromCDS
Break	<SET_THISIFS_UNC - put UNC_FS_HDR into [THISIFS]>
;************************************************************************************
;   SET_THISIFS_UNC
;   Inputs:	DS - IFSSEG, UNC_FS_HDR set
;   Outputs:	[THISIFS] = UNC_FS_HDR
;   Registers Revised: none
;************************************************************************************
Procedure   SET_THISIFS_UNC,NEAR
	MOV	AX,CS:WORD PTR [UNC_FS_HDR]
	MOV	CS:WORD PTR [THISIFS],AX
	MOV	AX,CS:WORD PTR [UNC_FS_HDR+2]
	MOV	CS:WORD PTR [THISIFS+2],AX
	return
EndProc SET_THISIFS_UNC
Break	<SET_CATEGORY - set category for ifs dependent ioctl request>
;************************************************************************************
;
;   SET_CATEGORY
;
;   Inputs:	DS - IFSSEG, ES:BX -> IFSR, THISIFS set
;   Outputs:	CL set to 1 for unc fs, 0 otherwize
;
;   Registers Revised: CX
;
;************************************************************************************
Procedure   SET_CATEGORY,NEAR
	SaveReg <AX>				; preserve used regs
	XOR	CH,CH
	MOV	CL,CATEGORY_FS			; set category: 0 - non-UNC
	TEST	IFSFUNC_FLAGS,UNC_INSTALLED	; check if unc fs installed
	JZ	SC_20				; no unc - go set category to fs
	MOV	AX,WORD PTR [THISIFS]		; now must check if thisifs=unc
	CMP	AX,WORD PTR [UNC_FS_HDR]
	JNE	SC_20
	MOV	AX,WORD PTR [THISIFS+2]
	CMP	AX,WORD PTR [UNC_FS_HDR+2]
	JNE	SC_20
	INC	CL				; is unc - inc category to 1=unc
SC_20:
	RestoreReg <AX>
	return
EndProc SET_CATEGORY
Break	<SET_DEPIOCTL_IFSR - set length,function,apifunc,func ifsr fields>
;************************************************************************************
;   SET_DEPIOCTL_IFSR
;   Inputs:	ES:BX -> IFSR
;   Outputs:	IFSR_LENGTH, IFSR_FUNCTION, IFSR_APIFUNC, IFSR_FUNC set
;   Registers Revised: none
;************************************************************************************
Procedure   SET_DEPIOCTL_IFSR,NEAR
	ifsr_fcn_def	EXECAPI
	ifsr_api_def	DEPIOCTL
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_DEPIOCTL
	MOV	ES:[BX.IFSR_FUNCTION],IFSEXECAPI
	MOV	ES:[BX.IFSR_APIFUNC],IFSDEPIOCTL
	MOV	ES:[BX.IFSR_FUNC],GEN_IOCTL_BY_DEVNUM
	return
EndProc SET_DEPIOCTL_IFSR

Break	<GET_UNC_FS_NAME - put UNC ifs driver name into esdi>
;************************************************************************************
;   GET_UNC_FS_NAME
;   Inputs:
;		ES:DI -> BUFFER
;   Outputs:	Buffer contains asciiz form of ifs driver name
;   Registers Revised: none
;************************************************************************************
Procedure   GET_UNC_FS_NAME,NEAR
	SaveReg <DS,SI,DI>
	LDS	SI,CS:UNC_FS_HDR
	CALL	MOVE_DRIVER_NAME
	RestoreReg <DI,SI,DS>
	return
EndProc GET_UNC_FS_NAME

Break	<MOVE_DRIVER_NAME - put ifs driver name into esdi>
;************************************************************************************
;   MOVE_DRIVER_NAME
;   Inputs:	DS:SI -> IFS DRIVER
;		ES:DI -> BUFFER
;   Outputs:	Buffer contains asciiz form of ifs driver name
;   Registers Revised: SI,DI
;************************************************************************************
Procedure   MOVE_DRIVER_NAME,NEAR
	ADD	SI,IFS_NAME			; space to name in ifs hdr
	MOV	CX,8
MDN_20: 					; move name into buffer
	LODSB					; move till 1st space or 8 chars
	CMP	AL," "                          ; then add 0
	JE	MDN_40
	STOSB
	LOOP	MDN_20
MDN_40:
	XOR	AL,AL
	STOSB
	return
EndProc MOVE_DRIVER_NAME
Break	<CONVERT_NAME_ASCIIZ - put name into buffer in asciiz form>

;************************************************************************************
;
;   CONVERT_NAME_ASCIIZ
;
;   Inputs:	DS:SI -> NAME
;		ES:DI -> BUFFER
;
;   Outputs:	Buffer contains asciiz form of name
;
;   Regs:	All but SI preserved
;
;************************************************************************************

Procedure   CONVERT_NAME_ASCIIZ,NEAR
	SaveReg <DI,AX> 			; esdi buffer offset
	CLD					; store name in asciiz format
	MOV	CX,8				; in esdi buffer
CNA_20:
	LODSB
	CMP	AL," "
	JE	CNA_40
	STOSB
	LOOP	CNA_20
CNA_40:
	XOR	AL,AL
	STOSB
	RestoreReg <AX,DI>			; esdi buffer offset
	return
EndProc CONVERT_NAME_ASCIIZ
Break	<CHECK_SEQ - check for unc vs ifs device>
;************************************************************************************
;
;   CHECK_SEQ
;
;   Inputs:	[THISCDS],[THISDFL]
;		DS - dosgroup
;
;   Function:	Check whether function has device_cb@ associated with it.
;		(Rule out deviceless attach function)
;
;   Outputs:	cf = 0 seq (deviceless)
;		cf = 1 device
;
;   Registers Revised: none
;
;************************************************************************************

Procedure   CHECK_SEQ,NEAR
ASSUME	DS:DOSGROUP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;	SaveReg <SI,AX> 	    ;							 ;AD007;
;	MOV	SI,[WFP_START]	    ;							 ;AD007;
;	LODSW			    ;							 ;AD007;
;	CMP	AX,"\\"             ;                                                    ;AD007;
;	JE	CS_10		    ;							 ;AD007;
;	STC			    ;							 ;AD007;
;	JMP	SHORT CS_20	    ;							 ;AD007;
;S_10:				    ;							 ;AD007;
;	CLC			    ;							 ;AD007;
;				    ;							 ;AD007;
;S_20:				    ;							 ;AD007;
;	RestoreReg <AX,SI>	    ;							 ;AD007;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	SaveReg <DS,SI> 		; save used regs
	LDS	SI,[THISCDS]		; check for cds
	CMP	SI,NULL_PTR
	JNE	CS_10
	LDS	SI,CS:[THISDFL] 	; no cds, check dfl
	CMP	SI,NULL_PTR
	JNE	CS_10
	CLC				; no cds, no dfl  - is deviceless - clear carry
	JMP	SHORT CS_1000
CS_10:
	STC				; has device - set carry
CS_1000:
	RestoreReg <SI,DS>		; restore used regs
	return
EndProc CHECK_SEQ
Break	<INIT_DFL - zero out dfl entry>
;************************************************************************************
;   INIT_DFL
;   Inputs:	DS:SI -> dfl entry
;   Outputs:	dfl entry zeroed out
;   Registers Revised: none
;************************************************************************************
Procedure   INIT_DFL,NEAR
	SaveReg <ES,DI,AX,CX,DS>
	RestoreReg <ES>
	MOV	DI,SI
	MOV	CX,SIZE DFLL_LIST / 2
	XOR	AX,AX
	CLD
	REP	STOSW
	RestoreReg <CX,AX,DI,ES>
	return
EndProc INIT_DFL
BREAK <NET_TRANS -- A Routine which does NAMETRANS on session start strings>
;************************************************************************************
;   NET_TRANS
;   Inputs:
;	ES:DI -> Double string session start string for blockredir
;		 or printerredir.
;   Function:
;	Perform NAMETRANS DOS function on the connect part of the string
;   Outputs:
;		ES:DI points to NAMETRANSed REDIR string
;		password, or extra 0, appended at end of string
;   Registers Revised:
;		ES,DI Revised, others preserved
;************************************************************************************
	procedure NET_TRANS,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <DS,SI,AX,BX>
	SaveReg <ES>				; set ds:si -> string
	RestoreReg <DS> 			; for nametrans input
	MOV	SI,DI

	PUSH	CS
	POP	ES
	MOV	DI,OFFSET NET_TRANS_BUFFER	; name transed string will be placed
						; in temporary buffer
	SaveReg <DI,DS,SI>			; $NAMETRANS zaps these
	CallInstall  $Nametrans,MultDOS,33
	RestoreReg <SI,DS>
	JNC	NT_20
	RestoreReg <DI> 			; nametrans error - set carry & exit
	JMP	SHORT	NT_60

						; dssi -> input target string
NT_20:						; esdi -> nametrans version in nettranbuf
	LODSB					; move password or zero
	OR	AL,AL
	JNZ	NT_20				; skip to password  (or zero)
;;;;;;;;MOV	DI,OFFSET TEMPBUF		; no need for this;			 ;AC001;;AD013;
;	SaveReg <DI>				; nametrans already does it;		 ;AC001;;AD013;
;NT_40: 							  ;			  ;AC001;;AD013;
;	 MOV	 AL,BYTE PTR ES:[DI]				  ;			  ;AC001;;AD013;
;	 INC	 DI						  ;			  ;AC001;;AD013;
;	 OR	 AL,AL						  ;			  ;AC001;;AD013;
;;;;;;;;;JNZ	 NT_40				 ; Skip first part;			  ;AD013;
	CallInstall  StrCpy,MultDOS,17	; Copy password string
	RestoreReg <DI>
	CLC
NT_60:
	RestoreReg <BX,AX,SI,DS>
	return
EndProc NET_TRANS

Break	<STRIP_WFP_START - strip leading d:\ >
;************************************************************************************
;   STRIP_WFP_START
;
;   Called by:	IFS_SEARCH_FIRST
;   Inputs:	DS:SI -> WFP_START
;   Outputs:	none
;   Registers Revised: none
;************************************************************************************
Procedure   STRIP_WFP_START,NEAR
	CMP	BYTE PTR DS:[SI+1],":"
	JNE	SW_1000
	ADD	SI,2
	CMP	BYTE PTR DS:[SI],"\"
	JE	SW_20
	CMP	BYTE PTR DS:[SI],"/"
	JNE	SW_1000
SW_20:
	INC	SI
SW_1000:
	return
EndProc STRIP_WFP_START


Break	<CHECK_IFS_ATTRIBUTE - check if fs supports function in DX>

;************************************************************************************
;
;   CHECK_IFS_ATTRIBUTE
;
;   Called by:	IFS_DEPENDENT_IOCTL
;
;   Inputs:	DX = ifs_attribute equate
;
;   Outputs:	ZF = attribute not supported
;		NZ = attribute supported
;
;   Registers Revised: none
;
;************************************************************************************
Procedure   CHECK_IFS_ATTRIBUTE,NEAR
	SaveReg <ES,DI>

	LES	DI,[THISIFS]		 ; esdi -> ifs header
	TEST	ES:[DI.IFS_ATTRIBUTE],DX ; test attribute

	RestoreReg <DI,ES>
	return
EndProc CHECK_IFS_ATTRIBUTE


Break	<CHECK_IFS_SUPPORT - check if IFS supports request>

;************************************************************************************
;
;   CHECK_IFS_SUPPORT
;
;   Called by:	CALL_IFS
;
;   Inputs:	TBD
;
;   Outputs:	TBD
;
;
;   Registers Revised: TBD
;
;************************************************************************************
Procedure   CHECK_IFS_SUPPORT,NEAR

	return

EndProc CHECK_IFS_SUPPORT

IFSSEG	ENDS
    END
