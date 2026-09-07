TITLE	CHKPROC2 - PART2 Procedures called from chkdsk
page	,132					;

	.xlist
	include chkseg.inc
	INCLUDE CHKCHNG.INC
	INCLUDE DOSSYM.INC
	INCLUDE CHKEQU.INC
	INCLUDE CHKMACRO.INC
	include pathmac.inc

CONST	SEGMENT PUBLIC PARA  'DATA'
	EXTRN	FIXMES_ARG:word
	EXTRN	FATAL_ARG:word
	EXTRN	BADW_ARG:word,FATAL_END:word
	EXTRN	badrw_num:word,BADRW_STR:WORD,HAVFIX:byte
	EXTRN	DIRTYFAT:byte,CROSSCNT:dword,DOFIX:byte,SECONDPASS:byte
	EXTRN	BADSIZ:word,ORPHSIZ:word,ORPHFCB:byte
	EXTRN	HECODE:byte,USERDIR:byte,FRAGMENT:byte
	EXTRN	ORPHEXT:byte,ALLDRV:byte,FIXMFLG:byte,DIRCHAR:byte
	EXTRN	EOFVAL:word,BADVAL:word
	extrn	fTrunc:BYTE
CONST	ENDS

DATA	SEGMENT PUBLIC PARA 'DATA'
	extrn	fatcnt:byte, orph_arg:word
	EXTRN	THISDPB:dword,NUL_ARG:byte
	EXTRN	NAMBUF:byte,SRFCBPT:word,FATMAP:word
	EXTRN	MCLUS:word,CSIZE:byte,SSIZE:word
	EXTRN	DSIZE:word,ARG_BUF:byte,ERRCNT:byte
	EXTRN	USERDEV:byte,HARDCH:dword,CONTCH:dword
	EXTRN	ExitStatus:Byte,Read_Write_Relative:Byte
	extrn	bytes_per_sector:word
	extrn	fattbl_seg:word, fatsiz:word,  paras_per_fat:word
	extrn	fatmsg1:word
	extrn	fatmsg2:word
	EXTRN	dbcs_vector:byte
	EXTRN	dbcs_vector_off:word
	EXTRN	dbcs_vector_seg:word
DATA	ENDS

CODE	SEGMENT PUBLIC PARA 'CODE'
ASSUME	CS:DG,DS:DG,ES:DG,SS:DG
	EXTRN	PRINTF_CRLF:NEAR,FCB_TO_ASCZ:NEAR
	EXTRN	PROMPTYN:NEAR,DIRPROC:NEAR
	EXTRN	DOCRLF:NEAR,UNPACK:NEAR,PACK:NEAR
	EXTRN	CHECKNOFMES:NEAR
	EXTRN	multiply_32_bits:near
	extrn	nowrite:near, done:near, pack:near, unpack:near
	extrn	promptrecover:near, findchain:near
public RECOVER, DoAsk
public MAKORPHNAM, NAM0, NAMMADE
public GETFILSIZ, NCLUS, GOTEOF, CHKCROSS, RET8
public FATAL, hav_fatal_arg,  INT_23, RDONE
public Systime
public int_24
public CHECK_DBCS_CHARACTER
	.list



	pathlabl chkproc2
;*****************************************************************************
; RECOVER -
; free orphans or do chain recovery.  Note that if we have NOT been able to
; process the entire tree (due to inability to CHDIR), we temporarily set
; DoFix to FALSE, do the operation, and then reset it.
;
; inputs:   si - total number of clusters
;	    es - points to fatmap
;
; outputs:  orphaned clusters are converted to files
; LOGIC
;	- display dont fix msg if appropriate
;	- display number of lost clusters
;	- ask the user if he wants the chains converted to files
;***************************************************************************
RECOVER:
    mov     al,1
    xchg    al,[fixmflg]
    or	    al,al
;   $IF     Z				; where there any errors found?
    JNZ $$IF1
	cmp	[dofix],0		; yes - is the /f flag off?
;	$IF	Z			; yes - display the dont fix msg
	JNZ $$IF2
	    mov     dx,offset dg:FIXMES_arg
	    CALL    PRINTf_crlf
	    call    DoCRLF			    ;
;	$ENDIF
$$IF2:
;   $ENDIF
$$IF1:
    CALL    DOCRLF
CHAINREPORT:
;;;;mov     si,orphsiz		   ;get number of bad clusters found (recover)
;;;;mov     [orph_num],si	   ; Prints "XXX lost clusters found in YYY chains."
    call    findchain		   ;   On entry SI is the XXX value and the YYY value is
    mov     dx,offset dg:orph_arg  ;   in orphan-count.
    call    printf_crlf
    TEST    fTrunc,-1
;   $IF     NZ
    JZ $$IF5
	XOR	AX,AX	     ; We have truncated the scan.  Set DoFix to FALSE,
	XCHG	AL,DoFix     ; do the operation and then restore things.
	PUSH	AX
	CALL	PromptRecover
	POP	AX
	MOV	DoFix,AL
DoAsk:
;   $ELSE
    JMP SHORT $$EN5
$$IF5:
	CALL	PromptRecover
;   $ENDIF
$$EN5:
    return








;*****************************************************************************
;*****************************************************************************
MAKORPHNAM:
	PUSH	SI
	MOV	SI,OFFSET DG:ORPHEXT - 1
NAM0:
	INC	BYTE PTR [SI]
	CMP	BYTE PTR [SI],'9'
	JLE	NAMMADE
	MOV	BYTE PTR [SI],'0'
	DEC	SI
	JMP	NAM0

NAMMADE:
	POP	SI
	RET




;*****************************************************************************
; GETFILSIZ - calculate the file size based on the number of clusters.
;
; WARNING!! NOTE!! -->
;
; called by - PROCEDURE NAME
;
; inputs: AX -
;	  BX -
;	  CX -
;	  DX -
;	  SP -
;	  BP -
;	  SI - conatins the starting cluster number
;	  DI -
;	  DS -
;	  ES -
;
; output: AX - low word of the file size
;	  BX -
;	  CX -
;	  DX - hi  word of the file size
;	  SP -
;	  BP -
;	  SI -
;	  DI -
;	  DS -
;	  ES -
;
; Regs abused - none
;
;logic: 1. save bx & cx for 32 bit mul
;
;	2. zero out file size results
;
;	3. do for all clusters:
;
;	   4. get the next one and inc cluster counter
;
;	5. multiply clusters times sectors per cluster to give
;	   number of sectors in file.  This can be a 2 word value - DX:AX.
;
;	6. multiply the sectors times the number of bytes per sector.  This
;	   yields the number of bytes in the file.
;*****************************************************************************
;SI is start cluster, returns filesize as DX:AX
Procedure getfilsiz,near
    savereg <bx,cx>
	XOR	AX,AX			;zero out low word
	XOR	DX,DX			;zero out high word
	OR	SI,SI			;did we get a zero cluster?
;	$if	NZ
	JZ $$IF8
;	    $DO 			;do for all clusters
$$DO9:
NCLUS:		CALL	UNPACK		;find the next cluster
		XCHG	SI,DI		;put output into input for unpack
		INC	AX		;found another cluster
		CMP	SI,[EOFVAL]	;did we find last cluster?
;	    $leave    ae		;yes, so exit loop
	    JAE $$EN9
					;;;;;;;CMP     SI,2
					;;;;;;;JAE     NCLUS
;	    $enddo
	    JMP SHORT $$DO9
$$EN9:
GOTEOF:
	    MOV     BL,[CSIZE]		;get sectors per cluster
	    XOR     BH,BH
	    MUL     BX			;clusters * secs/cluster = sectors
	    mov     bx,dx		;get high num for 32bit mult
	    mov     cx,ssize		;cx = word to mult with
	    call    multiply_32_bits	;mul bx:ax * cx
	    mov     dx,bx		;save high word
;	$endif
$$IF8:
    restorereg <bx,cx>
  return
EndProc getfilsiz



;*****************************************************************************
;*****************************************************************************
Public Chkcross
CHKCROSS:
;Check for Crosslinks, do second pass if any to find pairs
	MOV	SI,word ptr CROSSCNT
	cmp	word ptr crosscnt,0	;if there is at least one crossed
;	$if	nz,or
	JNZ $$LL13
	cmp	word ptr crosscnt+2,0
;	$if	nz
	JZ $$IF13
$$LL13:
	    CALL    DOCRLF		;display another line
	    MOV     SecondPass,(True) AND 0FFh	;	     ;
	    XOR     AX,AX		;
	    PUSH    AX
	    PUSH    AX
	    CALL    DIRPROC			    ;Do it again
;	$endif
$$IF13:
RET8:	RET



;*****************************************************************************
;*****************************************************************************
FATAL:
;Unrecoverable error
	mov	dx,offset dg:FATAL_arg
	mov	[fatmsg1],bx
	cmp	byte ptr [nul_arg],0
	jnz	hav_fatal_arg
	mov	[fatmsg2],offset dg:fatal_end
hav_fatal_arg:
	CALL	PRINTf_crlf
	MOV	DL,[USERDEV]			;At least leave on same drive
	DOS_Call Set_Default_Drive		;
						;MOV	 AH,EXIT
	mov	ExitStatus,Bad_Exit		;Get return code
						;INT	 21H
	ret					;Ret Main_Init for common exit




;*****************************************************************************
;*****************************************************************************
iNT_24	PROC	FAR
aSSUME	DS:NOTHING,ES:NOTHING,SS:NOTHING
	PUSHF
	push	ax				;Save AX register
	test	al,Disk_Error			;Is it a disk critical err?
;	$IF	Z				;Yes
	JNZ $$IF15
	   mov	   ax,di			;Get error (DI low)
	   cmp	   al,Write_Protect		;Special case errors
;	   $IF	   E,OR 			;If write protect or
	   JE $$LL16
	   cmp	   al,Drive_Not_Ready		; if drive not ready
	   pop	   ax				;Balance stack again
;	   $IF	   E				;
	   JNE $$IF16
$$LL16:
	      CALL    dword ptr HardCh		; let parent's handler decide what to do
;	   $ELSE				;Other error
	   JMP SHORT $$EN16
$$IF16:
	      pop     ax			;balance stack
	      mov     al,Critical_Error_Fail	;Fail the operation
;	   $ENDIF				;
$$EN16:
;	$ELSE					;Not disk error
	JMP SHORT $$EN15
$$IF15:
	   CALL    dword ptr HardCh		; let parent's handler decide what to do
;	$ENDIF
$$EN15:
	CMP	AL,2				;Abort?
;	$IF	E				;Yes
	JNE $$IF21
	   STI					;Turn off Interrupts
	   CALL    DONE 			;Forget about directory, restore users drive
	   mov	   ExitStatus,Bad_Exit		;Get return code
;	$ENDIF
$$IF21:
	IRET
iNT_24	ENDP




;*****************************************************************************
;*****************************************************************************
INT_23	proc	far
	STI
	LDS	DX,[HARDCH]
	mov	al,24h				;
	DOS_Call Set_Interrupt_Vector		;
	LDS	DX,cs:[CONTCH]
	mov	al,23h				;
	DOS_Call Set_Interrupt_Vector		;
	PUSH	CS
	POP	DS
ASSUME	DS:DG
	MOV	[FRAGMENT],0
RDONE:
	CALL	NOWRITE 			;Restore users drive and directory
						;MOV	 AH,EXIT
						;MOV	 AL,0FFH
						;INT	 21H
	mov	ExitStatus,Bad_Exit		;Get return code
	stc
	ret					;Ret for common exit
int_23	endp





;*****************************************************************************
;*****************************************************************************
;
; Systime returns the current date in AX, current time in DX
;   AX - HHHHHMMMMMMSSSSS  hours minutes seconds/2
;   DX - YYYYYYYMMMMDDDDD  years months days
;
public	Systime
Systime:
	DOS_Call Get_Time			;
	SHL	CL,1				;Minutes to left part of byte
	SHL	CL,1
	SHL	CX,1				;Push hours and minutes to left end
	SHL	CX,1
	SHL	CX,1
	SHR	DH,1				;Count every two seconds
	OR	CL,DH				;Combine seconds with hours and minutes
	MOV	DX,CX
	PUSH	DX				; Save time
;
; WARNING!  MONTH and YEAR must be adjacently allocated
;
	DOS_Call Get_Date			;
	SUB	CX, 1980
	MOV	AX, CX
	MOV	CL, 4
	SHL	AL, CL				; Push year to left for month
	OR	AL, DH				; move in month
	MOV	CL,4
	SHL	AX,CL				;Push month to left to make room for day
	SHL	AX,1
	OR	AL, DL
	POP	DX				; Restore time
	XCHG	AX, DX				; Switch time and day
	return


;*****************************************************************************
;Routine name: Check_DBCS_CharACter
;*****************************************************************************
;Description: Check if specified byte is in rANges of DBCS vectors
;Called Procedures: None
;Input: AL = CharACter to check for DBCS lead charACter
;	DBCS_Vector = YES/NO
;Output: CY set if DBCS charACter
;	 DBCS_VECTOR = YES
;Psuedocode
;----------
;	Save registers
;	IF DBCS vector not found
;	   Get DBCS environmental vector (INT 21h
;	   Point at first set of vectors
;	ENDIF
;	SEARCH
;	LEAVE End of DBCS vectors
;	EXITIF CharACter > X1,AND  (X1,Y1) are environment vectors
;	EXITIF CharACter < Y1
;	  STC (DBCS charACter)
;	ORELSE
;	   Inc pointer to next set of vectors
;	ENDLOOP
;	   CLC (Not DBCS charACter)
;	ENDSRCH
;	Restore registers
;	ret
;*****************************************************************************
DBCS_Vector_Size	equ 2
end_of_vector		equ 0
Procedure	Check_DBCS_Character		      ;
	push	ds				;Save registers
	push	si				; "  "	  "  "
	push	ax				; "  "	  "  "
;;;;;;;;push	ds				; "  "	  "  "
;;;;;;;;pop	es				;Establish addressability
	cmp	byte ptr es:DBCS_VECTOR,Yes	;Have we set this yet?
;	$IF	NE				;Nope
	JE $$IF23
	   push    ax				   ;Save input charACter
	   mov	   al,0 			;Get DBCS environment vectors
	   DOS_Call Hongeul			;  "  "    "  "
	   mov	   byte ptr es:DBCS_VECTOR,YES	;Indicate we've got vector
	   mov	   es:DBCS_Vector_Off,si	;Save the vector
	   mov	   ax,ds			;
	   mov	   es:DBCS_Vector_Seg,ax	;
	   pop	   ax				   ;Restore input charACter
;	$ENDIF					; for next time in
$$IF23:
	mov	si,es:DBCS_Vector_Seg		;Get saved vector pointer
	mov	ds,si				;
	mov	si,es:DBCS_Vector_Off		;
;	$SEARCH 				;Check all the vectors
$$DO25:
	   cmp	   word ptr ds:[si],End_Of_Vector ;End of vector table?
;	$LEAVE	E				;Yes, done
	JE $$EN25
	   cmp	   al,ds:[si]			;See if char is in vector
;	$EXITIF AE,AND				;If >= to lower, ANd
	JNAE $$IF25
	   cmp	   al,ds:[si+1] 		; =< thAN higher rANge
;	$EXITIF BE				; then DBCS charACter
	JNBE $$IF25
	   stc					;Set CY to indicate DBCS
;	$ORELSE 				;Not in rANge, check next
	JMP SHORT $$SR25
$$IF25:
	   add	   si,DBCS_Vector_Size		;Get next DBCS vector
;	$ENDLOOP				;We didn't find DBCS char
	JMP SHORT $$DO25
$$EN25:
	   clc					;Clear CY for exit
;	$ENDSRCH				;
$$SR25:
	pop	ax				;Restore registers
	pop	si				; "  "	  "  "
	pop	ds				;Restore data segment
	ret					;
Check_DBCS_CharACter endp			;



	pathlabl chkproc2
CODE	ENDS
	END
