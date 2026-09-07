	 PAGE	 ,132				; 
TITLE	IFSFUNC DEVICE ROUTINES - Device/IOCTL routines
NAME	IFSDEV
;******************************************************************************
;
; Device related IFS calls
;
;   Printer_GetSet_String
;   IFS_Device_Check
;   IFS_Device_Close
;   IFS_Device_Oper
;   IFS_Spool_Echo_Check
;   IFS_DEPENDENT_IOCTL
;   DEVICE_IOCTL
;   GET_DFL_FROM_INDEX
;
; Programming notes:
;   Old redirector segmentation and DOS interface preserved.
;   Routine prologues are accurate for input/output.
;   However, the pseudocode was not kept up to date.
;   Use it for a rough idea of the routine function.
;
.xlist
.xcref
INCLUDE IFSSYM.INC
INCLUDE IFSFSYM.INC
INCLUDE DOSSYM.INC
INCLUDE DEVSYM.INC
.cref
.list
AsmVars <IBM,KANJI,DEBUG>
; define the base code segment of the network support first
IFSSEG	SEGMENT BYTE PUBLIC 'IFSSEG'
IFSSEG	ENDS
; include THE REST Of the segment definitions for normal MSDOS
.xlist
include dosseg.asm
.list
DATA		SEGMENT WORD PUBLIC 'DATA'
	; DOSGROUP Data
	Extrn	THISCDS:DWORD
	Extrn	THISSFT:DWORD
	Extrn	CDSAddr:DWORD
	Extrn	CDSCount:BYTE
	Extrn	CurrentPDB:WORD
DATA		ENDS
IFSSEG	SEGMENT BYTE PUBLIC 'IFSSEG'
	ASSUME	SS:DOSGROUP,CS:IFSSEG
	; IFS data
;;;aliasExtrn	NLAddr:DWORD
	Extrn	TEMPBUF:BYTE
	Extrn	UNC_FS_HDR:DWORD
	Extrn	THISIFS:DWORD
	Extrn	THISDFL:DWORD
	Extrn	DFLCount:BYTE
	Extrn	DFLAddr:DWORD
	Extrn	IFSDRV:BYTE
	Extrn	fAssign:BYTE
	Extrn	CDSAlt:DWORD
	Extrn	TRUNCATE_FLAG:BYTE
	Extrn	IFSPROC_FLAGS:WORD
	Extrn	IFSFUNC_FLAGS:WORD
	Extrn	IFSR:WORD
	Extrn	LPT1_NAME:BYTE
	Extrn	DEVICE_CB@_OFFSET:WORD
BREAK <PRINTER_GETSET_STRING Get/Set a Pre-pend string>
;******************************************************************************
; PRINTER_GETSET_STRING Get or Set the printer string and flag word
; Called by:  Dispatcher
; Routines called: CALL_IFS		DOS: Get_User_Stack
;		   GET_DFL_FROM_INDEX
;		   DF_TO_DFL
; Inputs:
;	AL has function type (2-printer-set 3-printer-get
;			     4-printer-set-flags 5-printer-get-flags
;		VALUE ALREADY RANGE CHECKED BY CALLER
;	DS:SI is user string pointer (call 2)
;	ES:DI is user buffer (call 3)
;	BX is assign index (calls 2,3,4,5)
;	CX is length DS:SI (call 2)
;	DX is flag word (call 4)
; Function:
;	Prep IFSRH:
;	*  IFSR_LENGTH	    DW	   48	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DW	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   16 DUP(0)
;	*  IFSR_APIFUNC     DB	   16	    ; REDIR IOCTL (Printer Getset String)
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	   IFSR_ALLOWED     DB	    ?
;	   IFSR_I24_RETRY   DB	    ?
;	   IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	*  IFSR_DEVICE_CB@  DD	    ?	    ; DFL entry found by IFSFUNC
;					    ; Step through CDS & DFL lists counting
;					    ; (0,1,2,...) ones with IFS bit set.
;					    ; Stop at BXth one.  Pass that in
;					    ; IFSR_DEVICE_CB@.
;	   IFSR_OPEN_CB@    DD	    ?
;	*  IFSR_FUNC	    DB	    0	    ; subfunction:
;					    ;	00 Generic IOCTL by device number
;	   IFSR_RESV3	    DB	    0
;	*  IFSR_BUFFER@     DD	    ?	    ; user buffer (see below)
;	*  IFSR_BUFSIZE     DW	    ?	    ; length
;	*  IFSR_CATEGORY    DB	    1	    ; category 1 for REDIR
;	*  IFSR_CTLFUNC     DB	    ?	    ; For AL=2,3 00F00001H F=0 GET,F=1 SET
;					    ;			   printer string
;					    ; For AL=4,5 00F00010H F=0 GET,F=1 SET
;					    ;			   printer flag
;	   BUFFER	   LABEL   WORD     ; AL=2,3
;	   DATA 	   DB	   ...
;	   BUFFER	   LABEL   WORD     ; AL=4,5
;			   DW	   FLAGS    ; Printer mode flags
;					    ;  8000H=binary (vs.ascii)
;	CALL routine, CALL_IFS, with pointer to UNC capable IFS header
;	IF IFSR_RETCODE = 0 THEN
;	   DO
;	     IF AL=5 THEN DX = Flags
;	     Call DF_TO_DFL
;	   ENDDO
;	ELSE
;	   Set carry
;	   Put error code in AX
;	ENDIF
;   Outputs:
;		If AL = 3 then CX bytes have been put at input ES:DI
;		If AL = 5 then DX is the flag word
;   Regs: nothing preserved
;   Notes:  This request is a REDIR.SYS dependent ioctl request
;******************************************************************************
	procedure PRINTER_GETSET_STRING,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	TEST	CS:IFSFUNC_FLAGS,UNC_INSTALLED		; unc (redir.sys) must be
	JNZ	PGS_05					; installed, else do nothing
	MOV	AX,error_invalid_function
	transfer ifs_980
PGS_05:
	ifsr_fcn_def	EXECAPI
	ifsr_api_def	DEPIOCTL
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@	; make sure this positioned
							; right
	SaveReg <ES,AX> 				; preserve input es since
							; next call destroys it
							; preserve ax too
	CALL	GET_DFL_FROM_INDEX			; sets [THISDFL],
							; ifsr_device_cb@ &
							; [THISIFS]
	JNC	PGS_10					; error on carry - no dfl
	ADD	SP,4					;   restore stack and
	transfer IFS_980				;   go return in ifsutil
PGS_10:
	RestoreReg <AX> 				; restore input al
	invoke	SET_DEPIOCTL_IFSR			; prep IFSRH
	MOV	ES:[BX.IFSR_CATEGORY],CATEGORY_REDIR
	CMP	AL,PRINTER_SET_STRING
	JNE	PGS_20
							; printer set string
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@],SI	;
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@+2],DS	;
	MOV	ES:[BX.IFSR_BUFSIZE],CX 		;
	MOV	ES:[BX.IFSR_CTLFUNC],CTLFUNC_PRINTER_SET_STRING
	ADD	SP,2					; restore stack (es) &
	JMP	SHORT PGS_100				; go call redir.sys
PGS_20:
	CMP	AL,PRINTER_GET_STRING			; printer get string
	JNE	PGS_40
	POP	CX					; retrieve es in cx
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@],DI	;
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@+2],CX
	MOV	ES:[BX.IFSR_CTLFUNC],CTLFUNC_PRINTER_GET_STRING
	JMP	SHORT PGS_100
PGS_40: 						; flags
	ADD	SP,2					; 1st clean stack of es
	PUSH	CS					;   not needed here
	POP	DS					; must set up buffer
ASSUME	DS:IFSSEG					; to hold flag word
	MOV	SI,OFFSET TEMPBUF
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@],SI
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@+2],DS
	CMP	AL,PRINTER_SET_FLAGS
	JNE	PGS_60
	MOV	DS:[SI],DX				; printer set flags
	MOV	ES:[BX.IFSR_CTLFUNC],CTLFUNC_PRINTER_SET_FLAGS
	JMP	PGS_100
PGS_60: 						; printer get flags
	MOV	ES:[BX.IFSR_CTLFUNC],CTLFUNC_PRINTER_GET_FLAGS
PGS_100:
	PUSH	AX					; save function
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	invoke	SET_THISIFS_UNC 			; set thisifs to unc
	invoke	CALL_IFS				; call ifs driver w/request
	JNC	PGS_120
	ADD	SP,2					; clean stack of ax (fcn #)
	transfer ifs_980				;  go ret on error
PGS_120:
	POP	AX					; restore original input fcn	 ;AN000;;AM013;
	invoke	DF_TO_DFL				; Update dfl entry
	CMP	AL,PRINTER_GET_FLAGS			; if printer get flags
	JE	PGS_140 				;    put flags in DX
	CMP	AL,PRINTER_GET_STRING			; if printer get string
	JE	PGS_160 				;    put stg size in CX
	transfer ifs_990
PGS_140:
	LES	DI,ES:[BX.IFSR_BUFFER@]
	MOV	DX,WORD PTR ES:[DI]
	CallInstall Get_User_Stack,multDOS,24
	MOV	[SI].User_DX,DX 			; return user flags to dos
	transfer ifs_990				; go return with no carry
PGS_160:
	MOV	CX,ES:[BX.IFSR_BUFSIZE]
	CallInstall Get_User_Stack,multDOS,24
	MOV	[SI].User_CX,CX 	; Size of pre string just transferred
	transfer ifs_990				; go return with no carry
EndProc PRINTER_GETSET_STRING
BREAK <IFS_DEVICE_CHECK  See if given path is device>
;******************************************************************************
; IFS_DEVICE_CHECK
; Called by:  Dispatcher
; Routines called: DFL_MATCH		DOS: PathChrCmp
;		   DFL_TO_DF		     StrCpy
;		   CALL_IFS
; Inputs:
;	DS:SI -> name
;	ES:DI -> buffer
; Function:
;	Search DFL for match on name.
;	IF match found THEN
;	   DO  /* match found */
;	     IF DFL_TYPE = 3 (net device) THEN
;		ES:DI -> parms
;	     Clear carry
;	   ENDDO
;	ELSE   /* no match found */
;	   Set carry
;	ENDIF
; Outputs:
;	no match:  carry set
;	match:	   carry clear,  es:di -> parms if unc
;   Regs: nothing preserved
; Programming notes:  Most of this code lifted right out of the Redirector.
;******************************************************************************
	procedure IFS_DEVICE_CHECK,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	ifsr_fcn_def	ATTSTAT
	LocalVar    Src,DWORD				; ** netprn parse code begins
	LocalVar    Dst,DWORD
	LocalVar    DotPos,WORD
	Enter
; Preserve all of the input quantities
	MOV	SrcL,SI
	MOV	SrcH,DS
	MOV	DstL,DI
	MOV	DstH,ES
	MOV	DotPos,-1
; Check for a UNC string. If UNC, is not spooled.
	MOV	AX,[SI]
	CallInstall PathChrCmp,multDOS,4,<AX>,<AX>
	JNZ	NOT_UNC
	XCHG	AH,AL
	CallInstall PathChrCmp,multDOS,4,<AX>,<AX>
	JZ	NOTSpool
NOT_UNC:
; Scan string remembering previous path separator char.
	MOV	DI,SI			; remember first character
PathSkip:
	LODSB
	OR	AL,AL
	JZ	FoundEnd
IF Kanji
 kanji load of next char too
ENDIF
	CallInstall PathChrCmp,multDOS,4,<AX>,<AX>
	JZ	SaveSI
	CMP	AL,':'
	JNZ	TestDot
SaveSI:
	MOV	DI,SI
	JMP	PathSkip
TestDot:
	CMP	AL,'.'
	JNZ	PathSkip
	MOV	DotPos,SI
	JMP	PathSkip
; Better check for trailing :.	They are ILLEGAL (read this comment, IBM) in
;  file names.
FoundEnd:
	CMP	BYTE PTR [SI-2],':'
	JNZ	NOCOL
NotSpool:
	SaveReg <AX,CS>
	RestoreReg <DS>
	MOV	AX,NULL_PTR
	MOV	WORD PTR [THISDFL],AX
	MOV	WORD PTR [THISDFL+2],AX
	RestoreReg <AX>
	LDS	SI,Src
	STC
Done:
	LES	DI,Dst
	Leave
	return
NotSpoolLv:
	LeaveCrit   critNet
	JMP	NotSpool
NOCOL:
	XCHG	SI,DI
; DS:SI points to remainder of string.	DS:DI points to 1 past NUL.  AL = 0
	CMP	DotPos,-1
	JZ	GetP
	MOV	DI,DotPos
	XCHG	AL,[DI-1]
; DI points to 1 past either former . (now NUL) or terminating NUL.  AL has
; former character (. or NUL)
						; ** end of netprn code
GETP:						; ds:si -> parsed string
	invoke	DFL_MATCH
	MOV	ES,SrcH
	MOV	ES:[DI-1],AL			; replace original character
	JNC	IDC_100 			; not in dfl; set bl=ff
	JMP	NotSpool
IDC_100:					; match found
	LES	DI,[THISDFL]
	CMP	ES:[DI.DFL_TYPE],TYPE_NET_DEVICE
	JE	IDC_120
	LES	DI,Dst
	JMP	IDC_220
IDC_120:					; ifs: get parms
	invoke	PREP_IFSR			; clear ifsr
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	invoke	DFL_TO_DF			; DFL: sets [THISIFS]
						;	    ES:BX -> IFSRH
						;	    IFSR_DEVICE_CB@
						;	    ds - IFSSEG
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_ATTSTAT
	MOV	ES:[BX.IFSR_FUNCTION],IFSATTSTAT
	invoke	SET_CATEGORY			; this has nothing to do w/catrgory
						; want to determine if unc or not
	OR     CL,CL				; unc cl=1, other cl=0
	JNE	IDC_140
	MOV	ES:[BX.IFSR_TYPE],TYPE_DEVICE
	JMP	SHORT IDC_160
IDC_140:
	MOV	ES:[BX.IFSR_TYPE],TYPE_NET_DEVICE
IDC_160:
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	MOV	SI,OFFSET TEMPBUF
	MOV	WORD PTR ES:[BX.IFSR_PARMS@],SI
	MOV	WORD PTR ES:[BX.IFSR_PARMS@+2],DS
	invoke	CALL_IFS
	JNC	IDC_200
	JMP	NotSpool
IDC_200:
	MOV	SI,ES:WORD PTR [BX.IFSR_PARMS@]
	MOV	DS,ES:WORD PTR [BX.IFSR_PARMS@+2]
	MOV	BL,ES:[BX.IFSR_TYPE]
	XOR	BH,BH
	INC	SI				; ds:si -> parms returned by redir
	INC	SI
	LES	DI,Dst
	CallInstall StrCpy,multDOS,17
	DEC	DI				; now append device name to net path
	MOV	AL,'\'                          ;     |
	STOSB					;     |
	LDS	SI,CS:[THISDFL] 		;     |
	ADD	SI,2				;     |
	invoke	CONVERT_NAME_ASCIIZ		;     | mov name string over

IDC_220:
	LDS	SI,Dst
	CLC
	JMP	DONE
EndProc IFS_DEVICE_CHECK
BREAK <IFS_DEVICE_CLOSE  Do a close on a device session directly>
;******************************************************************************
; IFS_DEVICE_CLOSE
; Called by:  IFSFUNC Dispatcher
; Routines called:
;		     SFT_TO_SFF
;		     SFF_TO_SFT
;		     CALL_IFS
; Inputs:  ES:DI -> SFT
; Function:
;	Send request below to IFS specified if SFT.
;	Prep IFSRH:
;	*  IFSR_LENGTH	    DW	   48	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DW	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   16 DUP(0)
;	*  IFSR_APIFUNC     DB	   16	    ; IFS dependent IOCTL
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	   IFSR_ALLOWED     DB	    ?
;	   IFSR_I24_RETRY   DB	    ?
;	   IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	*  IFSR_DEVICE_CB@  DD	    ?	    ; DF
;	*  IFSR_OPEN_CB@    DD	    ?	    ; SF
;	*  IFSR_FUNC	    DB	    0	    ; generic IOCTL by handle
;	   IFSR_RESV3	    DB	    0
;	   IFSR_BUFFER@     DD	    ?
;	   IFSR_BUFSIZE     DW	    ?
;	   IFSR_CATEGORY    DB	    1 for UNC, 0 for all other FSs
;	   IFSR_CTLFUNC     DB	    00000101B ; device spool close
; Outputs:
;	Carry set   - error code in AX
; Regs: nothing preserved
;******************************************************************************
	procedure IFS_DEVICE_CLOSE,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	ifsr_fcn_def	EXECAPI
	ifsr_api_def	DEPIOCTL
	SaveReg <DS,SI,ES,DI>			; preserve these for dos - guesing
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	MOV	CS:IFSPROC_FLAGS,SETDEVICECB	; init processing flags
	Context DS
	MOV	WORD PTR [THISSFT],DI
	MOV	WORD PTR [THISSFT+2],ES

	invoke	PREP_IFSR			;  &  ifsr				 ;AM011;
	invoke	SFT_TO_SFF			; sets [THISIFS]
						;      ES:BX -> IFSRH
						;      IFSR_OPEN_CB@
						;      IFSR_DEVICE_CB@
						;      ds - IFSSEG
	invoke	SET_DEPIOCTL_IFSR		; prep IFSRH
;;;;;;;;INC	ES:[BX.IFSR_FUNC]		; inc func from gen_ioctl_by_devnum	 ;AD011;
;;;;;;;;					; to gen_ioctl_by_handle		 ;AD011;
	invoke	SET_CATEGORY
	MOV	ES:[BX.IFSR_CATEGORY],CL
	MOV	ES:[BX.IFSR_CTLFUNC],CTLFUNC_DEVCLOSE
	invoke	CALL_IFS			; call ifs w/device close request
	JNC	IDCL_60
	JMP	IDCL_1000			; go ret w/carry already set
IDCL_60:
	invoke	SFF_TO_SFT
;;;;;;;;transfer ifs_990								 ;AD011;
IDCL_1000:
	RestoreReg <DI,ES,SI,DS>
	XOR	CX,CX				; set zero flag
	return
EndProc IFS_DEVICE_CLOSE
BREAK <IFS_DEVICE_OPER	 Do various device control functions>
;******************************************************************************
; IFS_DEVICE_OPER
; Called by:  IFSFUNC Dispatcher
; Routines called:   PREP_IFSR
;		     CALL_IFS
;		     DFL_TO_DF
; Inputs:  AL = 7  Get truncate flag
;	   AL = 8  Set truncate flag
;		   DL = value
;	   AL = 9  Close all spool files
; Function:
;	IF AL=7 THEN DL = [TRUNCATE_FLAG]
;	ELSE DO
;	       Get addr of 1st DFL entry.
;	       FOR I = 1 to last DFL entry in use
;		    Send request below to IFS specified if DFL.
;	     ENDDO
;	Prep IFSRH:
;	*  IFSR_LENGTH	    DW	   48	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DW	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   16 DUP(0)
;	*  IFSR_APIFUNC     DB	   16	    ; IFS dependent IOCTL
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	   IFSR_ALLOWED     DB	    ?
;	   IFSR_I24_RETRY   DB	    ?
;	   IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	*  IFSR_DEVICE_CB@  DD	    ?	    ; DF
;	   IFSR_OPEN_CB@    DD	    ?
;	*  IFSR_FUNC	    DB	    0	    ;	00 Generic IOCTL by device number
;	   IFSR_RESV3	    DB	    0
;	*  IFSR_BUFFER@     DD	    ?
;	*  IFSR_BUFSIZE     DW	    1
;	   IFSR_CATEGORY    DB	    1 for UNC, 0 for other FSs
;	   IFSR_CTLFUNC     DB	    00000110 ; device_oper
;	   BUFFER	   LABEL   BYTE
;			   DB	   function   ; 8 set truncate flag
;					      ; 9 close all spool files
;			   DB	   truncate flag on set
; Outputs:
;	Carry clear - DL = truncate flag on get
;	Carry set   - AX = error code
; Regs: nothing preserved
; Notes: DFL not updated
;******************************************************************************
	procedure IFS_DEVICE_OPER,NEAR
	CMP	AL,GET_TRUNCATE_FLAG
	JNE	IDO_20
	MOV	DL,[TRUNCATE_FLAG]		; Get truncate flag
	XOR	DH,DH
	CallInstall Get_User_Stack,multDOS,24
	MOV	[SI].User_DX,DX
	transfer ifs_990			;  go ret no carry
IDO_20: 					; Set truncate flag or close all
	ifsr_fcn_def	EXECAPI 		; spool files
	ifsr_api_def	DEPIOCTL
	PUSH	CS				; get addressability to IFSSEG
	POP	DS
ASSUME	DS:IFSSEG,ES:NOTHING
	MOV	DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	CMP	AL,SET_TRUNCATE_FLAG		; Set local storage of truncate_flag
	JNE	IDO_30
	MOV	[TRUNCATE_FLAG],DL
	MOV	AH,DL				; for safekeeping
IDO_30:
	MOV	CL,[DFLCount]			; Prep loop through DFL list
	OR	CL,CL				;   check for no dfl
	JNZ	IDO_35
	transfer ifs_990			;   no dfl - just go successfully
IDO_35:
	XOR	CH,CH
	MOV	DX,SIZE DFLL_LIST
	LDS	SI,[DFLAddr]
IDO_40: 					; ** Loop here thru DFL list entries
;;;aliasCMP	DS:[SI.DFLL_TYPE],TYPE_ALIAS
;;;aliasJE	IDO_100 			; skip alias dfl entries
;;;alias
	TEST	DS:[SI.DFLL_FLAGS],DFL_INUSE	; skip unused dfl entries
	JZ	IDO_100
	MOV	WORD PTR [THISDFL],SI		; Prep IFSRH
	MOV	WORD PTR [THISDFL+2],DS
	invoke	PREP_IFSR
	invoke	DFL_TO_DF			; DFL: sets [THISIFS]
						;	    ES:BX -> IFSRH
						;	    IFSR_DEVICE_CB@
						;	    ds - IFSSEG
	invoke	SET_DEPIOCTL_IFSR		; prep IFSRH
	MOV	SI,OFFSET TEMPBUF		; prep devoper buffer
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@],SI
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@+2],DS
	MOV	BYTE PTR DS:[SI],AL		; buffer contains: db fcn
	MOV	ES:[BX.IFSR_BUFSIZE],1
	CMP	AL,CLOSE_SPOOL_FILES		;		   db truncate flag
	JE	IDO_60
	MOV	BYTE PTR DS:[SI+1],AH
	INC	ES:[BX.IFSR_BUFSIZE]
IDO_60:
	invoke	SET_CATEGORY
	MOV	ES:[BX.IFSR_CATEGORY],CL
	MOV	ES:[BX.IFSR_CTLFUNC],CTLFUNC_DEVOPER
	SaveReg <CX>				; save count
	invoke	CALL_IFS			; call ifs with device oper request
	RestoreReg <CX> 			; restore count
IDO_100:
	ADD	SI,DX				; prep for next dfl
	LOOP	IDO_40				; go process next dfl
	transfer ifs_990			; Finished.  Go ret no carry.
EndProc IFS_DEVICE_OPER
BREAK <IFS_SPOOL_ECHO_CHECK  See if FS controling LPT1 allows echo>
;******************************************************************************
; IFS_SPOOL_ECHO_CHECK
;   Called by:	Dispatcher
;   Routines called: DFL_MATCH
;		     DFL_TO_DF
;		     CALL_IFS
; Inputs:  None
; Function:
;	Call DFL_MATCH for match on "LPT1".
;	IF match found THEN
;	   DO
;	     Prep IFSRH:
;	     *	IFSR_LENGTH	 DW	48	 ; Request length
;	     *	IFSR_FUNCTION	 DB	 4	 ; Execute API function
;		IFSR_RETCODE	 DW	 ?
;		IFSR_RETCLASS	 DB	 ?
;		IFSR_RESV1	 DB	16 DUP(0)
;	     *	IFSR_APIFUNC	 DB	16	 ; IFS dependent IOCTL
;		IFSR_ERROR_CLASS DB	 ?
;		IFSR_ERROR_ACTION DB	 ?
;		IFSR_ERROR_LOCUS DB	 ?
;		IFSR_ALLOWED	 DB	 ?
;		IFSR_I24_RETRY	 DB	 ?
;		IFSR_I24_RESP	 DB	 ?
;		IFSR_RESV2	 DB	 ?
;	     *	IFSR_DEVICE_CB@  DD	 ?	 ; DF
;		IFSR_OPEN_CB@	 DD	 ?
;	     *	IFSR_FUNC	 DB	 0	 ; 00 Generic IOCTL by devnum
;		IFSR_RESV2	 DB	 0
;	     *	IFSR_BUFFER@	 DD	 ?
;	     *	IFSR_BUFSIZE	 DW	 ?
;		IFSR_CATEGORY	 DB	 ?	 ; 0 non-unc, 1 unc
;		IFSR_CTLFUNC	 DB	 00000011B
;		BUFFER	LABEL	BYTE
;			DB	VALUE,0 	; 0 echo allowed
;						; 1 echo not allowed
;	     Call routine, CALL_IFS, with DFL_IFSR_HDR
;	   ENDDO
; Outputs:
;	Carry clear - echo allowed
;	Carry set   - echo NOT allowed
; Regs: nothing preserved
; Programming notes:  DFL FSDA not updated
;******************************************************************************
	procedure IFS_SPOOL_ECHO_CHECK,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	ifsr_fcn_def	EXECAPI
	ifsr_api_def	DEPIOCTL
	SaveReg <ES,DI,DS,SI>			; save these for ibmdos (guessing which)
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@	; make sure this positioned
							; right
	PUSH	CS				; Set ds:si -> "lpt1",0
	POP	DS				; want to find dfl entry with
ASSUME	DS:IFSSEG				; this dev name
	MOV	SI,OFFSET LPT1_NAME
	invoke	DFL_MATCH
	JNC	ISEC_10
	CLC					; not in dfl; assume echo ok
	JMP	ISEC_1000
ISEC_10:
	LES	DI,[THISDFL]
;;;aliasCMP	ES:[DI.DFL_TYPE],TYPE_ALIAS
;;;aliasJNE	ISEC_15
;;;aliastransfer ifs_980			; lpt1 is alias, assume no echo
ISEC_15:
	invoke	PREP_IFSR			; zero out ifsr
	invoke	DFL_TO_DF			; DFL: sets [THISIFS]
						;	    ES:BX -> IFSRH
						;	    IFSR_DEVICE_CB@
						;	    ds - IFSSEG
	invoke	SET_DEPIOCTL_IFSR		; prep IFSRH
	MOV	SI,OFFSET TEMPBUF
	MOV	WORD PTR ES:[BX.IFSR_BUFFER@],SI	; use tempbuf for
	MOV	WORD PTR ES:[BX.IFSR_BUFFER@+2],DS	; return byte value
	MOV	ES:[BX.IFSR_BUFSIZE],LENGTH_DEVECHOCHECK_BUFFER ; (1)
	invoke	SET_CATEGORY
	MOV	ES:[BX.IFSR_CTLFUNC],CTLFUNC_DEVECHOCHECK  ; (00000011)
	invoke	CALL_IFS
	JNC	ISEC_60
	JMP	SHORT ISEC_1000 			; no echo on err, cf set
ISEC_60:
	CMP	BYTE PTR DS:[SI],0			; else byte returned in buffr
	JE	ISEC_80 				; determines echo (0-yes,1-no)
	STC
	JMP	SHORT ISEC_1000 			; no echo ret
ISEC_80:
	CLC


ISEC_1000:						; echo ret
	RestoreReg <SI,DS,DI,ES>
	RET

EndProc IFS_SPOOL_ECHO_CHECK
BREAK <IFS_DEPENDENT_IOCTL  - dependent ioctl>
;******************************************************************************
; IFS_DEPENDENT_IOCTL
; Called by:  Dispatcher
; Routines called:  CALL_IFS
;		    CDS_TO_CD	SFT_TO_SFF
;		    CD_TO_CDS	SFF_TO_SFT
; Inputs:
;	AL = 0 - Generic by device number
;	   BH = 0, BL = device number (0-def,1=a,2=b,...)  [THISCDS] set
;	   CX = private subfunction
;	   DS:DX -> buffer
;	AL = 1 - Generic by handle
;	   BX = handle	[THISSFT] set
;	   CX = private subfunction
;	   DS:DX -> buffer
;	AL = 2 - Query OS type
;	   BH = 0, BL = device number (0-def,1=a,2=b,...)  [THISCDS] set
;	   CX = buffer size
;	   ES:DI -> buffer
; Function:
;	Prep IFSRH:
;	*  IFSR_LENGTH	    DW	   48	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DW	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   16 DUP(0)
;	*  IFSR_APIFUNC     DB	   16	    ; IFS dependent IOCTL
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	   IFSR_ALLOWED     DB	    ?
;	   IFSR_I24_RETRY   DB	    ?
;	   IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	*  IFSR_DEVICE_CB@  DD	    ?	    ; Set by CDS_TO_CD (subfs 0,2)
;	*  IFSR_OPEN_CB@    DD	    ?	    ; Set by SFT_TO_SFF (subf 1)
;	*  IFSR_FUNC	    DB	    0	    ; AL - 0,1,or 2
;	   IFSR_RESV2	    DB	    0
;	*  IFSR_BUFFER@     DD	    ?	    ; al-2 es:di, else ds:dx
;	*  IFSR_BUFSIZE     DW	    ?	    ; al-2 cx, else ???
;;;; for al=0,1
;	*  IFSR_CATEGORY    DB	    1	    ; 1 for UNC, 0 for non-UNC
;	*  IFSR_CTLFUNC     DB	    ?	    ; al-2 ???, else cx
;	CALL routine, CALL_IFS, with pointer to IFS header
;	IF IFSR_RETCODE = 0 THEN
;	   DO
;	     IF CDS THEN
;		Call CD_TO_CDS
;	     ELSE Call SFF_TO_SFT
;	   ENDDO
;	ELSE
;	   Set carry
;	   Put error code in AX
;	ENDIF
;   Outputs: function dependent
;   Regs: nothing preserved
;******************************************************************************
	procedure IFS_DEPENDENT_IOCTL,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	ifsr_fcn_def	EXECAPI
	ifsr_api_def	DEPIOCTL
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@	; make sure this positioned
							; right
	SaveReg <BX,ES> 			; save input es for query os type
						; and bx for drive # / handle
	MOV	CS:IFSPROC_FLAGS,ZERO		; init ifsfunc flags
	invoke	PREP_IFSR			;  & IFSR
	invoke	SET_DEPIOCTL_IFSR		; prep IFSRH
	MOV	ES:[BX.IFSR_FUNC],AL		; 0,1, or 2
	CMP	AL,QUERY_OS_TYPE
	JE	IDI_10
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@],DX  ; ioctl generic
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@+2],DS
	MOV	ES:[BX.IFSR_CTLFUNC],CL
	ADD	SP,2				; ditch es stored on stack
	JMP	SHORT IDI_15
IDI_10: 					; query os type
	MOV	ES:[BX.IFSR_BUFSIZE],CX 	; cx is bufsize
	POP	CX				; pop input es in cx
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@],DI
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@+2],CX
IDI_15:
	CMP	AL,GEN_IOCTL_BY_HANDLE
	RestoreReg <CX> 			; restore input bx into ax, no cx
						;	  (drive # or handle)
	JE	IDI_20
;;;;;;; LDS	SI,[THISCDS]			; have device number (block only???)	 ;AD006;
						; Now get CDS:
	SaveReg <AX>				; function 0,1,2
	MOV	AX,CX				; input bx
	DEC	AL				; make 0-based
	MOV	CS:[IFSDRV],AL			; set this for possible i24
	CallInstall GetCDSFromDrv,multDOS,23,AX,AX
	RestoreReg <AX> 			; fcn 0,1,2
	JNC	IDI_17
IDI_16:
	MOV	AX,error_invalid_drive		;   no cds, set error & ret
	JMP	IDI_120 			; ret up in FA to preserve DS
IDI_17: 					; (welcome lock)
	TEST	DS:[SI.curdir_flags],curdir_isifs	; check if drive ifs
	JZ	IDI_16
	SaveReg <DS,SI> 			; save cds ptr	al=0,2
	OR	IFSPROC_FLAGS,ISCDS
	invoke	CDS_TO_CD			; CDS: sets [THISIFS]
						;      IFSR_DEVICE_CB@
						;      ds - netwrk
	CMP	AL,QUERY_OS_TYPE
	JNE	IDI_40
	JMP	SHORT IDI_60
IDI_20: 					; al=1
	Context DS
	OR	IFSPROC_FLAGS,SETDEVICECB
						; Now, need to get THISSFT set:
	SaveReg <ES,DI,BX>			; these about to be clobbered
	MOV	BX,CX				; put handle in bx
	CallInstall pJFNFromHandle,multDOS,32	; intermediate step to getting sft
	JC	IDI_25
	CMP	BYTE PTR ES:[DI],-1		; unused handle
	JE	IDI_25
	MOV	BL,BYTE PTR ES:[DI]		; get SFN
	XOR	BH,BH				; ignore upper half
	CallInstall SFFromSFN,multDOS,22	; get real sf spot
	MOV	WORD PTR [THISSFT],DI
	MOV	WORD PTR [THISSFT+2],ES
	RestoreReg <BX,DI,ES>
	JMP	SHORT IDI_30
IDI_25: 					; sft error
	RestoreReg <BX,DI,ES>			; restore regs
	MOV	AX,error_invalid_handle
	JMP	IDI_120

IDI_30:
	invoke	SFT_TO_SFF			; sets: [THISIFS]
						;	IFSR_OPEN_CB@
						;	ds - netwrk
IDI_40:
	invoke	SET_CATEGORY			; set category 1-unc 0-other
	MOV	ES:[BX.IFSR_CATEGORY],CL
IDI_60:
	MOV	DX,IFSIOCTL			; check if fs supports fs ioctl
	invoke	CHECK_IFS_ATTRIBUTE
	JZ	IDI_80				; Z = no support, NZ = yes support
	JMP	DI_70				; continues in device_ioctl
IDI_80: 					; error invalid fcn - fs doesn't support
	TEST	IFSPROC_FLAGS,ISCDS		; if cds, must clean stack of
	JZ	IDI_100 			; cds ptr
	ADD	SP,4
IDI_100:
	MOV	AX,error_invalid_function
IDI_120:
	invoke	SET_EXTERR_INFO 		; set error info
	transfer ifs_980			; go to general error return
EndProc IFS_DEPENDENT_IOCTL


BREAK <DEVICE_IOCTL  - device ioctl>
;******************************************************************************
;
; DEVICE_IOCTL
;
; Called by:  Dispatcher
;
; Routines called:  CALL_IFS
;		    CDS_TO_CD	SFT_TO_SFF
;		    CD_TO_CDS	SFF_TO_SFT
;
; Inputs:
;	AL = 02H(03H0 Read from(Write to) character device
;	   BX = handle	 [THISSFT] set
;	   CX = number of bytes to read(write)
;	   DS:DX -> buffer
;	AL = 0CH Character Generic IOCTL
;	   CH = 1-async, 3-display, 5-printer
;	   CL = 5F-set, 7F-get
;	   DS:DX -> buffer
;	AL = 0DH Block Generic IOCTL
;	   BH = 0
;	   BL = Drive number  [THISCDS] set (0-based)
;	   CH = 08
;	   CL = 43-set, 63-get media id
;	   DS:DX -> buffer
;
; Function:
;	Prep IFSRH:
;	*  IFSR_LENGTH	    DW	   48	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DW	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   16 DUP(0)
;	*  IFSR_APIFUNC     DB	   17	    ; IFS device IOCTL
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	   IFSR_ALLOWED     DB	    ?
;	   IFSR_I24_RETRY   DB	    ?
;	   IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	*  IFSR_DEVICE_CB@  DD	    ?	    ; Set by CDS_TO_CD (0DH)
;	*  IFSR_OPEN_CB@    DD	    ?	    ; Set by SFT_TO_SF (0CH)
;	*  IFSR_FUNC	    DB	    0	    ; AL 2,3,12,or 13
;	   IFSR_RESV2	    DB	    0
;	*  IFSR_BUFFER@     DD	    ?	    ; ds:dx
;	*  IFSR_BUFSIZE     DW	    ?	    ; cx for al=2,3
;	*  IFSR_CATEGORY    DB	    1	    ; ch for al=12,13
;	*  IFSR_CTLFUNC     DB	    ?	    ; cl for al=12,13
;
;
;	CALL routine, CALL_IFS
;	IF IFSR_RETCODE = 0 THEN
;	   DO
;	     IF CDS THEN
;		Call CD_TO_CDS
;	     ELSE Call SFF_TO_SFT
;	   ENDDO
;	ELSE
;	   Set carry
;	   Put error code in AX
;	ENDIF
;
;   Outputs: function dependent
;
;   Regs: nothing preserved
;
;******************************************************************************
	procedure DEVICE_IOCTL,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
;	mov	ax,26				; these two instrs temporary
;	transfer ifs_980

	ifsr_fcn_def	EXECAPI
	ifsr_api_def	DEVIOCTL
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@	; make sure this positioned
							; right
	PUSH	DS				; save input ds
	MOV	CS:IFSPROC_FLAGS,ZERO		; init processing flags
	invoke	PREP_IFSR			;  & ifsr
	POP	ES:WORD PTR [BX.IFSR_BUFFER@+2] ; put input ds in now before clobber it
	CMP	AL,BLOCK_GENERIC
	JNE	DI_20
	LDS	SI,[THISCDS]			; block generic - cds processing
	SaveReg <DS,SI> 			; save cds ptr
	OR	IFSPROC_FLAGS,ISCDS
	invoke	CDS_TO_CD			; CDS: sets [THISIFS]
						;      IFSR_DEVICE_CB@
						;      ds - netwrk
	JMP	SHORT DI_40
DI_20:						; handle function
	OR	CS:IFSPROC_FLAGS,SetDeviceCB	; to get possible related cd or df
	Context DS
	invoke	SFT_TO_SFF			; sets: [THISIFS]
						;	IFSR_OPEN_CB@
						;	ds - netwrk
DI_40:
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_DEVIOCTL
	MOV	ES:[BX.IFSR_FUNCTION],IFSEXECAPI
	MOV	ES:[BX.IFSR_APIFUNC],IFSDEVIOCTL
	MOV	ES:[BX.IFSR_FUNC],AL		; 2,3,12 or 13
;;;;;	POP	DS				; retrieve input ds			 ;AD005;
	MOV	ES:WORD PTR [BX.IFSR_BUFFER@],DX
;;;;;	MOV	ES:WORD PTR [BX.IFSR_BUFFER@+2],DS					 ;AD005;
	CMP	AL,CHAR_GENERIC 		; fork 2,3 vs 12,13
	JGE	DI_60				; go if 12,13
	MOV	ES:[BX.IFSR_BUFSIZE],CX 	; 2,3 processing
	JMP	SHORT DI_70
DI_60:						; 12,13 processing
	MOV	ES:[BX.IFSR_CATEGORY],CH	; 1,3,5,or 8
	MOV	ES:[BX.IFSR_CTLFUNC],CL 	; 5F,7F,4E,or 6E
DI_70:
;-----------------------------------------------------------------------------------------
	invoke	CALL_IFS			; call ifs driver w/request
;-----------------------------------------------------------------------------------------
	JNC	DI_100
	TEST	IFSPROC_FLAGS,ISCDS		; error return
	JNZ	DI_80				;   if cds clean up stack
	transfer ifs_1000			; go return in ifsutil
DI_80:
	ADD	SP,4				; restore stack
	transfer ifs_980
DI_100:
	TEST	IFSPROC_FLAGS,ISCDS
	JNZ	DI_120
	MOV	AX,ES:[BX.IFSR_BUFSIZE] 	; set return size for 2,3 (won't hurt
	invoke	SFF_TO_SFT			; for 12 either
	transfer ifs_990
DI_120:
	MOV	CX,ES:[BX.IFSR_BUFSIZE]
	RestoreReg <DI,ES>			; restore cds ptr into esdi
	invoke	CD_TO_CDS
	transfer ifs_990
EndProc DEVICE_IOCTL
BREAK <GET_DFL_FROM_INDEX  Get DFL entry from index>
;******************************************************************************
; GET_DFL_FROM_INDEX
; Called by:  PRINTER_GETSET_STRING
; Routines called: none
; Inputs:
;	BX is index number (as in GetIFSFUNCItem)
; Outputs:
;	Carry Clear
;		[THISDFL] set
;	Carry Set
;		Bad index number
; Regs: Preserves Printer Get/Set String input regs
;******************************************************************************
	procedure GET_DFL_FROM_INDEX,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <DS,SI,CX,DX>			; save Ptr GetSet Str input regs
						;     (removed ax from above)
	PUSH	BX
; Compute index # of first device
	XOR	BX,BX
	MOV	CX,BX
	Context DS				; DS-Dosgroup
	MOV	CL,[CDSCount]
	LDS	SI,[CDSAddr]			; Assume not paused
	CMP	CS:[fAssign],0
	JNZ	GDFI_20
	LDS	SI,CS:[CDSAlt]			; Paused, get REAL CDSs from here
GDFI_20:
	TEST	[SI.CURDIR_FLAGS],CURDIR_ISIFS
	JZ	GDFI_40
	INC	BX
;;;	TEST	[SI.CURDIR_TYPE],TYPE_NET_DRIVE 					 ;AD003;
;;;	JZ	GDFI_40 			; count 2 for redir			 ;AD003;
;;;	INC	BX									 ;AD003;
GDFI_40:
	ADD	SI,SIZE CURDIR_LIST		; Next CDS
	LOOP	GDFI_20
						; BX is index # of first device
	POP	AX				; Get user index #
	SUB	AX,BX
	JB	GDFI_60 			; if carry set (JB), user index <
						; 1st device index - too low
						; go return w/carry already set
	MOV	CL,CS:[DFLCount]
	CMP	CL,AL				; AL is now device index #
	JAE	GDFI_80
GDFI_60:
	MOV	AX,error_invalid_parameter	; user index too high
	JMP	GDFI_980			; go return w/carry already set
GDFI_80:
	LDS	SI,CS:[DFLAddr]
	MOV	BL,SIZE DFLL_list		; size in convenient spot
;;;	DEC	AX									 ;AD003
	MUL	BL				; get net offset
	ADD	SI,AX				; convert to true pointer
	TEST	DS:[SI.DFLL_FLAGS],dfl_inuse	; is this device attached?????
	JZ	GDFI_60 			; error if not
	PUSH	DS
	POP	DX
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	MOV	WORD PTR [THISDFL],SI
	MOV	WORD PTR [THISDFL+2],DX
	invoke	PREP_IFSR			; init ifsr
	invoke	DFL_TO_DF
	JMP	GDFI_990
GDFI_980:					; Return area
	SaveReg <AX,CS> 			; set thisdfl null on error
	RestoreReg <DS>
	MOV	AX,NULL_PTR
	MOV	WORD PTR [THISDFL],AX
	MOV	WORD PTR [THISDFL+2],AX
	RestoreReg <AX>
	STC
	JMP	GDFI_1000
GDFI_990:
	CLC
GDFI_1000:
	RestoreReg <DX,CX,SI,DS>		; restore regs
						;     (removed ax from above)
	return
EndProc GET_DFL_FROM_INDEX
IFSSEG	ENDS
	END
