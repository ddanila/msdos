 page 80,132
TITLE	COMMAND - resident code for COMMAND.COM
NAME	COMMAND

;*****************************************************************************
;
; MODULE:	       COMMAND.COM
;
; DESCRIPTIVE NAME:    Default DOS command interpreter
;
; FUNCTION:	       This version of COMMAND is divided into three distinct
;		       parts.  First is the resident portion, which includes
;		       handlers for interrupts	23H (Cntrl-C), 24H (fatal
;		       error), and 2EH (command line execute); it also has
;		       code to test and, if necessary, reload the transient
;		       portion. Following the resident is the init code, which
;		       is overwritten after use.  Then comes the transient
;		       portion, which includes all command processing (whether
;		       internal or external).  The transient portion loads at
;		       the end of physical memory, and it may be overlayed by
;		       programs that need as much memory as possible. When the
;		       resident portion of command regains control from a user
;		       program, a check sum is performed on the transient
;		       portion to see if it must be reloaded.  Thus programs
;		       which do not need maximum memory will save the time
;		       required to reload COMMAND when they terminate.
;
; ENTRY POINT:	       PROGSTART
;
; INPUT:	       command line at offset 81H
;
; EXIT_NORMAL:	       No exit from root level command processor.  Can exit
;		       from a secondary command processor via the EXIT
;		       internal command.
;
; EXIT_ERROR:	       Exit to prior command processor if possible, otherwise
;		       hang the system.
;
; INTERNAL REFERENCES:
;
;     ROUTINES:        See the COMMAND Subroutine Description Document
;		       (COMMAND.DOC)
;
;     DATA AREAS:      See the COMMAND Subroutine Description Document
;		       (COMMAND.DOC)
;
; EXTERNAL REFERENCES:
;
;      ROUTINES:       none
;
;      DATA AREAS:     none
;
;*****************************************************************************
;
; EXE loading can overwrite the transient, so load errors must return through
; resident code. Copy an environment before resizing its old block: SETBLOCK
; can write an arena marker into the old environment.

.XCREF
.XLIST
	INCLUDE DOSSYM.INC
	INCLUDE comsw.asm
	INCLUDE comequ.asm
	INCLUDE resmsg.equ
	INCLUDE RESBIND.INC
	INCLUDE SHELLGATE.INC
IFDEF COMMAND_RESIDENT_BINDING
SHELL_EXEC_STATE TEXTEQU <DS>
SHELL_CTRL_STATE TEXTEQU <DS>
ELSE
SHELL_EXEC_STATE TEXTEQU <CS>
SHELL_CTRL_STATE TEXTEQU <CS>
ENDIF
.LIST
.CREF

CODERES 	SEGMENT PUBLIC BYTE
CODERES ENDS

DATARES SEGMENT PUBLIC BYTE
	EXTRN	LOADHIGH_PENDING:BYTE
	EXTRN	LOADHIGH_SAVED_LINK:BYTE
	EXTRN	LOADHIGH_SAVED_STRATEGY:WORD
	EXTRN	LOADHIGH_REGION_MASK:WORD
	EXTRN	LOADHIGH_MINIMUMS:WORD
	EXTRN	LOADHIGH_SHRINK:BYTE
	EXTRN	LOADHIGH_SAVED_FILTER:WORD
	EXTRN	BATCH:WORD
	EXTRN	ECHOFLAG:BYTE
	EXTRN	disp_class:byte
	EXTRN	execemes_block:byte
	EXTRN	execemes_off:word
	EXTRN	execemes_subst:byte
	EXTRN	execemes_seg:word
	EXTRN	EXTCOM:BYTE
	EXTRN	FORFLAG:BYTE
	EXTRN	IFFlag:BYTE
	EXTRN	InitFlag:BYTE
	EXTRN	NEST:WORD
	EXTRN	number_subst:byte
	EXTRN	PIPEFLAG:BYTE
	EXTRN	RETCODE:WORD
	EXTRN	SINGLECOM:WORD
DATARES ENDS

IFDEF COMMAND_HIGH_RESIDENT
FORMATDATA SEGMENT PUBLIC BYTE
FORMATDATA ENDS
SHELLCODE SEGMENT PUBLIC BYTE
SHELLCODE ENDS
ENDIF

HMACODE SEGMENT PUBLIC BYTE
HMACODE ENDS

MSGOPT SEGMENT PUBLIC BYTE
MSGOPT ENDS

IFDEF COMMAND_HIGH_RESIDENT
SHELLFIX SEGMENT PUBLIC WORD
PUBLIC shell_format_fixups
shell_format_fixups LABEL WORD
SHELLFIX ENDS
ENDIF

BATARENA	SEGMENT PUBLIC PARA
BATARENA ENDS

BATSEG		SEGMENT PUBLIC PARA
BATSEG	 ENDS

ENVARENA	SEGMENT PUBLIC PARA
ENVARENA  ENDS

ENVIRONMENT SEGMENT PUBLIC PARA 	; Default COMMAND environment
ENVIRONMENT ENDS

INIT	SEGMENT PUBLIC PARA
	EXTRN	CONPROC:NEAR
	EXTRN	init_contc_specialcase:near
INIT	ENDS

TAIL	SEGMENT PUBLIC PARA
TAIL	ENDS

TRANCODE	SEGMENT PUBLIC PARA
TRANCODE	ENDS

TRANDATA	SEGMENT PUBLIC BYTE
TRANDATA	ENDS

TRANSPACE	SEGMENT PUBLIC BYTE
TRANSPACE	ENDS

TRANEXT	SEGMENT PUBLIC BYTE
TRANEXT	ENDS

TRANTAIL	SEGMENT PUBLIC PARA
TRANTAIL	ENDS

	IFDEF COMMAND_HIGH_RESIDENT
RESGROUP GROUP CODERES,DATARES,FORMATDATA,SHELLCODE,HMACODE,MSGOPT,SHELLFIX,BATARENA,BATSEG,ENVARENA,ENVIRONMENT,INIT,TAIL
	ELSE
RESGROUP  GROUP CODERES,DATARES,HMACODE,MSGOPT,BATARENA,BATSEG,ENVARENA,ENVIRONMENT,INIT,TAIL
	ENDIF
TRANGROUP GROUP TRANCODE,TRANDATA,TRANSPACE,TRANEXT,TRANTAIL

	INCLUDE envdata.asm

; START OF RESIDENT PORTION

CODERES 	SEGMENT PUBLIC BYTE


	PUBLIC	EXT_EXEC
	PUBLIC	CONTC
	PUBLIC	Exec_Wait

ASSUME	CS:RESGROUP,DS:NOTHING,ES:NOTHING,SS:NOTHING

	EXTRN	lodcom:near
	EXTRN	LODCOM1:near

	ORG	0
ZERO	=	$

	ORG 80h-1
	PUBLIC	RESCOM
RESCOM	LABEL BYTE

	ORG	100H

PROGSTART:
	JMP	RESGROUP:CONPROC

	IFDEF COMMAND_RESIDENT_BINDING
	EXTRN DSKERR:NEAR,INT_2E:NEAR,THEADFIX:NEAR,TREMCHECK:NEAR
	EXTRN READ_DISK_PROC:FAR
	PUBLIC shell_gate_start,shell_service_start
shell_gate_start LABEL BYTE
SHELL_GATE_EMIT MACRO slot,target
	PUBLIC shell_gate_&slot,shell_gate_&slot&_segment
shell_gate_&slot LABEL BYTE
	IFDEF COMMAND_HIGH_RESIDENT
	call shell_restore_a20
	ENDIF
	db 0eah
	dw offset resgroup:target
shell_gate_&slot&_segment dw 0
ENDM
	SHELL_ENTRY_LIST SHELL_GATE_EMIT
	IFDEF COMMAND_HIGH_RESIDENT
	INCLUDE SHELLLOW.INC
CODERES ENDS
SHELLCODE SEGMENT PUBLIC BYTE
	ENDIF
shell_service_start LABEL BYTE
IFDEF COMMAND_HIGH_RESIDENT
PUBLIC shell_int21_bridge,shell_int2f_bridge
EXTRN LOADCOM:NEAR,CHKSUM:NEAR,RPRINT:NEAR,ENDINIT:NEAR
PUBLIC shell_loadcom_far,shell_chksum_far,shell_rprint_far
shell_loadcom_far PROC FAR
    call LOADCOM
    retf
shell_loadcom_far ENDP
shell_chksum_far PROC FAR
    call CHKSUM
    retf
shell_chksum_far ENDP
shell_rprint_far PROC FAR
    call RPRINT
    retf
shell_rprint_far ENDP
shell_int21_bridge PROC NEAR
    SHELL_FAR_TRANSFER 09ah,int21,shell_int21_low
    ret
shell_int21_bridge ENDP
shell_int2f_bridge PROC NEAR
    SHELL_FAR_TRANSFER 09ah,int2f,shell_int2f_low
    ret
shell_int2f_bridge ENDP
ENDIF
	ENDIF

;
; COMMAND has issued an EXEC system call and it has returned an error.	We
; examine the error code and select an appropriate message.
;
EXEC_ERR:
	push	ds				;AC000; get transient segment
	pop	es				;AC000;     into ES
	SHELL_OWNER_SEG DS,exec_err_ds
ASSUME	DS:RESGROUP
	MOV	BX,RBADNAM			;AC000; Get message number for Bad command
	CMP	AX,error_file_not_found
	JZ	GOTEXECEMES
	MOV	BX,TOOBIG			;AC000; Get message number for file not found
	CMP	AX,error_not_enough_memory
	JZ	GOTEXECEMES
	MOV	BX,EXEBAD			;AC000; Get message number for bad exe file
	CMP	AX,error_bad_format
	JZ	GOTEXECEMES
	MOV	BX,AccDen			;AC000; Get message number for access denied
	CMP	AX,error_access_denied
	JZ	GOTEXECEMES			;AC000; go print message

DEFAULT_MESSAGE:
	MOV	BX,EXECEMES			;AC000; Get message number for default message
	SHELL_FORMAT_REF <MOV SHELL_FORMAT_SEG EXECEMES_OFF,DX>,0 ;AN000; put offset of EXEC string in subst block
	SHELL_FORMAT_REF <MOV SHELL_FORMAT_SEG EXECEMES_SEG,ES>,0 ;AN000; put segment of EXEC string in subst block
	SHELL_FORMAT_REF <MOV AL,SHELL_FORMAT_SEG EXECEMES_SUBST>,0 ;AN000; get number of substitutions
	SHELL_FORMAT_REF <MOV SHELL_FORMAT_SEG NUMBER_SUBST,AL>,0
	SHELL_FORMAT_REF <MOV SI,OFFSET RESGROUP:EXECEMES_BLOCK>,0 ;AN000; get address of subst block
GOTEXECEMES:
	SHELL_OWNER_SEG ES,exec_msg_es
ASSUME	ES:RESGROUP
	MOV	DX,BX				;AN000; get message number in DX
	INVOKE	RPRINT
	JMP	NOEXEC
;
; The transient has set up everything for an EXEC system call.	For
; cleanliness, we issue the EXEC here in the resident so that we may be able
; to recover cleanly upon success.
;
EXT_EXEC:
	IFDEF COMMAND_RESIDENT_BINDING
	; Preserve the transient filename owner; select low state only while
	; preparing/restoring LOADHIGH. ES:BX remains the EXEC parameter block.
	push ds
	SHELL_OWNER_SEG DS,exec_pre_ds
	ENDIF
	cmp	byte ptr SHELL_EXEC_STATE:[LOADHIGH_PENDING],0
	je	EXT_EXEC_CALL
	cmp	byte ptr SHELL_EXEC_STATE:[LOADHIGH_PENDING],3
	jne	short EXT_EXEC_HIGH
	mov	byte ptr SHELL_EXEC_STATE:[LOADHIGH_PENDING],0
	jmp	EXT_EXEC_CALL
EXT_EXEC_HIGH:
	mov	byte ptr SHELL_EXEC_STATE:[LOADHIGH_PENDING],2
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	bp
	mov	ax,5800h
	SHELL_INT	int_command
	mov	SHELL_EXEC_STATE:[LOADHIGH_SAVED_STRATEGY],ax
	mov	ax,5802h
	SHELL_INT	int_command
	mov	SHELL_EXEC_STATE:[LOADHIGH_SAVED_LINK],al
	mov	cx,4d55h
	mov	si,2142h
	mov	di,0a55ah
	mov	ax,5808h
	SHELL_INT	int_command
	mov	SHELL_EXEC_STATE:[LOADHIGH_SAVED_FILTER],ax
	mov	bx,SHELL_EXEC_STATE:[LOADHIGH_REGION_MASK]
	mov	ax,5807h
	SHELL_INT	int_command
	cmp	byte ptr SHELL_EXEC_STATE:[LOADHIGH_SHRINK],0
	je	short EXT_EXEC_PROFILE_READY
	mov	bp,SHELL_EXEC_STATE:[LOADHIGH_REGION_MASK]
	xor	di,di
EXT_EXEC_LIMIT_LOOP:
	test	bp,1
	jz	short EXT_EXEC_LIMIT_NEXT
	mov	dx,SHELL_EXEC_STATE:[LOADHIGH_MINIMUMS+di]
	or	dx,dx
	jz	short EXT_EXEC_LIMIT_NEXT
	mov	bx,di
	shr	bx,1
	inc	bx
	mov	cx,4d55h
	mov	si,2142h
	push	di
	mov	di,0a55ah
	mov	ax,580ah
	SHELL_INT	int_command
	pop	di
EXT_EXEC_LIMIT_NEXT:
	shr	bp,1
	add	di,2
	cmp	di,32
	jb	short EXT_EXEC_LIMIT_LOOP
EXT_EXEC_PROFILE_READY:
	mov	bx,1
	mov	ax,5803h
	SHELL_INT	int_command
	mov	bx,0080h			; upper memory first, then conventional
	mov	ax,5801h
	SHELL_INT	int_command
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
EXT_EXEC_CALL:
	IFDEF COMMAND_RESIDENT_BINDING
	pop ds
	ENDIF
	push	dx				;AN000; save the command name offset
	SHELL_INT	int_command			; Do the EXEC
	pop	dx				;AN000; restore the command name offset
	pushf
	IFDEF COMMAND_RESIDENT_BINDING
	push ds
	SHELL_OWNER_SEG DS,exec_post_ds
	ENDIF
	cmp	byte ptr SHELL_EXEC_STATE:[LOADHIGH_PENDING],2
	jne	EXT_EXEC_RESTORED
	mov	byte ptr SHELL_EXEC_STATE:[LOADHIGH_PENDING],0
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	bp
	cmp	byte ptr SHELL_EXEC_STATE:[LOADHIGH_SHRINK],0
	je	short EXT_EXEC_LIMITS_RESTORED
	mov	bp,SHELL_EXEC_STATE:[LOADHIGH_REGION_MASK]
	xor	di,di
EXT_EXEC_RESTORE_LIMIT_LOOP:
	test	bp,1
	jz	short EXT_EXEC_RESTORE_LIMIT_NEXT
	cmp	word ptr SHELL_EXEC_STATE:[LOADHIGH_MINIMUMS+di],0
	je	short EXT_EXEC_RESTORE_LIMIT_NEXT
	mov	bx,di
	shr	bx,1
	inc	bx
	mov	dx,0ffffh
	mov	cx,4d55h
	mov	si,2142h
	push	di
	mov	di,0a55ah
	mov	ax,580ah
	SHELL_INT	int_command
	pop	di
EXT_EXEC_RESTORE_LIMIT_NEXT:
	shr	bp,1
	add	di,2
	cmp	di,32
	jb	short EXT_EXEC_RESTORE_LIMIT_LOOP
EXT_EXEC_LIMITS_RESTORED:
	mov	bx,SHELL_EXEC_STATE:[LOADHIGH_SAVED_FILTER]
	mov	cx,4d55h
	mov	si,2142h
	mov	di,0a55ah
	mov	ax,5807h
	SHELL_INT	int_command
	mov	bx,SHELL_EXEC_STATE:[LOADHIGH_SAVED_STRATEGY]
	mov	ax,5801h
	SHELL_INT	int_command
	xor	bx,bx
	mov	bl,SHELL_EXEC_STATE:[LOADHIGH_SAVED_LINK]
	mov	ax,5803h
	SHELL_INT	int_command
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
EXT_EXEC_RESTORED:
	IFDEF COMMAND_RESIDENT_BINDING
	pop ds
	ENDIF
	popf
	JC	EXEC_ERR			; EXEC failed
;
; The exec has completed.  Retrieve the exit code.
;
EXEC_WAIT:
	SHELL_OWNER_SEG DS,exec_wait_ds
	MOV	AH,WAITPROCESS			;AC000; Get errorlevel
	SHELL_INT	int_command			; Get the return code
	MOV	[RETCODE],AX
;
; We need to test to see if we can reload the transient.  THe external command
; may have overwritten part of the transient.
;
NOEXEC:
	JMP	LODCOM
;
; This is the default system INT 23 handler.  All processes (including
; COMMAND) get it by default.  There are some games that are played:  We
; ignore ^C during most of the INIT code.  This is because we may perform an
; ALLOC and diddle the header!	Also, if we are prompting for date/time in the
; init code, we are to treat ^C as empty responses.
;
CONTC	PROC	FAR
	ASSUME	CS:ResGroup,DS:NOTHING,ES:NOTHING,SS:NOTHING
	IFDEF COMMAND_RESIDENT_BINDING
	push ds
	SHELL_OWNER_SEG DS,contc_entry_ds
	ENDIF
	test	SHELL_CTRL_STATE:[InitFlag],initINIT ; in initialization?
	jz	NotAtInit			; no
	test	SHELL_CTRL_STATE:[InitFlag],initSpecial ; doing special stuff?
	jz	CmdIRet 			; no, ignore ^C
	IFDEF COMMAND_RESIDENT_BINDING
	pop ds
	ENDIF
	IFDEF COMMAND_RESIDENT_BINDING
	SHELL_FAR_TRANSFER 0eah,init,init_contc_specialcase
	ELSE
	jmp	resgroup:init_contc_specialcase ; Yes, go handle it
	ENDIF
CmdIret:
	IFDEF COMMAND_RESIDENT_BINDING
	pop ds
	ENDIF
	iret					; yes, ignore the ^C
NotAtInit:
	test	SHELL_CTRL_STATE:[InitFlag],initCtrlC ; are we already in a ^C?
	jz	NotInit 			; nope too.
;
; We are interrupting ourselves in this ^C handler.  We need to set carry
; and return to the user sans flags only if the system call was a 1-12 one.
; Otherwise, we ignore the ^C.
;
	cmp	ah,1
	jb	CmdIRet
	cmp	ah,12
	ja	CmdIRet
	IFDEF COMMAND_RESIDENT_BINDING
	pop ds
	ENDIF
	add	sp,6				; remove int frame
	stc
	ret	2				; remove those flags...
;
; We have now received a ^C for some process (maybe ourselves but not at INIT).
;
; Note that we are running on the user's stack!!!  Bad news if any of the
; system calls below go and issue another INT 24...  Massive stack overflow!
; Another bad point is that SavHand will save an already saved handle, thus
; losing a possible redirection...
;
; All we need to do is set the flag to indicate nested ^C.  The above code
; will correctly flag the ^C diring the message output and prompting while
; ignoring the ^C the rest of the time.
;
; Clean up: flush disk.  If we are in the middle of a batch file, we ask if
; he wants to terminate it.  If he does, then we turn off all internal flags
; and let the DOS abort.
;
NotInit:
	or	SHELL_CTRL_STATE:[InitFlag],initCtrlC ; nested ^c is on
	IFDEF COMMAND_RESIDENT_BINDING
	pop ds
	ENDIF
	STI
	SHELL_OWNER_SEG DS,contc_body_ds
ASSUME	DS:RESGROUP
	SHELL_FORMAT_REF <MOV SHELL_FORMAT_SEG DISP_CLASS,UTIL_MSG_CLASS>,1 ;AN055; reset display class
	SHELL_FORMAT_REF <MOV SHELL_FORMAT_SEG NUMBER_SUBST,NO_SUBST>,1 ;AN055; reset number of substitutions
	MOV	AX,SingleCom
	OR	AX,AX
	JNZ	NoReset
	PUSH	AX
	MOV	AH,DISK_RESET
	SHELL_INT	int_command			; Reset disks in case files were open
	POP	AX
NoReset:
;
; In the generalized version of FOR, PIPE and BATCH, we would walk the entire
; active list and free each segment.  Here, we just free the single batch
; segment.
;
	TEST	Batch,-1
	JZ	CONTCTERM
	OR	AX,AX
	JNZ	Contcterm
	invoke	SavHand
	invoke	ASKEND				; See if user wants to terminate batch
;
; If the carry flag is clear, we do NOT free up the batch file
;
	JNC	ContBatch
	mov	cl,echoflag			;AN000; get current echo flag
	PUSH	BX				;G

ClearBatch:
	MOV	ES,[BATCH]			; get batch segment
	mov	di,batfile			;AN000; get offset of batch file name
	mov	ax,mult_shell_brk		;AN000; does the SHELL want this terminated?
	SHELL_INT	2fh				;AN000; call the SHELL
	cmp	al,shell_action 		;AN000; does shell want this batch?
	jz	shell_bat_cont			;AN000; yes - keep it

	MOV	BX,ES:[BATFORPTR]		;G get old FOR segment
	cmp	bx,0				;G is a FOR in progress
	jz	no_bat_for			;G no - don't deallocate
	push	es				;G
	mov	es,bx				;G yes - free it up...
	MOV	AH,DEALLOC			;G
	SHELL_INT	21H				;G
	pop	es				;G restore to batch segment

no_bat_for:
	mov	cl,ES:[batechoflag]		;G get old echo flag
	MOV	BX,ES:[BATLAST] 		;G get old batch segment
	MOV	AH,DEALLOC			; free it up...
	SHELL_INT	21H
	MOV	[BATCH],BX			;G get ready to deallocate next batch
	DEC	NEST				;G Is there another batch file?
	JNZ	CLEARBATCH			;G Keep going until no batch file

;
; We are terminating a batch file; restore the echo status
;

shell_bat_cont: 				;AN000; continue batch for SHELL

	POP	BX				;G
	MOV	ECHOFLAG,CL			;G reset echo status
	MOV	PIPEFLAG,0			;G turn off pipeflag
ContBatch:
	invoke	CRLF				;G print out crlf before returning
	invoke	RestHand
;
; Yes, we are terminating.  Turn off flags and allow the DOS to abort.
;
CONTCTERM:
	XOR	AX,AX				; Indicate no read
	MOV	BP,AX
;
; The following resetting of the state flags is good for the generalized batch
; processing.
;
	MOV	IfFlag,AL			; turn off iffing
	MOV	[FORFLAG],AL			; Turn off for processing
	call	ResPipeOff
	CMP	[SINGLECOM],AX			; See if we need to set SINGLECOM
	JZ	NOSETSING
	MOV	[SINGLECOM],-1			; Cause termination on pipe, batch, for
NOSETSING:
;
; If we are doing an internal command, go through the reload process.  If we
; are doing an external, let DOS abort the process.  In both cases, we are
; now done with the ^C processing.
;
	AND	InitFlag,NOT initCtrlC
	CMP	[EXTCOM],AL
	JNZ	DODAB				; Internal ^C
	JMP	LODCOM1
DODAB:
	STC					; Tell DOS to abort
	RET					; Leave flags on stack
ContC	ENDP

public	ResPipeOff
	assume	ds:nothing,es:nothing
ResPipeOff:
	SaveReg <AX>
	IFDEF COMMAND_RESIDENT_BINDING
	push ds
	SHELL_OWNER_SEG DS,pipeoff_ds
	ENDIF
	xor	ax,ax
	xchg	SHELL_CTRL_STATE:[PipeFlag],al
	or	al,al
	jz	NoPipePop
	shr	SHELL_CTRL_STATE:[EchoFlag],1
NoPipePop:
	IFDEF COMMAND_RESIDENT_BINDING
	pop ds
	ENDIF
	RestoreReg  <AX>
	return
	IFDEF COMMAND_HIGH_RESIDENT
SHELLCODE ENDS
	ELSE
CODERES ENDS
	ENDIF
	END	PROGSTART
