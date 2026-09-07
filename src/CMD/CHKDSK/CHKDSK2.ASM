TITLE	CHKDSK - MS-DOS Disk consistancy checker
page	,132					;

	.xlist
	include chkseg.inc
	INCLUDE CHKCHNG.INC
	INCLUDE DOSSYM.INC
	INCLUDE CHKEQU.INC
	INCLUDE CHKMACRO.INC
	include pathmac.inc
	.list

SUBTTL	Initialized Data
PAGE
CONST	SEGMENT PUBLIC PARA 'DATA'
	EXTRN  BADVER:byte,BADDRV_ARG:word,INVPATH_ARG:word
	EXTRN  FILE_ARG:word
	EXTRN  BADCD_ARG:word,BADSUBDIR:byte
	EXTRN  BADDRVM:byte
	EXTRN  BADIDBYT:byte
	EXTRN  OPNERR_ARG:word,NOEXT_ARG:word,EXTENT_ARG:word
	EXTRN  IDMES_ARG:WORD
	EXTRN  FILE_ARG1:WORD,FILE_ARG2:WORD
	EXTRN  badrw_num:word,BADRW_STR:WORD,BLOCK_NUM:WORD
	EXTRN  BADSW_ARG:WORD,DSKSPC:WORD
	EXTRN  HIDMES:WORD,DIRMES:WORD,FILEMES:WORD,ORPHMES2:WORD
	EXTRN  ORPHMES3:WORD,BADSPC:WORD,FRESPC:WORD
	EXTRN  TOTMEM:WORD,FREMEM:WORD,REPORT_ARG:WORD,CRLF_ARG:WORD
	EXTRN  RARG1:dWORD,RARG3:dWORD,ORPHCNT:dWORD
	EXTRN  SubstErr:BYTE
	extrn  tot_bytes_lo:word, tot_bytes_hi:word

	extrn	SWITCHAR:byte,TCHAR:byte,HECODE:byte,CONBUF:byte
	extrn	DOTMES:byte,NOISY:byte,HAVFIX:byte
	extrn	DOFIX:byte,DIRBUF:near,PARSTR:byte
	extrn	NUL:byte,ERRSUB:word,ALLFILE:byte
	extrn	ORPHFCB:byte,ORPHEXT:byte,HIDCNT:dword
	extrn	HIDSIZ:word,FILCNT:dword,FILSIZ:word,DIRCNT:dword
	extrn	DIRSIZ:word,CROSSCNT:dword,BADSIZ:word
	extrn	ORPHSIZ:word
	extrn	LCLUS:word
	extrn	USERDIR:byte,FRAGMENT:byte
	extrn	ALLDRV:byte,FIXMFLG:byte,DIRCHAR:byte
	extrn	EOFVAL:word
	extrn	Idmes2:Byte,Idmes1:Byte,idmes3:byte
CONST	ENDS

SUBTTL	Un-initialized Data
PAGE
DATA	SEGMENT PUBLIC PARA 'DATA'
	extrn	THISDPB:dword,DOTSNOGOOD:byte,NUL_ARG:byte
	extrn	NAMBUF:byte,SRFCBPT:word
	extrn	ISCROSS:byte,MCLUS:word,CSIZE:byte,SSIZE:word
	extrn	DSIZE:word,ARG1:word,ARG_BUF:byte,ERRCNT:byte
	extrn	USERDEV:byte,HARDCH:dword,CONTCH:dword
	extrn	mem_size:word
	extrn	psp_segment:word
	extrn	write_fault:byte
DATA	ENDS

CODE	SEGMENT PUBLIC PARA 'CODE'
ASSUME	CS:DG,DS:DG,ES:DG,SS:DG
	EXTRN	INT_23:NEAR
	EXTRN	PROMPTYN:NEAR,GET_CURRDIRERR:NEAR,GET_CURRDIR:NEAR
	EXTRN	FINDCHAIN:NEAR,CHECKERR:NEAR
	EXTRN	Write_Disk:Near, multiply_32_bits:near

	PUBLIC	PRINTF_CRLF,DOCRLF,SUBERRP,FCB_TO_ASCZ,EPRINT
	PUBLIC	DOINT26,DOTCOMBMES,REPORT
	public	ramcarv


;EPRINT:
;	 CALL	 CHECKERR
;	 JNZ	 RET14
;	 cmp	 byte ptr [nul_arg],0
;	 jnz	 hav_eprint_arg
;	 mov	 [file_arg2],offset dg:nul
;hav_eprint_arg:
;	 mov	 [file_arg1],dx
;	;mov	 dx,offset dg:file_arg
;	 mov	 dx,file_arg			 ;Get offset of message
;	 call	 printf_crlf
;	 mov	 byte ptr [nul_arg],0
;RET14:  ret


EPrint:
	call	CheckErr			;See if we should display msg
	pathlabl chkdsk2
;	$IF	Z				;Yes if Z set
	JNZ $$IF1
	push	dx				;Save message
	Message File_Arg			;Put out file in question
	pop	dx				;Get back message
	call	Printf_CRLF			;Print it
	cmp	byte ptr [nul_arg],0		;Is there a second message?
;	$IF	NZ				;Yes if not nul
	JZ $$IF2
	mov	dx,File_Arg2			;Display it
	call	Printf_CRLF			;
;	$ENDIF					;
$$IF2:
	mov	byte ptr [nul_arg],0		;Re-init this field
;	$ENDIF
$$IF1:
	ret					;

DOTCOMBMES:
	CMP	[NOISY],0
	JZ	SUBERRP
	mov	[file_arg2],dx
	CALL	get_currdirERR
       ;MOV	DX,OFFSET DG:CENTRY		;Centry got split into 3 msg's
       ;inc	byte ptr [nul_arg]		;
	CALL	EPRINT
	RET

SUBERRP:
	MOV	AL,1			;found a subdir error
	XCHG	AL,BYTE PTR [ERRSUB]	;set error flag and get old flag
	CMP	AL,0			;were any errors found before?
;	$if	z			;no errors found yet
	JNZ $$IF5
					 ;JNZ	  RET32
	    MOV     SI,OFFSET DG:NUL	   ;display error msgs
	    CALL    get_currdirERR
	    MOV     DX,OFFSET DG:BADSUBdir
	    CALL    EPRINT
;	$endif
$$IF5:
RET32:	RET

;****************************************************************************
; called by:  get_thisel2
; inputs:   DS:SI - pointer to file name
;****************************************************************************
FCB_TO_ASCZ:				;Convert DS:SI to ASCIZ ES:DI
	PUSH	CX
;move filename from ds:si to es:di
	MOV	CX,8			; Pack the name
	REP	MOVSB			; Move all of it
main_kill_tail:
; delete trailing spaces in name
	CMP	BYTE PTR ES:[DI-1]," "	;was the last char in name a space?
	JNZ	find_check_dot
	DEC	DI			; Back up over trailing space
	INC	CX
	CMP	CX,8
	JB	main_kill_tail
find_check_dot:
; ???
	CMP	WORD PTR [SI],(" " SHL 8) OR " "
	JNZ	got_ext 		; Some chars in extension
	CMP	BYTE PTR [SI+2]," "
	JZ	find_done		; No extension
got_ext:
; move period for extension
	MOV	AL,"."
	STOSB
; move 3 byte extension
	MOV	CX,3
	REP	MOVSB
ext_kill_tail:
;delete trailing blanks
	CMP	BYTE PTR ES:[DI-1]," "	;
	JNZ	find_done		;
	DEC	DI			; Back up over trailing space
	JMP	ext_kill_tail		;
find_done:				;
; put hex zero at the end
	XOR	AL,AL			;
	STOSB				; NUL terminate
	POP	CX
	RET


DOINT26:
;	PUSH	CX			;reg saves are handled in write_disk
;	PUSH	DX			;reg saves are handled in write_disk
;	PUSH	BX			;reg saves are handled in write_disk
	call	Write_Disk		;
;	POP	BX			;reg saves are handled in write_disk
;	POP	DX			;reg saves are handled in write_disk
;	POP	CX			;reg saves are handled in write_disk
;	JNC	RET23
       ;MOV	SI,OFFSET DG:WRITING
       ;CALL	DSKERR
;      $IF	C
       JNC $$IF7
	   mov	   dx,offset dg:write_fault
	   invoke  printf_crlf
;      $ENDIF
$$IF7:
;Need to handle 'Fail' option of critical error here.
;	JZ	DOINT26
RET23:	RET



;**************************************
; Prints all reporting data
;**************************************

REPORT:
;total disk space
    mov     bx,offset dg:dskspc
    mov     dx,tot_bytes_hi		;total bytes   in disk
    mov     ax,tot_bytes_lo		;total bytes   in disk
    xor     si,si			;no file count
    xor     di,di			;no file count
    call    Report_Mes_2		;
;hidden files
    mov     ax,hidsiz			;get cluster count
    or	    ax,ax			;are there any hidden files?
;   $IF     NZ				;yes
    JZ $$IF9
	mov	si,word ptr hidcnt	;si=low file count
	mov	di,word ptr hidcnt+2	;di=hi file count
	mov	bx,offset dg:hidmes	;bx=msg ;
	call	report_mes_1			;
;   $ENDIF				    ;
$$IF9:
;space in subdirectories
    mov     ax,dirsiz			;get cluster count
    or	    ax,ax			;Are there any directories?
;   $IF     NZ				;yes
    JZ $$IF11
	mov	si,word ptr dircnt	;si=low file count
	mov	di,word ptr dircnt+2	;di=hi file count
	mov	bx,offset dg:dirmes	;bx=msg
	call	report_mes_1
;   $ENDIF				    ;
$$IF11:
;user files
    mov     ax,filsiz			;get cluster count
    or	    ax,ax			;Are there any user files?
;   $IF     NZ				;yes
    JZ $$IF13
	mov	si,word ptr filcnt	;si=lo file count
	mov	di,word ptr filcnt+2	;di=hi file count
	mov	bx,offset dg:filemes	;bx=msg
	call	report_mes_1
;   $ENDIF				    ;
$$IF13:
;chains of lost clusters
    mov     ax,orphsiz			;get cluster count
    or	    ax,ax			;Are there any lost clusters?
;   $IF     NZ				;yes
    JZ $$IF15
	mov	si,word ptr orphcnt	;si=lo file count
	mov	di,word ptr orphcnt+2	;di=hi file count
	cmp	dofix,0 		;/F entered?
;	$IF	Z			;no
	JNZ $$IF16
	    mov     bx,offset dg:orphmes3 ;bytes would be recovered
;	$else
	JMP SHORT $$EN16
$$IF16:
	    mov     bx,offset dg:orphmes2 ;bytes were	recovered
;	$ENDIF					;
$$EN16:
	call	report_mes_1
;   $ENDIF				    ;
$$IF15:
;clusters of bad spots
    mov     ax,badsiz			;get cluster count
    or	    ax,ax			;Are there any bad spots on disk?
;   $IF     NZ				;if low word > zero, then yes
    JZ $$IF20
	xor	si,si			;no files to count
	xor	di,di			;no files to count
	mov	bx,offset dg:badspc		;Issue report
	call	report_mes_1
;   $ENDIF				    ;
$$IF20:
;bytes on disk left - free space
	mov	ax,[dsize]		;get total disk clusters
	sub	ax,[dirsiz]		; - dirs
	sub	ax,[filsiz]		; - files
	sub	ax,[hidsiz]		; - hidden files
	sub	ax,[badsiz]		; - bad spots
	sub	ax,[orphsiz]		; - lost clusters recovered
	sub	ax,[lclus]		; - lost clusters not recovered
	xor	si,si
	xor	di,di
	mov	bx,offset dg:frespc
	call	report_mes_1		;Free space is whats left
	call	docrlf				;
;size of each allocation unit
	xor	dx,dx				;Figure out cluster size
	xor	ah,ah				;
	mov	cx,SSize			;Bytes/sector *
	mov	al,CSize			; Sectors/cluster
	mul	cx				; = Bytes/Cluster in AX
	mov	bx,offset dg:idmes2		;Allocation size message
	xor	si,si
	xor	di,di
	call	Report_Mes_2			;
;total clusters
	mov	ax,Mclus			;Allocation units available
	dec	ax				;MCLUS is # clusters+1
	xor	dx,dx				;
	mov	bx,offset dg:idmes1		;
	xor	si,si
	xor	di,di
	call	Report_Mes_2			;
;;;;;;;;call	docrlf			;
;avail clusters
public avail_clus
avail_clus:
	mov	ax,[dsize]		;total clusters on disk
	sub	ax,[dirsiz]		; - clusters in subdirs
	sub	ax,[filsiz]		; - user files
	sub	ax,[hidsiz]		; - hidden files
	sub	ax,[badsiz]		; - bad spots
	sub	ax,[orphsiz]		; - lost clusters recovered
	sub	ax,[lclus]		; - lost clusters not recovered
	mov	bx,offset dg:idmes3		;
	xor	dx,dx				;
	xor	si,si
	xor	di,di
	call	Report_Mes_2		;dont convert to bytes!
	call	docrlf


;dcl Jan 8, 87 Compensate for RAM Carving - Start

ramcarv:
	push	es
	xor	bx,bx
	mov	ah,0c1h 		; return Ext'd Bios Data Seg Address
	int	15h
;	$IF	NC			; ram carving exists if no carry
	JC $$IF22
	   xor	   ax,ax		; zero out ax
	   mov	   al,byte ptr es:[0]	; pointer to # of 1k blocks of RAM Carve
	   mov	   dx,64		; convert 1k blocks to paras
	   mul	   dx
	   mov	   bx,ax		   ; save value in BX
;	$ENDIF					;
$$IF22:
	pop	es

;dcl Jan 8, 87 Compensate for RAM Carving - End

	mov	ax,[mem_size]	     ;Find out about memory
	add	ax,bx			; dcl Jan 8, 87 Compensate for RAM Carving
	mov	dx,16			;Mul to convert kbytes to bytes
	mul	dx
	mov	bx,offset dg:totmem
	call	report_mes_2
	mov	ax,[mem_size]
;;;;;;; mov	dx,psp_segment
	sub	ax,psp_segment
	mov	dx,16
	mul	dx
	mov	bx,offset dg:fremem
	call	report_mes_2
	ret

;*************************************************************
;
;  Print the message specified by the control string.
;
; REPORT_MES_1
; On entry:
;     BX contains the address of the control string.
;     AX contains a cluster count for the %ld argument in the control string.
;     CX contains a word count for the %d argument in the control string
;	 or is meaningless.
;
; REPORT_MES_2
; On entry:
;     BX contains the address of the control string.
;     AX,DX contain a long integer.
;     CX contains a word count for the %d argument in the control string
;	 or is meaningless.
;
;*************************************************************

;*****************************************************************************
; REPORT_MES_1 -  Print the report messages.  Display the file count and
;		 translate the number of clusters into the number of bytes.
;
; WARNING!! NOTE!! -->
;
; called by - PROCEDURE NAME
;
; inputs: AX - cluster count (1-ffff)
;	  BX - offset of control string
;	  CX -
;	  DX - high word of cluster count is zero'd out here.
;	  SP -
;	  BP -
;	  SI - low word of file count
;	  DI - hi  word of file count
;	  DS - segment of control string
;	  ES -
;
; output: DISPLAY OF DATA TO SCREEN
;
; Regs abused - ALL
;
;logic: 1. zero out hi word of cluster count, and multiply by sectors per
;	   cluster.  This gives number of sectors, which is a double word.
;
;	2. multiply by bytes per sector to give number of bytes.
;
;	3. place values in diplay fields, and call the msg. retriever.
;
;*****************************************************************************
report_mes_1:
	push	bx			;save it
	xor	dx,dx			;zero out hi word for multiply
	mov	cl,csize		;get sectors per cluster
	xor	ch,ch			;zero out hi byte of word
	mul	cx			;Convert cluster count to sector count ax/dx

	mov	bx,dx			;bx:ax is number to be mult;bgb
	mov	cx,ssize		;cx is number to mult with  ;bgb
	call	multiply_32_bits		       ;bgb
	mov	dx,bx			;move hi value to dx
	pop	bx			;retore pointer;bgb

report_mes_2:
	mov	word ptr rarg1,ax	;Lo word of bytes in ax
	mov	word ptr rarg1+2,dx	;Hi word of bytes in dx
	mov	word ptr rarg3,si	;lo word of file count in si
	mov	word ptr rarg3+2,di	;hi word of file count in di
	mov	report_arg,bx		;Store the offset of the ctrl string
	mov	dx,bx			;dx has ptr to msg for disp_interface
	call	printf_crlf		;print msg, then carraige return
	ret

PRINTF_CRLF:
	call	display_interface   ;
DOCRLF: mov	dx,offset dg:crlf_arg
	call	Display_Interface	;Replace old printf call with SysDispMsg
	ret				;


	pathlabl chkdsk2
CODE	ENDS
	END
