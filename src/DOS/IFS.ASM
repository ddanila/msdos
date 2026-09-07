


.xlist
include    dosseg.asm

CODE	SEGMENT BYTE PUBLIC  'CODE'
	ASSUME	CS:DOSGROUP,  SS:DOSGROUP
.xcref
include    dossym.inc
include    devsym.inc
include    doscntry.inc
.cref
.list
StackSize   =	180h			; gross but effective

	i_need	VERFLG		       ; verify status flag
	i_need	CNTCFLAG	       ; break status flag
	i_need	CPSWFLAG	       ; CP switch logic ON/OFF
	I_need	CURRENTPDB,WORD        ; Current process identifier
	I_need	HIGH_SECTOR,WORD
	I_need	BUF_HASH_COUNT,WORD
	I_need	FAILERR,WORD
	I_need	USER_ID,WORD
	I_need	CALLDEVAD,DWORD       ;
	I_need	SYSINITVAR,WORD
	I_need	MYNAME,16	      ; NetBIOS name
	I_need	RETRYCOUNT,WORD       ; retry count
	I_need	COUNTRY_CDPG,BYTE
	i_need	DAY,BYTE	      ; date
	i_need	MONTH,BYTE
	i_need	YEAR,WORD
	i_need	CURBUF,DWORD
	i_need	IFS_DRIVER_ERR,WORD
	i_need	DOS34_FLAG,WORD       ; IFS function Read/Write flag
	i_need	Callback_SS,WORD      ;
	i_need	Callback_SP,WORD
	i_need	SaveBX,WORD
	i_need	Temp_Var,WORD
	i_need	INDOS,BYTE
	i_need	DskStack,BYTE
	i_need	IOStack,BYTE
	i_need	Callback_flag,BYTE

DOSINFO     STRUC
bsize	  dw	0
files	  dw	0
fcbs1	  dw	0
fcbs2	  dw	0
buffers   dw	0
	  dw	0
lastdrv   dw	0
secsize   dw	0
DosInfo       ENDS



	extrn	ABSDRD:NEAR
	extrn	ABSDWRT:NEAR
	extrn	READTIME:NEAR
	extrn	CHECKFLUSH:NEAR
	extrn	GETCURHEAD:NEAR


;******************************************************************************
; *
; *	 MODULE: IFS_DOSCALL
; *
; *	 FUNCTION: IFS to DOS function request dispatcher
; *
; *	 FUNCTION: This procedure dispatches the IFS DOS service requests
; *		   by calling various DOS service routines
; *
; *	 CALLING SEQUENCE:
; *
; *		   CALL  DWORD PTR IFS_DOSCALL@
; *
; *
; *	 RETURN SEQUENCE:
; *
; *		   If AX = 0	No error
; *
; *		   If AX <> 0	Error
; *		      AX = Error Code:
; *
; *
; *	 INTERNAL REFERENCES:	None
; *
; *
; *	 EXTERNAL REFERENCES:	STRATEGY, INTERRUPT, ABSDRD, ABSDWRT,
; *				FIND_SECTOR, MARK_SECTOR, WRITE_BUFFR,
; *				READ_BUFFR, WRITE_BUFFR, FREE_BUFFR,
; *				GET_DOS_INFO, FLUSH_BUFF
; *
; *	 NOTES:  None
; *
; *	 COPYRIGHT:  "MS DOS IFS Function"
; *		     "Version 1.00 (C) Copyright 1988 Microsoft Corporation"
; *		     "Licensed Material - Program Property of Microsoft"
; *
; *************************************************************************





PROCEDURE   IFS_DOSCALL,FAR
 assume DS:NOTHING,ES:NOTHING

	 CLI			;
	 CMP	 AH,39		;
	 JNZ	 others 	;
	 INC	 CS:[INDOS]	; in DOS
	 JMP	 Dosend 	;
others:
	 CMP	 AH,40		;
	 JNZ	 others2	;
	 DEC	 CS:[INDOS]	; out DOS
	 JMP	 Dosend 	;
others2:
	 CMP	 AH,38		;
	 JNZ	 not_stack	;
	 PUSH	 CS		;
	 POP	 DS		;
	 MOV	 SI,OFFSET DOSGROUP:IOSTACK
	 MOV	 CX,stacksize
	 JMP	 Dosend 	;
not_stack:			;
	 MOV	 CS:[Temp_Var],DS; save ds for strcmp strcpy
	 PUSH	 CS		;
	 POP	 DS		;
 assume DS:DOSGROUP
	 INC	 [INDOS]	; in DOS
	 PUSH	 CX		; save cx
	 PUSH	 DX		; save cx
	 MOV	 CX,SS		; cx=stack
	 MOV	 DX,CS		; cx=stack
	 CMP	 CX,DX		; dosgroup stack ?
	 POP	 DX		; save cx
	 POP	 CX		; restore cx
	 JZ	 withSS_SP	; yes
	 MOV	 [Callback_SS],SS ;save SS:SP
	 MOV	 [Callback_SP],SP
	 MOV	 [SaveBX],BX	;
	 MOV	 BX,CS		; prepare system stack
	 MOV	 SS,BX		;
	 MOV	 SP,OFFSET DOSGROUP:DSKSTACK
	 MOV	 BX,[SaveBX]	;
	 MOV	 [Callback_flag],1  ;set flag
withSS_SP:			;
	 STI
 ASSUME DS:NOTHING
;	 OR	 [DOS34_FLAG],Force_I24_Fail
;	 cmp	 ah,0		 ; call Strategy routine ??
;	 jne	 dos_chk_ah1	 ; jump if not
;	 CALL	 STRATEGY	 ; else call strategy routine
;	 jmp	 dos_exit	 ; then exit
;Dos_Chk_Ah1:
;	 cmp	 ah,1		 ; call interrupt routine
;	 jne	 dos_chk_ah2	 ; jump if not
;	 CALL	 INTERRUPT	 ; else call interrupt routine
;	 jmp	 dos_exit	 ; then exit
;Dos_Chk_Ah2:
;	 cmp	 ah,4
;	 jae	 Dos_Chk_Ah8
;	 mov	 High_Sector,si  ; save HI sector word
;	 mov	 dx,di		 ; save low sector
;	 push	 es
;	 invoke  FIND_DPB	 ; ds:si -> DPB
;	 mov	 bp,si
;	 push	 ds
;	 pop	 es		 ; es:bp -> DPB
;	 pop	 ds		 ; DS:BX-->Input buffer
;
;	 cmp	 ah,2		 ; absolute read ??
;	 jne	 dos_chk_ah3	 ; jump if not
;
;	 invoke  DSKREAD	 ; else do absolute read
;	 jmp	 dos_exit	 ; then return

;Dos_Chk_Ah3:
;	 invoke  DSKWRITE	 ; do absolute write
;	 jmp	 dos_exit	 ; then exit



Dos_chk_ah32:
	 cmp	 ah,32
	 jne	 str_cmp
	 CALL	 GET_DOS_INFO	 ; else get DOS information
	 jmp	 SHORT dos_exit
str_cmp:
	 mov	 DS,[Temp_Var]	  ; restore DS
	 cmp	 ah,36
	 jne	 str_cpy
	 invoke  strcmp 	 ; string compare
	 jmp	 SHORT dos_exit
str_cpy:
	 cmp	 ah,37
	 jne	 dos_error
	 invoke  strcpy 	 ; string copy
	 jmp	 SHORT dos_exit

Dos_Error:
	 stc
Dos_Exit:
	 CLI
	 PUSHF
	 AND	 [DOS34_FLAG],No_Force_I24_Fail
	 DEC	 [INDOS]	 ; exit DOS
	 CMP	 [Callback_flag],0  ;from dosgroup
	 JZ	 noSS_SP	    ;yes
	 MOV	 [Callback_flag],0  ;
	 POPF
	 MOV	 SP,CS:[Callback_SP];
	 MOV	 SS,CS:[Callback_SS]; restore user's SS:SP
	 JMP	 SHORT DOSend
noSS_SP:
	 POPF
Dosend:
	 STI			 ;

	 ret			 ;return


ENDPROC   IFS_DOSCALL





; ****************************************************************************
; *
; *	 MODULE: STRATEGY
; *
; *	 FUNCTION: Call Strategy Routine
; *
; *	 FUNCTION: This procedure dispatches the IFS DOS service requests
; *		   by calling various DOS service functions
; *
; *	 INPUT:    ES:BX ---> Device Request Header
; *		   AL  = Drive #
; *
; *		   CALL STRATEGY
; *
; *	 OUTPUT:   output of driver
; *
; *	 INTERNAL REFERENCES:	None
; *
; *
; *	 EXTERNAL REFERENCES:	GETTHISDRV
; *
; *	 NOTES:  None
; *
; *	 REVISION HISTORY:  New
; *
; *************************************************************************

;PROCEDURE   STRATEGY,NEAR

;	 INVOKE  FIND_DPB		 ; get DPB from drive number
;					 ; DS:SI-->DPB for drive
;	 LDS	 DI,DS:[SI.DPB_Driver_Addr]   ; get driver addres from DPB
;	 MOV	 DX,WORD PTR [DI.SDEVSTRAT]    ;get strategy routine address
;Driver_Call:
;	 MOV	 WORD PTR [CALLDEVAD],DX	; save it
;	 MOV	 WORD PTR [CALLDEVAD+2],DS	;
;	 CALL	 DWORD	PTR  [CALLDEVAD]	; call strategy routine
;STRAT_Exit:
;	 RET					; return

;ENDPROC   STRATEGY








; ****************************************************************************
; *
; *	 MODULE: INTERRUPT
; *
; *	 FUNCTION: This procedure calls the interrupt routine of the drive
; *		   specified in the drive#.
; *
; *	 INPUT:    AL = Drive #
; *
; *
; *	 OUTPUT:   output of driver
; *
; *
; *	 INTERNAL REFERENCES:	None
; *
; *
; *	 EXTERNAL REFERENCES:	FIND_DPB
; *
; *	 NOTES:  None
; *
; *	 REVISION HISTORY:  New
; *
; *************************************************************************

;PROCEDURE    INTERRUPT,NEAR

;	 INVOKE  FIND_DPB		 ; get DPB from drive number
;	 LDS	 DI,DS:[SI.DPB_Driver_Addr]   ; get driver addres from DPB
;	 MOV	 DX,WORD PTR [DI.SDEVINT]     ; get interrupt routine addrs
;	 JMP	 Driver_Call

;ENDPROC  INTERRUPT








; ************************************************************************* *
; *
; *	 MODULE: Get_Dos_Info
; *
; *	 FUNCTION: Get DOS information
; *
; *	 INPUT:    AL = Dos info code
; *
; *	 OUTPUT:   Dos Information  in registers
; *
; *	 INTERNAL REFERENCES:	None
; *
; *
; *	 EXTERNAL REFERENCES:	READTIME, $GETEXTCNTRY
; *
; *	 NOTES:  None
; *
; *	 REVISION HISTORY:  New
; *
; *************************************************************************

PROCEDURE  GET_DOS_INFO,NEAR

	cmp    al,0			; TIME and DATE ??
	jne    chk_al1

	Invoke	ReadTime		; get time in CX:DX

	push	cx			; save time
	push	dx

	MOV	CX,[YEAR]
	ADD	CX,1980
	MOV	DX,WORD PTR [DAY]	; fetch both day and month

	pop	bx			; bh = seconds	bl = hundredths
	pop	ax			; ah = hour  al = minutes
					; cx = year  dh = month
	jmp	get_info_exit


chk_al1:				; Active process info ??
	cmp    al,1
	jne    chk_al2			; no, try next
	MOV	BX,[CurrentPDB]        ; BX = active process ID
	mov	DX,[User_ID]	       ; User ID
	jmp	get_info_exit	       ; exit


chk_al2:
;	cmp    al,2		       ; get CPSW info ??
;	jne    chk_al3		       ; jump if not
;	MOV	SI,OFFSET DOSGROUP:COUNTRY_CDPG
;	MOV	BX,[SI.ccDosCodePage]  ; get dos code page id in BX
;	MOV	DL,CPSWFLAG	       ; get CP Switch status
;	jmp	get_info_exit	       ; exit


chk_al3:
;	cmp    al,3		       ; get CTRL BRK status ??
;	jne    chk_al4
;	mov    dl,CNTCFLAG	       ; DL = break status flag
;	jmp    get_info_exit	       ; exit


chk_al4:
;	cmp    al,4		       ; get Verify status ??
;	jne    chk_al5
;	mov    dl,VERFLG	       ; DL = verify status flag
;	jmp    get_info_exit	       ; exit


chk_al5:
	cmp    al,5		      ; Config.sys info ??
	jne    chk_al6

	mov	si,OFFSET DOSGROUP:SYSINITVAR	 ; DS:SI-->SysInitVar
	push	ds
	push	si
	lds	si,[si].Sysi_SFT      ; get SFT address
	mov	ax,[si].SFCount       ; get number of files
	lds	si,[si].SFlink	      ; get next SFT table
	cmp	si,-1		      ; end of table
	jz	nomore		      ;
	add	ax,[si].SFCount       ;
nomore: 			      ;
	mov	es:[di].files,ax	 ; save files= value
	pop	si
	pop	ds
	mov	ax,[si].Sysi_MaxSec	 ; get maximum sector size
	mov	es:[di].secsize,ax	 ; save files= value
	mov	ax,[si].Sysi_Keep	 ;
	mov	es:[di].fcbs2,ax	 ;
	lds	si,[si].Sysi_FCB      ; get FCB address
	mov	ax,[si].SFCount       ; get number of fcbs
	mov	es:[di].fcbs1,ax	 ; save fcbs=  value
	jmp	get_info_exit



chk_al6:
	cmp    al,6			; get machine name ??
	jne    chk_al7			; no, check next function
	context  DS
	mov	si,offset DOSGroup:MyName   ; DS:SI-->name string
					; ES:DI-->return buffer
	add	di,2			; skip max return size
	mov	cx,15			; name size
Chk6_Loop:
	rep	movsb			; copy machine name to return buffer
	xor	al,al			; set 16th byte is 0
	stosb
	jmp	get_info_exit		; return
Chk_Al7:
;	cmp	al,7			; get country information ??
;	jne	chk_al8 		; no, try next function
;	mov	al,dl			; AL = info ID
;	mov	bx,-1			; select active code page
;	mov	dx,-1			; select active country
;	mov	cx,-1			; get all
;	INVOKE	$getExtCntry		; get country info
;	jmp	SHORT Get_Info_Exit	; exit


Chk_Al8:
	cmp	al,8			; get share retry count ??
	jne	bad_param		; no, Bad parameter
	mov	bx,RetryCount		; BX = Share retry count
	jmp	SHORT Get_Info_Exit	      ; exit

Bad_Param:				; Bad parameter
	stc				;

Get_Info_Exit:				; exit

	ret


ENDPROC   GET_DOS_INFO








; ************************************************************************* *
; *
; *	 MODULE: $IFS_IOCTL
; *
; *	 FUNCTION: Handle IFS Driver IOCTL calls
; *
; *	 INPUT:    AH = 6B  function code
; *		   AL = XX  00 = Drive IOCTL, 01 = Psudo device IOCTL
; *		   CX = 00  Reserved
; *		   BL = XX  Device Number
; *		   DS:DX    Pointer to Buffer
; *
; *	 OUTPUT:
; *		   IF CARRY = 0  No Error
; *		   IF CARRY = 1  Error
; *			 AX = ERROR CODE
; *
; *	 INTERNAL REFERENCES:	None
; *
; *
; *	 EXTERNAL REFERENCES:	INT 2F
; *
; *	 NOTES:  None
; *
; *	 REVISION HISTORY:  New
; *************************************************************************

PROCEDURE  $IFS_IOCTL,NEAR

	PUSH	AX
	MOV	AX,(multnet SHL 8) OR 47    ; pass control to IFS Func
	INT	2FH
	POP	BX
	JC	ABB_ERR
	TRANSFER   SYS_RET_OK		      ; return

ABB_ERR:
	transfer SYS_RET_ERR		    ; error return

ENDPROC  $IFS_IOCTL



CODE	ENDS
    END

