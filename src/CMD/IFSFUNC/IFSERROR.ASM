	PAGE	,132				; 
TITLE	IFSFUNC ERROR ROUTINES
NAME	IFSERROR
;************************************************************************************
; IFS error Routines
;   INT_2F_5
;   IFS_I24
;   SET_EXTERR_INFO
;   PHONEY_DPB
.xlist
.xcref
INCLUDE IFSSYM.INC
INCLUDE IFSFSYM.INC
INCLUDE DOSSYM.INC
INCLUDE DEVSYM.INC
INCLUDE SYSMSG.INC
msg_utilname <IFSFUNC>
.cref
.list
AsmVars <IBM, Installed, Debug>
; define the base code segment of the network support  first
IFSSEG	SEGMENT BYTE PUBLIC 'IFSSEG'
IFSSEG	ENDS
; include the rest of the segment definitions for normal MSDOS
include dosseg.asm
DATA		SEGMENT WORD PUBLIC 'DATA'
	; DOSGROUP Data
	Extrn	THISDPB:DWORD
	Extrn	EXTERR:WORD
	Extrn	EXTERR_ACTION:BYTE
	Extrn	EXTERR_CLASS:BYTE
	Extrn	EXTERR_LOCUS:BYTE
	Extrn	ALLOWED:BYTE
	Extrn	ExitHold:DWORD
	Extrn	ERR_TABLE_21:BYTE
DATA		ENDS
IFSSEG	SEGMENT BYTE PUBLIC 'IFSSEG'
	ASSUME	SS:DOSGROUP,CS:IFSSEG
	; IFS Data
	Extrn	IFSDRV:BYTE
	Extrn	IFSR:WORD
	Extrn	TEMPBUF:BYTE
	Extrn	IFSPROC_FLAGS:WORD
	Extrn	SYSGetMsg:NEAR
	Extrn	IFSSEM:BYTE
	Extrn	THISIFS:DWORD
; Phoney DPB used by IFS Share/Lock errors
DUMMY_DPB LABEL BYTE
	DB	0   ; dpb_drive
	DB	0   ; dpb_UNIT
	DW	512 ; dpb_sector_size
	DB	0   ; dpb_cluster_mask
	DB	0   ; dpb_cluster_shift
	DW	1   ; dpb_first_FAT
	DB	1   ; dpb_FAT_count
	DW	16  ; dpb_root_entries
	DW	3   ; dpb_first_sector
	DW	3   ; dpb_max_cluster
	DB	1   ; dpb_FAT_size
	DW	2   ; dpb_dir_sector
	DD	?   ; dpb_driver_addr
	DB	0F8H ; dpb_media
	DB	-1  ; dpb_first_access
	DW	-1  ; dpb_next_dpb low
	DW	-1  ; dpb_next_dpb high
	DW	0   ; dpb_next_free
	DW	-1  ; dpb_free_cnt
; Phoney device headers used by IFS INT 24H
PHONEY_BLOCK	LABEL  BYTE
	DD	?			; Pointer
	DW	ISNET			; Block net dev
	DW	?			; Strat entry
	DW	?			; Int entry
	DB	8 DUP (0)
PHONEY_DEVICE	LABEL  BYTE
	DD	?			; Pointer
	DW	DEVTYP + ISNET		; Char net dev
	DW	?			; Strat entry
	DW	?			; Int entry
	PUBLIC	PHONEY_NAME
PHONEY_NAME	DB	"        "
NEXT_2F_5	DD	?
PUBLIC	NEXT_2F_5
MAXERR	EQU	89		; Don't know errors above 79
	PUBLIC	 RODS_LABEL
RODS_LABEL	LABEL	BYTE
.xcref
.xlist
MSG_SERVICES <IFSFUNC.CL1>
.cref
.list

;
; The following table defines CLASS ACTION and LOCUS info for the INT 21H/24H
; errors.  Each entry is 5 bytes long:
;
;	Err#,Class,Action,Locus,Allowed_Val
;

ERR_TABLE_IFS	LABEL	BYTE
  DB errCLASS_BadFmt,  errACT_User,   errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;50
  DB errCLASS_TempSit, errACT_DlyRet, errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;51
  DB errCLASS_Already, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;52
  DB errCLASS_NotFnd,  errACT_User,   errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;53
  DB errCLASS_TempSit, errACT_DlyRet, errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;54
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;55
  DB errCLASS_OutRes,  errACT_DlyRet, errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;56
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;57
  DB errCLASS_BadFmt,  errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;58
  DB errCLASS_SysFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;59
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;60
  DB errCLASS_OutRes,  errACT_DlyRet, errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;61
  DB errCLASS_OutRes,  errACT_DlyRet, errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;62
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;63
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;64
  DB errCLASS_Auth,    errACT_User,   errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;65
  DB errCLASS_BadFmt,  errACT_User,   errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;66
  DB errCLASS_NotFnd,  errACT_User,   errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;67
  DB errCLASS_OutRes,  errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;68
  DB errCLASS_OutRes,  errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;69
  DB errCLASS_TempSit, errACT_DlyRet, errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;70
  DB errCLASS_BadFmt,  errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;71
  DB errCLASS_TempSit, errACT_Retry,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;72
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;73
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;74
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;75
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;76
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;77
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;78
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;79
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;80
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;81
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;82
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;83
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;84
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;85
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;86
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;87
  DB errCLASS_HrdFail, errACT_Abort,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;88
  DB errCLASS_Unk,     errACT_Panic,  errLOC_Disk, Allowed_FAIL+Allowed_RETRY	;??

;
; We need to map old int 24 errors and device driver errors into the new set
; of errors.  The following table is indexed by the new errors
;
ErrMap24    Label   BYTE
    DB	error_write_protect		;   0
    DB	error_bad_unit			;   1
    DB	error_not_ready 		;   2
    DB	error_bad_command		;   3
    DB	error_CRC			;   4
    DB	error_bad_length		;   5
    DB	error_Seek			;   6
    DB	error_not_DOS_disk		;   7
    DB	error_sector_not_found		;   8
    DB	error_out_of_paper		;   9
    DB	error_write_fault		;   A
    DB	error_read_fault		;   B
    DB	error_gen_failure		;   C
    DB	error_gen_failure		;   D	RESERVED
    DB	error_gen_failure		;   E	RESERVED
    DB	error_wrong_disk		;   F

ErrMap24End LABEL   BYTE


BREAK <INT_2F_5 -- Routine for Extended error messages>

;************************************************************************************
;
; INT_2F_5
;
; Called by:	   COMMAND.COM
;
; Routines called: CALL_IFS
;
; Input:  [THISIFS] set
;	  BX = extended error number
;	  AL = component ID  0 - install check
;			     1 - command.com
;			     2 - message retriever
; Function:
; This handler uses 2F multiplex number 5. It allows the INT 24H
; Handler in COMMAND to get message texts for NET extended errors.
;
;   IF AH = 5 THEN
;     DO
;      IF AL < 0F8H  THEN
;	  DO
;	  ³ IF AL .NE. 0 THEN
;	  ³    DO
;	  ³    ³ IF AL >= 50 .AND. AL <= 74 THEN    /* or AL = 88 */
;	  ³    ³    DO
;	  ³    ³    ³ Prep IFSRH below
;	  ³    ³    ³	*  IFSR_LENGTH	    DW	   28	    ; Request length
;	  ³    ³    ³	*  IFSR_FUNCTION    DB	    6	    ; Get Criter Text
;	  ³    ³    ³	*+ IFSR_RETCODE     DB	    ?	    ; AL
;	  ³    ³    ³	   IFSR_RETCLASS    DB	    ?
;	  ³    ³    ³	   IFSR_RESV1	    DB	   17 DUP(0)
;	  ³    ³    ³	*+ IFSR_MSG@	    DD	    ?	    ; Msg buffer address
;	  ³    ³    ³	*+ IFSR_MSG_TYPE    DB	    ?	    ; Msg type
;	  ³    ³    ³	   IFSR_RESV2	    DB	    ?
;	  ³    ³    ³
;	  ³    ³    ³ Call IFS specified in [THISIFS]
;	  ³    ³    ³ IF IFSR_RETCODE = 0 THEN
;	  ³    ³    ³	 DO
;	  ³    ³    ³	   ES:DI = IFSR_MSG@
;	  ³    ³    ³	   AL = IFSR_MSG_TYPE
;	  ³    ³    ³	 ENDDO
;	  ³    ³    ³ ELSE  get ifsfunc standard msg
;	  ³    ³    ³ ENDIF
;	  ³    ³    ³ RET 2
;	  ³    ³    ENDDO
;	  ³    ³ ELSE  RET 2
;	  ³    ³ ENDIF
;	  ³    ENDDO
;	  ³ ELSE DO
;	  ³	   AL = 0FFH  /* install check */
;	  ³	   iret
;	  ³	 ENDDO
;	  ³ ENDIF
;	  ENDDO
;      ELSE  iret
;      ENDIF
;     ENDDO
; ELSE	jump far to [NEXT_2F_5]
; ENDIF
;
; Output:  carry clear - AL = msg type (0 or 1)
;			   If EType is 1 then message is printed in form
;				<message>
;				Abort, Retry Ignore
;			   If EType is 0 then message is printed in form
;				<message> error (read/writ)ing (drive/device) XXX
;				Abort, Retry Ignore
;			   The message is ASCIZ and DOES NOT
;			   include a trailing CR,LF
;			 ES:DI -> message text
;			 carry set   - no message
;
; Notes:   all destroyed
;
;************************************************************************************
	procedure INT_2F_5,FAR
ASSUME	DS:NOTHING,ES:NOTHING,SS:NOTHING
	ifsr_fcn_def  CRITMSG
	CMP	AH,5				; check for IFS error 2F call
	JZ	I2F5_20
	JMP	[NEXT_2F_5]
I2F5_20:					; call ok
	STI					; INTs OK
	CMP	AL,0F8H
	JB	I2F5_40
	IRET					; IRET on reserved functions
I2F5_40:
	OR	AL,AL
	JNZ	I2F5_60
	MOV	AL,0FFH 			; Tell Ellen I'm here
	IRET
I2F5_60:
;;;;;;;;CMP	AL,error_NET_write_fault	 ; check for special error
;;;;;;;;JE	I2F5_80
	CMP	BX,50
	JAE	I2F5_70
	JMP	I2F5_1000			; Carry set
I2F5_70:
	CMP	BX,MAXERR
	JBE	I2F5_80
I2F5_75:
	STC
	JMP	I2F5_1000
I2F5_80:
	CMP	WORD PTR CS:[THISIFS+2],NULL_PTR ;if no ifs driver set, quit w/carry
	JNE	I2F5_85
	CMP	WORD PTR CS:[THISIFS],NULL_PTR
	JZ	I2F5_75
I2F5_85:
	TEST	CS:IFSSEM,MR_ERRMSG_SEM 	; if already in msgret loop, exit fast
	JNZ	I2F5_75
	MOV	CS:IFSPROC_FLAGS,0
	CMP	AL,I2F5_MsgRet
	JNE	I2F5_90
	OR	CS:IFSPROC_FLAGS,IsMsgRet
	OR	CS:IFSSEM,MR_ERRMSG_SEM 	; set msgret error msg semaphore
I2F5_90:
	SaveReg <DS,SI,BX,CS>			; save command.com regs
	RestoreReg <DS> 			; set ds-ifsseg
	MOV	AX,BX				; whole ax now ext error
	SaveReg <AX>				; save ext err #
	invoke	PREP_IFSR			; zero out ifsr, sets es:bx -> ifsr
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_CRITMSG
	MOV	ES:[BX.IFSR_FUNCTION],IFSCRITMSG
	MOV	ES:[BX.IFSR_RETCODE],AX

;***********************************************************************************************
	invoke	CALL_IFS			; call ifs with chance to set errmsg
;***********************************************************************************************

	JNC	I2F5_200
	POP	AX				; fs error set - get ifsfunc msg
	TEST	CS:IFSPROC_FLAGS,IsMsgRet	;   if msg ret don't call msg ret for
	JZ	I2F5_95 			;   default msg - just fail
	STC
	JMP	SHORT I2F5_220
I2F5_95:
	MOV	DH,1
	CALL	SYSGETMSG			; puts msg in dssi,cx=msg size
	MOV	AH,1				; set al = msg type 0 or 1
	CMP	AL,55				; all but 55,64,65,88 are 1
	JL	I2F5_120
	JE	I2F5_100
	CMP	AL,64
	JL	I2F5_120
	JE	I2F5_100
	CMP	AL,65
	JE	I2F5_100
	CMP	AL,88
	JNE	I2F5_120
I2F5_100:
	DEC	AH
I2F5_120:
	MOV	AL,AH
	SaveReg <CS>				; msg ret has 0D0A24 at end of msg
	RestoreReg <ES> 			; must change this to asciiz
	MOV	DI,OFFSET CS:TEMPBUF+80 	; move to temp buff and put 0 at 0DH	 ;AN003;;AC008;(80)
	SaveReg <DI,AX> 			; preserve msg offset and msg type
	REP	MOVSB				; move msg to temp buff
	XOR	AL,AL
	STOSB					; store zero at end
I2F5_160:
	RestoreReg <AX,DI>			; msg type/ msg offset
	JMP	SHORT I2F5_220
I2F5_200:					; fs supplies error msg
	MOV	AL,ES:[BX.IFSR_MSG_TYPE]	; grab ifs msg info
	MOV	DI,WORD PTR ES:[BX.IFSR_MSG@]
	MOV	ES,WORD PTR ES:[BX.IFSR_MSG@+2]
	ADD	SP,2				; restore stack
I2F5_220:
	PUSHF					; save carry
	TEST	CS:IFSPROC_FLAGS,IsMsgRet	; if msgret reset semaphore
	JZ	I2F5_240
	AND	CS:IFSSEM,NOT MR_ERRMSG_SEM
I2F5_240:
	POPF					; restore carry
	RestoreReg <BX,SI,DS>			; retrieve command.com regs
I2F5_1000:
	RET	2				; Fakey IRET
EndProc INT_2F_5
ASSUME	SS:DOSGROUP
BREAK <SET_EXTERR_INFO -- Set IBMDOS error info>
;************************************************************************************
; SET_EXTERR_INFO
; Inputs:
;	AL is extended error
;	IFSR
; Function:
;	Set all the EXTERR stuff and ALLOWED
; Outputs:
;	following set:
;	EXTERR		word
;	EXTERR_ACTION	byte
;	EXTERR_CLASS	 "
;	EXTERR_LOCUS	 "
;	ALLOWED 	 "
; Regs: all preserved
;************************************************************************************
	procedure SET_EXTERR_INFO,NEAR
    ASSUME  DS:IFSSEG,ES:NOTHING
	ifsr_fcn_def  EXECAPI
	PUSHF
	SaveReg <AX,CX,SI,DS>
	XOR	AH,AH				; set unknown ah=0
	MOV	SS:[EXTERR],AX			; Set extended error
	MOV	SI,OFFSET ERR_TABLE_IFS
	SaveReg <CS>
	RestoreReg <DS> 			; ds-ifsseg to access err_table_ifs
	CMP	AL,50				; if err not in range, set to ??
	JL	SEI_10
	CMP	AL,88
	JLE	SEI_20
SEI_10:
	MOV	AL,89
SEI_20:
	SUB	AL,50				; space to correct table entry
	MOV	CL,4
	MUL	CL
	ADD	SI,AX

SEI_40:
	LODSW					; AL is CLASS, AH is ACTION
	MOV	[EXTERR_ACTION],AH		; Set ACTION
	MOV	[EXTERR_CLASS],AL		; Set CLASS
	LODSW					; al- LOCUS ah- ALLOWED
	TEST	IFSPROC_FLAGS,ISCDS
	JNZ	SEI_50
	ADD	AL,2
SEI_50:
	MOV	[EXTERR_LOCUS],AL
	MOV	[ALLOWED],AH
	MOV	SI,BX				; Set ds:si -> ifsr so can use
	SaveReg <ES>				; lodsw to get cl,act,loc,allowed
	RestoreReg <DS>
	ADD	SI,IFSR_ERROR_CLASS
						; only set if ifs set (not -1)
	LODSW					; AH = action,	AL = class
	CMP	AL,ERROR_INFO_NOT_SET
	JE	SEI_60
	MOV	[EXTERR_CLASS],AL		; set class
SEI_60:
	CMP	AH,ERROR_INFO_NOT_SET
	JE	SEI_80
	MOV	[EXTERR_ACTION],AH		; set action
SEI_80:
	LODSW					; AH = allowed, AL = locus
	CMP	AL,ERROR_INFO_NOT_SET
	JE	SEI_100
	MOV	[EXTERR_LOCUS],AL		; Set locus
SEI_100:
	CMP	AH,ERROR_INFO_NOT_SET
	JE	SEI_1000
	MOV	[ALLOWED],AH

SEI_1000:
	RestoreReg <DS,SI,CX,AX>
	POPF
	return

EndProc SET_EXTERR_INFO


BREAK <DEVICE2EXTERR   -- Convert device error to extended error >

;************************************************************************************
;
; DEVICE2EXTERR
;
; Inputs:
;	AX is device error
;
; Function:
;	Convert device error to extended error
;	This is essentially the same routine as in IBMDOS
;
; Outputs:
;	AX = extended error
;
; Regs: all preserved
;
;************************************************************************************

	procedure DEVICE2EXTERR,NEAR
	SaveReg <DI>
	MOV	DI,AX
	MOV	AX,OFFSET ErrMap24End
	SUB	AX,OFFSET ErrMap24		; AX is the index of the first
						; unavailable error.
						; Do not translate if >= AX.
	CMP	DI,AX
	MOV	AX,DI
	JAE	D2E_20
	MOV	AL,ErrMap24[DI]
	XOR	AH,AH
D2E_20:
	RestoreReg <DI>
	return
EndProc DEVICE2EXTERR

BREAK <IFS_I24 -- Do an INT 24 error>
;************************************************************************************
; IFS_I24
; Called by: CALL_IFS
; Routines called:  DOS: NET_I24_ENTRY
; Inputs:
;	[IFSDRV] set (-1 = device, PHONEY_NAME set)
;	[EXTERR...] Set
;	[ALLOWED] Set
;	IFSR
; Function:
;	DI = Mapped I 24 error code (0-12)
;	AH is bit info (if block)
;	Perform I 24 error to get user response
; Outputs:
;	AL = 0
;	    Ignore
;	AL = 1
;	    Retry
;	AL = 3
;	    Fail
; Regs: DI, AX Revised
;************************************************************************************
	procedure IFS_I24,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	XOR	AH,AH				; AL - extended error (retcode) 	 ;AD007;
	MOV	DI,AX				; set DI = i24 error code C-general fail
	MOV	WORD PTR [EXITHOLD+2],ES	; save es:bp here since fetchi
	MOV	WORD PTR [EXITHOLD],BP		; restores in NET_I24_ENTRY
	PUSH	CS
	POP	BP				; BP=seg part of BP:SI dev ptr
	MOV	AL,[IFSDRV]			; set dev hdr offset
	CMP	AL,-1
	JZ	I24_20
	MOV	SI,OFFSET PHONEY_BLOCK		;     block device
	JMP	SHORT I24_40
I24_20:
	MOV	SI,OFFSET PHONEY_DEVICE 	;     char device
	MOV	AH,87H				;     char dev, write, data area
I24_40:
	OR	AH,ES:[BX.IFSR_ALLOWED] 	; bit 7 = 0-disk or 1(other),...
	CallInstall NET_I24_ENTRY,MultDOS,6,<AX>,<SI>
	return
EndProc IFS_I24
BREAK <PHONEY_DPB -- Set up a phoney DPB for sharing NET INT 24 errors>
;************************************************************************************
; PHONEY_DPB
; Input:
;	[IFSDRV] Set
; Function:
;	Build a phoney DPB for IFS Share/Lock errors
; Outputs:
;	[THISDPB] Set
; Regs: ALL preserved
;************************************************************************************
	procedure PHONEY_DPB,NEAR
ASSUME	DS:DOSGROUP,ES:NOTHING
	PUSH	AX
	MOV	WORD PTR [THISDPB],OFFSET DUMMY_DPB
	MOV	WORD PTR [THISDPB+2],CS
	MOV	AL,[IFSDRV]
	MOV	BYTE PTR [DUMMY_DPB + dpb_drive],AL
	MOV	WORD PTR [DUMMY_DPB + dpb_driver_addr],OFFSET PHONEY_BLOCK
	MOV	WORD PTR [DUMMY_DPB + dpb_driver_addr + 2],CS
	POP	AX
	return
EndProc PHONEY_DPB

include msgdcl.inc
IFSSEG	ENDS
    END
