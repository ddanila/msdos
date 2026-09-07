TITLE	LOCK ROUTINES - Routines for file locking
NAME	LOCK

;
;   LOCK_CHECK
;   LOCK_VIOLATION
;   $LockOper
;
include dosseg.asm

CODE	SEGMENT BYTE PUBLIC  'CODE'
	ASSUME	SS:DOSGROUP,CS:DOSGROUP

.xlist
.xcref
INCLUDE DOSSYM.INC
INCLUDE DEVSYM.INC
include lock.inc
.cref
.list

AsmVars <IBM, Installed>

Installed = TRUE

	i_need	THISSFT,DWORD
	i_need	THISDPB,DWORD
	i_need	EXTERR,WORD
	i_need	ALLOWED,BYTE
	i_need	RetryCount,WORD
	I_need	fShare,BYTE
	I_Need	EXTERR_LOCUS,BYTE	; Extended Error Locus
	i_need	JShare,DWORD
	i_need	Lock_Buffer,DWORD	;AN000; DOS 4.00
	i_need	Temp_Var,WORD		;AN000; DOS 4.00

BREAK <$LockOper - Lock Calls>

;
;   Assembler usage:
;	    MOV     BX, Handle	       (DOS 3.3)
;	    MOV     CX, OffsetHigh
;	    MOV     DX, OffsetLow
;	    MOV     SI, LengthHigh
;	    MOV     DI, LengthLow
;	    MOV     AH, LockOper
;	    MOV     AL, Request
;	    INT     21h
;
;   Error returns:
;	    AX = error_invalid_handle
;	       = error_invalid_function
;	       = error_lock_violation
;
;   Assembler usage:
;	    MOV     AX, 5C??	       (DOS 4.00)
;
;				    0? lock all
;				    8? lock write
;				    ?2 lock multiple
;				    ?3 unlock multiple
;				    ?4 lock/read
;				    ?5 write/unlock
;				    ?6 add (lseek EOF/lock/write/unlock)
;	    MOV     BX, Handle
;	    MOV     CX, count or size
;	    LDS     DX, buffer
;	    INT     21h
;
;   Error returns:
;	    AX = error_invalid_handle
;	       = error_invalid_function
;	       = error_lock_violation

	procedure   $LockOper,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
;	MOV	BP,AX			;MS. BP=AX
;	AND	BP,7FH			;MS. clear bit 7
;	CMP	BP,Lock_add		;MS. supported function ?
;	JA	lock_bad_func		;MS. no,

	CMP	AL,1			;AN000;;MS. no,
	JA	lock_bad_func		;AN000;;MS. no,

	PUSH	DI			       ; Save LengthLow
	invoke	SFFromHandle		       ; ES:DI -> SFT
	JNC	lock_do 		       ; have valid handle
	POP	DI			       ; Clean stack
	error	error_invalid_handle
lock_bad_func:
	MOV	EXTERR_LOCUS,errLoc_Unk        ; Extended Error Locus
	error	error_invalid_function

; Do not call Align_Buffer here: it corrupts the caller's DTA.

lock_do:
old_33:
	MOV	BX,AX			;AN000;;MS. save AX
	MOV	BP, OFFSET DOSGROUP:Lock_Buffer ;AN000;;MS. get DOS LOCK buffer
	MOV	WORD PTR [BP.Lock_position],DX	;AN000;;MS. set low offset
	MOV	WORD PTR [BP.Lock_position+2],CX;AN000;;MS. set high offset
	POP	CX				;AN000;;MS. get low length
	MOV	WORD PTR [BP.Lock_length],CX	;AN000;;MS. set low length
	MOV	WORD PTR [BP.Lock_length+2],SI	;AN000;;MS. set high length
	MOV	CX,1				;AN000;;MS. one range
	PUSH	CS				;AN000;;MS.
	POP	DS				;AN000;;MS. DS:DX points to
	MOV	DX,BP				;AN000;;MS.   Lock_Buffer
	TEST	AL,Unlock_all			;AN000;;MS. function 1
	JNZ	DOS_Unlock			;AN000;;MS. yes
	JMP	DOS_Lock			;AN000;;MS. function 0
DOS_Unlock:
	TEST	ES:[DI.sf_flags],sf_isnet
	JZ	LOCAL_UNLOCK
;;	invoke	OWN_SHARE			 ;AN000;;MS. IFS owns share ?
;;	JNZ	LOCAL_UNLOCK			 ;AN000;;MS. no

	CallInstall Net_Xlock,multNet,10
	JMP	SHORT ValChk
LOCAL_UNLOCK:
if installed
	Context DS
	Call	DWORD PTR SS:[JShare + 7 * 4]
else
	Call	clr_block
endif
ValChk:
	JNC	Lock_OK
lockerror:
	transfer SYS_RET_ERR
Lock_OK:
	MOV	AX,[Temp_VAR]			 ;AN000;;MS. AX= number of bytes
	transfer SYS_Ret_OK
DOS_Lock:
	TEST	ES:[DI.sf_flags],sf_isnet
	JZ	LOCAL_LOCK
;;	invoke	OWN_SHARE			 ;AN000;;MS. IFS owns share ?
;;	JNZ	LOCAL_LOCK			 ;AN000;;MS. no
	CallInstall NET_XLock,multNet,10
	JMP	ValChk
LOCAL_LOCK:
if installed
	Context DS
	Call	DWORD PTR SS:[JShare + 6 * 4]
else
	Call	Set_Block
endif
	JMP	ValChk

EndProc $LockOper

BREAK <Set_Lock>

;   Input:
;	   BP = Lock_Buffer addr
;	   CX = lock length
;   Function:
;	   set the lock
;   Output:
;	   carry clear ,Lock is set
;			DS:DX = addr of
;	   carry set Lock is not set
;	   DS,DX,CX preserved

;	procedure   Set_Lock,NEAR
;ASSUME  DS:NOTHING,ES:NOTHING
;	PUSH	DS			    ;MS. save regs
;	PUSH	DX			    ;MS.
;	PUSH	CX			    ;MS.
;	PUSH	CS			    ;MS.
;	POP	DS			    ;MS. DS:DX poits to Lock_Buffer
;	MOV	DX,BP			    ;MS.
;	PUSH	BX			    ;MS. save handle
;	PUSH	AX			    ;MS. save functions
;	MOV	CX,1			    ;MS. set one lock
;if installed
;	Call	JShare + 6 * 4		    ;MS. call share set block
;else
;	Call	Set_Block		    ;MS.
;endif
;	POP	AX			    ;MS. restore regs
;	POP	BX			    ;MS.
;	POP	CX			    ;MS.
;	POP	DX			    ;MS.
;	POP	DS			    ;MS.
;	return				    ;MS.
;EndProc Set_Lock

BREAK <Set_Lock_Buffer>

;   Input:
;	   ES:DI = addr of SFT
;	   CX = lock length
;   Function:
;	   set up the lock buffer
;   Output:
;	   Lock_Buffer is filled with position and lock length
;	   BP = Lock_Buffer addr
;

;	procedure   Set_Lock_Buffer,NEAR
;ASSUME  DS:NOTHING,ES:NOTHING
;
;	MOV	BP, OFFSET DOSGROUP:Lock_Buffer   ;MS. move file position
;	MOV	SI,WORD PTR ES:[DI.sf_position]   ;MS. to DOS lock_buffer
;	MOV	WORD PTR [BP.Lock_position],SI	  ;MS.
;	MOV	SI,WORD PTR ES:[DI.sf_position+2] ;MS.
;	MOV	WORD PTR [BP.Lock_position+2],SI  ;MS.
;	MOV	WORD PTR [BP.Lock_length],CX	  ;MS. move cx to lock_buffer
;	MOV	WORD PTR [BP.Lock_length+2],0	  ;MS.
;	return					  ;MS.
;
;EndProc Set_Lock_Buffer

; Inputs:
;	Outputs of SETUP
;	[USER_ID] Set
;	[PROC_ID] Set
; Function:
;	Check for lock violations on local I/O
;	Retries are attempted with sleeps in between
; Outputs:
;    Carry clear
;	Operation is OK
;    Carry set
;	A lock violation detected
; Outputs of SETUP preserved

	procedure   LOCK_CHECK,NEAR
	DOSAssume   CS,<DS>,"Lock_Check"
	ASSUME	ES:NOTHING

	MOV	BX,RetryCount		; Number retries
LockRetry:
	SaveReg <BX,AX> 		; MS. save regs
if installed
	Context DS
	call	DWORD PTR SS:[JShare + 8 * 4]
else
	Call	chk_block
endif
	RestoreReg  <AX,BX>		; MS. restrore regs
	retnc				; There are no locks
	Invoke	Idle			; wait a while
	DEC	BX			; remember a retry
	JNZ	LockRetry		; more retries left...
	STC
	return
EndProc LOCK_CHECK

; Inputs:
;	[THISDPB] set
;	[READOP] indicates whether error on read or write
; Function:
;	Handle Lock violation on compatibility (FCB) mode SFTs
; Outputs:
;	Carry set if user says FAIL, causes error_lock_violation
;	Carry clear if user wants a retry
;
; DS, ES, DI, CX preserved, others destroyed

	procedure   LOCK_VIOLATION,NEAR
	DOSAssume   CS,<DS>,"Lock_Violation"
	ASSUME	ES:NOTHING

	PUSH	DS
	PUSH	ES
	PUSH	DI
	PUSH	CX
	MOV	AX,error_lock_violation
	MOV	[ALLOWED],allowed_FAIL + allowed_RETRY
	LES	BP,[THISDPB]
	MOV	DI,1				; Fake some registers
	MOV	CX,DI
	MOV	DX,ES:[BP.dpb_first_sector]
	invoke	HARDERR
	POP	CX
	POP	DI
	POP	ES
	POP	DS
	CMP	AL,1
	retz			; 1 = retry, carry clear
	STC
	return

EndProc LOCK_VIOLATION

IF  INSTALLED
;
; do a retz to return error
;
Procedure   CheckShare,NEAR
	ASSUME	CS:DOSGROUP,ES:NOTHING,DS:NOTHING,SS:NOTHING
	CMP	fShare,0
	return
EndProc CheckShare
ENDIF

CODE	ENDS
    END
