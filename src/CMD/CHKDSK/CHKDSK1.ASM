 TITLE	 CHKDSK - MS-DOS Disk consistancy checker ;
page	,132					;

	.xlist
	include chkseg.inc
	INCLUDE CHKCHNG.INC
	INCLUDE DOSSYM.INC
	INCLUDE syscall.inc
	INCLUDE ioctl.inc
	INCLUDE CHKEQU.INC
	INCLUDE CHKMACRO.INC
	include chkdata.inc
	include pathmac.inc

CODE	SEGMENT PUBLIC PARA 'CODE'
ASSUME	CS:DG,DS:NOTHING,ES:DG,SS:dg
 EXTRN	INT_23:NEAR,   readft:near
 EXTRN	FATAL:NEAR, PROMPTYN:NEAR, GET_CURRDIR:NEAR
 extrn	calc_fatmap_seg:near, FINDCHAIN:NEAR, CHECKERR:NEAR, DIRPROC:NEAR
 extrn	CHKMAP:NEAR, Main_Init:Near
 EXTRN	CHKCROSS:NEAR, AMDONE:NEAR, UNPACK:NEAR, GET_THISEL2:NEAR
 EXTRN	PRINTF_CRLF:NEAR, DOCRLF:NEAR, REPORT:NEAR
 extrn	init_fatmap:near, CHKPRMT_END:near
 extrn	hook_interrupts:near
 extrn	CHECK_DBCS_CHARACTER:NEAR

public SETSTACK, OkDrive, DRVISOK, Root_CD_Ok, NOTVOLID, fat16b, SMALLFAT
public BAD_STACK, RDLOOP, NORETRY1, RDOK, IDOK, ALLDONE, CHECKFILES, GotPath
public IS_ROOT_DIR, NOT_ROOT_DIR, VALID_PATH, ParseName, ScanFile, FRAGCHK
public EACHCLUS, LASTCLUS, NXTCHK, GETNXT, MSGCHK, FILSPOK, CDONE, CDONE1
public PRINTID, FIGREC, Main_Routine, checkit
	.list


	pathlabl chkdsk1
CHKDSK:
; --- /? help (before memory setup so it works on any DOS version) ---
	MOV	AH, 062H
	INT	21H			; BX = PSP segment
	MOV	ES, BX			; ES = PSP
	MOV	SI, 081H		; SI = command line in PSP
CK_SKIP_SP:
	CMP	BYTE PTR ES:[SI], ' '
	JNE	CK_CHK_SL
	INC	SI
	JMP	SHORT CK_SKIP_SP
CK_CHK_SL:
	CMP	BYTE PTR ES:[SI], '/'
	JE	CK_CHK_Q
	JMP	CK_NO_HELP
CK_CHK_Q:
	CMP	BYTE PTR ES:[SI+1], '?'
	JE	CK_DO_HELP
	JMP	CK_NO_HELP
CK_DO_HELP:
	CALL	CK_HELP_END
CK_HELP_STR DB "Checks a disk and displays a status report.",0Dh,0Ah
	DB	0Dh,0Ah
	DB	"CHKDSK [drive:][path][filename] [/F] [/V]",0Dh,0Ah
	DB	0Dh,0Ah
	DB	"  [drive:][path]  Drive and directory to check.",0Dh,0Ah
	DB	"  [filename]      File(s) to check for fragmentation.",0Dh,0Ah
	DB	"  /F              Fixes errors on the disk.",0Dh,0Ah
	DB	"  /V              Displays every file on the disk.",0Dh,0Ah,"$"
CK_HELP_END:
	POP	DX
	PUSH	CS
	POP	DS
	MOV	AH, 09H
	INT	21H
	MOV	AX, 4C00H
	INT	21H
CK_NO_HELP:
; --- end /? help ---
; find out if we have enough memory to do the job
    mov     cs:save_drive,al		;save drive validity
;;;;int     12h 			;1k blocks (640k = 280h)
;;;;mov     bx,64			;number of paragraphs
;;;;mul     bx				;640k = a000
;;;;mov     cs:[mem_size],ax		    ;returns number of 1k blocks
    DOS_Call GetCurrentPSP		    ;Get PSP segment address
    mov     cs:psp_segment,bx
    mov     ds,bx			    ;ds points to the psp
    Assume  DS:Nothing
    MOV     DX,DS:[2]			    ;High break
    mov     cs:[mem_size],dx		    ;move it into data area
    MOV     BX,0FFFFH			    ;need at least 64k bytes
    MOV     CX,CS	    ;get segment of where we are
    SUB     DX,CX	    ;top-of-mem  -  pgm  =  # para left in alloc block
    CMP     DX,0FFFH	    ; is the space available > 64K ?
;   $IF     B
    JNB $$IF1
	MOV	CX,4		; Yes, set SP to BX (FFF0)
	SHL	DX,CL		; Convert remaining memory to bytes
	MOV	BX,DX
;   $ENDIF
$$IF1:
SETSTACK:	       ;***Set_Memory*********
    CLI
    PUSH    CS
    POP     SS
ASSUME	SS:DG
    MOV     SP,BX
    STI
    PUSH    AX
    JMP     Main_Init			    ;Go to init routines


;**************************************************************************
; MAIN-ROUTINE
;
; called by - main-init
;
; LOGIC
; *****
;	- get the dpb addr
;	- set the default drive to here
;	- save the directory we are on
;	- set the directory to the root of the drive
;	- print the volume name
;	- get the dpb info
;	- get the addr of the fatmap area
;	- calculate the amount of stack space we have
;**************************************************************************
Main_Routine:
    set_data_segment
OkDrive:
;get the dpb addr  from this drive
    mov      dl,AllDrv			     ;Get drive number
    DOS_Call Get_DPB		 ;func 32    ;Get DPB pointer
    ASSUME  DS:NOTHING,cs:DG
    CMP     AL,-1			   ;is this a good drive?
;   $IF  Z
    JNZ $$IF3
;;;;;;;;JNZ	DRVISOK 		   ;Bad drive (should always be ok)
	LEA	DX,BADDRV_arg		   ;This should never happen
	push	cs
	pop	ds
	call	PRINTf_crlf		       ;
	mov	ExitStatus,Bad_Exit	;Get return code
	ret					;Go back to Main_Init
;   $ENDIF
$$IF3:
    MOV     WORD PTR CS:[THISDPB+2],DS	    ;get the dpb segment
    set_data_segment			    ;reset ds to the pgm
    MOV     WORD PTR [THISDPB],BX	    ;get the dpb offset

;**Set_Drive_Info*************************************************************
DRVISOK:
    push    dx
    push    es
    call    hook_interrupts
    pop     es
    pop     dx
; make this drive the default drive
    DEC     DL				    ;A=0 b=1 c=2
    DOS_Call	    Set_Default_Drive	    ;func 0e - no return

;get the name of the current directory
    INC     DL				    ;drive number a=1 b=2 c=3
    LEA     SI,USERDIR+1		    ;
    DOS_Call	    Current_Dir 	    ;
;;;;PUSH    CS
;;;;POP     ES

;change the current directory to the root
    lea     DX,rootstr			;
    DOS_Call	    ChDir		    ;
;   $IF     C				;will this ever happen?
    JNC $$IF5
;;;;;;;;jnc	Root_CD_Ok			;
	MOV	DX,OFFSET DG:BADCD_arg
	call	display_interface		       ;
	mov	ExitStatus,Bad_Exit	;Get return code
	ret					;Go back to Main_Init
;   $ENDIF
$$IF5:

;get the dpb info
    LDS     BX,[THISDPB]		;ds:bx--> dpb area
    ASSUME  DS:NOTHING
    MOV     AX,[BX.dpb_sector_size]	;Bytes/sector
    MOV     [SSIZE],AX			;Sector size in bytes
    MOV     AL,[BX.dpb_cluster_mask]
    INC     AL
    MOV     [CSIZE],AL			;Sectors per cluster
    MOV     AX,[BX.dpb_max_cluster]	; number of clusters in the disk
    MOV     [MCLUS],AX			;Bound for FAT searching
    DEC     AX			    ;ax= max clusters - 1
    MOV     [DSIZE],AX		    ;Total data clusters on disk
    CMP     AX,4096-8			;Big or little FAT?
;   $IF     NB
    JB $$IF7
fat16b: INC	es:[BIGFAT]		   ;set 16-bit fat flag to true
	MOV	es:[EOFVAL],0FFF8H	   ;set 16-bit compare fields for fat
	MOV	es:[CHAIN_END],0FFFFh		   ;Marker for end of chain
	MOV	es:[BADVAL],0FFF7H	   ;set 16-bit compare fields for fat
;   $ENDIF
$$IF7:
    mov     ax,[bx.dpb_FAT_size]    ;Sectors for one fat (DCR)
    mov     fatsiz,ax		    ;Sectors for one fat (DCR)
    MOV     CL,[BX.dpb_FAT_count]	   ;Number of FATs
    mov     fatcnt,cl
    MOV     DX,[BX.dpb_first_FAT]	   ;First sector of FAT
    MOV     firstfat,dx 		   ;First sector of FAT
    MOV     DX,[BX.dpb_first_sector]	   ;First sector of data
    MOV     firstsec,dx 		   ;First sector of data
    MOV     DX,[BX.dpb_dir_sector]	 ;First sector of dir
    MOV     dirsec,dx			 ;First sector of dir
    MOV     DX,[BX.dpb_root_entries]	 ;First sector of dir
    MOV     root_entries,dx			 ;First sector of dir
    set_data_segment			;reset ds to point to data area

;calc fatmap area
SMALLFAT:	    ;do this for both size fats
    ;old calculation
    ;;;;DEC	AX			;ax= max clusters - 1
    ;;;;MOV	[DSIZE],AX		;Total data clusters on disk
    ;;;;MOV	AX,[BX.dpb_FAT_size]	;Sectors for one fat (DCR)
    ;;;;MOV	CX,AX			;CX = Sectors/Fat
    ;;;;MUL	[SSIZE] 		;times bytes/sector = bytes per fat
    ;;;;ADD	fatmap,AX	      ;Allocate FAT space
    ;;;;MOV	AX,fatmap		 ;  get seg of fatmap

Root_CD_Ok:					 ;
;set dta area----do i need to do this since we are using int 25?
;set it to fat table
    call    calc_fatmap_seg	    ;find the addr of where to put the fat map
;see if we still have enough memory
    mov     ax,mem_size 	     ;get top of memory
    cmp     ax,end_of_fatmap	     ;mem_size must be greater or equal
;   $IF     B			     ; if not, display error msg
    JNB $$IF9
	MOV	DX,OFFSET DG:no_mem_arg
	invoke	printf_crlf
	jmp	alldone 	     ;finished with pgm
;   $ENDIF
$$IF9:
    push    ds				;save ds
    mov     ds,fattbl_seg		;get seg
    xor     dx,dx			;ds:dx--> dta area
;;;;mov     fatmap,dx
    DOS_Call	    Set_DMA		;function 1a
    pop     ds				;restore ds

;look for volume entry in dir
    lea     DX,volid			    ;Look for VOL ID
    DOS_Call	    Dir_Search_First	    ;function 11
    CMP     AL,0			;did we find it?
;   $IF     Z				;yes
    JNZ $$IF11
;;;;;;;;JZ	NOTVOLID
	CALL	PRINTID 		;print volume name, date, time
;   $ENDIF
$$IF11:
NOTVOLID:
    call    get_serial_num		;print volume serial number
;;;;call    hook_interrupts
; calculate the place where we run out of ram space
;;;;ADD     AX,[MCLUS]	    ;5000    ;fatmap seg + num of clusters?
;;;;ADD     AX,2	    ;5002   ;Insurance
;;;;MOV     [SECBUF],AX 	    ;Allocate fatmap space
    mov     ax, offset dg:chkprmt_end ;this label must be the last thing in the code segment
    mov     [secbuf],AX 	    ;location of read/write buffer for dir entries
;;;;ADD     AX,[SSIZE]	    ;5202
;;;;ADD     AX,20	    ;5216   ;Insurance
    mov     ax,0ffffh	    ;get end of segment
    lea     bx,fattbl	    ;get end of program
    sub     ax,bx	    ;this is the amount of stack space we have
    MOV     [STACKLIM],AX	    ;Limit on recursion
; see if we have already overrun the stack
    MOV     DI,SP		     ;where is the stack pointer now?
    SUB     DI,100H		    ; Want AT LEAST this much stack from
				       ;  our current location
    CMP     DI,AX
;   $IF     B
    JNB $$IF13
;;;;;;;;JB	BAD_STACK		; Already in trouble
BAD_STACK:
	MOV	BX,OFFSET DG:STACKMES	;Out of stack
	PUSH	CS
	POP	DS
	JMP	FATAL
;   $ENDIF
$$IF13:

;
;**Read in FAT*****************************************************************
;;;;MOV     DI,fatsiz			;sectors per fat
;;;;MOV     CL,[BX.dpb_FAT_count]	   ;Number of FATs
;;;;MOV     DX,[BX.dpb_first_FAT]	   ;First sector of FAT
    mov     cx,fatsiz			;number of sectors to read
    mov     dx,firstfat 		;starting sector number
    mov     es,fattbl_seg   ;set up bx for read-disk
    xor     bx,bx
    MOV     AL,[ALLDRV]     ;set up al with drive letter for read-disk
    DEC     AL		    ;zero based
;;;;MOV     AH,1
RDLOOP:
;;;;XCHG    CX,DI			    ;DI has # of Fats
    call    readft		    ;	readft ();
;   $IF     C			    ; could the fat be read from disk?
    JNC $$IF15
	inc	byte ptr [nul_arg]
;;;;;;;;mov	[fatal_arg2],offset dg:baddrvm
	mov	[fatmsg2],offset dg:baddrvm
	lea	BX,badread
	JMP	FATAL			;Couldn't read any FAT, BARF
;   $ENDIF			    ;fat could be read from disk
$$IF15:

;   savereg <dx,cx,di,ax>
;   mov     Read_Write_Relative.Start_Sector_High,0 ;
;   call     Read_Disk		     ;Read in the FAT
;   $IF      C
;;;;;;;;JNC	RDOK
;;;;;;;;mov	[badrw_str],offset dg:reading
;	POP	AX			; Get fat# in ah
;	PUSH	AX			; Back on stack
;	xchg	al,ah			; Fat # to AL
;	xor	ah,ah			; Make it a word
;	mov	[badrw_num],ax
;	mov	dx,offset dg:badr_arg
;	invoke	printf_crlf
;	restorereg <ax,cx,di,dx>
;	INC	AH
;	ADD	DX,DI
;	LOOP	RDLOOP			;Try next FAT
;;;;;;;;JMP	NORETRY1		;Couldn't read either
NORETRY1:
;	inc	byte ptr [nul_arg]
;	mov	[fatal_arg2],offset dg:baddrvm
;	MOV	BX,OFFSET DG:BADRDMES
;	JMP	FATAL			;Couldn't read any FAT, BARF
;   $ENDIF
RDOK:	;**Check_for_FAT_ID**********************************************
;;;;restorereg <ax,ax,ax,ax>	    ;Clean up
    mov     es,fattbl_seg	     ;segment of fat-table
    xor     si,si		     ;offset of first byte in fat-table
;;;;LODSB			    ;Check FAT ID byte
    mov     al,byte ptr es:[si]     ;get first byte of fat table
    CMP     AL,0F8H		    ;is it the correct id byte?
;   $IF     B,AND
    JNB $$IF17
;;;;;;;;JAE	IDOK
    CMP     AL,0F0H		    ;if not, Is it a "strange" medium?
;   $IF     NZ
    JZ $$IF17
;;;;;;;;jz	IDOK		    ;neither fat nor strange
	MOV	DX,OFFSET DG:BADIDBYT	;FAT ID bad
	CALL	PROMPTYN		;Ask user to stop or not
;	$IF	NZ
	JZ $$IF18
;;;;;;;;;;;;JZ	    IDOK
	    JMP     ALLDONE		    ;User said stop
;	$ENDIF
$$IF18:
;   $ENDIF
$$IF17:

;initialize the fatmap area to all zeros
IDOK:
    call    init_fatmap

;set the dta addr to here for all searches
    MOV     DX,OFFSET DG:DIRBUF     ;FOR ALL SEARCHING
    DOS_Call	    Set_DMA	    ;
    XOR     AX,AX		    ;zero out ax
    PUSH    AX			    ;I am root
    PUSH    AX			    ;Parent is root
;
    set_data_segment
checkit:
    CALL    DIRPROC
    CALL    CHKMAP		    ;Look for badsectors, orphans
    CALL    CHKCROSS		    ;Check for second pass
    INVOKE  DOCRLF		     ;display new line
    CALL    REPORT		     ;finished, display data to screen

;*****************************************************************************
ALLDONE:
    CALL    AMDONE
;;;;;MOV     AH,EXIT
;;;;;;;;XOR	AL,AL
;;;;;; ;mov	ExitStatus,Bad_Exit	;Get return code
;;;;;;;;INT	21H
	ret				;Ret to Main_Init for common exit

ASSUME	DS:DG
;**Extent_Check***************************************************************
Break	<Check for extents in specified files>
;
; Search the directory for the files specified on the command line and report
; the number of fragmented allocation units found in each one.	We examine the
; given path name for a directory.  If it is found, we CHDIR to it.  In any
; event, we move to the file name part and do a parseFCB call to convert it
; into an FCB for a dir_search_first.  If the parse did NOT advance the
; pointer to the null byte terminating the string, then we have a bogus anme
; and we should report it.
;

CHECKFILES:
	set_data_segment
; see if there is a '\' in the path name
	MOV	DI,OFFSET DG:PATH_NAME
	MOV	SI,DI
	MOV	CX, FNAME_LEN		;
	ADD	DI,CX			; ES:DI points to char AFTER last char
	DEC	DI			; Point to last char
doagain: MOV	 AL,[DIRCHAR]		 ;try to find '\' in path name
	STD
	REPNE	SCASB
	CLD
;	$IF	Z			;a '\' was found in path
	JNZ $$IF21
	    mov     al,[di]		;get byte preceding '\'
	    call    check_dbcs_character ;see if dbcs leading char
;	    $IF     C			;carry means dbcs leading char
	    JNC $$IF22
		jmp	doagain 	;so ignore
;	    $ELSE
	    JMP SHORT $$EN22
$$IF22:
		jmp	GotPath 	;found a '\' and not dbcs
;	    $ENDIF
$$EN22:
;	$ENDIF
$$IF21:
;;;;;;;;;;;;;;;;;;;;;JZ      GotPath		     ; found path char.
; No '\' was found.  set up pointers for parse FCB call.
	MOV	DI,OFFSET DG:PATH_NAME
	CMP	BYTE PTR [DI+1],':'  ;was a drive letter entered?
	JNZ	ParseName
	ADD	DI,2
	JMP	SHORT ParseName

;*****************************************************************************
; found a '\' in the path name
;Change directories and set up the appropriate FCB
GotPath:
	INC	DI			; DI points AT the path sep
	PUSH	WORD PTR [DI]		; Save two chars here
	PUSH	DI			; Save location
	SUB	SI,DI
	JZ	IS_ROOT_DIR		; SI=DI=First char which is a dirchar
	NEG	SI
	CMP	SI,2
	JNZ	NOT_ROOT_DIR
	CMP	BYTE PTR [DI-1],':'	; d:\ root spec?
	JNZ	NOT_ROOT_DIR		; Nope
IS_ROOT_DIR:
	INC	DI			; Don't zap the path sep, zap NEXT char
NOT_ROOT_DIR:
	MOV	BYTE PTR [DI],0
	MOV	DX,OFFSET DG:PATH_NAME
	DOS_Call	Chdir		;
	POP	DI			; Recall loc
	POP	WORD PTR [DI]		; recall chars
	JNC	VALID_PATH
	INVOKE	DOCRLF
	MOV	DX,OFFSET DG:INVPATH_arg
	invoke	printf_crlf
	JMP	CDONE1

;*****************************************************************************
VALID_PATH:
	INC	[DIR_FIX]
	INC	DI		; Point past path sep to first char of name
ParseName:
; parse the filename and get back a formatted fcb for it in es:di
	MOV	SI,DI		      ; DS:SI points to name
	MOV	DI,offset dg:FCB_copy ; ES:DI points to FCB
	MOV	AL,ALLDRV	      ; drive number
	STOSB			      ; put it into fcb
	DEC	DI		      ; Back to start of FCB
	MOV	pFileName,SI	      ; save end of file name
	MOV	AL,00000010B	      ; tell parse to change drive letter if needed
	DOS_Call	Parse_File_Descriptor	;
	CMP	BYTE PTR [SI],0       ;ds:si should point past filename
	JZ	ScanFile
;
; Twiddle the file name to be truly bogus.  Zorch the drive letter
;
	MOV	BYTE PTR es:[DI],-1
ScanFile:
	INVOKE	DOCRLF
;set dma pointer to here
	MOV	DX,OFFSET DG:DIRBUF	;FOR ALL SEARCHING
	MOV	BP,DX
	ADD	BP,27			;bp points to clus in the dir entry
	DOS_Call	Set_DMA 	;set dma ptr here for dir search
;try to find the file specified
	MOV	AH,DIR_SEARCH_FIRST		 ;Look for the first file
FRAGCHK:
	MOV	DX,offset dg:FCB_copy
	INT	21H
	OR	AL,AL			;Did we find it?
	JNZ	MSGCHK			;No -- we're done
; we found the file
; look for fragmentation
	XOR	AX,AX			;Initialize the fragment counter
	MOV	SI,[BP] 		;Get the first cluster
	CALL	UNPACK			;see what that cluster points to
	CMP	DI,[EOFVAL]		;End-of-file?
	JAE	NXTCHK			;Yes -- go report the results
	INC	SI
	CMP	SI,DI
	JZ	EACHCLUS
	INC	AX
EACHCLUS:
	MOV	[OLDCLUS],DI		;Save the last cluster found
	MOV	SI,DI			;Get the next cluster
	CALL	UNPACK
	INC	[OLDCLUS]		;Bump the old cluster
	CMP	DI,[OLDCLUS]		;Are they the same?
	JNZ	LASTCLUS		;No -- check for end-of-file
	JMP	SHORT EACHCLUS		;Continue processing
LASTCLUS:
	CMP	DI,[EOFVAL]		;End-of-file?
	JAE	NXTCHK			;Yes -- go report the results
	INC	AX			;No -- found a fragement
	JMP	SHORT EACHCLUS		;Continue processing
NXTCHK: 	      ;reached the end of a file
	OR	AX,AX			;did we find any fragmentation?
	JZ	GETNXT
;we found fragmentation
	MOV	[FRAGMENT],2		;Signal that we output at least one file
	inc	ax			;bump by one for ends
	mov	[block_num],ax
	mov	word ptr rarg1,ax		 ;
	mov	word ptr rarg1+2,0
	mov	si,offset dg:dirbuf	;point to filename
	INC	SI			;move pointer past drive letter
; get the full path name for this file
	CALL	get_THISEL2
; print it out
	mov	dx,offset dg:extent_arg
	invoke	printf_crlf
GETNXT:
	MOV	AH,DIR_SEARCH_NEXT	    ;Look for the next file
	JMP	FRAGCHK
MSGCHK:
	CMP	AH,DIR_SEARCH_FIRST	;was this the first file searched for?
	JNZ	FILSPOK
;	MOV	SI,offset dg:FCB_copy + 1   ;File not found error
;	CALL	get_THISEL2
	MOV	SI,pFileName
	CALL	get_currdir
	mov	dx,offset dg:OPNERR_arg
	invoke	printf_crlf		    ;bad file spec
	jmp	short cdone
FILSPOK:
	CMP	BYTE PTR [FRAGMENT],2
	JZ	CDONE
; all files were ok
	mov	dx,offset dg:NOEXT_arg
	invoke	printf_crlf
CDONE:
	CMP	BYTE PTR [DIR_FIX],0
	JZ	CDONE1
	MOV	DX,OFFSET DG:USERDIR
	DOS_Call	ChDir			;
CDONE1:
	RET



; This is the old parameter passing scheme
; inputs: AH - the sector number within the cluster
;	  BX - cluster number
; output: DX - absolute sector number
;*****************************************************************************
; FIGREC - This procedure calculates the absolute sector number of a logical
;	   drive, given any cluster number and the sector within that cluster.
;	   You can use this to find the sector number for a file.
;	   This procedure was entirely re-written for dos 4.0, since the
;	   sector number can now be a DOUBLE word value.
; called by: getent in chkproc
; inputs: BX - cluster number
;	  AH - sector number within cluster
;	  csize - sectors per cluster (from dpb)
;	  firstsec - starting sector number of the data area (from dpb)
;outputs: DX - absolute sector number (low order)
;	  INT26.start_sector_high     (hi  order)
;regs changed: DX only
;formula: cluster (3-fff7) * secs/cluster (1-8) = (3-7ffb8)
;	  + sector-offset (0-8) + first-sector (1-ffff) = (7ffb9-8ffbf)
; logic: 1. adjust the cluster number, since the 1st two clusters in the fat
;	    are not used. cluster number can be from 3-fff7.
;	 2. get the sectors-per-cluster, and multiply it times cluster number
;	    in AX.  since this is a word multiply, the high order number goes
;	    into DX.
;	 3. add in the sector-number-within-the-cluster.  Each cluster
;	    (usually) contains several sectors within a cluster.  This sector
;	    number is that number.  It may be from zero to the max number of
;	    sectors/cluster (which can be up to 8 so far on IBM systems).
;	    Do an ADC in case there is a overflow of the word register.
;	 4. add in the starting cluster number of the data area.  This now
;	    gives you the logical sector number within that drive.
;*****************************************************************************
procedure figrec,NEAR
	push	ax		   ;save registers
	push	bx		   ;save registers
	push	cx		   ;save registers
	xor	ch,ch		 ;clear out hi byte of sector-offset
	mov	cl,ah		 ;move sector-offset into cx
	mov	ax,bx		   ;move cluster number into ax for mult
	xor	bh,bh		   ;zero out bh
	mov	bl,csize	   ;get sectors per cluster
	dec	ax		   ; sub 2 for the 1st 2 unused clus in the fat
	dec	ax			;
	mul	bx		   ;ax=low word, dx=hi word
	add	ax,cx		   ;add sector offset
	adc	dx,0		   ;inc hi word if overflow
	add	ax,[firstsec]	   ;add first data sector
	adc	dx,0		   ;inc hi word if overflow
	mov	Read_Write_Relative.Start_Sector_High,dx ;save hi value
	mov	dx,ax		 ;convert to old format- dx=low
	pop	cx
	pop	bx
	pop	ax
	RET
endproc figrec


;*****************************************************************************
SUBTTL	PRINTID - Print Volume ID info
PAGE
PRINTID:
ASSUME	DS:DG
	call	docrlf				;
;get volume name
	xor	si,si			;Point at DTA where find first just done;
	lea	DI,arg_buf		;Where to put vol name for message
	add	si,DirNam		;Point at the vol label name
;;;;;;;;lea	DI,arg_buf		;Point at vol label location in arg_Buf
	MOV	CX,11			; Pack the name
	push	ds
	mov	ds,fattbl_seg
	REP	MOVSB			; Move all of it
;get the year
	xor	si,si			;Get back pointer to FCB
	mov	ax,ds:[si].DirDat	   ;yyyyyyym mmmddddd Put in SysDisp form
	and	ax,Year_Mask		;yyyyyyy0 00000000
	shr	ax,1			;0yyyyyyy 00000000
	xchg	al,ah			;00000000 0yyyyyyy
	add	ax,1980 		;
	mov	es:Sublist_msg_Idmes.Sublist_Offset+(size Sublist_Struc),ax ;
;get the month
	mov	ax,ds:[si].DirDat	   ;yyyyyyym mmmddddd
	and	ax,Month_Mask		;0000000m mmm00000
	mov	cl,5			;
	shr	ax,cl			;00000000 0000mmmm
	mov	cl,al			;0000mmmm
;get the day
	mov	ax,ds:[si].DirDat	   ;yyyyyyym mmmddddd
	and	ax,Day_Mask		;00000000 000ddddd
	mov	ah,cl			;0000mmmm 000ddddd
	xchg	ah,al			;make it display correctly
	mov	es:Sublist_msg_Idmes.Sublist_Segment+(size Sublist_Struc),ax ;
;get the time
	mov	ax,ds:[si].DirTim	   ;hhhhhmmm mmmsssss
	and	ax,Hour_Mask		;hhhhh000 00000000
	mov	cl,11			;
	shr	ax,cl			;00000000 000hhhhh
	mov	ch,al			;000hhhhh
	mov	ax,ds:[si].DirTim	   ;hhhhhmmm mmmsssss
	and	ax,Minute_Mask		;00000mmm mmm00000
	mov	cl,3			;
	shl	ax,cl			;00mmmmmm 00000000
	mov	al,ch			;00mmmmmm 000hhhhh
	mov	es:Sublist_msg_Idmes.Sublist_Offset+(size Sublist_Struc)+(size Sublist_Struc),ax
	mov	es:Sublist_msg_Idmes.Sublist_Segment+(size Sublist_Struc)+(size Sublist_Struc),0
	pop	ds
	Message Idmes_Arg		; the parts out as needed		;AC000'
;;;;;;;;call	doCRLF
	ret				;




;*****************************************************************************
; Get the volume serial number
;*****************************************************************************
; Input:  FCB_Drive
; Output: SerNum if no carry
; Notes:  Only DOS Version 3.4 and above will contain serial numbers
;*****************************************************************************
   PUBLIC GET_SERIAL_NUM
procedure Get_Serial_Num,NEAR		;AN000;S
   mov	al,GENERIC_IOCTL	   ;AN000;S
   xor	bx,bx			   ;zero out bx
   mov	bl,alldrv		   ;AN000;S Which drive to check
   mov	ch,rawio		   ;8 = disk io
   mov	cl,Get_Media_Id 	   ;66h = get media id
   LEA	dx,SerNumBuf		   ;AN000;S Pt to the buffer
   Dos_call ioctl		   ;AN000;S Make the call
;  $IF	NC
   JC $$IF26
       message	msgserialnumber
;  $ENDIF
$$IF26:
   ret				   ;AN000;S
endproc Get_Serial_Num			   ;AN000;S
	pathlabl chkdsk1
CODE	ENDS
	END	CHKDSK
