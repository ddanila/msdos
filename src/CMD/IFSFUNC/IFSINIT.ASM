	PAGE	,132			; 
TITLE	IFSFUNC INITIALIZATION ROUTINES - Routines for ifs
NAME	IFSINIT
;***********************************************************************************
; IFS Initialization Routines
; IFSINIT
.xlist
.xcref
INCLUDE IFSFSYM.INC
INCLUDE IFSSYM.INC
INCLUDE DOSSYM.INC
INCLUDE DEVSYM.INC
include sysmsg.inc
msg_utilname <IFSFUNC>			; resident msgret stuff
.cref
.list
.sall
AsmVars <IBM, INSTALLED, DEBUG, PATHGEN>
IFSSEG	SEGMENT BYTE PUBLIC 'IFSSEG'
IFSSEG	ENDS
include dosseg.asm
DATA		SEGMENT WORD PUBLIC 'DATA'
	; DOSGROUP data
	extrn	DataVersion:WORD	; version number of DOS data.
	extrn	SFTFCB:DWORD		; FCB SFT cache
	extrn	KeepCount:WORD		; FCB SFT cache
	Extrn	CDSAddr:DWORD
	Extrn	CDSCount:BYTE
	Extrn	DummyCDS:BYTE
	Extrn	CritPatch:WORD
DATA		ENDS
IFSSEG	SEGMENT BYTE PUBLIC 'IFSSEG'
	ASSUME	SS:DOSGROUP,CS:IFSSEG
	;IFS Data
	Extrn	CDSAlt:DWORD
	Extrn	DFLAddr:DWORD
	Extrn	DFLCount:BYTE
;;;aliasExtrn	NLAddr:DWORD
;;;aliasExtrn	NLSIZE:WORD
	Extrn	INT_2F_5:BYTE
	Extrn	NEXT_2F_5:DWORD
	Extrn	IFSR:WORD
	Extrn	CD1:WORD
	Extrn	DF1:WORD
	Extrn	SFF1:WORD
	Extrn	THISIFS:DWORD
	Extrn	IFSPROC_FLAGS:WORD
	Extrn	IFSFUNC_FLAGS:WORD
	Extrn	UNC_FS_HDR:DWORD
	Extrn	DEVICE_CB@_OFFSET:WORD
	Extrn	IFS_ATTRS:WORD
	Extrn	RODS_LABEL:BYTE
	Extrn	IFSSEM:BYTE
	PUBLIC	CODESIZE
CODESIZE	DB	'RMG'
		DB	30H
		DB	30H
		DB	30H
		DB	30H
		DB	30H
		DB	20H
	PUBLIC	TOTSIZE
TOTSIZE 	DB	30H
		DB	30H
		DB	30H
		DB	30H
		DB	30H
		DB	20H
Break	<INT 2F handler>
IF	DEBUG
Procedure   NetPointers,NEAR
	ASSUME	CS:IFSSEG,DS:NOTHING,ES:NOTHING,SS:NOTHING
	LDS	SI,[DFLAddr]
;;;aliasLES	DI,[NLAddr]
	return
EndProc NetPointers
Procedure   NetPointers2,NEAR
	ASSUME	CS:IFSSEG,DS:NOTHING,ES:NOTHING,SS:NOTHING
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	MOV	CX,[DFLCount]
;;;aliasMOV	DX,[NLSIZE]
	return
EndProc NetPointers2
ENDIF
IF	PATHGEN
Procedure   GetIFSFCSinES,NEAR
	ASSUME	CS:IFSSEG,DS:NOTHING,ES:NOTHING,SS:NOTHING
	PUSH	CS
	POP	ES
	return
EndProc     GetIFSFCSinES
ENDIF
Procedure   UnusedFunc,NEAR
	ASSUME	CS:IFSSEG,DS:NOTHING,ES:NOTHING,SS:NOTHING
	fmt <>,<>,<"Unused IFSFUNC function issued\n">
	MOV	AX,error_invalid_function
	STC
	return
EndProc UnusedFunc
; the following multiplex functions are implemented:
retn1	DD  ?
DMY	DW  ?
CONT	DD  ?
FOO	DW  Leave2F
INT2F	PROC	FAR
	ASSUME	CS:IFSSEG,DS:NOTHING,ES:NOTHING,SS:DOSGroup
	CMP	AH,multIFS
	JZ	IDispatch
	JMP	CONT
Leave2F:
	RET
INT2F	ENDP
Procedure   IDispatch,NEAR
	POP	WORD PTR retn1		; remove long return
	POP	WORD PTR retn1+2
	POP	DMY			; remove flags
	XCHG	AX,BX			; save bx/move index to index reg
	SHL	BL,1			; convert byte to word index
	XOR	BH,BH			; convert to word index
	POP	DMY			; save fictitious AX
	PUSH	DMY			; restore spot on stack
	PUSH	WORD PTR retn1+2 	; restore long return
	PUSH	WORD PTR retn1
	PUSH	FOO			; place near address of far return
	PUSH	CS:IFStable[BX] 	; place destination routine
	XCHG	AX,BX			; restore BX
	MOV	AX,DMY			; restore AX
	STI				; let Mani see Clock ticks
ShortReturn:
	return				; go to routine (dispatch for Aaron)
EDW	MACRO	name
	extrn	name:near
	DW	name
ENDM
IFSTable    LABEL   WORD
	DW	IFSInstall
	EDW	IFS_RMDIR		    ;	1   IFS_RMDIR
	EDW	IFS_SEQ_RMDIR		    ;	2   IFS_SEQ_RMDIR
	EDW	IFS_MKDIR		    ;	3   IFS_MKDIR
	EDW	IFS_SEQ_MKDIR		    ;	4   IFS_SEQ_MKDIR
	EDW	IFS_CHDIR		    ;	5   IFS_CHDIR
	EDW	IFS_CLOSE		    ;	6   IFS_CLOSE
	EDW	IFS_COMMIT		    ;	7   IFS_COMMIT
	EDW	IFS_READ		    ;	8   IFS_READ
	EDW	IFS_WRITE		    ;	9   IFS_WRITE
	EDW	IFS_XLOCK		    ;	10  IFS_XLOCK
	DW	UnusedFunc		    ;	11
	EDW	IFS_DISK_INFO		    ;	12  IFS_DISK_INFO
	EDW	IFS_SET_FILE_ATTRIBUTE	    ;	13  IFS_SET_FILE_ATTRIBUTE
	EDW	IFS_SEQ_SET_FILE_ATTRIBUTE  ;	14  IFS_SEQ_SET_FILE_ATTRIBUTE
	EDW	IFS_GET_FILE_INFO	    ;	15  IFS_GET_FILE_INFO
	EDW	IFS_SEQ_GET_FILE_INFO	    ;	16  IFS_SEQ_GET_FILE_INFO
	EDW	IFS_RENAME		    ;	17  IFS_RENAME
	EDW	IFS_SEQ_RENAME		    ;	18  IFS_SEQ_RENAME
	EDW	IFS_DELETE		    ;	19  IFS_DELETE
	EDW	IFS_SEQ_DELETE		    ;	20  IFS_SEQ_DELETE
	EDW	IFS_OPEN		    ;	21  IFS_OPEN
	EDW	IFS_SEQ_OPEN		    ;	22  IFS_SEQ_OPEN
	EDW	IFS_CREATE		    ;	23  IFS_CREATE
	EDW	IFS_SEQ_CREATE		    ;	24  IFS_SEQ_CREATE
	EDW	IFS_SEQ_SEARCH_FIRST	    ;	25  IFS_SEQ_SEARCH_FIRST
	EDW	IFS_SEQ_SEARCH_NEXT	    ;	26  IFS_SEQ_SEARCH_NEXT
	EDW	IFS_SEARCH_FIRST	    ;	27  IFS_SEARCH_FIRST
	EDW	IFS_SEARCH_NEXT 	    ;	28  IFS_SEARCH_NEXT
	EDW	IFS_ABORT		    ;	29  IFS_ABORT
	EDW	IFS_ASSOPER		    ;	30  IFS_ASSOPER
	EDW	Printer_GETSET_STRING	    ;	31  Printer_GETSET_STRING
	EDW	IFSFlushBuf		    ;	32  IFS_Flush_Buf
	EDW	IFS_LSEEK		    ;	33  IFS_LSEEK
	EDW	IFS_RESET_ENVIRONMENT	    ;	34  IFS_RESET_ENVIRONMENT
	EDW	IFS_DEVICE_CHECK	    ;	35  IFSDeviceCheck
	EDW	IFS_DEVICE_CLOSE	    ;	36  IFSDeviceClose
	EDW	IFS_DEVICE_OPER 	    ;	37  IFSDeviceOper
	EDW	IFS_SPOOL_ECHO_CHECK	    ;	38  IFSSpoolEchoCheck
	DW	UnusedFunc		    ;	39
	DW	UnusedFunc		    ;	40
	DW	UnusedFunc		    ;	41
	EDW	SERVER_DOSCALL_CLOSEFILES_FOR_UID ; 42			    util
	EDW	DEVICE_IOCTL		    ;	43			    dev
	EDW	IFS_UPDATE_CB		    ;	44  UPDATECB		    util
	EDW	IFS_FILE_XATTRIBUTES	    ;	45			    hand
	EDW	IFS_XOPEN		    ;	46  XOPEN		    file
	EDW	IFS_DEPENDENT_IOCTL	    ;	47			    util
	IF	DEBUG
	DW	NetPointers		    ;	47  NetPointers
	DW	NetPointers2		    ;	48  NetPointers2
	ENDIF
	IF	PATHGEN
	DW	GetIFSFCSinES		    ;	49 (if debug) GetRedirCSinES
					    ;	47 (if NOT debug) GetRedirCSinES
	ENDIF
IFSInstall:
	MOV	AL,0FFh
	MOV	BX,IFS_ATTRS
	return
EndProc IDispatch
Procedure   EcritNet,NEAR
	ASSUME	SS:NOTHING
	PUSHF
	CLI
	PUSH	AX
	MOV	AX,8000h+CritNet
	INT	int_ibm
	POP	AX
IF DEBUG
	JNC	NoCarry
	fmt <>,<>,<"$p: ECritNet overflowed semaphore\n">
NoCarry:
ENDIF
	STI
	POPF
	return
EndProc EcritNet
; Leave critical section for network.  Note that the first instruction (PUSH
; AX) here is used as the patch byte to enable the DOS critical section
; routines...
;   NOTE!!! On a 286, this instruction issues POPF!!!
Procedure   LcritNet,NEAR
	PUSH	AX
	PUSHF
	CLI
IF DEBUG
	JGE	NoWrap
	fmt <>,<>,<"$p: LCritNet decrementing semaphore through zero\n">
NoWrap:
ENDIF
	MOV	AX,8100h+critNet
	INT	int_ibm
	STI
	POPF				; NOTE that this restores entry
	POP	AX
	return
EndProc LcritNet
Procedure   EcritIFS,NEAR
	ASSUME	SS:NOTHING
	PUSHF
	CLI
	PUSH	AX
	MOV	AX,8000h+CritIFS
	INT	int_ibm
	POP	AX
	STI
	POPF
	return
EndProc EcritIFS
Procedure   LcritIFS,NEAR
	PUSH	AX
	PUSHF
	CLI
	MOV	AX,8100h+critIFS
	INT	int_ibm
	STI
	POPF				; NOTE that this restores entry
	POP	AX
	return
EndProc LcritIFS
	ASSUME	CS:IFSSEG,DS:NOTHING,ES:NOTHING,SS:DOSGroup
INTERR:
INTERRL:jmp	INTERRL 		; hang here - we're sick
	PUBLIC	TEMPBUF
TEMPBUF LABEL	BYTE
; THE SPACE FROM HERE TO NETEND CONSTITUTES THE TEMP AREA OF IFSFUNC.
; WARNING DANGER!!!!!!!!!
;	DO NOT reduce the size of this area without first checking
;	all users of it. It is OK to make it BIGGER without checking.
; Current size: ??
Break	<General IFSFUNC INIT>
;************************************************************************************
; map:	Resident:
;	IF_40 - (contifsinit) 2nd half of ifsfinit procedure  =  tempbuf area
;		allocate: DFL_LIST, altcds, sftfcb,
;		set TOTALSIZE
;	IFSFUNCINIT start
;	I_700 - INIT:	2nd half of IFSFUNCINIT
;			INT 23,24 stuff
;			call IFSFINIT
;			close std handles
;			enable critical section
;			terms & stays
;	tempbuf ends
;	Transient:
;	IFSFINIT procedure
;	Set interrupt vectors - 2F
;	Call AUTO_ATTACH
;	allocate stuff (write over code)
;	jumps up to 2nd half
;	IFSFUNCINIT init code
;	version checks
;	error msg processing
;	free environment
;	parsing
;	move stack
;	check size for everything
;	ifsfunc code size calculation
;	ifsfunc total size calculation
;	jmps to I_700
;	AutoAttach
;	CheckUNCpresence
;************************************************************************************
; This Code must be protected from overwrite when the structures are
;  initialized
IF_40:						; CONTIFSINIT
ASSUME	DS:IFSSEG,ES:NOTHING,SS:NOTHING
; Allocate and init DFL_LIST
	MOV	WORD PTR DFLAddr,DI
	MOV	WORD PTR DFLAddr+2,ES
	MOV	AL,DFLCount
	XOR	AH,AH
	MOV	BX,SIZE DFLL_LIST
	MUL	BX
	MOV	CX,AX
	XOR	AX,AX
	REP	STOSB
;;;aliasMOV	WORD PTR NLAddr,DI
;;;	MOV	WORD PTR NLAddr+2,ES
;;;	MOV	AX,NLSIZE
;;;	STOSW
;;;	XOR	AX,AX
;;;	STOSW
;;;aliasADD	DI,NLSIZE-4
; Allocate alt CDSs area
	TEST	IFSFUNC_FLAGS,UNC_INSTALLED
	JZ	IF_50
	MOV	WORD PTR CDSAlt,DI
	MOV	WORD PTR CDSAlt+2,ES
	PUSH	DS
	MOV	AX,(multDOS SHL 8) OR 3
	INT	2FH
ASSUME	DS:DOSGROUP
	MOV	AL,CDSCount		;	Alt = Alloc ((sizeof(CDS)+1)*CDSCount);
	XOR	AH,AH
	INC	AX
	MOV	BX,SIZE curdir_list
	MUL	BX
	ADD	DI,AX
	JMP	SHORT IF_55
IF_50:
	PUSH	DS
	MOV	AX,(multDOS SHL 8) OR 3
	INT	2FH
ASSUME	DS:DOSGROUP
; Allocate new FCB cache if appropriate
IF_55:
	CMP	BYTE PTR CS:NEWFCBCACHE,0  ; Damn forward reference
	JZ	IF_80			   ; JZ NO_FCB_CACHE
; We need to allocate (NewNumFCB * size of SF_entry) + size of sfTable.
	CLI				; Diddling a DOS table, make sure
; Make dos point to new table
	MOV	WORD PTR SFTFCB,DI
	MOV	WORD PTR SFTFCB+2,ES
; Initialize table parts, next link and size
	MOV	WORD PTR ES:[DI.sfLink],-1
	MOV	WORD PTR ES:[DI.sfLink+2],-1
	MOV	CX,NewNumFCB
	MOV	ES:[DI.sfcount],CX
; Set up keepcount
	MOV	KeepCount,NewKeepVal
; Clean out the new FCB Cache
	LEA	DI,[DI].SFTable 		; Point to the FCB SFTs
IF_60:						; CleanScan:
	MOV	ES:[DI.sf_ref_count],0
	MOV	WORD PTR ES:[DI.sf_position],0
	MOV	WORD PTR ES:[DI.sf_position+2],0
	ADD	DI,SIZE sf_entry
	LOOP	IF_60
	STI
IF_80:						; NO_FCB_CACHE:
	POP	DS
ASSUME	DS:IFSSEG
	MOV	[TOTALSIZE],DI		; Offset of 1st free byte
	POP	AX
	POP	BX
	POP	CX
	POP	DX
	POP	DI
	POP	SI
	POP	ES
	POP	DS
	return
	ASSUME	CS:IFSSEG,DS:IFSSEG,ES:NOTHING,SS:STACK
.xlist
.xcref
	msg_services <MSGDATA>
	PUBLIC	SYSGETMSG
	msg_services <GETmsg>
.cref
.list
Break	<Installable Network INIT>
Totalsize   DW	    ?
NEWFCBCACHE DB	    0
INT_24: 				; INT 24 handler used during INIT.
	MOV	AL,3			;    FAIL any INT 24s
INT_23: 				; ^C handler used during INIT.
	IRET				;    ignores any ^C.
I_700:					; Init
	ASSUME	CS:IFSSEG,DS:NOTHING,ES:NOTHING,SS:NOTHING
; We are now going to set lots of INT vectors and other stuff. We need
; to make ourselves immune to INT 24 and ^C
	PUSH	CS
	POP	DS
	MOV	DX,OFFSET INT_23
	MOV	AX,(Set_Interrupt_Vector SHL 8) + 23H
	INT	21H
	MOV	DX,OFFSET INT_24
	MOV	AX,(Set_Interrupt_Vector SHL 8) + 24H
	INT	21H
	invoke	IFSFINIT			; Do general INIT
	XOR	BX,BX
	MOV	CX,5				; StdIN,StdOUT,StdERR,StdAUX,StdPRN
I_720:						; Close STD handles before
						; keep process
	MOV	AH,CLOSE
	INT	21H
	INC	BX
	LOOP	I_720
; Enable the critical section code.  This consists of replacing the RETs at
; the beginning of each critical section routine with a PUSH AX
	PUSH	CS
	POP	DS				; ds - ifsseg
	TEST	IFSFUNC_FLAGS,UNC_INSTALLED	; 1st check if unc fs loaded
	JZ	I_800				;   only do this for unc
	MOV	AH,Get_In_Vars			; do crit patch
	INT	21h
	cld
	ASSUME	ES:DOSGroup
	MOV	AL,BYTE PTR LCritNet
	MOV	BX,OFFSET DOSGROUP:CritPatch
	CLI
I_760:						; Scan
	MOV	DI,ES:[BX]
	ADD	BX,2
	OR	DI,DI
	JZ	I_780
	stosb
	JMP	I_760
I_780:
	STI
I_800:											 ;AC012;moved
	MOV	CS:IFSSEM,0			; initialize ifs semaphores
; Compute total size for residency.
	MOV	DX,TotalSize			; size of code and structs
	ADD	DX,100H+0Fh			; Add size of header
	RCR	DX,1
	MOV	CL,3
	SHR	DX,CL
	MOV	AX,(Keep_Process SHL 8) + 0
	INT	21h
	MOV	AX,(EXIT SHL 8) + 1
	INT	21h
; %%%% CODE/DATA BELOW IS OVERLAYED WHEN STRUCTURES ARE SET UP
NETEND	LABEL	BYTE
	procedure IFSFINIT,NEAR
ASSUME	DS:NOTHING,ES:NOTHING,SS:NOTHING
; Perform initialization at DOSINIT time
	PUSH	DS
	PUSH	ES
	PUSH	SI
	PUSH	DI
	PUSH	DX
	PUSH	CX
	PUSH	BX
	PUSH	AX
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
; SET INTERRUPT VECTORS
	MOV	AL,2FH
	PUSH	AX
	MOV	AX,(multDOS SHL 8) OR 2
	INT	2FH
	POP	AX				; no know contents
	PUSH	ES
	PUSH	BX
	LES	BX,DWORD PTR ES:[BX]		; setting int 2f mult 5
	MOV	WORD PTR [NEXT_2F_5],BX
	MOV	WORD PTR [NEXT_2F_5+2],ES
	POP	BX
	POP	ES
	MOV	DX,OFFSET INT_2F_5
	MOV	ES:[BX],DX
	MOV	ES:[BX+2],DS
	MOV	AX,(Get_Interrupt_Vector SHL 8) + 2Fh
	INT	21h
	MOV	WORD PTR CONT,BX
	MOV	WORD PTR CONT+2,ES
	MOV	AX,(Set_Interrupt_Vector SHL 8) + 2Fh
	MOV	DX,OFFSET INT2F 		; multIFS handler
	INT	21h
; auto - attach
	CALL	AUTO_ATTACH
; call swap setup
	PUSH	DS
	MOV	AX,(multDOS SHL 8) OR 3
	INT	2FH
ASSUME	DS:DOSGROUP
	invoke	SERVER_IFSFUNC_DATA_AREA
	POP	DS
	invoke	SET_IFS_DOSCALL@
	PUSH	CS
	POP	ES
; Prep error messages
	LEA	DI,Rods_label
	SaveReg <CS>
	RestoreReg <ES>
	MOV	AX,DOS_GET_EXT_PARSE_ADD
	MOV	DL,7				; set msg addr
	INT	2FH
; Now start clobbering code
	MOV	DI,OFFSET NETEND		; Start strucs here
	TEST	DI,1				; Word aligned?
	JZ	IF_20				; Yes, ok
	INC	DI				; Bump to word align
IF_20:						; NOADJ1
	JMP	IF_40				; jmp CONTIFSINIT
EndProc IFSFINIT
;************* ifsfuncinit transient portion ******************************
       AA_PARMS_BUF DB 6 DUP(0) 		; temp storage used by auto-attach
       S_SIZE1	DB 11				; Sublist size(PTR next SUBLIST)
		DB 0				; Reserved
		DD SUB_IFSFUNC			; Ptr to substituted string
		DB  1				; n of %n
		DB Left_Align+Char_Field_ASCIIZ ; Data-type flags
		DB 7				; Maximum field width
		DB 5				; Minimum field width
		DB " "                          ; Character for Pad field
       S_SIZE2	DB 11				; Sublist size(PTR next SUBLIST)
		DB 0				; Reserved
		DD SUB_SHARE			; Ptr to substituted string
		DB  1				; n of %n
		DB Left_Align+Char_Field_ASCIIZ ; Data-type flags
		DB 7				; Maximum field width
		DB 5				; Minimum field width
		DB " "                          ; Character for Pad field
SUB_IFSFUNC	DB	"IFSFUNC",0
SUB_SHARE	DB	"SHARE",0
DEFAULT_DFLCount DB	4
;;;alias DEFAULT_NLSize   DW	 172			 ; 4 * 43
	ASSUME	CS:IFSSEG,DS:NOTHING
.xlist
.xcref
	INCLUDE IFSPARSE.INC
	msg_services <DISPLAYmsg,CHARmsg,LOADmsg>
	msg_services <ifsfunc.cla,ifsfunc.cl2>	; parse/install msgs
.cref
.list
;******************************************************************************
;		!!!!!!!   IFSFUNC starts here	!!!!!!! 	(see END statement)
;******************************************************************************
IFSFUNCINIT:

; --- /? help (before sysloadmsg so it works on any DOS version) ---
; DS = PSP segment at EXE entry; DS:[81H] = command line
	MOV	SI, 081H
IFS_SKIP_SP:
	CMP	BYTE PTR DS:[SI], ' '
	JNE	IFS_CHK_SL
	INC	SI
	JMP	SHORT IFS_SKIP_SP
IFS_CHK_SL:
	CMP	BYTE PTR DS:[SI], '/'
	JE	IFS_CHK_Q
	JMP	IFS_NO_HELP			; not '/' - skip help
IFS_CHK_Q:
	CMP	BYTE PTR DS:[SI+1], '?'
	JE	IFS_DO_HELP
	JMP	IFS_NO_HELP			; not '?' - skip help
IFS_DO_HELP:
	CALL	IFS_HELP_DONE			; push runtime addr of IFS_HELP_STR
IFS_HELP_STR DB	"Manages installable file system drivers.",c_CR,c_LF
	DB	c_CR,c_LF
	DB	"IFSFUNC [NAMES=n]",c_CR,c_LF,"$"
IFS_HELP_DONE:
	POP	DX				; DX = runtime addr of IFS_HELP_STR
	PUSH	CS
	POP	DS
	MOV	AH, 09H
	INT	21H
	MOV	AX, 4C00H
	INT	21H
IFS_NO_HELP:
; --- end /? help ---

	CALL	SYSLOADMSG
	JNC	I_20
	SaveReg <CS>
	RestoreReg <DS>
	CALL	SYSDISPMSG
Badver_msg proc    far
	MOV	AL,0FFh
	SaveReg <CS>
	RestoreReg <DS>
	MOV	AH,EXIT
	INT	21h
	PUSH	ES
	XOR	AX,AX
	PUSH	AX
	RET
badver_msg  ENDP
Badmes	proc	far
	ASSUME	CS:IFSSEG,DS:NOTHING,ES:NOTHING,SS:NOTHING
	MOV	BX,STDERR
	XOR	DL,DL
	CALL	SYSDISPMSG
	MOV	AX,(EXIT SHL 8) + 0FFH
	INT	21h
badmes	ENDP
I_20:						; Version OK
	MOV	AX,(multIFS SHL 8)+0		; Check if IFSFUNC already installed
	INT	2Fh
	CMP	AL,0
	JE	I_40
	MOV	AX,COMMON_ERR_2 		; yes - already installed - error 2
	PUSH	CS
	POP	DS
	MOV	SI,OFFSET S_SIZE1		;	prep for sysdispmsg call
	MOV	CX,1
	MOV	DH,UTILITY_MSG_CLASS
I_30:
	PUSH	CS
	POP	DS
	JMP	BADMES
						; no error on install check,
I_40:						; free environment - no longer needed
	MOV	AX,DS:[PDB_ENVIRON]
	OR	AX,AX
	JZ	I_60
	PUSH	ES
	MOV	ES,AX
	MOV	AH,DEALLOC
	INT	21H
	POP	ES
I_60:
;************************************************************************************
;	Parse IFSFUNC parameter :
;		   NAMES = n		 ;;;alias[n | (n {m})]
;************************************************************************************
						; Set default n and m
	MOV	AL,DEFAULT_DFLCount
	MOV	[DFLCount],AL			; 4	   (n)
;;;aliasMOV	AX,DEFAULT_NLSize
;;;aliasMOV	NLSize,AX			; 4 * 43   (m)
	MOV	SI,81h				; ds:si -> cmd parameter
	XOR	CX,CX				; no operands parsed yet
	PUSH	CS
	POP	ES
ASSUME	ES:IFSSEG
	MOV	DI,OFFSET IFSF_PARMS		; es:di -> parse control blocks
	XOR	DX,DX				; reserved
	CALL	SYSPARSE			; call parser
	CMP	AX,-1				; End of cmd?
	JNE	I_70
	JMP	I_160				;    if so continue w/init
I_70:
	CMP	AX,0				; Error?
	JNE	I_140				;    yes - go display parse error
;;;aliasCMP	IFSF_RESULT,COMPLEX		; complex?
;;;aliasJE	I_80
	CMP	IFSF_TAG,"N"                    ;   no - n only
	MOV	AX,PARSE_ERR_6
	JNE	I_140
	MOV	AL,IFSF_NM
	MOV	[DFLCount],AL
	CALL	SYSPARSE
	CMP	AX,-1
	JE	I_160
	MOV	AX,PARSE_ERR_1
;;;aliasJMP	I_140				; go display parse error
;;;aliasI_80:					; process complex  (n,m)
;;;	XOR	CX,CX				; prep for new parse call
;;;	XOR	DX,DX
;;;	CALL	SYSPARSE
;;;	CMP	AX,-1				; End of cmd?
;;;	JE	I_160				;    if so continue w/init
;;;	CMP	AX,0				; Error?
;;;	JNE	I_140				;    if so go display error
;;;	CMP	IFSF_TAG,"N"                    ; check if n or m parm
;;;	JNE	I_100
;;;	MOV	AL,IFSF_NM			; n parm
;;;	MOV	DFLCount,AL
;;;	CALL	SYSPARSE			; go back for m
;;;	CMP	AX,-1				; End of cmd?
;;;	JE	I_160				;    if so continue w/init
;;;	CMP	AX,0				; Error?
;;;	JNE	I_140				;    if so go display error
;;;00:
;;;	CMP	IFSF_TAG,"M"                    ; check if m parm
;;;	JE	I_120
;;;	MOV	AX,PARSE_ERR_7			; not m - error
;;;	JMP	I_140
;;;20:
;;;	MOV	AX,WORD PTR IFSF_NM		; m parm
;;;	MOV	NLSize,AX
;;;	CALL	SYSPARSE			; call parser again to check for
;;;	CMP	AX,-1				; possible garbage
;;;	JE	I_160
;;;	MOV	AX,PARSE_ERR_1
;;;alias
I_140:						; display parse error
	MOV	DH,PARSE_ERR_CLASS		; then continue w/defaults
	XOR	CX,CX
;;;	MOV	BX,STDERR								 ;AD005;
;;;	XOR	DL,DL									 ;AD005;
;;;	CALL	SYSDISPMSG								 ;AD005;
	JMP	I_30
I_160:
						; doinit
	MOV	AX,DS				; Move the stack so it doesn't
						; get blasted by structure init
	MOV	SS,AX				; Set stack in the PSP overlaying
	MOV	SP,100H 			; parms just processed
; We must now do some computation. We have to check if there is enough room
;  for everything. We must do this here BEFORE we start overlaying this
;  code
	PUSH	CS
	POP	DS
ASSUME	DS:IFSSEG
	MOV	DI,OFFSET NETEND		; We have this much code
	TEST	DI,1				; Word aligned?
	JZ	I_180				; Yes, OK.
	INC	DI				; Make word aligned
I_180:						; no adjust 5 label
; This code is added to make it easy to determine the code size
; of IFSFUNC for debug purposes. It is overlayed, so does not use extra
; storage.
	PUSH	DI		       ;
	PUSH	SI		       ;
	LEA	SI,CODESIZE+3	       ;
I_200:				       ; TENT
	SUB	DI,10000	       ;
	JC	I_220		       ;
	INC	BYTE PTR [SI]	       ;
	JMP	I_200		       ;
I_220:				       ; NEG1
	ADD	DI,10000	       ;
	INC	SI		       ;
I_240:				       ; THOU
	SUB	DI,1000 	       ;
	JC	I_260		       ;
	INC	BYTE PTR [SI]	       ;
	JMP	I_240		       ;
I_260:				       ; NEG2
	ADD	DI,1000 	       ;
	INC	SI		       ;
I_280:				       ; HUND
	SUB	DI,100		       ;
	JC	I_300		       ;
	INC	BYTE PTR [SI]	       ;
	JMP	I_280		       ;
I_300:				       ; NEG3
	ADD	DI,100		       ;
	INC	SI		       ;
I_320:				       ; TENS
	SUB	DI,10		       ;
	JC	I_340		       ;
	INC	BYTE PTR [SI]	       ;
	JMP	I_320		       ;
I_340:				       ; NEG4
	ADD	DI,10		       ;
	INC	SI		       ;
I_360:				       ; ONES
	SUB	DI,1		       ;
	JC	I_380		       ;
	INC	BYTE PTR [SI]	       ;
	JMP	I_360		       ;
I_380:				       ; DONE
	POP	SI		       ;
	POP	DI		       ;
; Allocate the DFL
	MOV	AL,DFLCount
	XOR	AH,AH
	MOV	CX,SIZE DFLL_LIST
	MUL	CX
	OR	DX,DX
	JZ	I_402
	JMP	I_640				; out of memp
I_402:
	ADD	DI,AX
	JNC	I_403
	JMP	I_640				; out of memp
I_403:
;;;aliasADD	DI,NLSIZE
;;;aliasJNC	I_404
;;;aliasJMP	I_640				; out of memp
I_404:
	CALL	CHECK_UNC_PRESENCE		; check if unc present, if not,
	TEST	IFSFUNC_FLAGS,UNC_INSTALLED
	JZ	I_415				; no need to allocate altcds
; Allocate the TEMP CDS area
	PUSH	DS
	MOV	AX,(multDOS SHL 8) OR 3
	INT	2FH
ASSUME	DS:DOSGROUP
	MOV	CL,CDSCount
	XOR	CH,CH
	INC	CX
	MOV	AX,SIZE curdir_list
	MUL	CX
	OR	DX,DX
	JZ	I_410
	JMP	I_640
I_410:
	ADD	DI,AX				; Temp CDS area
	JNC	I_417
	JMP	I_640
I_415:
; Determine if need new FCB cache and Allocate it if appropriate
	PUSH	DS				; get addressability to DOSGROUP
	MOV	AX,(multDOS SHL 8) OR 3
	INT	2FH
ASSUME	DS:DOSGROUP
I_417:
	CMP	KeepCount,DefKeepVal
	JNZ	I_420
	LDS	SI,SFTFCB
ASSUME	DS:NOTHING
	CMP	[SI].sfCount,DefNumFCB
	JNZ	I_420
	INC	NEWFCBCACHE			; Flag ourselves
	ADD	DI,((SIZE sf_entry) * NewNumFCB)+((SIZE sf)-2) ; New cache
	JC	I_640				; out of memp
I_420:						; no fcb
	POP	DS
ASSUME	DS:IFSSEG
; This code is added to make it easy to determine the total size	   @A1A
; of IFSFUNC.	      It is overlayed, so does not use extra storage.	   @A1A
					;				   @A1A
	PUSH	DI			;				   @A1A
	PUSH	SI			;				   @A1A
	LEA	SI,TOTSIZE		;				   @A1A
I_440:					; TENT2 			   @A1A
	SUB	DI,10000		;				   @A1A
	JC	I_460			;				   @A1A
	INC	BYTE PTR [SI]		;				   @A1A
	JMP	I_440			;				   @A1A
I_460:					; NEG5				   @A1A
	ADD	DI,10000		;				   @A1A
	INC	SI			;				   @A1A
I_480:					; THOU2 			   @A1A
	SUB	DI,1000 		;				   @A1A
	JC	I_500			;				   @A1A
	INC	BYTE PTR [SI]		;				   @A1A
	JMP	I_480			;				   @A1A
I_500:					; NEG6				   @A1A
	ADD	DI,1000 		;				   @A1A
	INC	SI			;				   @A1A
I_520:					; HUND2 			   @A1A
	SUB	DI,100			;				   @A1A
	JC	I_540			;				   @A1A
	INC	BYTE PTR [SI]		;				   @A1A
	JMP	I_520			;				   @A1A
I_540:					; NEG7				   @A1A
	ADD	DI,100			;				   @A1A
	INC	SI			;				   @A1A
I_560:					; TENS2 			   @A1A
	SUB	DI,10			;				   @A1A
	JC	I_580			;				   @A1A
	INC	BYTE PTR [SI]		;				   @A1A
	JMP	I_560			;				   @A1A
I_580:					; NEG8				   @A1A
	ADD	DI,10			;				   @A1A
	INC	SI			;				   @A1A
I_600:					; ONES2 			   @A1A
	SUB	DI,1			;				   @A1A
	JC	I_620			;				   @A1A
	INC	BYTE PTR [SI]		;				   @A1A
	JMP	I_600			;				   @A1A
I_620:					; DONE2 			   @A1A
	POP	SI			;				   @A1A
	POP	DI			;				   @A1A
	JMP	I_700
I_640:					; OUT_OF_MEMP
	POP	DS
I_660:					; OUT_OF_MEM
	MOV	AX,PARSE_ERR_10
	XOR	CX,CX
	JMP	BADMES
ASSUME	DS:NOTHING
BREAK <AUTO_ATTACH -- Attempt attaches of non-FAT physical drives>
;************************************************************************************
; AUTO_ATTACH
; Called by: init
; Routines called:  CALL_IFS
;		    CDS_TO_CD
;		    CD_TO_CDS
;		    FIND_IFS_DRIVER
; Inputs:
;	None
; Function:
;	Get addressability to CDS structure  (SYSVARS - IBMDOS/BIO)
;	FOR I = 1 to # CDS
;	   DO
;	   �   Drive = I - 1  (0-A,1-B,...)
;	   �   IF (curdir_inuse == 0 & curdir_devptr .NOT. 0) THEN
;	   �	   DO
;	   �	   �   Get pointer to 1st IFS header
;	   �	   �   WHILE pointer .NOT. 0FFFFH
;	   �	   �	   DO
;	   �	   �	       START ATTACH
;	   �	   �		   (IFSR_TYPE	=  2
;	   �	   �		    IFSR_PARMS@ -> IFS name, 0 parms)
;	   �	   �	       IF Attach successful THEN
;	   �	   �		  DO
;	   �	   �		    IF IFSUSESHARE set THEN
;	   �	   �		       Set share flag
;	   �	   �		    ENDIF
;	   �	   �		    LEAVE While
;	   �	   �		  ENDDO
;	   �	   �	       ELSE
;	   �	   �		   Get pointer to next IFS header
;	   �	   �	       ENDIF
;	   �	   �	   ENDDO
;	   �	   �   ENDWHILE
;	   �	   ENDDO
;	   �   ENDIF
;	   ENDDO
;	IF Share flag set THEN
;	   DO
;	     IF SHARE .NOT. loaded  THEN
;		issue warning msg:  "SHARE not loaded"  using msg retriever
;	   END
;	ENDIF
; Outputs: Successful auto-attachments in effect
;************************************************************************************
	Procedure   AUTO_ATTACH,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	TEST	IFSFUNC_FLAGS,NO_IFS_DRIVERS
	JZ	AA_05
	JMP	AA_1000
AA_05:
	SaveReg <DS,ES,DI>			; preserve ds - psp,es di storage
	ifsr_fcn_def  ATTSTART
	MOV	CS:IFSPROC_FLAGS,THISIFS_SET+IsInit ; set this so that cds_to_cd doesn't
						; set thisifs
	MOV	AH,Get_In_Vars			; Get ptr to ifs hdr chain
	INT	21h				; es:bx -> sysinitvars
	LES	DI,ES:[BX.SYSI_IFS]		; es:di -> 1st ifs driver
	MOV	AX,(multDOS SHL 8) OR 3 	; get addressability to dosgroup
	INT	2FH
ASSUME	DS:DOSGROUP
	MOV	CL,[CDSCount]			; prep cds loop
	XOR	CH,CH
	MOV	DX,SIZE CURDIR_LIST
	LDS	SI,[CDSAddr]			; ds:si -> CDS list
ASSUME	DS:NOTHING
AA_10:						; ** Loop here on cds entries

	TEST	DS:[SI.CURDIR_FLAGS],CURDIR_INUSE ;  check for ifs-able drive
	JZ	AA_13
	JMP	AA_120				;    cds already inuse, try next cds
AA_13:
	CMP	WORD PTR DS:[SI.CURDIR_DEVPTR],0
	JNZ	AA_16
	CMP	WORD PTR DS:[SI.CURDIR_DEVPTR+2],0
	JNZ	AA_16
	JMP	AA_120				;    cds not real, try next cds
AA_16:
	MOV	AX,SI				;    attempt
	SaveReg <DS,AX> 			; cds seg, offset
	MOV	AX,(multDOS SHL 8) OR 3 	; get dosgroup in ds to access cdsaddr
	INT	2FH
ASSUME	DS:DOSGROUP
	RestoreReg <AX> 			; cds offset
	SUB	AX,WORD PTR [CDSADDR]		; get  drive # (0-based) in al
	MOV	BL,SIZE CurDir_list
	DIV	BL
	RestoreReg <DS> 			; cds segment
	SaveReg <AX>				; drive # (0-based 0=A)
	MOV	BL,AL
	INC	BL				; change to 1-based (1=A)
	MOV	AX,CHECK_REMOVABLE		; 4408H (device ioctl)
	INT	21H
	OR	AX,AX				; ax 0 - drive removable
	RestoreReg <AX> 			; drive # (0-based)
	JNZ	AA_19
	JMP	AA_120				; drive removable, don't auto-attach
AA_19:						;    cds ok, proceed with autoattach
	CBW					; convert al to word (ax)
	MOV	BL,10
	DIV	BL				; convert number (ex.14) to char
	ADD	AX,3030H			; (3134) (ah-remain,al-quot)
	SaveReg <ES,DI> 			; Save 1st ifs driver
	MOV	CS:WORD PTR [THISIFS],DI	; Send attach start request
	MOV	CS:WORD PTR [THISIFS+2],ES	; to all fs drivers.  Stop when
						; one clicks.
AA_20:
	SaveReg <ES,DI,CX,DX,DS,SI>		; ifs ptr, cds count-size-ptr
	SaveReg <AX,DS> 			; get ES -> dosgroup (save char drv#)
	MOV	AX,(multDOS SHL 8) OR 3
	INT	2FH
	SaveReg <DS>
	RestoreReg <ES>
ASSUME	DS:DOSGROUP,ES:DOSGROUP
						; do attach w/dummy cds so as not
	MOV	DI,OFFSET DOSGROUP:DummyCDS		 ; to ruin valid cds
	RestoreReg <DS>
ASSUME	DS:NOTHING
	PUSH	DI
	MOV	CX,SIZE curdir_list
	REP	MOVSB
	PUSH	ES
	POP	DS
	POP	SI		; DS:SI -> dummy CDS
	MOV	[SI.curdir_flags],curdir_isifs + curdir_inuse
	MOV	[SI.curdir_type],type_drive
	MOV	AX,WORD PTR CS:[THISIFS]
	MOV	WORD PTR [SI.CURDIR_IFS_HDR],AX
	MOV	AX,WORD PTR CS:[THISIFS+2]
	MOV	WORD PTR [SI.CURDIR_IFS_HDR+2],AX
	RestoreReg <AX> 			; char drive #
	SaveReg <DS,SI> 			; dummy cds ptr
	invoke	PREP_IFSR			; sets es:bx -> ifsr, 0s fields,
						; ds - ifsseg
	MOV	DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	invoke	CDS_TO_CD			; sets ifsr_device_cb@
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_ATTSTART
	MOV	ES:[BX.IFSR_FUNCTION],IFSATTSTART
	MOV	ES:[BX.IFSR_TYPE],TYPE_DRIVE
	MOV	SI,OFFSET AA_PARMS_BUF		; set up attach parameter buffer
	MOV	WORD PTR DS:[SI],1		; in tempbuf = dw 1
	MOV	WORD PTR DS:[SI+2],AX		;	       db 3134,0
	XOR	AL,AL
	MOV	BYTE PTR DS:[SI+4],AL		; asciiz
	MOV	WORD PTR ES:[BX.IFSR_PARMS@],SI
	MOV	WORD PTR ES:[BX.IFSR_PARMS@+2],DS
AA_40:						; ** Loop here on ifs drivers
	invoke	CALL_IFS			; call ifs driver w/attach start req
	JC	AA_60				; jmp on no click
						; click:
	RestoreReg <DI,ES>			; restore cds ptr to es:di
	invoke	CD_TO_CDS			; update cds entry
	SaveReg <ES>				; move dummy cds ptr back to ds:si
	RestoreReg <DS>
	MOV	SI,DI				; ds:si -> dummy cds
	RestoreReg <DI,ES>			; es:di -> real cds
	MOV	CX,SIZE CURDIR_LIST		; copy dummy into real - ok to
	SaveReg <DI>
	OR	DS:[SI.CURDIR_FLAGS],CURDIR_ISIFS  ; set this cds as ifs
	REP	MOVSB				; clobber now
	RestoreReg <SI> 			; move real cds ptr back to ds:si
	SaveReg <ES>
	RestoreReg <DS>
	RestoreReg <DX,CX,DI,ES>		; restore cds size, count,
						;	  ifs ptr
	TEST	CS:IFSPROC_FLAGS,ISSHARE	; check if share checked
	JNZ	AA_100				; go process next cds
	TEST	ES:[DI.IFS_ATTRIBUTE],IFSUSESHARE
	JZ	AA_100				; ifs driver needs share
;; D526   CallInstall SHAREInstall,multSHARE,0	  ;   check that share loaded
	CallInstall SHAREInstall,multSHARE,40H	;   check that share loaded
	CMP	AL,(INSTALLED) AND 0FFh			;   if not generate warning
	JE	AA_50
	SaveReg <DS,SI,CX,DX>
	MOV	AX,COMMON_ERR_3 		; "SHARE not installed"
	PUSH	CS
	POP	DS
	MOV	SI,OFFSET S_SIZE2
	MOV	CX,1
	MOV	DH,UTILITY_MSG_CLASS
	MOV	BX,STDERR
	XOR	DL,DL
	CALL	SYSDISPMSG
	RestoreReg <DX,CX,SI,DS>
AA_50:
	OR	CS:IFSPROC_FLAGS,ISSHARE	; set this so won't check share again
	JMP	AA_100
AA_60:						; ** Next driver
	RestoreReg <AX,BX>			; dummy cds ptr
	RestoreReg <SI,DS,DX,CX,DI,ES>		; restore: ifs and cds ptrs,
						;	   cds count and size
	LES	DI,ES:[DI.IFS_NEXT]		; check next fs driver
	CMP	DI,NULL_PTR			; if ptr null, end of ifs drivers
	JNE	AA_80
	PUSH	AX				; dummy cds offset
	MOV	AX,ES
	CMP	AX,NULL_PTR
	POP	AX				; dummy cds offset
	JE	AA_100				; go process next cds if no more ifs
AA_80:
	MOV	CS:WORD PTR [THISIFS],DI	; prep next ifs driver
	MOV	CS:WORD PTR [THISIFS+2],ES
	SaveReg <ES,DI,CX,DX,DS,SI>		; Save regs
	SaveReg <AX,BX> 			; dummy cds ptr
	SaveReg <CS,CS> 			; get esdi back to ifsrh
	RestoreReg <ES,DS>			; and ds-ifsseg
	MOV	BX,OFFSET IFSR
	XOR	AX,AX
	MOV	ES:[BX.IFSR_RETCODE],AX 	; restore error fields
	MOV	ES:[BX.IFSR_RETCLASS],AL
	JMP	AA_40				; go process next ifs driver
AA_100:
	RestoreReg <DI,ES>			; restore 1st ifs driver
AA_120:
	ADD	SI,DX				; ** Next CDS
	DEC	CX
	JZ	AA_990
	JMP	AA_10
AA_990:
	RestoreReg <DI,ES,DS>			; restore ds - psp,esdi - storage
AA_1000:
	AND	CS:IFSPROC_FLAGS,NOT IsInit	; reset isinit
	return
EndProc AUTO_ATTACH
BREAK <CHECK_UNC_PRESENCE -- check if UNC file system driver ifs'ed>                     ;AN000;
;************************************************************************************
; CHECK_UNC_PRESENCE
; Called by: init - general
; Routines called:  SYSDISPMSG
; Inputs:
;	None
; Function:
;	Get pointer to 1st IFS header
;	IF no file systems THEN
;	   Display warning
;	ELSE DO
;	       BX=0
;	       WHILE pointer .NOT. 0FFFFH
;		  DO
;		    OR BX,IFS_ATTRIBUTES
;		    IF file system driver has unc bit set THEN
;		       DO
;			 Set unc_installed flag in IFSFUNC_FLAGS
;			 Set UNC_FS_HDR = unc file system driver header
;			 Set unc_found
;		       ENDDO
;		  ENDDO
;	       ENDWHILE
;	       IF unc not found THEN
;		  Set UNC_FS_HDR = null ptr
;	       ENDIF
;	       IFS_ATTRS=BX
;	     ENDDO
;	ENDIF
; Outputs: unc_installed flag set in ifsfunc_flags in unc present
;	   IFS_ATTRS set
;************************************************************************************
	Procedure   CHECK_UNC_PRESENCE,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	SaveReg <DS,ES,DI,BX>			; preserve ds - psp,es di storage
	MOV	AH,Get_In_Vars			; Get ptr to ifs hdr chain
	INT	21h				; es:bx -> sysinitvars
	LES	DI,ES:[BX.SYSI_IFS]		; es:di -> 1st ifs driver
	XOR	BX,BX
	CMP	DI,NULL_PTR			; if 1st null, then no drivers
	JNE	CUP_20				; must display no driver msg
	MOV	AX,ES
	CMP	AX,NULL_PTR
	JNE	CUP_20
	MOV	AX,UTIL_ERR_4			; def 4  "No IFS drivers found",CR,LF
	MOV	BX,STDERR
	XOR	CX,CX
	MOV	DL,NO_INPUT
	MOV	DH,UTILITY_MSG_CLASS
	PUSH	CS
	POP	DS
	CALL	SYSDISPMSG
	MOV	CS:IFSFUNC_FLAGS,NO_IFS_DRIVERS
	JMP	SHORT CUP_1000
CUP_20:
	OR	BX,ES:[DI.IFS_ATTRIBUTE]
	TEST	ES:[DI.IFS_ATTRIBUTE],IFSUNC	; now set UNC_FS_HDR
	JNZ	CUP_40
CUP_30:
	LES	DI,ES:[DI.IFS_NEXT]
	CMP	DI,NULL_PTR
	JNE	CUP_20
	MOV	AX,ES
	CMP	AX,NULL_PTR
	JNE	CUP_20
	TEST	IFSFUNC_FLAGS,UNC_INSTALLED
	JNZ	CUP_1000
	MOV	WORD PTR [UNC_FS_HDR],NULL_PTR	; no unc - set unc ptr null
	MOV	WORD PTR [UNC_FS_HDR+2],NULL_PTR
	JMP	SHORT CUP_1000
CUP_40: 					; found unc - set unc ptr
	MOV	WORD PTR [UNC_FS_HDR],DI	; and unc flag
	MOV	WORD PTR [UNC_FS_HDR+2],ES
	OR	IFSFUNC_FLAGS,UNC_INSTALLED
	JMP	SHORT CUP_30
CUP_1000:
	RestoreReg <BX,DI,ES,DS>		; restore ds - psp,esdi - storage
	return

include msgdcl.inc
EndProc CHECK_UNC_PRESENCE
IFSSEG	ENDS
STACK	SEGMENT STACK
DB  278 + 128 DUP (?)		; 278 == IBM's ROM requirements
STACK	ENDS
END IFSFUNCinit
END
