page	,132				;
TITLE	RECOVER.SAL - MS-DOS File/Disk Recovery Utility
;----------------------------------------------------------
;
;	Recover - Program to rebuild an ms.dos directory
;
;	Copyright 1988 by Microsoft Corporation
;
;-----------------------------------------------------------
.xlist
	include recchng.inc
	include recseg.inc
	INCLUDE DOSSYM.INC
	INCLUDE RECEQU.INC
	INCLUDE RECdata.INC
	INCLUDE recmacro.inc
	INCLUDE sysmsg.INC
	include pathmac.inc
	msg_utilname<recover>
;*****************************************************************************
; Extrn Declarations
;*****************************************************************************
data	segment public para 'DATA'
	extrn	Askmsg:Byte
	extrn	Baddrv:Byte
	extrn	FatErrRead:Byte
	extrn	FATErrWrite:Byte
	extrn	Dirmsg:Byte
	extrn	RecMsg:Byte
	extrn	OpnErr:Byte
	extrn	no_mem_arg:word
data	ends


;******************************************************************************
; Public entries
;******************************************************************************
code	segment public para 'code'
	pathlabl recover
public	GetFat, getSmall, getfat1, getret, SetFat, setsmall, f_exists
public nofspec, kill_bl, endl, next_char
Public	Main_Routine

IF KANJI
   public islead
   PUBLIC	notlead
   PUBLIC	dbcsmore
   PUBLIC	TESTKANJ
ENDIF


;PUBLIC  stop
public	setfat2, setfat1, setRet, GetKeystroke, Prompt, Load, ReadFt, WrtFat
public	wrtit,	wrtok, fEOF, EOFok, printerr, SFFromFCB, Main_Routine
public	slashok, kill_bl, next_char, name_copied, sja, sjb, not_root
public	same_drive, sj1, no_errors, same_dir, noname, drvok, See_If_File
public	step2,	step3, step4, direrr, fill_dir, file_spec
public	RecFil, recfil0, rexit1, int_23, rabort, rest_dir, no_fudge
public	int_24, int_24_back, ireti, Read_File, Bad_File_Read, read_fats
public	fill_fat, rexit2, sfsize, stop_read, calc_fat_addr
	EXTRN	Write_Disk:NEAR,Read_Disk:NEAR,report:NEAR
	Extrn	Main_Init:Near
	Extrn	Change_Blanks:Near
	Extrn	Build_String:Near
	extrn	seg_adj:near
	extrn	exitpgm:near
.list

;*****************************************************************************
;   calc_fat_addr - calculate the seg/off of the fat cell from the cell number
;   Inputs:	AX the fat cell number
;		BX the fat table offset
;		ES the fat table segment (same as program seg)
;   Outputs:	BX contains the offset of the fat cell
;		ES contains the segment of the fat cell
; LARGE FAT SUPPORT
;*******************
; the offset into the fat table is cluster number times 2 (2 bytes per fat entry)
; This will result not only in the segment boundary being passed, but also in
; a single-word math overflow.	  So, we calculate the the address as follows:
; 0. start with cluster number (1-65535)
; 1. divide by 8 to get the number of paragraphs per fat-cell  (0-8191)
;    remainder =					       (0-7)
; 2. multiply the remainder by 2 to get offset in bytes        (0-15)
; You now have a paragraph-offset number that you can use to calc the addr into
; the fat table.  To get the physical addr you must add it to the offset of the
; table in memory.
; 3. add the paras to the segment register
; 4. add the offset to the offset register
;******************************************************************************
Procedure calc_fat_addr,near
    savereg <ax,dx>		    ; ax already has cluster number
    lea     bx,fattbl		    ;point to fat table in memory
    call    seg_adj		    ;es:bx = es:00
    mov     bx,0008h		    ;  set up div by para (* 2 bytes per clus)
    xor     dx,dx		    ; zero dx for word divide
    div     bx			    ; do it
    mov     bx,es		    ; get fat table segment
    add     bx,ax		    ; add number of paras to the cluster
    mov     es,bx		    ; move it back
    shl     dx,1		    ; remainder times 2
    mov     bx,dx		    ; offset = 00 + remainder
    restorereg <dx,ax>
  return
EndProc calc_fat_addr



	break	<GetFat - return the contents of a fat entry>
;*****************************************************************************
;   GetFat - return the contents of a fat cell
;
;   Inputs:	AX the fat cell number
;   Outputs:	BX contains the contents of the fat cell AX
;		CX contains the number of bytes per sector
;   Registers Revised: SI
;
; pseudocode:
; ----------
;    if large-fat, then
;	double fat-number			 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
;	fat-table offset = fat-num * 2		 2  4  6  8  10 12 14 16 18 20
;    else
;	fat-table offset = fat-num + (fat-num/2)
;
; LARGE FAT SUPPORT  - if this is a 16-bit fat, use the new calc algorithm
; *****************
;******************************************************************************
Procedure GetFat,NEAR
	set_data_segment
	lea	bx,fattbl		;point to fat table in memory
	cmp	MaxClus,4086		;   if (MaxClus >= 4086) {
;	$IF	AE			;changed to above because max clusters
	JNAE $$IF1
					;can now be 'FFFF'hex
		call	calc_fat_addr		; ;set up div by para
		mov	bx,word ptr es:[bx]	; get contents of fat
;	$ELSE	;small fat
	JMP SHORT $$EN1
$$IF1:
getSmall:   push    ax			    ;save fat-num     ;       i = clus + clus/2;
	    mov     si,ax		    ;save fat-num     ;
	    sar     ax,1		    ;div by 2	      ;
	    pushf			    ;save low bit     ;
	    add     si,ax		    ;clus + clus/2    ;
	    mov     bx,word ptr [bx][si]    ;	    b = b[i];
	    popf			    ;get low bit      ;
;	    $IF     C
	    JNC $$IF3
		mov	cl,4			;	    b >>= 4;
		shr	bx,cl			;
;	    $ENDIF
$$IF3:
getfat1:    and bh,0fh	     ;even fat-num  ;	    b &= 0xFFF
	    pop     ax			    ;	    }
;	$ENDIF
$$EN1:
getret: mov	cx,secsiz		;   c = SecSize;
	return
EndProc GetFat

;
	break	<SetFat - change the contents of a fat element>
;*****************************************************************************
;   SetFat - given a fat index and a value, change the contents of the fat
;   cell to be the new value.
;
;   Inputs:	AX contains the fat cell to change
;		DX contains the new value to put into the fat cell
;   Outputs:	FAT [AX] = DX
;   Registers Revised: CX, SI
;
; LARGE FAT SUPPORT  - if this is a 16-bit fat, use the new calc algorithm
; *****************
;*****************************************************************************
Procedure SetFat,NEAR
	set_data_segment
	lea	bx,fattbl		;   b = &Table;
	cmp	MaxClus,4086 ;12 bit fat?   if (MaxClus >= 4086) {
;	$IF	AE  ;changed to above because max clusters now 'ffff'hex
	JNAE $$IF6
	    call    calc_fat_addr	    ; calc the fat cell addr
	    mov     word ptr es:[bx],dx     ; get the contents
;	$ELSE
	JMP SHORT $$EN6
$$IF6:
setsmall:   SaveReg <ax,dx>  ;yes, 12 bit fat
	    mov     si,ax    ; fat cell number	    i = clus + clus / 2;
	    sar     ax,1     ; fat cell num /2
	    pushf	     ; save result if ax was odd
	    add     si,ax    ; offset = 1 1/2 bytes * fat cell num
	    mov     ax,word ptr [bx][si]    ; get contents of fat cell
	    popf    ; get results from div  ;	    if ((clus&1) != 0) {
;	    $IF     C	; was fat cell num odd?
	    JNC $$IF8
		and	ax,000fh   ;yes 	;keep unchanged part
		mov	cl,4			;	    d <<= 4;
		shl	dx,cl
;	    $ELSE
	    JMP SHORT $$EN8
$$IF8:
setfat2:	and	ax,0f000h  ; no, even	;keep unchanged part
;	    $ENDIF
$$EN8:
setfat1:    or ax,dx		   ; move new value into ax
	    mov     word ptr [bx][si],ax    ;	    b[i] = a;
	    RestoreReg <dx,ax>
;	$ENDIF
$$EN6:
setret: return				;   return;
EndProc SetFat

;
	Break	<GetKeystroke - await a single keystroke and flush all remaining>
;*****************************************************************************
;   GetKeystroke - let the user hit a key and flush the input buffer.  Kanji/
;   Taiwanese force this
;
;   Inputs:	None.
;   Outputs:	None.
;   Registers Revised: AX
;*****************************************************************************
Procedure GetKeystroke,NEAR
	MOV	AX,(Std_CON_Input_Flush SHL 8) + Std_CON_Input_No_Echo
	INT	21H
	MOV	AX,(Std_CON_Input_Flush SHL 8) + 0
	INT	21H
	return
EndProc GetKeystroke


;*****************************************************************************
;PROMPT
;*****************************************************************************
Procedure Prompt,NEAR
	Cmp	Prompted,0
	retnz
	MOV	Prompted,1
	push	ds
	push	cs
; move drive letter in message
	lea	dx,askmsg
; display msg
	call	DISPLAY_interface
	pop	ax			;
	pop	ds
; wait for user
	call	GetKeystroke

	    MOV     AL,cs:DRIVE 	; This is for ibm's single drive sys
	    CMP     AL,1
	    JA	    NOSET		; Values other than 0,1 are not appropriate.
	    PUSH    DS
	    MOV     BX,50H
	    MOV     DS,BX
	    MOV     DS:(BYTE PTR 4),AL	; Indicate drive changed
	    POP     DS
NOSET:

	return
EndProc Prompt


;
	Break	<Load	- set up registers for abs sector read/write>
;******************************************************************************
;   Load - load up all registers for absolute sector read/write of FAT
;
; called by: readft, writeft
;
;   Inputs:	none.
;   Outputs:	AL    - drive number (a=0)
;		ES:BX - point to FAT table
;		CX    - number of sectors in FAT
;		DX    - sector number of the first FAT sector
;		FatCnt - is set to the number of fats
;   Registers Revised: ax, dx, cx, bx
;******************************************************************************
Procedure Load,NEAR
	set_data_segment
	mov	dx,firfat		;sector number of first fat 1-65535
	mov	al,fatnum		;number of fats 	    2
	mov	fatcnt,al		;FatCnt = FatNum;	    1-65535
	mov	al,drive		;drive number		    a=0 b=1
	mov	cx,fatsiz		;sectors in the fat	    1-65535
	lea	bx,fattbl		; es:bx --> fat table
	return
EndProc Load

	Break	<ReadFT - read in the entire fat>
;******************************************************************************
;   ReadFt - attempt to read in the fat.  If there are errors, step to
;   successive fats until no more.
;
;   Inputs:	none.
;   Outputs:	Fats are read until one succeeds.
;		Carry set indicates no Fat could be read.
;   Registers Revised: all
; LOGIC
; *****
;  DO for each of the fats on the disk:
;     read - all the sectors in the fat
;     increase the starting sector by the number of sectors in each fat
;
; LARGE FAT SUPPORT - the big change here is in read disk.  since the fat must
;     be within the first 32M, then the starting sector number of 65535 is ok,
;     as is a larger number of sectors to read/write.
;******************************************************************************
Procedure ReadFt,NEAR
	set_data_segment
	mov	dx,firfat		;sector number of first fat 1-65535
	mov	al,fatnum		;number of fats 	    2
	mov	fatcnt,al		;FatCnt = FatNum;	    1-65535
	mov	al,drive		;drive number		    a=0 b=1
	mov	cx,fatsiz		;sectors in the fat	    1-65535
	lea	bx,fattbl		; es:bx --> fat table
	clc				;clear carry flag
	mov	Read_Write_Relative.Start_Sector_High,bp ;set hi word to zero
	call	Read_Disk		; read in fat #1
;	$IF  C				; was it a bad read?
	JNC $$IF12
	    add     dx,cx		;point to 2nd fat
	    call    Read_Disk		; read in 2nd fat
;	$ENDIF				;carry flag set if both fats bad
$$IF12:
ret
EndProc ReadFt


;
	Break	<WrtFat - write out the fat>
;*****************************************************************************
;   WrtFat - using the results of a ReadFt, attempt to write out the fat
;   until successful.
;
;   Inputs:	none.
;   Outputs:	A write of the fat is attempted in each fat position until
;		one succeeds.
;   Registers Revised: all
; LOGIC
; *****
;    DO for each fat on the disk
;	write the fat to disk
;	increase the starting sector number by the number of sectors per fat
;
; LARGE FAT SUPPORT - the big change here is in read disk.  since the fat must
;     be within the first 32M, then the starting sector number of 65535 is ok,
;     as is a larger number of sectors to read/write.
;****************************************************************************
Procedure WrtFat,NEAR
	call	load			;   load ();
;	$DO
$$DO14:
wrtit:	    call    Write_Disk		    ;	    Write_Disk ();
;	    $LEAVE  C
	    JC $$EN14
wrtok:	    add     dx,cx		    ;	    fatStart += fatsize;
	    dec     byte ptr fatcnt	    ;	} while (--fatcnt);
;	$ENDDO	Z
	JNZ $$DO14
$$EN14:
	return
EndProc WrtFat


;
	Break	<fEOF	- check to see if the argument is EOF>
;*****************************************************************************
;   fEOF - test BX to see if it indicates EOF
;
;   Inputs:	BX - contains cluster
;   Outputs:	Carry is set if BX indicates EOF
;   Registers Revised: none
;*****************************************************************************
Procedure fEOF,NEAR
    CMP     BX,MaxClus
	JBE	EOFok
	CMP	BL,0F7h 		; bad sector indicator
	JZ	EOFok
	STC
	return
EOFok:	CLC
	return
EndProc fEOF


;*****************************************************************************
;*****************************************************************************


;
	Break	<sfFromFCB - take an FCB and convert it to a sf pointer>
;*****************************************************************************
; SFFromFCB - index into System File tables for SFN.
;
;   Input:	ES:DI has FCB pointer
;   Output:	ES:DI points to Sys-File-table entry
;   Registers Revised: ES:DI, BX only
;
;*****************************************************************************
procedure SFFromFCB,NEAR
	MOV	BL,ES:[DI].FCB_SFN ;fcb+18 = system file table 00
	XOR	BH,BH		   ; 00
	SaveReg <AX,BX>
	MOV	AH,Get_IN_Vars		;52h
	INT	21h			;   p = DOSBASE();
					; bx = 0026, ax=5200 es=0257
	LES	DI,DWORD PTR ES:[BX].SYSI_FCB ;load es:di w/ ptr to sf table
					; es:di = 0b37:0000
	LEA	DI,[DI].sfTable 	; di=6			  AC000;bgb
	RestoreReg <BX>
	SaveReg <DX>
	MOV	AX,SIZE SF_Entry	;42
	MUL	BX			;0
	ADD	DI,AX			;6
	RestoreReg <DX,AX>
	return				;   return p;
EndProc SFFromFCB

;*****************************************************************************
;*****************************************************************************
Procedure get_dpb_info,Near
; get dpb for drive indicated
	push	ds			;save ds seg reg
	mov	dl,drive		; get drive number a=0 b=1 c=2
	inc	dl			; a=1, b=2, c=3
	mov	ah,GET_DPB		; hidden system call (032h)
	int	21h			; call dos
; note: ds is now changed !!!!
	cmp	al,0FFH 		; -1 = bad return code
;	$IF	NZ
	JZ $$IF17
; get sector size
	    mov     ax,word ptr [bx].dpb_sector_size ; get physical sector size
	    mov     es:bytes_per_sector,ax ; save bytes per sector 200
; get sectors per cluster
	    xor     ch,ch		; zero out high byte
	    mov     cl,byte ptr [bx].dpb_cluster_mask ; get sectors/cluster - 1
	    inc     cx			;1+1=2		  ; get sectors / cluster
	    mov     es:secall,cx	;2	   ; save sectors per cluster
; get bytes per cluster
	    mul     cx			; ax = bytes per cluster
	    mov     eS:secsiz,ax	;400	   ; save bytes per cluster
; first sector record
	    mov     ax,[bx].dpb_first_sector ; get record of first sector
	    mov     es:firrec,ax	;c	   ;
;first	 dir	 entry
	    mov     dx,[bx].dpb_dir_sector ; get record of first directory entry
	    mov     es:firdir,dx	;5	   ;
; first fat record
	    mov     si,[bx].dpb_first_fat ; get record of first fat
	    mov     es:firfat,si	;1     ; sector number of first fat
; records in fat
	    mov     cX,[bx].dpb_fat_size ; get size of fat (num of rcds)
	    mov     es:fatsiz,cX	;2	      ;SIZE OF FAT FROM DPB
; number of cluster
	    mov     di,[bx].dpb_max_cluster ; get number of clusters
	    mov     es:lastfat,di	;163	     ; number of fat entries
	    mov     es:MaxClus,di	;163	     ; number of fat entries
; number of fats (1 or 2)
	    mov     ch,[bx].dpb_fat_count ; get number of fats on drive
	    mov     byte ptr es:fatnum,ch ;2   ; save number of fats on disk
; max dir entries
	    mov     bx,[bx].dpb_root_entries ; get max number of dir entries
	    mov     ES:maxent,bx	;70	   ;
	    pop     ds			; restore ds register to group
;	$ELSE
	JMP SHORT $$EN17
$$IF17:
	    pop     ds			; restore ds register to group
	    jmp     noname		; bad return = display error msg
;	$ENDIF
$$EN17:
	ret				;
endproc get_dpb_info			    ;
;

;
;*****************************************************************************
; assemble this part if doing japanese version
;
;INPUTS:  es:di - points to last char in filename
;	  ds:dx - point to beginning of filename
;
;*****************************************************************************
Procedure check_kanji,Near
	IF	KANJI
	    lea     dx,[fname_buffer]	;point to filename
	    PUSH    DX			;save regs
	    PUSH    DI			;save regs
	    MOV     BX,DI		;bx and di now point to last char in filename
	    MOV     DI,DX		;di now points to filename

;do for entrire filename
delloop:    CMP     DI,BX		;are we at the beginning of the filename?
	    JAE     GOTDELE		;yes, and we are finished
	    MOV     AL,[DI]		;get next char in filename
	    INC     DI			;point one past it
	    CALL    TESTKANJ		;see if it is dbcs
	    JZ	    NOTKANJ11
	    INC     DI			;bump to past 2nd of dbcs pair
	    JMP     DELLOOP		;check next char in file name
notkanj11:  cmp     al,[dirchar]	;is it '\' ?
	    JNZ     DELLOOP		;no, check next char
	    MOV     DX,DI		; Point to char after '/'
	    DEC     DX
	    DEC     DX			; Point to char before '/'
	    JMP     DELLOOP

;completed filename
gotdele:    MOV     DI,DX ;point to?
	    POP     AX			; Initial DI
	    POP     DX	  ;re-point to beginning of filename
	    SUB     AX,DI		; Distance moved
	    SUB     CX,AX		; Set correct CX
;	    CMP     DX,DI
;stop:	     $if     b
;		pop ax
;		pop cx
;		jmp sja
;;;;;;;;;;;;;;; JB	sja		    ; Found a pathsep
;	    $endif
;	    $if     a
;		pop ax
;		pop cx
;		jmp sjb
;;;;;;;;;;;;;;; JA	sjb		    ; Started with a pathsep, root
;	    $endif
	    MOV     AX,[DI]
	    CALL    TESTKANJ
	    JNZ     same_dirjk
	    XCHG    AH,AL
;	    cmp     al,[dirchar]
;	    $if     z
;		pop ax
;		pop cx
;		jmp sja
;;;;;;;;;;;;;;;;jz	sja		    ; One character directory
;	    $endif
same_dirjk:
	    ret
	ENDIF
check_kanji endp			;
;

;****************************************************************************
;****************************************************************************
	break
	IF	KANJI
TESTKANJ:   push    ds		 ;get dbcs vector
	    push    si
	    push    ax
	    mov     ax,6300h	 ;get dbcs vector
	    int     21h
	    pop     ax
	    sub     si,2	 ;prep for loop
dbcsmore:
	    add     si,2		;point to next dbcs vector
	    cmp     word ptr ds:[SI],bp ;do until 00 found in dbcs vector table
	    je	    notlead		;00 found, quit
	    CMP     AL,byte ptr ds:[si] ;look at lead byte of dbcs char
	    jb	    dbcsmore		;al < lead byte means not dbcs
	    CMP     al,byte ptr ds:[si+1] ;look at 2nd byte of dbcs
	    JBE     ISLEAD  ;if it is between the 2 chars, it is dbcs
	    jmp     dbcsmore	 ;go get the next dbcs vector

NOTLEAD:
	    PUSH    AX
	    XOR     AX,AX		; Set zero
	    POP     AX
	    pop     si
	    pop     ds
	    RET
ISLEAD:
	    mov     es:dbcs_sw,1
	    PUSH    AX
	    XOR     AX,AX		; Set zero
	    INC     AX			; Reset zero
	    POP     AX
	    pop     si
	    pop     ds
	    RET
	ENDIF






;*****************************************************************************
; copy the filename from the fcb to the data segment
;*****************************************************************************
Procedure copy_fname,Near
;get fcb1 from the psp
slashok: mov	 cx,PSP_Segment 	 ;Get addrbility of psp
	mov	ds,cx			;  "  "    "  "  "  "
	assume	ds:dg,es:dg		; "   "    "  "  "  "
	call	get_fcb


; remove leading blanks and tabs from filename
nofspec: mov	 si,81h 		 ; point to command line
	lea	di,fname_buffer 	; point to filename
	xor	cx,cx			; zero pathname length
;	$DO		;get source chars until neither tabs or blanks found
$$DO20:
kill_bl:    lodsb			; get next char
	    cmp     al,tab		; leading tabs? (hex 9)
;	$LEAVE	NE,AND			; yes - done
	JE $$LL21
	    cmp     al,' '		; leading blanks? (hex 20)
;	$LEAVE	NE
	JNE $$EN20
$$LL21:
;	$ENDDO				;
	JMP SHORT $$DO20
$$EN20:
;

;was any parameter entered at all?
endl:	cmp	al,13			; no name found if the 1st char is CR
	jne	next_char		; file name or drive entered
	jmp	noname			; no parameter entered



;copy filename from cmd line to fname buffer
next_char:
	stosb				; move byte in al to fname_buffer
	inc	cx			;inc fname counter
	lodsb				; get next byte
	cmp	al,' '			; terminated by blank?
	je	name_copied		; yes
	cmp	al,9			;terminated by tab?
	je	name_copied		; yes
	cmp	al,13			; terminated by CR?
	jne	next_char		; yes


;reset ds to data segment
name_copied:				; got file name
	push	es
	pop	ds			;ds now points to data seg
	assume	ds:dg

	mov	byte ptr [di],0 	; nul terminate the pathname
	dec	di			; adjust to the end of the pathname
	    ret
copy_fname  endp			;




;*****************************************************************************
; get a copy of the fcb
;*****************************************************************************
Procedure get_fcb,Near
	mov	si,fcb			; ds:si point to fcb in the psp
	lea	di,fcb_copy		; es:di point to the copy in the data seg
	mov	cx,32			; move 32 bytes
	rep	movsb			; from ds:si (fcb) to es:di (fcb-copy)
;check if it is not there (in psp)
;	mov	si,fcb			;point to fcb1
;	cmp	byte ptr ds:[si+1],' '	;it will be blank if a filespec used
;	$IF	E,AND
;	cmp	byte ptr ds:[84h],0dh	;this will be CR if drive letter used
;	$IF	NE	    ;if no drive letter and fcb blank, then filespec!
;now get the filename from the command line
; step 1 - point to end of cmd line
	    mov     si,081h		;point to beginning of command line
	    mov     cl,byte ptr ds:[80h] ;get length of cmd line
	    xor     ch,ch		;zero out hi byte for word arith
	    add     si,cx		;begin plus length of cmd line = end
	    dec     si			;point to last char, not CR
;step 2 - find the first backslash
	    mov     exit_sw,bp ;false
;	    $DO 			;do until back slash found
$$DO23:
		cmp	byte ptr ds:[si],'\'	 ;look for back slash
;		$IF	E		;find it?
		JNE $$IF24
		    mov     al,[si-1]	;get possible leading byte
		    IF KANJI
		    call    testkanj	;is it a leading byte of DBCS?
		    ENDIF
;		    $IF     Z		;no- then it is subdir delimiter
		    JNZ $$IF25
			mov exit_sw,true    ;so exit the search loop
;		    $ELSE		;yes it is DBCS leading byte
		    JMP SHORT $$EN25
$$IF25:
			dec	si	;so skip the leading byte
;		    $ENDIF		;check for kanji
$$EN25:
;		$ENDIF
$$IF24:
		cmp	exit_sw,true
;		$LEAVE	E
		JE $$EN23
		cmp	byte ptr ds:[si],0	 ;look for 00 (not a filespec)
;		$IF	E
		JNE $$IF30
		    ret
;;;;;;;;;;;;;;;;je	nofspec 	;filespec not found
;		$ENDIF
$$IF30:
		dec	si		;no , next char
;	    $ENDDO
	    JMP SHORT $$DO23
$$EN23:
;found backslash, move it into fcb
	    inc     si			;point to 1st char of filename
	    lea     di,fcb_copy+1	    ; move addr of fcb_copy into di
;	    $DO 			;do until eol - CR found
$$DO33:
		lodsb			;get one byte of filename from cmd line
		cmp	al,0dh		;end of line?
;		$LEAVE	E		;if so, we are done
		JE $$EN33
		cmp	al,'.'		;is it extension indicator?
;		$IF	E		;yes
		JNE $$IF35
		    lea     di,fcb_copy ;point to extension in fcb
		    add     di,9	;point to extension in fcb
;		$ELSE			;dont move the period
		JMP SHORT $$EN35
$$IF35:
		    stosb		;move char into fcb
;		$ENDIF
$$EN35:
;	    $ENDDO
	    JMP SHORT $$DO33
$$EN33:
;	$ENDIF
	    ret
get_fcb  endp			     ;
;
	Break	<Main	code of recover - Version check and exit if incorrect>
;*****************************************************************************
;Routine name:	Main_routine
;*****************************************************************************
;
;description: Main routine for recovering a file from a bad sector
;
;Called from:	recover_ifs in RECINIT.SAL
;
;
;Called Procedures: prompt
;		    readft
;		    read_file
;		    getfat (sic)
;		    feof
;		    sffromFCB
;		    bad-file-read
;		    report
;		    wrtfat
;		    stdprintf
;		    RECPROC.SAL
;
;Input: ????
;
;Output: FAT is changed if a bad sector is found.
;	 The file is complete except for the data in the bad sector.
;
;Change History: header created 7-19-87 	BGB
;
;Psuedocode
;----------
;
;*****************************************************************************
Main_Routine:

;get system switch character
	xor	bp,bp
	set_data_segment		; set es,ds to data
		;;;;;;; call	change_blanks		; get dbcs blanks
	mov	ax,(char_oper shl 8)	; get switch character
	int	21h			; put into dl
	cmp	dl,"/"			; is it / ?
;	$IF	nz
	JZ $$IF39
	    jmp     slashok		    ; if not / , then not PC
;	$ENDIF
$$IF39:
	mov	[dirchar],"\"	     ; in PC, dir separator = \
	mov	[userdir],"\"

	call	copy_fname

;check for dbcs double byte chars
	push	di
	push	cx
	call	check_kanji
same_dirj:
	pop	cx
	pop	di
	mov	lastchar,di


;see if there are any '\' in filename parameter - means filespec
;do until a \ is found or end-of-string
;	  if a \ is found
;	     then test for dbcs leading byte
;		  if it is not dbcs leading byte
;		     then exit loop
;		     else continue loop
;   $DO
$$DO41:
	dec	cx
	and	cx,cx ;compare cx to zero
;   $LEAVE  E
    JE $$EN41
	mov	al,[dirchar]	    ;05ch ; get directory separator character
	cmp	al,byte ptr [di]    ; (cx has the pathname length)
;	$IF	E			; reset direction, just in case
	JNE $$IF43
	    mov     al,[di-1]	    ;get possible leading byte
	    IF KANJI
	       call    testkanj     ;see if it is leading byte
	    ENDIF
;	    $IF      Z		    ;not a leading byte? then its a '\'
	    JNZ $$IF44
		mov lastbs,di
		mov di,lastchar
		jmp sja 	    ;zero = not a leading byte
;	    $ENDIF
$$IF44:
;	$ENDIF
$$IF43:
	dec	di
;   $ENDDO
    JMP SHORT $$DO41
$$EN41:
;save current disk
	mov	ah,19h
	int	21h
	mov	old_drive,al
	jmp	same_dir		; no dir separator char. found, the
					; file is in the current directory
					; of the corresponding drive. Ergo,
					; the FCB contains the data already.


;handle filespec here
;at least one '\' found in filename
sja:
	jcxz	sjb			; no more chars left, it refers to root
	push	di
	mov	di,lastbs
	cmp	byte ptr [di-1],':'	  ; is the prvious character a disk def?
	pop	di
	jne	not_root
sjb:
	mov	[the_root],01h		; file is in the root
not_root:
	inc	di			; point to dir separator char.
	mov	ax,bp ;set to zero
	stosb				; nul terminate directory name
;	pop	ax
;	push	di			; save pointer to file name
	mov	[fudge],01h		; remember that the current directory
					; has been changed.
;save current disk
	mov	ah,19h
	int	21h
	mov	old_drive,al
;----- Save current directory for exit ---------------------------------;
	mov	dl, drive		; get specified drive if any
;;;;;;; or	dl,dl			; default disk?
;;;;;;; jz	same_drive
;;;;;;;;dec	dl			; adjust to real drive (a=0,b=1,...)
	mov	ah,set_default_drive	; change disks
	int	21h
;	cmp	al,-1			; error?
;	jne	same_drive
;BADDRVSPEC:
;	 lea	 dx,baddrv
;	 jmp	 printerr

same_drive:
	call	prompt
	mov	ah,Current_Dir		; userdir = current directory string
	mov	dx,bp ;set to zero
	lea	si,userdir+1
	int	21h

;----- Change directories ----------------------------------------------;
	cmp	[the_root],01h
	lea	dx,[dirchar]		; assume the root
	je	sj1
	lea	dx,[fname_buffer]
sj1:
	push	di
	mov	di,lastbs
	mov	byte ptr [di],0
	mov	ah,chdir		; change directory
	int	21h
	mov	byte ptr [di],'\'
	pop	di
	mov	al,Drive		;Get drive number
	add	al,"A"-1		;Make it drive letter
	mov	Drive_Letter_Msg,al	;Put in message
	lea	dx,baddrv
	jnc	no_errors
	call	printerr
	jmp	rabort

;
no_errors:

	Break	<Set	up exception handlers>

;----- Parse filename to FCB -------------------------------------------;
;	pop	si
	mov	si,lastbs
	inc	si
	lea	di,fcb_copy
	mov	ax,(parse_file_descriptor shl 8) or 1
	int	21h
;;;;;;;;push	ax
;-----------------------------------------------------------------------;
same_dir:
	lea	bx,fcb_copy		;point to 1st byte of fcb (drive num)
	cmp	byte ptr [bx+1],' '	; must specify file name
	jnz	drvok
	cmp	byte ptr [bx],0 ;or drive specifier
	jnz	drvok
	cmp	dbcs_sw,1		; or dbcs
	jz	drvok
noname:
	push	es
	pop	ds
	lea	dx,baddrv
	call	display_interface
	pop	ax		 ;reset stack
	pop	ax		 ;reset stack
	jmp	int_23
;****************************************************************************
; we're finished with parsing here, do the main function of recover.
drvok:
	CALL	Prompt			;wait for user keystroke to begin
	call	get_dpb_info		;get device info
	call	fill_fat		; fill fat table w/ null
;	$IF	C			;was there not enuff memory to run?
	JNC $$IF48
	    lea     dx,no_mem_arg	;
	    call    printerr
	    jmp     rabort
;	$ENDIF				;fat could be read from disk
$$IF48:

	call	readft			;   readft ();
;	$IF	C			; could the fat be read from disk?
	JNC $$IF50
	    lea     dx,FATErrRead	;
	    call    printerr
	    jmp     rabort
;	$ENDIF				;fat could be read from disk
$$IF50:
See_If_File:				;
	lea	bx,fname_buffer 	;
	cmp	byte ptr [bx+1],':'	;if fname = 'a:' and.....
;	$IF	E,AND			    ;
	JNE $$IF52
	cmp	word ptr [bx+2],bp ;set to zero       ;all zeros following that, then
;	$IF	E			;then drive spec
	JNE $$IF52
	    call    drive_spec		;only drive specified
;	$ELSE				; file name specified
	JMP SHORT $$EN52
$$IF52:
	    call    file_spec ;file can be 'f' or 'a:,0,file' or 'a:file' or 'file.ext'
;	$ENDIF
$$EN52:


int_23: sti				;allow interrupts
	lds	dx,cs:dword ptr [int_24_old_off]     ;point to old vector
	mov	al,24h			;which interrupt to set?
	DOS_Call Set_Interrupt_Vector	;set vector to old

	lds	dx,cs:dword ptr [int_23_old_off]     ;point to old vector
	mov	al,23h			;which interrupt to set?
	DOS_Call Set_Interrupt_Vector	;set vector to old

	PUSH	CS			;reset ds
	POP	DS
aSSUME	DS:DG
	call	rest_dir
	mov	cs:ExitStatus,0 	   ; good return
	jmp	[exitpgm]
rabort:
	ret				;Return to RECINIT for exit
					; mov	  ah,exit
					; int	  21h


;*************************************************************************
; DO until either
;*************************************************************************
procedure file_spec,near
; try to open the file
recfil: lea	dx,fcb_copy		;   if (FCBOpen (FCB) == -1) {
	mov	ah,FCB_OPEN   ; function ofh = open
	int	21h			;returns -1 in al if bad open
	cmp	al,0ffh 		;was file opened ok?
;	$IF	E			; no
	JNE $$IF55
; display error msg
	    lea     si,FCB_Copy.fcb_name ;Point at filename in FCB	 ;
	    lea     di,Fname_Buffer	;Point at buffer		;
	    mov     cx,FCB_Filename_Length ;Length of filename
	    call    Change_Blanks	;Convert DBCS blanks to SBCS
	    call    Build_String	;Build ASCIIZ string ending
	    lea     dx,opnerr		; AC000;SM	printf (Can't open);
	    call    display_interface
;ecfil0: $ELSE				;   LastFat = 1;
recfil0:
	 JMP SHORT $$EN55
$$IF55:
f_exists:   call    process_file	;file was opend ok
rexit1:     mov     ah,DISK_RESET
	    int     21h
	    call    wrtfat		; save the fat
;	    $IF     C			;Couldn't write it
	    JNC $$IF57
		lea	dx,FATErrWrite	;Just tell user he is in deep!
		call	display_interface ;
;	    $ELSE
	    JMP SHORT $$EN57
$$IF57:
		call	report			    ;	report ();
;	    $ENDIF
$$EN57:
;	$ENDIF
$$EN55:
	ret
endproc file_spec

;*************************************************************************
; DO until either
;*************************************************************************
Procedure process_file,Near		    ;
recfile0:
    mov     lastfat,1			;set to 1 : means 1st fat read in
    lea     di,fcb_copy 		;   d = &FCB
    mov     ax,[di].FCB_FilSiz		;55    siztmp = filsiz = d->filsiz;
    mov     filsiz,ax
    mov     siztmp,ax
    mov     ax,[di].FCB_FilSiz+2	;00
    mov     filsiz+2,ax
    mov     siztmp+2,ax
    SaveReg <ES,DI>			;   fatptr =
    call    sfFromFCB			;	sfFromFCB(d)->firclus;
    mov     ax,ES:[DI].sf_firclus	; es:di +0b = 84
    RestoreReg <DI,ES>
    mov     fatptr,ax
    or	    ax,ax			;   if (fatptr == 0)
;   $IF     NZ
    JZ $$IF61
; read each fat in the file
;	$DO				;Loop until entire file read in
$$DO62:
	    mov     bx,fatptr		;Get current cluster
	    call    fEOF		;Got to the end of the file?
;	$LEAVE	C			;Yes if CY
	JC $$EN62
STOP_read:	call	Read_File	;Go read in the cluster
;	    $IF     C			;CY indicates an error
	    JNC $$IF64
		call	Bad_File_Read	;Go play in the FAT
;	    $ELSE			;Read cluster in okay
	    JMP SHORT $$EN64
$$IF64:
		mov	ax,secsiz	;Get bytes/cluster
		sub	siztmp,ax	;Is size left < 1 cluster?
		sbb	siztmp+2,bp ;zero      ;
;		$IF	C		;Yes
		JNC $$IF66
		    xor     ax,ax	;Set our running count to 0
		    mov     siztmp,ax
		    mov     siztmp+2,ax
;		$ENDIF
$$IF66:
		mov	ax,fatptr	;The previous cluster is now
		mov	lastfat,ax	; the current cluster
;	    $ENDIF			;AX has current cluster
$$EN64:
	    call    getfat		;Get the next cluster
	    mov     fatptr,bx		;Save it
;	$ENDDO				;Keep chasing the chain
	JMP SHORT $$DO62
$$EN62:
;   $ENDIF				;All done with data
$$IF61:
; recover extended attributes
;   SaveReg <ES,DI>			;Save regs
;   call    sfFromFCB			;Get sf pointer
;   mov     ax,[di].sf_ExtCluster	;Look at extended attrib entry
;   cmp word ptr [di].sf_ExtCluster,bp ;zero   ;Is there extended attribs?     ;;an032;bgbAN000;
;   $IF     NE				;Yes
;	call	Read_File		;Try to read it in
;	$IF	C			;CY means we couldn't
;	    mov word ptr [di].sf_ExtCluster,bp ;zero	     ;Off with its head!
;	    and ES:[di].sf_flags,NOT devid_file_clean ; mark file dirty
;	$ENDIF				;
;   $ENDIF				;
;   RestoreReg <DI,ES>			;
    lea     dx,fcb_copy 		;   close (FCB);
    mov     ah,FCB_CLOSE
    int     21h 			;
  return
endproc process_file

;*************************************************************************
;***************************************************************************
	break
;----- Restore INT 24 vector and old current directory -----------------;
Procedure Rest_dir,Near 		;
	cmp	cs:[fudge],0
;	$IF	NE
	JE $$IF71
	    mov     ax,(set_interrupt_vector shl 8) or 24h
	    lds     dx,cs:[hardch]
	    int     21h
	    push    cs
	    pop     ds
	    lea     dx,userdir		    ; restore directory
	    mov     ah,chdir
	    int     21h
;	$ENDIF
$$IF71:
no_fudge:
	mov	dl,old_drive		; restore old current drive
	mov	ah,set_default_drive
	int	21h
	ret
endproc rest_dir

;;----- INT 24 Processing -----------------------------------------------;
;*************************************************************************
	int_24_retaddr dw int_24_back

	int_24	proc	far
	assume	ds:nothing,es:nothing,ss:nothing
	pushf				; ** MAKE CHANGES **
	push	cs
	push	[int_24_retaddr]
	push	word ptr [hardch+2]
	push	word ptr [hardch]
	assume	ds:dg,es:dg,ss:dg
	ret
endproc int_24
;*************************************************************************
int_24_back:
	cmp	al,2			; abort?
	jnz	ireti
	push	cs
	pop	ds
assume	ds:dg,es:dg,ss:dg
	call	rest_dir
	ret				;Ret for common exit
ireti:
	iret

	break	< read in a cluster of the file>
;****************************************************************************
; READ_FILE
;Read in cluster of file.
;
; Input: Secall = sectors/cluster
;	 FatPtr = cluster to read
;	 Firrec = Start of data area - always in first 32mb of partition
;	 dx	= offset of fcb_copy ???
;
; Output: CY set if error on read on ret
;	  DI = pointer to FCB
;*****************************************************************************
Procedure Read_File,Near		;
	mov	cx,secall   ;2		;if (aread((fatptr-2)*secall+firrec) == -1) {
	mov	ax,fatptr   ;84 	;cluster number to read
	sub	ax,2	    ;ax=82	; -1
	mul	cx	    ;ax=104	; sectors/clus * (clus-2)
	add	ax,firrec   ;ax=110	; plus beg of data area
	adc	dx,bp	    ;0		;Handle high word of sector
	mov	Read_Write_Relative.Start_Sector_High,dx ;Start sector
	mov	dx,ax	    ;110	;clus-2
	mov	es,table    ;2b62	;segment of area past fat table
	xor	bx,bx			;es:bx --> dir/file area
	mov	al,drive    ;0		;drive num
	call	Read_Disk		;	    ;
	lea	di,fcb_copy		;
	ret				;
endproc Read_File			    ;


	break	< found a bad cluster in the file >
;*************************************************************************
;Play around with the FAT cluster chain, by marking the cluster that failed
;to read as bad. Then point the preceding cluster at the one following it.
;Special case if there is only one cluster, than file gets set to zero
;length with no space allocated.
;
; Input: FatPtr = Cluster that failed to read
;	 LastFat = Previous cluster, equals 1 if first cluster
;
; Output: AX = previous cluster
;	  File size = file size - cluster size ( = 0 if cluster size > file)
;***************************************************************************
Procedure Bad_File_Read,Near
	mov	ax,fatptr		;Get current cluster
	call	getfat			;Get the next cluster in BX
	cmp	lastfat,1		;Is this the first entry?
;	$IF	E			;Yes
	JNE $$IF73
	    call    fEOF		;Is the next the last cluster?
;	    $IF     C			;Yes
	    JNC $$IF74
		xor	bx,bx		;Need to zero out first cluster
;	    $ENDIF			; because the first one is bad!
$$IF74:
	    SaveReg <ES,DI,BX>		;Save some info
	    call    sfFromFCB		;Get pointer to sf table
	    RestoreReg <BX>		;Get back clus to point to
	    mov     ES:[DI].sf_firclus,BX ;Skip offending cluster
	    RestoreReg <DI,ES>		;Get back regs
;	$ELSE				;Not first entry in chain
	JMP SHORT $$EN73
$$IF73:
	    mov     dx,bx		;DX = next cluster
	    mov     ax,lastfat		;AX = Previous cluster
	    call    setfat  ;prev fat points to next fat
					; offending cluster
;	$ENDIF				; Ta-Da!
$$EN73:
	mov	ax,fatptr		;Get the offending cluster
	mov	dx,0fff7h		;Mark it bad
	call	setfat			;Never use it again!
	mov	ax,secsiz		;Get bytes/sector
	cmp	siztmp+2,bp		;Is file  < 32mb long?
;	$IF	NE,AND			;     and
	JE $$IF78
	cmp	siztmp,ax		;Shorter than cluster size?
;	$IF	BE			;Yes
	JNBE $$IF78
	    mov     ax,siztmp		;File size = smaller of the two
;	$ENDIF
$$IF78:
	SaveReg <ES,DI> 		;Save regs
	call	sfFromFCB		;Get sf pointer
sfsize: sub	word ptr ES:[di].sf_size,ax ;Adjust internal file sizes
	sbb	word ptr ES:[di].sf_size+2,bp ;   "  "	 "  "
	sub	siztmp,ax		;Keep track of how much done
	sbb	siztmp,bp		 ;
	and	ES:[di].sf_flags,NOT devid_file_clean ; mark file dirty
	RestoreReg <DI,ES>		;	    sfFromFCB(d)->flags &= ~CLEAN;
	lea	di,fcb_copy
	sub	word ptr [di].fcb_filsiz,ax ;And change the FCB
	sbb	word ptr [di].fcb_filsiz+2,bp ;
	and	byte ptr [di].fcb_nsl_bits,NOT devid_file_clean ; mark file dirty
	mov	ax,lastfat		;AX = previous cluster
	ret				;
endproc Bad_File_Read			    ;


;*****************************************************************************
; description: fill the fat table in memory with the 'E5' character
; called from: main-routine
;Change History: Created	8/7/87	       bgb
;Input: bytes-per-sector
;	fatsiz
;	maxent
;Output: ram-based fat table
; LOGIC
;----------
;	calc number of para in fat table
;	    = bytes-per-sector / 16 * sectors-per-fat
;	calc segment of directory area in memory
;	    = fat-table offset + length of fat-table
;	calc number of para in directory
;	    = entries-per-directory * bytes-per-entry / 16
;	do for each para
;	   move 16 bytes into memory
;*****************************************************************************
	  even
Procedure fill_fat,Near
; calc fat table length
	set_data_segment
	mov	ax,bytes_per_sector	; bytes per sector
	xor	dx,dx
	mov	bx,16
	div	bx			; paras per sector
	mov	cx,fatsiz		;2	   ; get sectors per fat
	xor	dx,dx
	mul	cx			; paras per fat
	mov	paras_per_fat,ax	;length of fat in paragraphs
; calc dir area addr
	mov	bx,es
	add	ax,bx			;seg of dir area
	mov	es,ax
	lea	bx,fattbl		;off
	call	seg_adj 		;seg:off = seg:0000
	mov	table,es		;segment of beginning of fat table
; calc dir area length
	mov	ax,maxent		;ax= max dir entries
	mov	bx,32			; 32 bytes per dir entry
	xor	dx,dx
	mul	bx			; bytes per dir
	xor	dx,dx			;zero out for divide
	mov	bx,16			;divide by bytes per para
	div	bx			;paras per dir
; calc total length to fill
	add	ax,paras_per_fat ;paras/fat + paras/dir = total paras
; see if we have enough memory
    push    ax
    push    ds				;save ds reg
    mov     bx,es
    add     ax,bx			;add in starting seg of fat table
    inc     ax				; one more to go past our area
    DOS_Call GetCurrentPSP		;Get PSP segment address
    mov     ds,bx			;ds points to the psp
    Assume  DS:Nothing			;point to psp
    MOV     DX,DS:[2]			;get the last para of memory
    pop     ds
    assume  ds:dg
    cmp     dx,ax		     ;last-para must be greater or equal
;   $IF     AE		;it was, so complete filling the fat
    JNAE $$IF80
	pop	ax
;fill each para
	push	ds
	pop	es
	lea	bx,fattbl		; es:di = point to beg of fat table
	call	seg_adj
	mov	di,bx
	mov	bx,ax			;total number of paras to do
	mov	ax,0e5e5h		;fill characters  Fill (d, 16*dirent, 0xe5e5);
;	$DO				;do for each para
$$DO81:
	   mov	   cx,8 		   ; number of times to repeat
	   xor	   di,di		;bump addr pointers by 16 bytes -
	   rep	   stosw		   ; mov 2 bytes, 1 ea for 16 * num-of-entries
	   dec	   bx			;loop counter
;	$LEAVE	 Z			;until zero
	JZ $$EN81
	   mov	   dx,es		;since we move more than 64k total, we
	   inc	   dx			;have to bump es by 1 para, keeping
	   mov	   es,dx		;di at zero
;	$ENDDO
	JMP SHORT $$DO81
$$EN81:
;   $ELSE			     ;not enough memory
    JMP SHORT $$EN80
$$IF80:
	pop ax
	stc			     ;set carry flag indicating badddd!!!
;   $ENDIF
$$EN80:
    return
endproc fill_fat
;

;

;*****************************************************************************
;*****************************************************************************
Procedure printerr,Near
	push	cs
	pop	ds
	PUSH	DX			; Save message pointer
	mov	dl,[user_drive] 	; restore old current drive
	mov	ah,set_default_drive
	int	21h
	POP	DX
	call	display_interface
	mov	al,0ffh 		;   erc = 0xFF;
	ret
endproc printerr


;*************************************************************************
; CHK_FAT:
;
; inputs:  AX - last fat number for a file
;	   CX - bytes per cluster
;*************************************************************************
Procedure chk_fat,Near			;
	push es
step1a: mov	filsiz,bp		 ;start the file size at 0
	mov	word ptr filsiz+2,bp	 ;start the file size at 0
	mov	dx,MaxClus		;	dx = MaxClus;
	mov	target,ax		; target = last fat in this file
	mov	exit_sw2,bp ;false	; set exit switch to no
;	$DO	COMPLEX 		; DO until exit
	JMP SHORT $$SD86
$$DO86:
	    mov     target,ax		;    do this 2+ times around
;	$STRTDO 			;    START here 1st time
$$SD86:
step2:	    add     filsiz,cx		;add in cluster size
	    adc     word ptr filsiz+2,bp ;inc 2nd word if there was a carry
	    mov     ax,2		;start at first cluster
;	    $DO 			;DO until exit
$$DO88:
Step3:		call	getfat		;   bx= contents of fat cell
		cmp	bx,target	;   reached the end of file yet?
;	    $LEAVE   E			;   yes - return to outer loop
	    JE $$EN88
step4:		inc	ax		;   no - inc target
		cmp	ax,dx		;	target > max-clusters?
;		$IF	NBE		;	yes
		JBE $$IF90
		    mov     exit_sw2,true ;	      request exit both loops
;		$ENDIF			;
$$IF90:
		cmp	exit_sw2,true	 ;	 exit requested?
;	    $ENDDO  E			;    $ENDDO if exit requested
	    JNE $$DO88
$$EN88:
endlop2:    cmp     exit_sw2,true	 ;    outer loop test- exit requested?
;	$ENDDO	E			; ENDDO if exit requested
	JNE $$DO86
	pop es				;	else- go do mov target,ax
	ret
endproc chk_fat


;*****************************************************************************
;*****************************************************************************
	  even
Procedure main_loop1,Near
;	$DO
$$DO94:
	    call    read_fats		;inner loop AN000;bgb
	    cmp     exit_sw,true	; 1st way out of loop - fatptr>maxclus
;	$LEAVE	E			;  goto step7		     AN000;bgb
	JE $$EN94
	    call    chk_fat		; ended read_fats on carry from feof
; at this point target = head of list, filsiz = file size
step4a:     inc     filcnt		;   filcnt++;
	    mov     ax,maxent		;   if (filcnt > maxent)
	    cmp     filcnt,ax		; more files than possible dir entries?
;	    $IF     A			; yes - this is an error
	    JNA $$IF96
direrr: 	dec	filcnt
		lea	dx,dirmsg	;
		call	display_interface ;
		mov	exit_sw,true
;	    $ENDIF
$$IF96:
nodirerr:   cmp     exit_sw,true
;	$LEAVE	E
	JE $$EN94
	    call    fill_dir
	    mov     ax,fatptr
	    cmp     ax,MaxClus
;	$LEAVE	A
	JA $$EN94
;ndlop1: $ENDDO
endlop1:
	 JMP SHORT $$DO94
$$EN94:
	ret
endproc main_loop1			    ;


;*****************************************************************************
; purpose: this procedure looks at all the fats for a particular file, until
;	   the end of file marker is reached. then returns
; inputs:  AX = fat cell number 2
; outputs: if any of the
;*****************************************************************************
Procedure read_fats,Near
	push es
	mov	filsiz,bp		 ;start the file size at 0
	mov	word ptr filsiz+2,bp	 ;start the file size at 0
;	$DO
$$DO101:
step1:	    call    getfat		;   if (fEOF (GetFat (a)) {
	    add     filsiz,cx		;add in cluster size
	    adc     word ptr filsiz+2,bp ;inc 2nd word if there was a carry
	    call    fEOF		;
;	$LEAVE	C			; goto step1a		       AN000;bgb
	JC $$EN101
step6:	    inc     fatptr		;   if (++fatptr <= MaxClus)
	    mov     ax,fatptr
	    cmp     ax,MaxClus
;	    $IF     A
	    JNA $$IF103
		mov	exit_sw,true
;	    $ENDIF
$$IF103:
	    cmp     exit_sw,true	; time to end?
;	$ENDDO	E			;	goto step7
	JNE $$DO101
$$EN101:
	pop es
	ret
endproc read_fats			   ;

;*****************************************************************************
;*****************************************************************************
	even
Procedure fill_dir,Near
	lea	si,dirent+7		;   s = &dirent[7];
;	$DO
$$DO106:
nam0:	    inc     byte ptr [si]	;   while (++*s > '9')
	    cmp     byte ptr [si],'9'
;	$LEAVE	LE
	JLE $$EN106
	    mov     byte ptr [si],'0'	;	*s-- = '0';
	    dec     si
;	$ENDDO
	JMP SHORT $$DO106
$$EN106:
nam1:	mov	ah,GET_DATE		;   dirent.dir_date = GetDate ();
	int	21h
	sub	cx,1980 		; cx = 87
	add	dh,dh			; dh = 1-12
	add	dh,dh
	add	dh,dh
	add	dh,dh
	add	dh,dh			; dh = dh * 32 (32-384)
	rcl	cl,1
	or	dh,dl
	mov	byte ptr dirent+24,dh
	mov	byte ptr dirent+25,cl
	mov	ah,GET_TIME		;   dirent.dir_time = GetTime ();
	int	21h
	shr	dh,1			;seconds/2
	add	cl,cl			;minutes
	add	cl,cl
	add	cl,cl			;mins * 8
	rcl	ch,1
	add	cl,cl
	rcl	ch,1
	add	cl,cl
	rcl	ch,1
	or	dh,cl
	mov	byte ptr dirent+22,dh
	mov	byte ptr dirent+23,ch
	mov	ax,filsiz		;   dirent.dir_fsize = filsiz;
	mov	word ptr dirent+28,ax
	mov	ax,word ptr filsiz+2
	mov	word ptr dirent+30,ax
	mov	ax,target		;   dirent.dir_firclus = target;
	mov	word ptr dirent+26,ax
	lea	si,dirent		; di:si --> directory entry
	mov	cx,32			;move 32 bytes - 1 dir entry
	rep	movsb			;move ds:si to es:di, then
					;inc di and inc si
	inc	fatptr			;   if (++fatptr <= MaxClus)
	ret
endproc fill_dir			   ;
;
;*****************************************************************************
; DRIVE_SPEC -	this procedure is executed if the user only specifies a drive
;		letter to recover.
;*****************************************************************************
Procedure drive_spec,Near
recdsk: xor	di,di			;init addr of dir/file area
	mov	es,table		;es:di --> area
			 ;this addr is incremented by the rep movsb in fill_dir
	mov	fatptr,2		;INIT FATPTR	 ;   a = fatPtr = 2;
	mov	ax,fatptr		;
	MOV	exit_sw,bp ; false	; default to continue looping until true
	call	main_loop1
step7:	mov	al,drive
	mov	dx,firdir		; write out constructed directory
	mov	cx,firrec
	sub	cx,dx
	xor	bx,bx			;addr of dir area
	mov	es,table		;seg of dir area
	call	Write_Disk
;	$IF	NC			;good write?
	JC $$IF109
	    lea     dx,recmsg		    ;
	    mov     si,filcnt
	    mov     rec_num,si
	    call    display_interface
;	$ENDIF
$$IF109:
rexit2: mov	ah,DISK_RESET
	int	21h
	call	wrtfat			; save the fat
;	$IF	C			;Couldn't write it
	JNC $$IF111
	    lea     dx,FATErrWrite	;Just tell user he is in deep!		;
	    call    display_interface	;
;	$ENDIF				;
$$IF111:
	ret
endproc drive_spec			    ;
;
	pathlabl recover

include msgdcl.inc

code	ends
	end				;recover

