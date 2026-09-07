	PAGE	,132				; 
TITLE	IFSFUNC SESSION ROUTINES - IFS Attach Routines
NAME	IFSSESS
;************************************************************************************
;
; IFSSESS
;
; Session related IFS calls    (Session = attachment)
;
;   IFS_ASSOPER
;   RETURN_ASSIGN_MODE
;   SET_ASSIGN_MODE
;   GET_IFSFUNC_ITEM
;   ATTACH_START
;   ATTACH_END
;   IFS_RESET_ENVIRONMENT
;   IFS_ABORT
;   GET_IFS_DRIVER_NAME
;   FIND_IFS_DRIVER
;   AssignOn/AssignOff
;   PrintOn/PrintOff
;   GET_UNC_ITEM_INFO
;
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
; NOTE: We cannot include DOSSEG here because the START seg is not declared
;	as PARA aligned in DOSSEG.
START		SEGMENT PARA PUBLIC 'START'
START		ENDS
CONSTANTS	SEGMENT WORD PUBLIC 'CONST'
CONSTANTS	ENDS
DATA		SEGMENT WORD PUBLIC 'DATA'
DATA		ENDS
TABLE		SEGMENT BYTE PUBLIC 'TABLE'
TABLE		ENDS
CODE		SEGMENT BYTE PUBLIC 'CODE'
CODE		ENDS
LAST		SEGMENT PARA PUBLIC 'LAST'
LAST		ENDS
DOSGROUP    GROUP   START,CONSTANTS,DATA,TABLE,CODE,LAST
DATA		SEGMENT WORD PUBLIC 'DATA'
	;DOSGROUP Data
	Extrn	CurrentPDB:WORD
	Extrn	THISCDS:DWORD
	Extrn	CDSAddr:DWORD
	Extrn	CDSCount:BYTE
	Extrn	MYNAME:BYTE
	Extrn	DummyCDS:BYTE
	Extrn	sftFCB:DWORD
	Extrn	THISSFT:DWORD
	Extrn	SysInitTable:BYTE
	Extrn	EXIT_TYPE:BYTE
	Extrn	IFS_HEADER:DWORD
if debug
	Extrn	BugLev:WORD
	Extrn	BugTyp:WORD
	include bugtyp.asm
endif
DATA		ENDS
; define our own code segment
IFSSEG	SEGMENT BYTE PUBLIC 'IFSSEG'
	ASSUME	SS:DOSGROUP,CS:IFSSEG
	;IFS Data - external
	Extrn	TEMPBUF:BYTE
	;IFS Data - public - *** IFSFUNC SWAPPABLE DATA AREA ***
PUBLIC	IFSF_SWAP_START
IFSF_SWAP_START      LABEL BYTE
	PUBLIC	THISIFS
THISIFS 	DD	-1

	PUBLIC	THISDFL
THISDFL 	DD	-1

	PUBLIC	IFSR
IFSR		DB	72 DUP (0)

	PUBLIC	SFF1
SFF1		DB	62 DUP (0)

	PUBLIC	CD1
CD1		DW	84 DUP (0)

	PUBLIC	DF1
DF1		DW	18 DUP (0)

	PUBLIC	IFSPROC_FLAGS
IFSPROC_FLAGS	DW	0

; Number of net drive (0=A) for use on net I 24
	PUBLIC	IFSDRV
IFSDRV		DB	-1

	PUBLIC	DEVICE_CB@_OFFSET
; This used to set offset of ifsr_device_cb@ in common routine cds_to_cd
; in ifsutil.  If not used, offset always 1EH since that's what it is at
; ifsutil assembly time.  This not good for control fcns (attstart,attstat).
DEVICE_CB@_OFFSET DW	0			; offset in ifsrh of device cb@

	PUBLIC	SAVE_CB@
; This used by SFT_TO_SFF and SFF_TO_SFT routines in IFSUTIL to save cds ptr.
SAVE_CB@	DD	-1

	PUBLIC	IFSSEM
; This used as byte of semaphores.
IFSSEM		DB	0

IFSF_SWAP_END	 LABEL	 BYTE
PUBLIC	IFSF_SWAP_END
	;IFS Data - public
	PUBLIC	DFLAddr
DFLAddr 	DD	-1

	PUBLIC	DFLCount
DFLCount	DB	0

;;;aliasPUBLIC	NLAddr
;;;aliasNLAddr		DD	-1

;;;aliasPUBLIC	NLSIZE
;;;aliasNLSIZE		DW	0

	PUBLIC	CDSAlt
CDSAlt		DD	-1

	PUBLIC	UNC_FS_HDR
UNC_FS_HDR	DD	-1

	PUBLIC	IFSFUNC_FLAGS
IFSFUNC_FLAGS	DW	0

	PUBLIC	IFS_ATTRS
IFS_ATTRS	DW	0			; all ifs_attribute words from ifs
						; headers or'ed together (ifsinit)
	PUBLIC	DOSCALL@
DOSCALL@	DD	0			; IFS_DOSCALL@ set by ibmbio

	PUBLIC	SFT_SERIAL_NUMBER
SFT_SERIAL_NUMBER DW	0			; to get sfts unique for fcb reasons

	PUBLIC	fAssign
fAssign 	DB	-1

	PUBLIC	fPrint
fPrint		DB	-1

	PUBLIC	TRUNCATE_FLAG								 ;AC030;moved out of swap
TRUNCATE_FLAG	DB	0								 ;AC030;    "   "


	;IFS Data - local
;SetBP		DB	0			; flag indicates whether to return	 ;AD003;
						; LSN on getuncitem call (GII)
;ERROR_STATUS	DW	1			; Status returned on error return	 ;AD029;
ERROR_STATUS	DB	"ERROR",0               ; from fs (GII)
BREAK <IFS_ASSOPER -- Do the $Assignoper call>
copyright	db	" IFSFUNC.EXE                  "
INCLUDE copyrigh.inc

;************************************************************************************
; IFS_ASSOPER
; Called by: IFSFUNC dispatcher
; Routines called:
;	      RETURN_ASSIGN_MODE
;	      SET_ASSIGN_MODE
;	      GET_IFSFUNC_ITEM
;	      ATTACH_START
;	      ATTACH_END
; Inputs:
;	AL = 00 get / 01 set - redir assign mode    (Return/Set Mode)
;	AL = 02 get attach list entry		    (Get ifsfunc item)
;	AL = 03 Define Macro  (attach start)
;	AL = 04 Cancel Attach (attach end)
;	AL = 05 Revised get assign list entry	    (Getifsfuncitem2)
;	AL = 06 Get IFSFUNC Item		    (Getifsfuncitem3)
; Function:
;	IF	AL=0 call RETURN_ASSIGN_MODE
;	ELSE IF AL=1 call SET_ASSIGN_MODE
;	ELSE IF AL=2 call GET_IFSFUNC_ITEM
;	ELSE IF AL=3 call ATTACH_START
;	ELSE IF AL=4 call ATTACH_END
; Outputs:
;	see subroutines
;************************************************************************************
AO_TABLE LABEL	WORD
	DW	RETURN_ASSIGN_MODE
	DW	SET_ASSIGN_MODE
	DW	GET_IFSFUNC_ITEM
	DW	ATTACH_START
	DW	ATTACH_END
	DW	GET_IFSFUNC_ITEM2
	DW	GET_IFSFUNC_ITEM3
	Procedure   IFS_ASSOPER,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	TEST	CS:IFSFUNC_FLAGS,no_ifs_drivers
	JZ	AO_20
AO_10:
	MOV	AX,error_not_supported
	transfer ifs_980
AO_20:
	CMP	AL,0
	JNE	AO_40
	CMP	AL,1
	JNE	AO_40
	TEST	CS:IFSFUNC_FLAGS,unc_installed
	JZ	AO_10
AO_40:
	MOV	CS:IFSPROC_FLAGS,ZERO
	PUSH	BX				; save macro type
	XOR	AH,AH
	SHL	AL,1				; AL x 2
	MOV	BX,AX
	JMP	CS:AO_TABLE[BX]
EndProc IFS_ASSOPER
BREAK <RETURN_ASSIGN_MODE -- Return Assign Mode>
;************************************************************************************
; RETURN_ASSIGN_MODE
; Called by:  IFS_ASSOPER
; Routines called:	DOS: Get_User_Stack
; Inputs:
;	    BL = macro type
; Function:
;	If macro type = 3 (network printer) THEN
;	   BX = fPrint .AND. 1
;	Elseif macro type = 4 (network disk) THEN
;	   BX = fAssign .AND. 1
;	Else set error_invalid_function
; Output:
;	IF AL==0 BX value on user stack
; Notes:  This routine is used only for UNC file system.  This is the
;	  only FS that supports pause.
;************************************************************************************
	Procedure   RETURN_ASSIGN_MODE,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	POP	BX			; macro type
	CMP	BL,3			; if (type == drive)
	JZ	GAM_20
	CMP	BL,4
	JNZ	GAM_60
	MOV	BH,fAssign		;    t = fAssign;
	JMP	Short GAM_40		; else
GAM_20: 				; if (type == print)
	MOV	BH,fPrint		;    t = fPrint;
GAM_40:
	AND	BH,1			;   return t&1;
	CallInstall Get_User_Stack,multDOS,24
	MOV	[SI].User_BX,BX
	transfer ifs_990		; go to general good ret in util
GAM_60:
	MOV	AL,error_invalid_function
	transfer ifs_980		; go to general bad ret in util
EndProc RETURN_ASSIGN_MODE
BREAK <SET_ASSIGN_MODE -- set assign mode>
;************************************************************************************
; SET_ASSIGN_MODE
; Called by: IFS_ASSOPER
; Routines called:
; Inputs:
;	    BL = macro type
;	    BH = assign mode   (0 = off - pause, 1 = on - no pause)
; Function:
; Output:
;************************************************************************************
	Procedure   SET_ASSIGN_MODE,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	POP	BX			; restore macro type (3 or 4)
	CMP	BL,3			; check if printer or drive
	JNZ	SAM_40			;
	OR	BH,BH			; printer - check mode
	JZ	SAM_20			; off - go pause
	CMP	BH,1
	JNZ	SAM_80			; jump on parm error
	CALL	PrintOn 		; turn print on
	transfer ifs_990		; go to general good ret in util
SAM_20: 				; print off - pause
	CALL	PrintOff
	transfer ifs_990		; go to general good ret in util
SAM_40: 				; Drive
	CMP	BL,4
	JNZ	SAM_80			; jump on parm error
	OR	BH,BH
	JZ	SAM_60
	CMP	BH,1
	JNZ	SAM_80			; jump on parm error
	CALL	AssignOn		; drive on
	transfer ifs_990		; go to general good ret in util
SAM_60: 				; drive off
	invoke	AssignOff		; turn drives off (pause)
	transfer ifs_990		; go to general good ret in util
SAM_80:
	MOV	AX,error_invalid_parameter
	invoke	SET_EXTERR_INFO
	transfer ifs_980		; go to general bad ret in util
EndProc SET_ASSIGN_MODE
BREAK <GET_IFSFUNC_ITEM -- for get attach list >
;************************************************************************************
; GET_IFSFUNC_ITEM
; Called by: IFS_ASSOPER
; Routines called:
;	     GET_IFS_DRIVER_NAME	DOS: STRCPY
;	     CDS_TO_CD			     GET_USER_STACK
;	     DFL_TO_DF
;	     CALL_IFS
; Inputs:
;	    BL = redirection index
;	    DS:SI -> Device name buffer
;	    ES:DI -> Target buffer:  old - net path string
;				     new - dw file system driver name
;					   dw # parms
;					   db parms
; Function:
;	     STRUCTURE = 1st CDS
;	     INDEX = 0
;	     WHILE CDS structures
;	       DO
;		 IF curdir_isIFS TRUE THEN
;		    DO
;		      IF INDEX = BL THEN
;			DO
;			  DS:SI   = Letter version of Index (0=A:, 1=B:, ...)
;			  IF IFS .NOT. UNC THEN
;			    DO
;			      ES:[DI] = IFS name  (retrieved from CURDIR_IFSR_HDR)
;			      Send ATTACH_STAT request to IFS for parms
;			      ES:DI+2 = IFS parms
;			      FOUND = true
;			      TYPE = 2
;			      LEAVE WHILE
;			    ENDDO
;			  ELSE DO
;				 Send ATTACH_STAT request to REDIR.SYS for parms
;				 Move parms into one buffer and point with ES:DI
;				 FOUND = true
;				 TYPE = 4
;				 LEAVE WHILE
;			       ENDDO
;		      ELSE DO
;			     IF IFS UNC THEN
;			       DO
;				 INDEX=INDEX+1
;				 IF INDEX = BL THEN
;				    DO
;				      DS:SI   = Letter version of Index (0=A:, 1=B:,
;				      ES:DI = "REDIR"
;				      FOUND = true
;				      TYPE  = 2
;				      LEAVE WHILE
;				    ENDDO
;				 ENDIF
;			       ENDDO
;			     ENDIF
;			   ENDDO
;		      ENDIF
;		    ENDDO
;		 ENDIF
;		 Get next CDS structure
;	       ENDDO
;	     ENDWHILE
;	     IF FOUND = false THEN
;		DO
;		  STRUCTURE = 1st DFL
;		  WHILE DFL structures
;		    DO
;		      IF INDEX = BL THEN
;			 DO
;			   DS:SI = name pointed to by DFLL_NAME_PTR
;			   IF IFS .NOT. UNC THEN
;			     DO
;			       ES:[DI] = IFS name  (retrieved from DFLL_IFSR_HDR)
;			       Send ATTACH_STAT request to IFS for parms
;			       ES:DI+2 = IFS parms
;			       FOUND = true
;			       TYPE = 1
;			       LEAVE WHILE
;			     ENDDO
;			   ELSE DO
;				  Send ATTACH_STAT request to REDIR.SYS for parms
;				  Move parms into one buffer and point with ES:DI
;				  FOUND = true
;				  TYPE = 3
;				  LEAVE WHILE
;				ENDDO
;		      ELSE DO
;			     IF IFS UNC THEN
;				DO
;				  INDEX=INDEX+1
;				  IF INDEX = BL THEN
;				     DO
;				       ES:DI = "REDIR"
;				       FOUND = true
;				       TYPE  = 3
;				       LEAVE WHILE
;				     ENDDO
;				  ENDIF
;				ENDDO
;			     ENDIF
;			   ENDDO
;		      ENDIF
;		      Get next DFL structure
;		    ENDWHILE
;		ENDDO
;	     ENDIF
;	     IF FOUND = FALSE THEN
;		DO
;		  Set carry
;		  AX = 18
;		ENDDO
;	     ELSE Clear carry
;	     ENDIF
;
;	     IFSRH for Attach Start:
;	       *  IFSR_LENGTH	   DW	  32	   ; Request length
;	       *  IFSR_FUNCTION    DB	   3	   ; Attach Start
;		+ IFSR_RETCODE	   DW	   0
;		+ IFSR_RETCLASS    DB	   ?
;		  IFSR_RESV1	   DB	  16 DUP(0)
;		+ IFSR_TYPE	   DB	   ?	   ; BL (1,2,3,or 4)
;		  IFSR_RESV2	   DB	   ?
;	       *+ IFSR_PARMS@	   DD	   PARMS   ; See below
;	       *+ IFSR_DEVICE_CB@  DD	   ?	   ; CD or DF (See below)
;		+ IFSR_USER_WORD   DW	   ?
;		+ IFSR_MAX_XMITT_SIZE DW   ?
;		+ IFSR_NET_NAME_ID DW	   ?
;		+ IFSR_LSN	   DW	   ?
;		+ IFSR_DEVICE_STATUS  DB   ?
;		  IFSR_RESV3	   DB	   ?
;
;
;
;	       *+ PARMS 	  LABEL   WORD
;				  DW	  PARMCOUNT ; Number of parms. (only for new style)
;				  DB	  ASCIIZ,...; Parms
;
; Outputs:
;	 No Carry - BH = device status flag
;			 bit 0=0 is device valid
;			       1 if device invalid
;		    BL = device type
;		    DS:SI = ASCIIZ local device name
;		    ES:DI = ASCIIZ network name
;		For old style call:
;		    CX = user word
;		    DX = max xmitt size
;		    BP = Low 8 bits has LSN from NCB_LIST if input AL ^=0
;		    AX = Net name ID
;
;	 Carry	  - AX = Error code
;			 18 - end of list
; Regs:
;************************************************************************************
	USER_WORD	DW	0		; i give in - temp storage
	Procedure   GET_IFSFUNC_ITEM
ASSUME	DS:NOTHING,ES:NOTHING
						; get_ifsfunc_item and get_ifsfunc_item2
	MOV	CS:IFSPROC_FLAGS,ZERO		; are old style - types 3,4 only
	JMP	SHORT GII_20
	entry	GET_IFSFUNC_ITEM2
	MOV	CS:IFSPROC_FLAGS,SetBP		; set this to get lsn
	JMP	SHORT GII_20
	entry	GET_IFSFUNC_ITEM3		; new style get ifsfunc item
	MOV	CS:IFSPROC_FLAGS,Filesys_Status ; gets types 1,2,3,4
;----------------------------------------------------------------------------------------
;   drive  loop
;----------------------------------------------------------------------------------------
GII_20:
	ifsr_fcn_def  ATTSTAT			; define ifsr for attach status
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	POP	BX				; index
	XOR	AX,AX				; ax will be counter through CDSs
	SaveReg <DS,SI> 			; save device/drive name buffer
GII_40:
	CMP	AL,SS:[CDSCount]		; if run out of CDSs,
	JB	GII_60				;    go to devices
	XOR	AL,AL				; reset for dfl count
	JMP	GII_400
GII_60:
	SaveReg <BX,AX> 			; save ax-cds count, bx-index
	LDS	SI,[CDSAddr]			; Point ds:si to correct CDS entry
	CMP	[fAssign],ZERO			; if pause in effect, must use
	JNZ	GII_80				; alternate cds list
	LDS	SI,[CDSAlt]
GII_80:
	MOV	BL,SIZE CurDir_list		; size in convenient spot
	MUL	BL				; get net offset
	ADD	SI,AX				; convert to true pointer
	RestoreReg  <AX,BX>
	TEST	[SI].curdir_flags,curdir_isnet	; make sure ifs drive
	JNZ	GII_100
	JMP	GII_280 			; next drive
GII_100:
	SUB	BX,1				; jae jumps if CF=0, CF=1 when
						; index hit
	JB	GII_120
	JMP	GII_280 			; next drive
GII_120:
	TEST	CS:IFSPROC_FLAGS,Filesys_Status ; check old vs. new style
	JNZ	GII_140
	CMP	[SI.CURDIR_TYPE],TYPE_NET_DRIVE ; old style: check for type 4
	JE	GII_140
	JMP	GII_280 			; not type 4, go get next one
GII_140:
	RestoreReg  <DX,CX>			; get devname ptr into es:di,
	SaveReg <CX,DX> 			; (push back for end ds:si setup)
	SaveReg <ES,DI> 			;   while preserving es:di - target
	MOV	ES,CX
	MOV	DI,DX
	ADD	AL,'A'                          ; storing d:0 in devname buffer
	STOSB
	MOV	AX,(0 SHL 8) + ':'
	STOSW
	RestoreReg <DI,ES>			; restore target ptr
	MOV	BL,[SI.CURDIR_TYPE]		; set bx=type (1,2,3,4)
	XOR	BH,BH
	TEST	CS:IFSPROC_FLAGS,Filesys_status ; target different for new style
	JNZ	GII_150
	PUSH	[SI.CURDIR_USER_WORD]
	POP	CS:[USER_WORD]
	JMP	GII_160
GII_150:
	PUSH	DI				; ifs drive; save target offset
	MOV	DI,ES:[DI]			; es:di -> FS name buffer
	OR	IFSPROC_FLAGS,ISCDS		; get ifs driver name into target
	CALL	GET_IFS_DRIVER_NAME
	POP	DI				; retrieve target offset from stack
	PUSH	DI
	INC	DI				; es:di -> parm buffer
	INC	DI
GII_160:
	SaveReg <ES,BX> 			; save target segment, type
						; go to IFS to fill in rest of tgt
	invoke	PREP_IFSR			; init ifsr
	MOV	DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	invoke	CDS_TO_CD			; CDS: sets [THISIFS]
						;	    ES:BX -> IFSRH
						;	    IFSR_DEVICE_CB@
						;	    ds - IFSSEG
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_ATTSTAT
	MOV	ES:[BX.IFSR_FUNCTION],IFSATTSTAT
	POP	AX				; type (BX)
	MOV	ES:[BX.IFSR_TYPE],AL
	POP	DX				; target segment (ES)
	TEST	IFSPROC_FLAGS,Filesys_status
	JNZ	GII_180
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	MOV	SI,OFFSET TEMPBUF
	MOV	WORD PTR ES:[BX.IFSR_PARMS@],SI
	MOV	WORD PTR ES:[BX.IFSR_PARMS@+2],DS
	PUSH	DI				; push tgt offset here for later pop
	JMP	GII_200
GII_180:
	MOV	WORD PTR ES:[BX.IFSR_PARMS@],DI
	MOV	WORD PTR ES:[BX.IFSR_PARMS@+2],DX
GII_200:
	PUSH	AX				; push type back (BX)
;***********************************************************************************************
	invoke	CALL_IFS			; call fs with attach status request
;***********************************************************************************************
	JNC	GII_220
						; attach status error:
	RestoreReg <BX,DI>			; type,target offset
	MOV	ES,DX
	SaveReg <DI>				; put "ERROR" in parms display
	TEST	CS:IFSPROC_FLAGS,Filesys_status ; don't add  if net use
	JZ	GII_210
	ADD	DI,2
	MOV	AX,1
	STOSW
GII_210:
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	MOV	SI,OFFSET ERROR_STATUS
	MOV	CX,4
	REP	MOVSW
	RestoreReg <DI,SI,DS>
	transfer ifs_1000			; go to general ret in util
GII_220:
	RestoreReg <AX,DI>			; device type, target offset
	TEST	IFSPROC_FLAGS,Filesys_status
	JZ	GII_240
;;;;;;;;RestoreReg <SI,DS>			; IFS drive - devname ptr		 ;AC003;;AD022;
;	MOV	ES,DX				; target				 ;AC003;;AD022;
;	MOV	BX,AX									 ;AC003;;AD022;
;;;;;;;;transfer ifs_1000								 ;AC003;;AD022;
	JMP	GII_630 			; want user bx set
GII_240:					; NET drive:
	JMP	GII_640 			; go down to net device processing-
						; does the same thing
GII_280:
	INC	AX				; next drive
	JMP	GII_40
;----------------------------------------------------------------------------------------
;   device loop
;----------------------------------------------------------------------------------------
GII_400:					; Device loop
	CMP	AL,CS:[DFLCount]		; if run out of devices
	JB	GII_460
	JMP	GII_800 			;    go set no_more error
GII_460:
	SaveReg <BX,AX> 			; save ax-dfl count, bx-index
	LDS	SI,CS:[DFLAddr] 		; Point ds:si to correct DFL entry
	MOV	BL,SIZE DFLL_list		; size in convenient spot
	MUL	BL				; get net offset
	ADD	SI,AX				; convert to true pointer
	RestoreReg  <AX,BX>
	TEST	[SI.DFLL_FLAGS],DFL_INUSE	; is dfl active???
	JNZ	GII_480
	JMP	GII_680
GII_480:
	TEST	CS:IFSPROC_FLAGS,Filesys_Status ; check old vs. new style
	JNZ	GII_520
	CMP	[SI.DFLL_TYPE],TYPE_NET_DEVICE	; old style: check for type 3
	JE	GII_520
	JMP	GII_680 			; not type 4, go get next one
GII_520:
	SUB	BX,1
	JB	GII_540
	JMP	GII_680 			; next device
GII_540:
	MOV	WORD PTR CS:[THISDFL],SI	; set thisdfl = dssi
	PUSH	DS
	POP	WORD PTR CS:[THISDFL+2]
	RestoreReg  <DX,CX>			; get devname ptr into es:di,
	SaveReg <CX,DX> 			; (push back for end ds:si setup)
	SaveReg <ES,DI> 			;   while preserving es:di - target
	MOV	ES,CX
	MOV	DI,DX
	PUSH	SI				; save DFL offset
	ADD	SI,DFLL_DEV_NAME
	MOV	CX,8
GII_545:					; store device name in asciiz format
	LODSB
	CMP	AL," "
	JE	GII_550
	STOSB
	LOOP	GII_545
GII_550:
	XOR	AL,AL
	STOSB
	RestoreReg <SI,DI,ES>			; restore target ptr & DFL offset
	MOV	BL,[SI.DFLL_TYPE]
	XOR	BH,BH
	TEST	CS:IFSPROC_FLAGS,Filesys_Status
	JNZ	GII_555
	PUSH	[SI.DFLL_USER_WORD]
	POP	[USER_WORD]
	JMP	GII_560
GII_555:
	PUSH	DI				; ifs device; save target offset
	MOV	DI,ES:[DI]			; es:di -> FS name buffer
	invoke	GET_IFS_DRIVER_NAME
	POP	DI				; retrieve target offset from stack
	PUSH	DI
	INC	DI				; es:di -> parm buffer
	INC	DI
GII_560:
	SaveReg <ES,BX> 			; save target segment, type
						; now go to IFS to fill in rest of target
	invoke	PREP_IFSR			; init ifsr
	invoke	DFL_TO_DF			; DFL: sets [THISIFS]
						;	    ES:BX -> IFSRH
						;	    IFSR_DEVICE_CB@
						;	    ds - IFSSEG
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_ATTSTAT
	MOV	ES:[BX.IFSR_FUNCTION],IFSATTSTAT
	POP	AX				; type (BX)
	MOV	ES:[BX.IFSR_TYPE],AL
	POP	DX				; target segment (ES)
	TEST	CS:IFSPROC_FLAGS,Filesys_Status
	JNZ	GII_580
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	MOV	SI,OFFSET TEMPBUF
	MOV	WORD PTR ES:[BX.IFSR_PARMS@],SI
	MOV	WORD PTR ES:[BX.IFSR_PARMS@+2],DS
	PUSH	DI				; push tgt offset here for later pop
	JMP	GII_600
GII_580:
	MOV	WORD PTR ES:[BX.IFSR_PARMS@],DI
	MOV	WORD PTR ES:[BX.IFSR_PARMS@+2],DX
GII_600:
	PUSH	AX				; push type back (BX)
;***********************************************************************************************
	invoke	CALL_IFS			; call fs with attach status request
;***********************************************************************************************
	JNC	GII_620
	RestoreReg <BX,DI>			; type,target offset,devname ptr
	MOV	ES,DX				; target
	SaveReg <DI>				; put "ERROR" in parms display
	TEST	CS:IFSPROC_FLAGS,Filesys_status ; don't add  if net use
	JZ	GII_610
	ADD	DI,2
	MOV	AX,1
	STOSW
GII_610:
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	MOV	SI,OFFSET ERROR_STATUS
	MOV	CX,4
	REP	MOVSW
	RestoreReg <DI,SI,DS>
	transfer ifs_1000			; go to general ret in util
GII_620:
	RestoreReg <AX,DI>			; device type, target offset
	TEST	IFSPROC_FLAGS,Filesys_Status
	JZ	GII_640 			; IFS device:
GII_630:
	CallInstall Get_User_Stack,MULTdos,24,<AX>,<AX>
	MOV	AH,ES:[BX.IFSR_DEVICE_STATUS]
	MOV	[SI].USER_BX,AX
	RestoreReg <SI,DS>			; target offset,devname ptr
	MOV	ES,DX				; target
;;;;;;;;MOV	BX,AX									 ;AC003;;AD022;
	transfer ifs_1000
GII_640:					; NET device:
	CallInstall Get_User_Stack,multDOS,24,<AX>,<AX>
	PUSH	CS:[USER_WORD]
	POP	[SI].User_CX		; User Word
	PUSH	ES:[BX.IFSR_MAX_XMITT_SIZE]
	POP	[SI].User_DX		; Max Xmitt size
	PUSH	ES:[BX.IFSR_NET_NAME_ID]					      ;AC003/AC008/AC009
	PUSH	ES:[BX.IFSR_NET_NAME_ID] ; leave this on stack for later pop into ax
	POP	[SI].User_AX		; Net name ID					 ;AC003/AC008;
;;;;;;;;PUSH	AX									 ;AN008/AD009;

	MOV	CH,ES:[BX.IFSR_DEVICE_STATUS]
	MOV	CL,AL
	MOV	[SI].User_BX,CX 	; Bits and macro type
	TEST	CS:IFSPROC_FLAGS,SetBP
	JZ	GII_660
	PUSH	ES:[BX.IFSR_LSN]
	POP	[SI].User_BP		; LSN
GII_660:
	MOV	SI,ES:WORD PTR [BX.IFSR_PARMS@]
	MOV	DS,ES:WORD PTR [BX.IFSR_PARMS@+2]
	INC	SI				; ds:si -> parms returned by redir
	INC	SI
	MOV	ES,DX				; es:di -> input target buffer
	SaveReg <DI>				; save offset
	CallInstall StrCpy,MultDOS,17
	RestoreReg <DI,AX,SI,DS>		; tgt offset,netpath id,devname ptr	 ;AC003/AC008;
	transfer ifs_990
GII_680:
	INC	AX				; next drive
	JMP	GII_400
GII_800:					; end of CDSs & devices
						; now check deviceless attaches
;----------------------------------------------------------------------------------------
;   deviceless loop
;----------------------------------------------------------------------------------------
	CALL	GET_UNC_ITEM_INFO
	JC	GII_820
	RestoreReg <SI,DS>			; set dev ptr null
	MOV	BYTE PTR DS:[SI],ZERO
	transfer ifs_990
GII_820:
	MOV	AX,error_no_more_files
	RestoreReg <SI,DI>			; restore regs
	return
EndProc GET_IFSFUNC_ITEM
BREAK <ATTACH_START -- Attach drive/device to IFS>
;************************************************************************************
; ATTACH_START
; Called by: IFS_ASSOPER
; Routines called:  CALL_IFS		DOS: GetCDSFromDrv
;		    CDS_TO_CD
;		    CD_TO_CDS
;		    CREATE_DFL_ENTRY
;		    DELETE_DFL_ENTRY
;		    DFL_MATCH
;		    DFL_TO_DF
;		    DF_TO_DFL
;		    CALL_IFS
;		    FIND_IFS_DRIVER
;;; alias	    PROCESS_ALIAS
; Inputs:
;	    BL = Macro type
;;; alias      = 0 alias
;	       = 1 device/file
;	       = 2 drive
;	       = 3 Char device -> network
;	       = 4 File device -> network
;	    DS:SI -> ASCIIZ source name
;	    ES:DI -> Target driver to attach to and parms.
;			    DW ASCIIZ  -  asciiz name of driver
;			    DW n       -  number of parms
;			    DW ASCIIZ,... parms
;	    CX is reserved (user word for REDIR)
; Function:
;	     IF BL > 0 THEN
;		DO
;		  Check that IFS driver exists
;		  IF found, set IFS header to that found
;		  ELSE set error_file_system_not_found
;		ENDDO
;	     IF (BL=2 .OR. BL=4) & no error THEN
;		DO
;		  Find CDS for this drive
;		  IF none exists, then set error_invalid_parameter
;		  ELSE Call CDS_TO_CD
;		END
;	     ELSE DO
;		    IF source name not in DFL THEN
;			 Call CREATE_DFL_ENTRY
;		    ELSE  Set error_device_already_attached
;		    ENDIF
;		  ENDDO
;	     IF no error THEN
;		DO
;		  Prep IFSRH for Attach Start:
;		    *  IFSR_LENGTH	DW     34	; Request length
;		    *  IFSR_FUNCTION	DB	2	; Attach Start
;		       IFSR_RETCODE	DW	0
;		       IFSR_RETCLASS	DB	?
;		       IFSR_RESV1	DB     16 DUP(0)
;		    *  IFSR_TYPE	DB	?	; BL (0,1,2,3,or 4)
;		       IFSR_RESV2	DB	?	;
;		    *  IFSR_PARMS@	DD	PARMS	; See below
;		    *  IFSR_DEVICE_CB@	DD	?	; CD or DF (See below)
;		    *  IFSR_USER_WORD	DW	?	; for deviceless attach
;		    *  PARMS	       LABEL   WORD
;				       DW      PARMCOUNT ; Number of parms. May be 0.
;				       DB      ASCIIZ,...; Parms
;		ENDDO
;	       IF no error THEN
;		  DO
;		    CALL routine, CALL_IFS, with pointer to IFS header
;		    IF IFSR_RETCODE = 0 THEN
;		       DO
;			 IF DFL flag set THEN
;			    DO
;			      Call DF_TO_DFL
;			      Set DFLL_PTR to IFS header
;			    ENDDO
;			 ELSE DO
;				Call CD_TO_CDS
;				Set CDS_IFSR_PTR to IFS header
;			      ENDDO
;			 ENDIF
;			 Clear carry
;		       ENDDO
;		    ELSE DO
;			   IF DFL flag set THEN
;			      Call DELETE_DFL_ENTRY
;			   Set carry
;			 ENDDO
;		    ENDIF
;		  ENDDO
;	       ELSE  Set carry
;	       ENDIF
;************************************************************************************
	Procedure   ATTACH_START,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	ifsr_fcn_def  ATTSTART
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	POP	BX
	XOR	BH,BH				; not interested in bh, but should
						; be 0 since later move type as word
AS_10:
	CMP	BL,TYPE_DRIVE			; check ifs vs. network
	JLE	AS_20
	CMP	BL,TYPE_NET_DRIVE
	JLE	AS_30
AS_15:
	MOV	AX,error_invalid_function	; invalid fcn type
	transfer ifs_980			; go ret w/carry
AS_20:						; IFS device/drive
	SaveReg <ES,DI> 			; save target ptr for parms@
	MOV	DI,ES:[DI]			; set ES:DI -> driver name
	invoke	FIND_IFS_DRIVER 		; sets [THISIFS]
	JC	AS_25
	SaveReg <CX>				; save cx since next destroys
	invoke	SET_CATEGORY			; do this to determine unc or not
	OR	CL,CL				; cl=1 unc  else ifs
	RestoreReg <CX> 			; restore before branch - zf preserved
	JZ	AS_50				; jmp if not unc
	ADD	BL,2				; change type from 1/2 to 3/4
	RestoreReg <DI,ES>			; retrieve orig target ptr
;;;;;;;;OR	CS:IFSPROC_FLAGS,Filesys_Network_Attach 				 ;AN010;;AD017;
	CMP	WORD PTR ES:[DI+2],2		; if # parms=2 then have password
	JE	AS_22
	MOV	CX,0001H			; User word without password
	JMP	SHORT AS_23			; go process as unc
AS_22:
	MOV	CX,8001H			; User word with password
AS_23:
	ADD	DI,4				; skip over ifs name offset & #parms
	JMP	SHORT AS_33			; go process as unc

AS_25:						; ifs driver not found
	POP	DI				; error, restore stack and return
	POP	ES
	transfer ifs_1000
AS_30:						; NETWORK device/drive
	TEST	CS:IFSFUNC_FLAGS,UNC_INSTALLED	; check that unc installed
	JZ	AS_15
AS_33:						; this label for unc already checked
	OR	IFSPROC_FLAGS,IsNetwork 	; set network bit
	CMP	BL,TYPE_NET_DRIVE		; check pause status
	JNE	AS_35
	CMP	CS:fAssign,-1
	JMP	SHORT AS_37
AS_35:
	CMP	CS:fPrint,-1
AS_37:
	JE	AS_40				; bad pause status
	MOV	AX,72				; set error and ret w/carry
AS_38:
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	invoke	SET_EXTERR_INFO
	transfer ifs_980
AS_40:
	invoke	SET_THISIFS_UNC
	SaveReg <CX>
	invoke	NET_TRANS
	RestoreReg <CX>
	JNC	SHORT AS_55
	MOV	AX,error_path_not_found 	; net trans failure = path not found
	JMP	AS_38
AS_50:
	RestoreReg <DI,ES>			; restore target parm ptr
AS_55:
	OR	CS:IFSPROC_FLAGS,THISIFS_SET	; do this so wont do in CDS_TO_CD
						; or DFL_TO_DF
	CMP	BL,TYPE_DEVICE
	JNE	AS_55_0
	JMP	AS_200
AS_55_0:
	CMP	BL,TYPE_NET_DEVICE
	JNE	AS_55_1
	JMP	AS_200
AS_55_1:
	CMP	BL,TYPE_NET_DRIVE		; deviceless attach check
	JNE	AS_56				; jmp if no
	CMP	BYTE PTR [SI],0 		; DEVICELESS ATTACH
	JNZ	AS_56				;   Set dummy CDS and flag
	Context DS
	MOV	SI,OFFSET DOSGROUP:DummyCDS
	MOV	WORD PTR [THISCDS+2],DS
	MOV	WORD PTR [THISCDS],SI
	OR	IFSPROC_FLAGS,ISDUMMYCDS
	JMP	SHORT AS_100
AS_56:						; DRIVE ATTACH
	CMP	WORD PTR [SI+1],ICOLON		;   if 2nd char not ":" - error
	JE	AS_60				;   else - find CDS
AS_57:
	MOV	AX,error_invalid_drive
	transfer ifs_980
AS_60:
	LODSB
	Context DS				; get addressability to DOSGROUP
	OR	AL,20H
	SUB	AL,"a"                          ;   0=A,1=B,...
	CallInstall GetCDSFromDrv,multDOS,23,AX,AX
ASSUME	DS:NOTHING
	JC	AS_57				; no cds - error
	TEST	[SI.curdir_flags],curdir_inuse	; DS:SI -> CDS
	JZ	AS_100
	TEST	[SI.curdir_flags],curdir_isnet + curdir_splice + curdir_local
	JZ	AS_100
	MOV	AX,error_already_assigned	; error - CDS already assigned
	transfer ifs_980			; go return with carry
AS_100:
	SaveReg <DS,SI,ES,DI>	; save real cds and target parm ptr
				; If all goes OK this will be the "REAL" CDS
	Context ES
	MOV	DI,OFFSET DOSGROUP:DummyCDS
	SaveReg <DI,CX> 		; dummy cds offset, input user word
	MOV	CX,SIZE curdir_list
	REP	MOVSB
	RestoreReg <CX> 		; input user word
	PUSH	ES
	POP	DS
	POP	SI		; DS:SI -> dummy CDS
	MOV	[SI.curdir_flags],curdir_isnet + curdir_inuse
	MOV	AX,WORD PTR [THISIFS]		; set ifs ptr in cds
	MOV	DS:WORD PTR [SI.CURDIR_IFS_HDR],AX
	MOV	AX,WORD PTR [THISIFS+2]
	MOV	DS:WORD PTR [SI.CURDIR_IFS_HDR+2],AX
	MOV	DS:[SI.CURDIR_TYPE],BL		; set CDS type
	MOV	DS:[SI.CURDIR_USER_WORD],CX	; set CDS user word
	MOV	AX,CX
	RestoreReg <DX,CX>			; get target parm ptr off stack
	SaveReg <DS,SI,BX>			; save type and dummy cds ptr
	invoke	PREP_IFSR			; clear ifsrh
	invoke	CDS_TO_CD			; CDS: sets ES:BX -> IFSRH
						;	    IFSR_DEVICE_CB@
						;	    ds - IFSSEG
	OR	IFSPROC_FLAGS,ISCDS
	TEST	IFSPROC_FLAGS,ISDUMMYCDS
	JZ	AS_120
	MOV	ES:[BX.IFSR_USER_WORD],AX
AS_120:
	POP	AX				; restore type in AL
	MOV	ES:[BX.IFSR_TYPE],AL
	SaveReg <CX,DX> 			; put target parm ptr back on stack
	JMP	SHORT AS_400			; go prep IFSRH
AS_200: 					; DEVICE ATTACH:
	invoke	DFL_MATCH			; check if device already assigned
	JC	AS_220				; cf-0 match, cf-set no match
	MOV	AX,error_already_assigned
	transfer ifs_980			; go return with carry
AS_220:
	SaveReg <ES,DI,BX>			; save target parm ptr & type
	invoke	CREATE_DFL_ENTRY		; DFL: sets ES:BX -> IFSRH
						;	    IFSR_DEVICE_CB@
						;	    ds - IFSSEG
	JNC	AS_240
	RestoreReg <BX,DI,ES>			; restore stack
	invoke	CONSIST_SFT
	transfer ifs_980			;  error ret
AS_240:
	POP	AX				; restore type in AL			 ;AN000;moved ;AM019;
	MOV	ES:[BX.IFSR_TYPE],AL
AS_400: 						; prep IFSRH
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_ATTSTART
	MOV	ES:[BX.IFSR_FUNCTION],IFSATTSTART
	POP	AX					; old target DI
;;;;;;;;TEST	IFSPROC_FLAGS,Filesys_Network_Attach					 ;AN010;;AD017;
;	JZ	AS_405									 ;AN010;;AD017;
;	ADD	AX,4					; filesys-net  skip name offset  ;AN010;;AD017;
;;;;;;;;JMP	SHORT AS_410				; and # parms - just want net path;AN010;;AD017;
;AS_405:										 ;AN010;;AD017;
	TEST	IFSPROC_FLAGS,IsNetwork
	JNZ	AS_410
	INC	AX
	INC	AX
AS_410:
	MOV	ES:WORD PTR [BX.IFSR_PARMS@],AX
	POP	AX					; old target ES
	MOV	ES:WORD PTR [BX.IFSR_PARMS@+2],AX

;***********************************************************************************************
	invoke	CALL_IFS
;***********************************************************************************************

	JNC	AS_440
	TEST	IFSPROC_FLAGS,ISCDS			; ifs error:
	JZ	AS_420
	RestoreReg <DS,SI,DS,SI>			; pop dummy & real cds
	transfer ifs_980
AS_420:
	SaveReg <AX>					; preserve error code
	invoke	DELETE_DFL_ENTRY
	invoke	CONSIST_SFT
	RestoreReg <AX>
	transfer ifs_980
AS_440: 						; successful attach
	TEST	IFSPROC_FLAGS,ISCDS
	JZ	AS_460
	RestoreReg <DI,ES>				; restore ES:DI -> dummy cds
	invoke	CD_TO_CDS
	RestoreReg <SI,DS>				; ds:si - real cds
	invoke	XCHGP
	MOV	CX,SIZE CURDIR_LIST
	OR	DS:[SI.CURDIR_FLAGS],CURDIR_ISIFS	; make sure this flag set
	REP	MOVSB
	transfer ifs_990
AS_460:
	invoke	DF_TO_DFL
	invoke	CONSIST_SFT
	transfer ifs_990
EndProc ATTACH_START
BREAK <ATTACH_END -- break attachment>
;************************************************************************************
; ATTACH_END
; Called by: IFS_ASSOPER
; Routines called:  DFL_MATCH	      DOS: StrCpy
;		    DFL_TO_DF		   DriveFromText
;		    DF_TO_DFL		   GetThisDrv
;		    CDS_TO_CD		   InitCDS
;		    CD_TO_CDS
;		    SET_EXTERR_INFO
;		    CALL_IFS
;		    DELETE_DFL_ENTRY
; Inputs:
;	    DS:SI -> ASCIZ source name
; Function:
;	     Prep IFSRH:
;	     *	IFSR_LENGTH	 DW	30	 ; Request length
;	     *	IFSR_FUNCTION	 DB	 4	 ; End Attach
;		IFSR_RETCODE	 DW	 ?
;		IFSR_RETCLASS	 DB	 ?
;		IFSR_RESV1	 DB	16 DUP(0)
;	     *	IFSR_DEVICE_CB@  DD	 ?	 ; CD or DF
;	     *	IFSR_NAME@	 DD	 ?	 ; for deviceless detach (unc)
;************************************************************************************
	Procedure   ATTACH_END,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	ifsr_fcn_def  ATTEND
	POP	BX
	MOV	CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	MOV	CS:IFSPROC_FLAGS,0
	invoke	PREP_IFSR
	PUSH	DS
	POP	ES
	MOV	DI,SI				; ES:DI=DS:SI=source name
	PUSH	SI				; Save SI
	CallInstall StrCpy,multDOS,17		; "Beautify" input string
						;   (converts to uppercase &
						;     / to \)
	POP	SI				; Recover string pointer
	CMP	WORD PTR [SI],"\\"              ; Special Case -
	JZ	AE_300				;	   deviceless detach
	CMP	WORD PTR [SI+1],":"             ; check for drive
	JNZ	AE_200				; no, go to device check
	CMP	fAssign,-1			; BREAK DRIVE ATTACH
	JZ	AE_20
AE_10:
	MOV	AX,72				; pause error
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	invoke	SET_EXTERR_INFO
	transfer ifs_980
AE_20:
	CallInstall DriveFromText,multDOS,26	; AL = drive # (0-not drive
	context DS				;      -1=a,1=b,2=c,...)
	CallInstall GetThisDrv,multDOS,25,AX,BX ; ES:DI->CDS
	JNC	AE_40
	MOV	AX,error_invalid_drive
	transfer ifs_1000
AE_40:
	LES	DI,[THISCDS]
	TEST	ES:[DI.curdir_flags],curdir_isnet
	JNZ	AE_60
	MOV	AX,error_invalid_drive		; not redirected
	transfer ifs_980
AE_60:
	PUSH	AX				; drive #
	PUSH	ES
	POP	DS
	MOV	SI,DI				; move cds ptr to ds:si
	invoke	CDS_TO_CD
	OR	IFSPROC_FLAGS,ISCDS
	JMP	SHORT AE_400
AE_200: 					; BREAK DEVICE ATTACH
	CMP	fPrint,-1			; check for pause error
	JZ	AE_210
	JMP	AE_10
AE_210:
	CALL	DFL_MATCH
	JNC	AE_220
	MOV	AX,device_not_attached
	transfer ifs_1000
AE_220:
	MOV	SI,WORD PTR [THISDFL]
	MOV	DS,WORD PTR [THISDFL+2]
	TEST	DS:[SI.DFLL_FLAGS],DFL_DEV_REAL
;	???????????? check with baf on what reverting to ...
	invoke	DFL_TO_DF			; DFL: sets [THISIFS]
						;	    ES:BX -> IFSRH
						;	    IFSR_DEVICE_CB@
						;	    ds - IFSSEG
	JMP	SHORT AE_400
AE_300: 					; deviceless detach
	SaveReg <CS>				;  restore es to ifsr & set seq flag
	RestoreReg <ES>
	OR	CS:IFSPROC_FLAGS,IsSeq
	CMP	fAssign,-1
	JZ	AE_320
	JMP	AE_10				; jump to pause error
AE_320:
	SaveReg <ES,BX,DS>			; ifsr ptr
	RestoreReg <ES> 			; set esdi = dssi = net path
ASSUME	ES:NOTHING
	MOV	DI,SI
	invoke	NET_TRANS
	SaveReg <ES>
	RestoreReg <AX> 			; name string segment
	MOV	SI,DI				; name string offset
	RestoreReg <BX,ES>			; ifsr pointer
ASSUME	ES:IFSSEG
	MOV	WORD PTR ES:[BX.IFSR_NAME@],DI
	MOV	WORD PTR ES:[BX.IFSR_NAME@+2],AX
	SaveReg <CS>
	RestoreReg <DS>
ASSUME	DS:IFSSEG
AE_400: 					; call ifs
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_ATTEND
	MOV	ES:[BX.IFSR_FUNCTION],IFSATTEND
;***********************************************************************************************
	invoke	CALL_IFS
;***********************************************************************************************
	JNC	AE_410
	TEST	IFSPROC_FLAGS,ISCDS		; att end error:
	JZ	AE_405
	ADD	SP,2				; clear ax (drive #) off stack
AE_405:
	transfer ifs_980
AE_410:
	TEST	CS:IFSPROC_FLAGS,ISCDS
	JZ	AE_420
	POP	AX				; drive
	ADD	AL,'A'
	CallInstall InitCDS,multDOS,31,AX,AX
	transfer ifs_990
AE_420:
	TEST	CS:IFSPROC_FLAGS,IsSeq
	JNZ	AE_440
	CALL	DELETE_DFL_ENTRY
AE_440:
	transfer ifs_990
EndProc ATTACH_END

BREAK <IFS_RESET_ENVIRONMENT -- reset IFS environment>

;***********************************************************************************
;
; IFS_RESET_ENVIRONMENT
;
; Called by:	   IFSFUNC Dispatcher
;
; Routines called:
;	jumps into ifs_abort
;
; Inputs:
;	[CurrentPDB] set to PID of process aborting
;
; Function:
;	Get address of IFS driver chain.
;	FOR I = 1 to last IFS driver
;	    Send request below to IFS driver
;
;	IFSRH:
;	*  IFSR_LENGTH	    DW	   42	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DW	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   16 DUP(0)
;	*  IFSR_APIFUNC     DB	   18	    ; End of Process
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	   IFSR_ALLOWED     DB	    ?
;	   IFSR_I24_RETRY   DB	    ?
;	   IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	   IFSR_DEVICE_CB@  DD	    ?	    ; CD
;	   IFSR_OPEN_CB@    DD	    ?
;	*  IFSR_PID	    DW	    ?	    ; process ID
;	*  IFSR_SUBFUNC     DB	    2	    ; 0=normal exit  1=abort exit
;					    ; 2=reset environment
;	   IFSR_RESV3	    DB	    ?
;
;	Call all IFSs with this info.
;	Scan through SFTFCB
;	IF (ref_count ^= 0 .AND. ^busy .AND. isifs .AND. SF_PID = currentPDB) THEN
;	   Call SF_IFS_HDR with close request
;	ENDIF
;
; Outputs: None
; DS Preserved, All others destroyed
;
;************************************************************************************

	procedure   IFS_RESET_ENVIRONMENT,NEAR
ASSUME	DS:DOSGROUP,ES:NOTHING

	ifsr_fcn_def EXECAPI
	ifsr_api_def EOP

	MOV	CS:IFSPROC_FLAGS,IsResetEnvirn
	Context DS				; make sure ds=ss=dosgroup
	JMP	IA_70

EndProc IFS_RESET_ENVIRONMENT


BREAK <IFS_ABORT -- Send CLOSE all files for process>
;************************************************************************************
;
; IFS_ABORT
;
; Called by:	   IFSFUNC Dispatcher
;
; Routines called:
;	CALL_IFS
;	IFS_CLOSE
;
; Inputs:
;	[CurrentPDB] set to PID of process aborting
;
; Function:
;	Get address of IFS driver chain.
;	FOR I = 1 to last IFS driver
;	    Send request below to IFS driver
;
;	IFSRH:
;	*  IFSR_LENGTH	    DW	   42	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DW	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   16 DUP(0)
;	*  IFSR_APIFUNC     DB	   18	    ; End of Process
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	   IFSR_ALLOWED     DB	    ?
;	   IFSR_I24_RETRY   DB	    ?
;	   IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	   IFSR_DEVICE_CB@  DD	    ?	    ; CD
;	   IFSR_OPEN_CB@    DD	    ?
;	*  IFSR_PID	    DW	    ?	    ; process ID
;	*  IFSR_SUBFUNC     DB	    ?	    ; 0=normal exit  1=abort exit
;					    ; 2=reset environment
;	   IFSR_RESV3	    DB	    ?
;
;	Call all IFSs with this info.
;	Scan through SFTFCB
;	IF (ref_count ^= 0 .AND. ^busy .AND. isifs .AND. SF_PID = currentPDB) THEN
;	   Call SF_IFS_HDR with close request
;	ENDIF
;
; Outputs: None
; DS Preserved, All others destroyed
;
;************************************************************************************

	procedure   IFS_ABORT,NEAR
ASSUME	DS:DOSGROUP,ES:NOTHING
	ifsr_fcn_def EXECAPI
	ifsr_api_def EOP

	MOV	CS:IFSPROC_FLAGS,ZERO
;   Scan the FCB Cache and close any NET FCBs
;   belonging to this process. The reason we must do this is that
;   NET FCBs are well behaved and must be closed on EXIT.
	LES	DI,[SFTFCB]
	MOV	CX,ES:[DI].sfCount
	LEA	DI,[DI].sfTable
	JCXZ	IA_70
IA_20:					; Loop through sftfcb's
	CMP	ES:[DI].sf_ref_count,0
	JZ	IA_60			; Ignore Free ones
	CMP	ES:[DI].sf_ref_count,sf_busy
	JZ	IA_60			; Ignore busy ones
	TEST	ES:[DI].sf_flags,sf_isnet
	JZ	IA_60			; Ignore non NET ones
	MOV	AX,[CurrentPDB]
	CMP	AX,ES:[DI].sf_PID
	JNZ	IA_60			; Ignore FCBs not for this proc
	MOV	WORD PTR [THISSFT],DI
	MOV	WORD PTR [THISSFT+2],ES
	PUSH	CX
IA_40:					; CLOSE
	invoke	IFS_CLOSE		; IGNORE ANY ERRORS ON THIS.
	CMP	ES:[DI].sf_ref_count,0	; Make sure it gets closed
	JNE	IA_40			; Loop until closed
	POP	CX
IA_60:
	ADD	DI,size sf_entry
	LOOP	IA_20
; Now loop through all ifs drivers with end of process request
IA_70:
	LDS	SI,IFS_HEADER
ASSUME	DS:NOTHING
	JMP	SHORT IA_100		; go check if null
IA_80:
	MOV	CS:WORD PTR [THISIFS],SI	; Send end of process request
	MOV	CS:WORD PTR [THISIFS+2],DS	; to all fs drivers.
	invoke	PREP_IFSR			; sets esbx -> ifsrh
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_EOP
	MOV	ES:[BX.IFSR_FUNCTION],IFSEXECAPI
	MOV	ES:[BX.IFSR_APIFUNC],IFSEOP
	MOV	AX,[CurrentPDB]
	MOV	ES:[BX.IFSR_PID],AX		 ; ?????
	MOV	AL,[EXIT_TYPE]
	MOV	ES:[BX.IFSR_SUBFUNC],AL
	TEST	CS:IFSPROC_FLAGS,IsResetEnvirn
	JZ	IA_90
	MOV	ES:[BX.IFSR_SUBFUNC],RESET_ENVIRONMENT
IA_90:
	SaveReg <DS,SI,CS>			; dssi - ifs driver
	RestoreReg <DS> 			; ds - ifsseg
;***********************************************************************************************
	invoke	CALL_IFS
;***********************************************************************************************
	RestoreReg <SI,DS>			; dssi - ifs driver
	LDS	SI,[SI.IFS_NEXT]		; check next fs driver
IA_100:
	CMP	SI,NULL_PTR			; if ptr null, no more
	JNE	IA_80
	PUSH	DS
	POP	AX
	CMP	AX,NULL_PTR
	JNE	IA_80
IA_1000:
	SaveReg <SS>				; dosgroup
	RestoreReg <DS>
	return				;????????? may need redir ioctl to
					; consist_refs
EndProc IFS_ABORT
BREAK <GET_IFS_DRIVER_NAME -- get IFS driver name>
;************************************************************************************
; GET_IFS_DRIVER_NAME
; Called by: GET_IFSFUNC_ITEM
; Routines called:
; Inputs:
;	    DS:SI -> CDS/DFL
;	    ES:DI =  buffer to place name
; Function:
;	Find FS name in IFS header pointed to by CDS or DFL
;	Place name in buffer pointed to by ES:DI
; Output:
;	buffer filled, hopefully with ifs name
;	pointer not checked for valid ifs driver hdr ptr
; Regs: all preserved
;************************************************************************************
	Procedure   GET_IFS_DRIVER_NAME,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <DS,SI,CX,DI>			; preserve cds/dfl ptr, cx, buffer
						; offset
	TEST	CS:IFSPROC_FLAGS,ISCDS		; get ifs hdr ptr from
	JZ	GIDN_20
	LDS	SI,[SI.CURDIR_IFS_HDR]		; cds
	JMP	GIDN_40
GIDN_20:
	LDS	SI,[SI.DFLL_IFS_HDR]		; dfl
GIDN_40:
	invoke	MOVE_DRIVER_NAME		; move ifs driver name into buffer
	RestoreReg <DI,CX,SI,DS>		; restore cds/dfl ptr, cx, buffer
						; offset
	return
EndProc GET_IFS_DRIVER_NAME
BREAK <FIND_IFS_DRIVER -- get IFS driver>
;************************************************************************************
;
; FIND_IFS_DRIVER
;
; Called by:		ATTACH_START
;
; Routines called:	CHECK_END_SPACE
;
; Inputs:
;	    ES:DI -> IFS driver name
; Function:
;	Loop through IFS driver chain until name match.
;	If match found - set [THISIFS] and clear carry
;	Else set carry.
; Output:
;	carry clear - match found,[THISIFS] set
;	carry set   - no match found
;
; Regs: all but ax preserved
;
;************************************************************************************
	Procedure   FIND_IFS_DRIVER
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <DS,SI,BX,ES,DI>		; save registers  (except ax for error)
	TEST	CS:IFSFUNC_FLAGS,NO_IFS_DRIVERS ; check for no drivers first
	JZ	FID_10
	JMP	FID_30
FID_10:

	SaveReg <SS>				; get addressability to dosgroup
	RestoreReg <DS> 			;  to get ifs driver chain
	LDS	SI,IFS_HEADER
ASSUME	DS:NOTHING				; ds:si -> 1st ifs driver
FID_20:
	SaveReg <DS,SI,ES,DI,CS>		; save ds,si,es,di
	RestoreReg <ES> 			; set es=cs
ASSUME	ES:IFSSEG
	MOV	DI,OFFSET TEMPBUF		; move ifs driver name into tempbuf
	SaveReg <SI,DI> 			; so that can be asciiz form before
	invoke	MOVE_DRIVER_NAME		; strcmp
	RestoreReg <SI,DI>			; dssi -> tempbuf (ifs driver asciiz
	SaveReg <ES>				; name)
	RestoreReg <DS,DI,ES>			; esdi -> ifs driver name (input)
	CALL	CHECK_END_SPACE 		; make sure ^ has no blanks

	CallInstall StrCmp,multDOS,30		; check for match (regs preserved)
	RestoreReg <SI,DS>			; (ifs driver)
	JZ	FID_40				; if match, go set thisifs & return
	LDS	SI,[SI.IFS_NEXT]		; else check next fs driver
	CMP	SI,MINUS_ONE			; if ptr null, no more = error
	JNE	FID_20
	PUSH	DS
	POP	AX
	CMP	AX,MINUS_ONE
	JNE	FID_20
FID_30:
	MOV	AX,fs_driver_not_found
	JMP	SHORT FID_980
FID_40:
	MOV	WORD PTR CS:[THISIFS],SI	    ; match.  Set [THISIFS] to this
	MOV	WORD PTR CS:[THISIFS+2],DS	    ; driver
	JMP	FID_990
FID_980:					; Return area
	STC
	JMP	SHORT FID_1000
FID_990:
	CLC
FID_1000:
	RestoreReg <DI,ES,BX,SI,DS>		; restore registers
	return
EndProc FIND_IFS_DRIVER
BREAK <ASSIGN_MODE_FUNCTIONS -- drive/print on/off>
;************************************************************************************
; AssignOn/AssignOff
; Called by: SET_ASSIGN_MODE
; AssignOn and AssignOFF copied from Network Redirector code
; PrintOn and PrintOff IFSFUNC new code
; Inputs:
; Function:
; Output:
; Regs: none preserved
;************************************************************************************
Procedure AssignOn,Near
ASSUME ES:NOTHING, DS:NOTHING
	EnterCrit CritNet
	CMP	fAssign,-1		;   if (fAssign)
	JZ	CrLvA			;	return;
	MOV	fAssign,-1		;   fAssign = TRUE;
	LDS	SI,CDSAlt		;   s = CDSAlt;
	LES	DI,CDSAddr		;   d = CDSAddr;
	MOV	AL,CDSCount
	MOV	DX,SIZE curdir_list
OnLoop:
	TEST	[SI].curdir_flags,curdir_isnet
	JNZ	RestCDS 		; Restore this NET guy
	ADD	SI,DX			; Skip to next CDS
	ADD	DI,DX
NextCDS:
	DEC	AL
	JNZ	OnLoop
CrLvA:
	LeaveCrit CritNet
	return
RestCDS:
	MOV	CX,DX
	REP	MOVSB			;   strcpy (d, s);
	JMP	NextCDS
EndProc AssignOn
Procedure AssignOff,Near
	ASSUME	ES:NOTHING, DS:NOTHING
	EnterCrit CritNet
	CMP	fAssign,0		;   if (!fAssign)
	JZ	CrLvB			;	return;
	LES	DI,CDSAlt		;   d = CDSAlt;
	LDS	SI,CDSAddr		;   s = CDSAddr;
	MOV	AL,CDSCount
	CBW				; always less or = 26
	MOV	CX,SIZE curdir_list
	MUL	CX
	MOV	CX,AX
	REP	MOVSB			;   Save current CDS state
	XOR	AL,AL
OffLoop:				;   for (i=0; p1=getcds(i); i++)
	CallInstall GetCDSFromDrv,multDOS,23,AX,AX  ; Set THISCDS for possible
					;	call to InitCDS
	JC	OffDone 		;
	TEST	[SI].curdir_flags,curdir_isnet
	JZ	OffInc
	SaveReg <AX>
	ADD	AX,'A'
	CallInstall InitCDS,multDOS,31,AX,AX ;	     initcds (p1);
	RestoreReg  <AX>
OffInc: INC	AL
	JMP	OffLoop
OffDone:
	MOV	fAssign,0		;   fAssign = FALSE;
CrLvB:
	LeaveCrit CritNet
	return
EndProc AssignOff
;******************************************************************************
; PrintOn/PrintOff
; Called by: SET_ASSIGN_MODE
; Routines called:  CALL_IFS
; Inputs:
; Function:
;	Print on - loop through dfl entries resetting pause flag to zero
;	Print off- loop through dfl entries, set pause flag if unc
;	Prep IFSRH:
;	*  IFSR_LENGTH	    DW	   48	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DB	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   17 DUP(0)
;	*  IFSR_APIFUNC     DB	   16	    ; IFS dependent IOCTL
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	   IFSR_ALLOWED     DB	    ?
;	   IFSR_I24_RETRY   DB	    ?
;	   IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	   IFSR_DEVICE_CB@  DD	    ?
;	   IFSR_OPEN_CB@    DD	    ?
;	*  IFSR_FUNC	    DB	    0	    ; 0 generic ioctl
;	   IFSR_RESV2	    DB	    0
;	*  IFSR_BUFFER@     DD	    ?	    ; al-2 es:di, else ds:dx
;	*  IFSR_BUFSIZE     DW	    ?	    ; al-2 cx, else ???
;	*  IFSR_CATEGORY    DB	    1	    ; 1 for UNC
;	*  IFSR_CTLFUNC     DB	    ?	    ; x - print on, y - print off
;	CALL routine, CALL_IFS, with pointer to IFS header
;   Outputs: none
;   Regs: nothing preserved
;******************************************************************************
Procedure PrintOn,Near
	ASSUME DS:NOTHING, ES:NOTHING
	EnterCrit CritNet
	CMP	fPrint,-1			;   if (fPrint)
	JNE	PON_20
	JMP	POF_1000			;	return;
PON_20:
	MOV	fPrint,-1			;   fPrint = TRUE;
	MOV	CS:IFSPROC_FLAGS,PRINT_ON
	JMP	POF_20				; finish in printoff routine
EndProc PrintOn
Procedure   PrintOff,NEAR
	ASSUME DS:NOTHING, ES:NOTHING
	EnterCrit CritNet
	CMP	fPrint,0			; quit if already off
	JZ	POF_1000			;	return
	MOV	fPrint,0			; set off
	MOV	CS:IFSPROC_FLAGS,ZERO		; init processing flags
POF_20: 					; (welcome print on)
	PUSH	CS				; get addressability to IFSSEG
	POP	DS
ASSUME	DS:IFSSEG,ES:NOTHING
	MOV	CL,[DFLCount]			; Prep loop through DFL list
	XOR	CH,CH				; For all unc devices, set pause
	XOR	DH,DH				; flag
	MOV	DL,SIZE DFLL_LIST
	LDS	SI,[DFLAddr]
POF_40: 					; *** loop on setting pause flag
	TEST	IFSPROC_FLAGS,PRINT_ON		;     on print on, just reset all
	JNZ	POF_50
	LES	DI,DS:[SI.DFLL_IFS_HDR]		;     only set pause on unc devices
	OR	DI,DI				; make sure this dfl taken
	JNZ	POF_45
	SaveReg <AX,ES>
	RestoreReg <AX>
	OR	AX,AX
	RestoreReg <AX>
	JZ	POF_60
POF_45:
	TEST	ES:[DI.IFS_ATTRIBUTE],IFSUNC
	JZ	POF_60
	OR	DS:[SI.DFLL_FLAGS],DFL_PAUSED
	JMP	SHORT POF_60
POF_50:
	AND	DS:[SI.DFLL_FLAGS],NOT DFL_PAUSED
POF_60:
	ADD	SI,DX				; prep for next dfl
	LOOP	POF_40				; go process next dfl
						; now go tell unc, device pause
						; is in effect
	invoke	PREP_IFSR			; init ifsr
	ifsr_fcn_def	EXECAPI 		; define ifsr for dep ioctl
	ifsr_api_def	DEPIOCTL
	invoke	SET_DEPIOCTL_IFSR
	TEST	IFSPROC_FLAGS,PRINT_ON
	JZ	POF_80
	MOV	ES:[BX.IFSR_CTLFUNC],CTLFUNC_PRINT_ON
	JMP	SHORT POF_100
POF_80:
	MOV	ES:[BX.IFSR_CTLFUNC],CTLFUNC_PRINT_OFF
POF_100:
	MOV	ES:[BX.IFSR_CATEGORY],1
	invoke	SET_THISIFS_UNC

;***********************************************************************************************
	invoke	CALL_IFS			; call ifs driver w/request
;***********************************************************************************************

	invoke	CONSIST_SFT
POF_1000:
	LeaveCrit CritNet
	return
EndProc PrintOff
BREAK <GET_UNC_ITEM_INFO  -- resv bits, net name id, user word, max xmitt sz>

;******************************************************************************
;
; GET_UNC_ITEM_INFO
;
; Called by:  GET_IFSFUNC_ITEM
;
; Routines called:  CALL_IFS
;
; Inputs:
;	    BL = redirection index
;	    ES:DI -> Target buffer:  old - net path string			   ;AN00
;				     new - dw file system driver name
;					   dw # parms
;					   db parms
;
; Function:
;
;	Prep IFSRH:
;	*  IFSR_LENGTH	    DW	   48	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DB	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   17 DUP(0)
;	*  IFSR_APIFUNC     DB	   16	    ; IFS dependent IOCTL
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	   IFSR_ALLOWED     DB	    ?
;	   IFSR_I24_RETRY   DB	    ?
;	   IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	   IFSR_DEVICE_CB@  DD	    ?
;	   IFSR_OPEN_CB@    DD	    ?
;	*  IFSR_FUNC	    DB	    0	    ; 0 generic ioctl
;	   IFSR_RESV2	    DB	    0
;	*  IFSR_BUFFER@     DD	    ?	    ; unc item info buffer
;	   IFSR_BUFSIZE     DW	    10
;	*  IFSR_CATEGORY    DB	    1	    ; 1 for UNC
;	*  IFSR_CTLFUNC     DB	    ?	    ; 4 - get unc item
;
;	buffer:  dw	index  (bx)
;		 dw	user word
;		 dw	max xmitt size
;		 dw	net name ID
;		 dw	lower 8 bits lsn from ncb_list
;		 db	redir reserved bits
;		 db	net path...(asciiz)
;
;
;	CALL routine, CALL_IFS, with pointer to IFS header
;
;   Outputs: user stack contains info
;		cx - user word
;		bx - bits and macro type
;		dx - max xmitt size
;		ax - net name id
;		bp - lsn (if specified)
;
;   Regs: nothing preserved
;
;******************************************************************************
	Procedure   GET_UNC_ITEM_INFO,NEAR
	TEST	CS:IFSFUNC_FLAGS,UNC_INSTALLED
	JNZ	GUI_05
	transfer ifs_980

GUI_05:
	SaveReg <ES,DI,BX>			; target ptr and index
	invoke	PREP_IFSR			; init ifsr
	SaveReg <CS>				; prep ds for call ifs call
	RestoreReg <DS>
ASSUME	DS:IFSSEG
	invoke	SET_DEPIOCTL_IFSR		; prep IFSRH
	invoke	SET_THISIFS_UNC 		; prep IFSRH
	MOV	ES:[BX.IFSR_CATEGORY],1
	MOV	ES:[BX.IFSR_CTLFUNC],CTLFUNC_GET_UNC_ITEM
	MOV	SI,OFFSET TEMPBUF
	MOV	WORD PTR ES:[BX.IFSR_BUFFER@],SI
	MOV	WORD PTR ES:[BX.IFSR_BUFFER@+2],DS
	RestoreReg <AX> 			; index
	MOV	WORD PTR DS:[SI],AX

;***********************************************************************************************
	invoke	CALL_IFS			; call redir w/get unc item request
;***********************************************************************************************

	JNC	GUI_10
	RestoreReg <DI,ES>
	return
GUI_10:
	MOV	SI,WORD PTR ES:[BX.IFSR_BUFFER@]
	MOV	DS,WORD PTR ES:[BX.IFSR_BUFFER@+2]
	SaveReg <SI>
	ADD	SI,2				; space to user word (skip index)
	LODSW					; user word
	MOV	CX,AX
	LODSW					; max xmitt size
	MOV	DX,AX
	LODSW					; net name id
	PUSH	AX
	LODSW					; lsn
	MOV	BP,AX
	LODSB					; redir bits
	MOV	BH,AL
	MOV	BL,4
	POP	AX				; net name id
	SaveReg <DS,SI>
	CallInstall Get_User_Stack,multDOS,24,<AX>,<AX>
	MOV	[SI].User_CX,CX 	; User Word
	MOV	[SI].User_BX,BX 	; Bits and macro type
	MOV	[SI].User_DX,DX 	; Max Xmitt size
	MOV	[SI].User_AX,AX 	; Net name ID
	TEST	CS:IFSPROC_FLAGS,SetBP
	JZ	GUI_15
	MOV	[SI].User_BP,BP 	; LSN
GUI_15:
	RestoreReg <SI,DS>
	TEST	IFSPROC_FLAGS,Filesys_status
	JNZ	GUI_20
	ADD	SP,2			; old si
	RestoreReg <DI,ES>		; buffer/target ptr	(dssi - 18)
	SaveReg <AX,DI>
	JMP	SHORT GUI_40
GUI_20: 				; new style
	RestoreReg <SI> 		; offset path
	ADD	SI,11
	RestoreReg <DI,ES>		; target - dw fsname
					;	   dw # parms
					;	   db asciiz,...
	SaveReg <DI>
	MOV	DI,ES:[DI]
	invoke	GET_UNC_FS_NAME
	RestoreReg <DI>
	SaveReg <AX,DI>
	INC	DI
	INC	DI
	MOV	WORD PTR ES:[DI],1
	INC	DI
	INC	DI
GUI_40:
	CallInstall StrCpy,MultDOS,17
	RestoreReg <DI>
;;;;;;;;TEST	CS:IFSPROC_FLAGS,FILESYS_STATUS 					 ;AN008;;AD018;
;;;;;;;;JZ	GUI_1000								 ;AN008;;AD018;
	RestoreReg <AX>

GUI_1000:
	return
EndProc GET_UNC_ITEM_INFO

BREAK <CHECK_END_SPACE -- check esdi string for blanks>
;************************************************************************************
; CHECK_END_SPACE
; Called by:		FIND_IFS_DRIVER
; Routines called:
; Inputs:
;	    ES:DI -> IFS driver name
; Function:
;	Replace any blanks in asciiz ifs driver name with 0's.
; Output:
;	none
; Regs: all preserved
;************************************************************************************
	Procedure   CHECK_END_SPACE
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <AX,DS,SI,ES>			; save registers
	RestoreReg <DS> 			; set dssi -> asciiz ifs name
	MOV	SI,DI
	CLD					; clear dir flag to count forward
CES_20: 					; search LOOP
	LODSB					; put char in al
	OR	AL,AL				; check for end of string
	JZ	CES_1000			; if so go quit
	CMP	AL," "                          ; check for blank
	JNE	CES_20				; cont loop if not
	MOV	BYTE PTR DS:[SI-1],0		; replace blank with zero
CES_1000:
	RestoreReg <SI,DS,AX>			; restore registers
	return
EndProc CHECK_END_SPACE

IFSSEG	ENDS
    END
