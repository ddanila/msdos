TITLE	CHKFAT	- procedures that acces the fat and/or fatmap
page	,132					;

	.xlist
	include chkseg.inc
	INCLUDE CHKCHNG.inc
	INCLUDE DOSSYM.inc
	INCLUDE CHKEQU.inc
	INCLUDE CHKMACRO.inc
	include pathmac.inc


CONST	SEGMENT PUBLIC PARA  'DATA'
	EXTRN	CREATMES:byte,FIXMES_ARG:word
	EXTRN	FREEMES:byte
	EXTRN	BADW_ARG:word,FATAL_END:word
	EXTRN	badrw_num:word,BADRW_STR:WORD,HAVFIX:byte
	EXTRN	FREEBYMES1:byte,FREEBYMES2:byte
	EXTRN	FREE_ARG1:WORD,FREE_ARG2:WORD,FREE_ARG3:WORD,ORPHCNT:dword
	EXTRN	DIRTYFAT:byte,CROSSCNT:dword,DOFIX:byte,SECONDPASS:byte
	EXTRN	BADSIZ:word,ORPHSIZ:word,LCLUS:word,ORPHFCB:byte
	EXTRN	HECODE:byte,USERDIR:byte,FRAGMENT:byte
	EXTRN	ORPHEXT:byte,ALLDRV:byte,FIXMFLG:byte,DIRCHAR:byte
	EXTRN	BIGFAT:byte,EOFVAL:word,BADVAL:word
	extrn	fTrunc:BYTE, rarg1:word
	extrn	temp_dd:dword
CONST	ENDS

DATA	SEGMENT PUBLIC PARA 'DATA'
	extrn	fatcnt:byte
	EXTRN	THISDPB:dword,NUL_ARG:byte
	EXTRN	NAMBUF:byte,SRFCBPT:word,FATMAP:word
	EXTRN	MCLUS:word,CSIZE:byte,SSIZE:word
	EXTRN	DSIZE:word,ARG1:word,ARG_BUF:byte,ERRCNT:byte
	EXTRN	USERDEV:byte,HARDCH:dword,CONTCH:dword
	EXTRN	ExitStatus:Byte,Read_Write_Relative:Byte
	extrn	bytes_per_sector:word, fattbl:word
	extrn	sec_count:word, secs_per_64k:word, paras_per_64k:word
	extrn	fattbl_seg:word, fatsiz:word, paras_per_fat:word
	extrn	end_of_fatmap:word
	extrn	root_entries:word
DATA	ENDS

CODE	SEGMENT PUBLIC PARA 'CODE'
ASSUME	CS:DG,DS:DG,ES:DG,SS:DG
	EXTRN	PRINTF_CRLF:NEAR,FCB_TO_ASCZ:NEAR, recover:near
	EXTRN	EPRINT:NEAR, makorphnam:near
	EXTRN	DOINT26:NEAR,PROMPTYN:NEAR,CHECKFILES:NEAR,DIRPROC:NEAR
	EXTRN	DOCRLF:NEAR, getfilsiz:near, fatal:near, write_disk:near
	EXTRN	GETENT:NEAR,CHECKNOFMES:NEAR, systime:near
	EXTRN	multiply_32_bits:near

public calc_fatmap_seg, MARKMAP, CHKMAP, CHKMAPLP, ORPHAN, CONTLP, RET18
public PromptRecover, NOCHAINREC, CHKMAPLP2, NEXTCLUS
public DISPFRB, FINDCHAIN, CHKMAPLP3, CHAINLP, INSERTEOF, FAT12_4, CHKCHHEAD
public ADDCHAIN, CHGOON, NEXTCLUS2
public CHAINREC, MAKFILLP, GOTENT, OPAGAIN, GOTORPHNAM, ENTMADE, NEXTENT
public NXTORP, RET100, nextorph
public AMDONE, REWRITE, WRTLOOP
public WRTOK, NOWRITE, DONE, CROSSCHK, calc_fat_addr, pack, unpack
	.list
PHONEY_STACK DW 5 DUP(0)

	pathlabl chkfat
;*****************************************************************************
;   CALC-FAT-ADDR - calculate the seg/off of the fat cell from the cell number
;   Inputs:   es - fat table segment
;	      si - cluster number
;
;   Outputs:  es - fat table segment + cluster seg
;	      di - cluster offset
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
    savereg <ax,bx,dx>		    ;
    mov     ax,si		     ;get cluster number from si
    mov     bx,0008h		    ; div by para (* 2 bytes per clus)
    xor     dx,dx		    ; zero dx for word divide
    div     bx			    ; do it				    ;an022;bgb;bgb
    mov     bx,es		    ; get fat table segment
    add     bx,ax		    ; add number of paras to the cluster
    mov     es,bx		    ; move it back
    shl     dx,1		    ; remainder times 2
    mov     di,dx		    ; offset = 00 + remainder
    restorereg <dx,bx,ax>
  return
EndProc calc_fat_addr

;=========================================================================
; UNPACK	:	This routine calculates the position in the FAT
;			where the cluster number resides and obtains
;			its contents.
;
;	Inputs	:	SI - Cluster number
;	Outputs :	DI - Cluster contents
;			zero flag is set if fat cell = zero
;
; LOGIC
;	- get addr of fat table
;	- if 16-bit fat,
;	  then get the address of the cell (calc_fat_addr)
;	       mov it into di
;	       set the zero flag
;	  else multiply the cluster-number by 1.5 to get the byte-offset
;	       move the contents of the cluster into di
;	       if the cluster-number is odd,
;	       then shift it right by 1 nibble
;		    set the zero flag
;	       else (its already shifted right)
;		    set the zero flag
;=========================================================================
UNPACK	proc	near				;ac005; dms;unpack FAT
	push	es
	mov	es,fattbl_seg			;point to FAT in memory
	mov	DI,SI				;put cluster number in DI
	cmp	[BIGFAT],0			;big fat?
;	$IF	nz				;yes
	JZ $$IF1
		call	calc_fat_addr		;calc addr of cluster
		mov	di,word ptr es:[di]	;es:bx points to fat cluster
		or	DI,DI			; Set zero
;	$ELSE					;small fat
	JMP SHORT $$EN1
$$IF1:
	       SHR     DI,1
	       ADD     DI,SI			; Mult by 1.5
	       mov     DI,word ptr es:[di]
	       TEST    SI,1			;is the cluster number odd?
;	       $IF     nz	     ;last bit is non-zero; means it is odd
	       JZ $$IF3
		       SHR     DI,1		;shift by 1 nibble
		       SHR     DI,1
		       SHR     DI,1
		       SHR     DI,1
		       and     di,0fffh
;		$ELSE				;ac005; dms;even cluster bound.
		JMP SHORT $$EN3
$$IF3:
		       AND     DI,0FFFH
;		$ENDIF
$$EN3:
;	$ENDIF
$$EN1:
	pop	es
	return
UNPACK	endp

;=========================================================================
; PACK		: This routine puts data into the FAT.
;
;	Inputs	: SI - Cluster number to be packed
;		  dx - Data to be packed
;
;	Outputs : Altered FAT
; LOGIC
;	- set the fat-changed-flags
;	- get the seg of the fat-table
;	- if 16-bit fat,
;	  then get the address of the cell (calc_fat_addr)
;	       mov the new value into it
;	  else multiply the cluster-number by 1.5 to get the byte-offset
;	       move the contents of the cluster into di
;	       if the cluster-number is odd,
;	       then shift it right by 1 nibble
;		    set the zero flag
;	       else (its already shifted right)
;		    set the zero flag
;=========================================================================
PACK	proc	near
	savereg <si,di,es>
	mov	[DIRTYFAT],1			;Set FAT dirty byte
	mov	[HAVFIX],1			;Indicate a fix
	mov	es,fattbl_seg			;
	mov	DI,SI
	cmp	[BIGFAT],0
;	$IF	nz				;ac005; dms;big fat?
	JZ $$IF7
		call	calc_fat_addr		;calc addr of cluster
		mov	es:[di],dx		;move dx into cluster
;	$ELSE
	JMP SHORT $$EN7
$$IF7:
		shr	di,1		;offset = clus-num * 1.5
		add	di,si		;offset = clus-num * 1.5
		push	di		;save cluster offset
		mov	DI,es:[di]	;get previous value, 4 nibbles
		test	si,1			;is the cluster number odd?
;		$IF	nz	      ;last bit is non-zero; means it is odd
		JZ $$IF9
			SHL	dx,1		;shift by 1 nibble
			SHL	dx,1
			SHL	dx,1
			SHL	dx,1
			AND	DI,0FH		;zero out 1st 3 nibbles '000f'
;		$ELSE				;even cluster number
		JMP SHORT $$EN9
$$IF9:
			AND	DI,0F000H	;zero out last 3 nibbles 'f000'
;		$ENDIF
$$EN9:
		or	DI,dx			;put new value in with old
		pop	si			;get cluster offset
		mov	es:[SI],DI
;	$ENDIF
$$EN7:
	restorereg <es,di,si>
	ret
PACK	endp

;=========================================================================
; CROSSCHK	: this proc gets the value of the fatmap entry that is pointed
;		    to by an orphan
;	Inputs	: si - cluster number of the orphan
;	Outputs : ah - contents of the fatmap pointed to by di
; LOGIC
; *****
;=========================================================================
procedure	CROSSCHK
	push	es
	mov	es,fatmap
	xor	di,di
	ADD	DI,SI
	mov	ah,es:[di]
	TEST	AH,10H
	pop	es
	ret
EndProc CROSSCHK

;*****************************************************************************
; INIT_FATMAP
; description: initialize the fatmap area to all zeros
; called from: main-routine
;Input: segment addr of the fatmap
;	number of clusters in the fat (1-65535)
;Output: fatmap
; LOGIC
;----------
;*****************************************************************************
Procedure init_fatmap,Near
    savereg <es,di,ax,cx>
    mov     es,fatmap			;get seg of the fatmap
    xor     di,di			;get off of the fatmap
    mov     cx,[MCLUS]			;do once for each cluster
    xor     AL,AL			;zero means free
    REP     STOSB		    ;Initialize fatmap to all free
    mov     byte ptr es:[di],al 			   ;
    restorereg <cx,ax,di,es>
    return
endproc init_fatmap			    ;
;
;*****************************************************************************
; CALC_FATMAP_SEG
; description: calculate the segment of the fatmap for addressing purposes
; called from: main-routine
;Input: bytes-per-sector
;	fatsiz
;Output: ram-based fat table
;	 paras-per-fat	     - number of paragraphs of mem in the fat
;	 fattbl-seg	     - segment number of fat table
;	 fatmap 	     - segment number of the fat map table
; LOGIC
;----------
;     - calc length fat-table (in paras)
;	    = bytes-per-sector / 16 * sectors-per-fat
;     - calc segment of fat table in memory
;	    = es  +   64k
;     - calc segment of fatmap area in memory
;	    = es + 64k	+ length of fat-table
;*****************************************************************************
Procedure calc_fatmap_seg,Near
; calc fat table length
	push	es
	mov	ax,bytes_per_sector	; bytes per sector
	xor	dx,dx
	mov	bx,16
	div	bx			; paras per sector		    ;an022;bgb;bgb
	mov	cx,fatsiz		;2	   ; get sectors per fat
	xor	dx,dx
	mul	cx			; paras per fat
	mov	paras_per_fat,ax
; calc fat table segment
	mov	bx,es			;get seg of fat-table
	add	bx,01000h		;add 64k for end of pgm seg
	mov	fattbl_seg,bx		;starting segment of fattbl
; calc fatmap segment								:an005;bgb
	add	ax,bx		 ;seg of fatmap= seg of fattbl + size of fattbl
	mov	fatmap,ax		 ;this is the seg of the fatmap
; find segment number of end of fatmap
;ptm p5000	  mov	  bx,paras_per_fat	  ;each fat cell is 2 bytes
;ptm p5000	  shr	  bx,1			  ;each fatmap cell is 1 byte =
	mov	bx, [MCLUS]		;P5000 INIT_FATMAP use [MCLUS]
	shr	bx, 1			;P5000 convert it to para.
	shr	bx, 1			;P5000
	shr	bx, 1			;P5000
	shr	bx, 1			;P5000
	add	ax,bx			;add in fatmap seg	   =
	inc	ax			;P5000
	mov	end_of_fatmap,ax	;last seg value
	pop	es
	ret				;
endproc calc_fatmap_seg 		    ;
;
;*****************************************************************************
; FIX_ENTRY - fill in the dir entry with the lost cluster information, give it
;	      unique filename, and write it back to disk.
; WARNING!! NOTE!! -->
; called by - CHAINREC
; inputs: AX - drive number
;	  BX - ram offset of beginning of sector
;	  CX -
;	  DX - sector number low
;	  SP -
;	  BP -
;	  SI - cluster number of first cluster in this lost chain
;	  DI - points to entry in ram
; output: AX -
;	  BX -
;	  CX -
;	  DX -
;	  SP -
;	  BP -
;	  SI -
;	  DI-
; Regs abused - di,si,cx
;logic: 1. save the starting cluster number
;	2. if the recovered file name already exists, then use the next one.
;	   do this until the name is unique.
;	3. move all the pertinant info into the dir entry.
;	4. write the dir entry out to disk.
;*****************************************************************************
procedure fix_entry,near
    mov     ds:[DI+26],SI		;move 1st clus num into dir entry
    savereg <ax,dx,bx>			;Save INT 26 data
;make sure this name is unique
    DOS_Call Disk_Reset 		;func 0d - flush buffers
    mov     dx,OFFSET DG:ORPHFCB	;point to filename file0000.chk
    mov     AH,FCB_OPEN 		;open the file just put into the dir
OPAGAIN:
;   $do
$$DO13:
	INT	21H
	or	AL,AL			;did the open fail?
;   $leave  nz
    JNZ $$EN13
	call	MAKORPHNAM		;Try next name
;   $enddo
    JMP SHORT $$DO13
$$EN13:
GOTORPHNAM:				 ;di still points to entry
	mov	SI,OFFSET DG:ORPHFCB + 1 ;ORPHFCB Now has good name
	mov	cx,11			 ;move filename, ext
	REP	MOVSB
	call	MAKORPHNAM		 ;Make next name
	xor	ax,ax			 ;fill dir entry with zeros
	mov	cx,11
	REP	STOSB
; Add in time for orphan file - BAS July 17/85
	push	dx			;save starting sector number
	call	SYSTIME
	STOSW				; Time
	mov	ax,dx
	STOSW				; Date
	pop	dx			;restore starting sector number
	mov	SI,ds:[DI]		;get starting cluster number
	inc	DI			;skip firstclus in entry
	inc	DI
	PUSH	DI			;save it from getfilsiz
	call	GETFILSIZ		;calc file size from number of clus
	POP	DI			;restore di
	STOSW				;ax=file size low
	mov	ax,dx			;dx=filesize high
	STOSW				;
	restorereg <bx,dx,ax>	;offset, sector num, drive num
	mov	cx,1		;number of sectors = 1
	call	DOINT26 	;write it out to disk
	ret
endproc fix_entry
;*****************************************************************************
; NEXTORPH - find the cluster number of the next orphan.  This assumes that
;	     there is at least one lost cluster available.
; WARNING!! NOTE!! -->
; called by - PROCEDURE NAME
; inputs: AX -
;	  BX -
;	  CX -
;	  DX -								      ;a;ac048;bgbn047;bgb
;	  SP -								       ;;ac048;bgban047;bgb
;	  BP -								      ;a;ac048;bgbn047;bgb
;	  SI - cluster number of the previous orphan			      ;a;ac048;bgbn047;bgb
;	  DI -								      ;a;ac048;bgbn047;bgb
;	  DS -								      ;a;ac048;bgbn047;bgb
;	  ES - points to one byte map of the fat			      ;a;ac048;bgbn047;bgb
;									      ;a;ac048;bgbn047;bgb
; output: AX -								       ;;ac048;bgban047;bgb
;	  BX -								      ;a;ac048;bgbn047;bgb
;	  CX -								       ;;ac048;bgban047;bgb
;	  DX -								      ;a;ac048;bgbn047;bgb
;	  SP -								      ;a;ac048;bgbn047;bgb
;	  BP -								      ;a;ac048;bgbn047;bgb
;	  SI - cluster number of one past the orphan
;	  DI - cluster number of the orphan				      ;a;ac048;bgbn047;bgb
;	  DS -								      ;a;ac048;bgbn047;bgb
;	  ES -								      ;a;ac048;bgbn047;bgb
;									      ;a;ac048;bgbn047;bgb
; Regs abused - none
;									       ;;ac048;bgban047;bgb
;logic: 1. save ax & es, and point to fat map
;									      ;a;ac048;bgbn047;bgb
;	2. do until the head of a chain is found:
;									       ;;ac048;bgban047;bgb
;	   3. get the next cell
;									       ;;ac048;bgban047;bgb
;	   4. bump pointers into fat map
;									       ;;ac048;bgban047;bgb
;	5. restore ax & es						       ;;ac048;bgban047;bgb
;*****************************************************************************;a;ac048;bgbn047;bgb
procedure NEXTORPH,near 						      ;a;ac048;bgbn047;bgb
    savereg <ax,es>			;save regs abused
    mov     es,[FATMAP] 		;point to fat map
;   $do
$$DO16:
loopno: mov	al,byte ptr es:[si]	;get the indicated fatmap entry
	inc	si			;point to the next one
	inc	di			;point to the next one
	cmp	AL,89H			;stop when you find an	89
;   $leave    z 	       ;this means head(80), found(1), and orphan(8)
    JZ $$EN16
;   $enddo
    JMP SHORT $$DO16
$$EN16:
    restorereg <es,ax>			;restore regs
return
endproc nextorph

;****************************************************************************
; MARKMAP - make a mark in the fat map for every cluster encountered
;
; called by - markfat,
;
; inputs  - AL - the mark
;	    DI - cluster number
;
; outputs - CY if crosslink found
;	  - AH - previous mark
;	  - crosscnt (count of number of crosslinks found)
;	  - fatmap marked
;
; LOGIC
;******
;	- point to fatmap with es
;	- if that cell has been found before,
;	    then mark it crossed x'10'
;	    else mark it found	 al
;****************************************************************************
markmap: savereg <si,es>			 ;Save registers
	xor	si,si				;Get addr of map
	mov	es,[FATMAP]			;Get addr of map
	mov	ah,es:[di]			   ;Get entry at that spot
	or	ah,ah				;Is it zero?			;     ;
;	$IF	NZ ;already found - mark crossed;If not, we got crosslink
	JZ $$IF19
	   add	   word ptr crosscnt,1		;Count the crosslink		;     ;
	   adc	   word ptr crosscnt+2,0	;Count the crosslink		;     ;
	   or	   byte ptr es:[di],10H 	;Resets zero in map
	   stc					;Indicate crosslink on ret	;     ;
;	$ELSE	  ;not found - mark found	;No crosslink			;     ;
	JMP SHORT $$EN19
$$IF19:
	   mov	es:[di],al			;Set mark in map
	   clc					;Indicate things okay		;     ;
;	$ENDIF					;
$$EN19:
	restorereg <es,si>			;
	ret					;				;     ;


;****************************************************************************
; CHKMAP - Compare FAT and FATMAP looking for badsectors and orphans
;
; called by -
;
; inputs  - fatmap
;	  - dsize - number of clusters on the disk
;
; outputs - badsiz -
;	  -
;	  -
; LOGIC
;******
;	- get addr of fatmap
;	- get offset of 1st cluster in fatmap
;	- do for all the clusters on the disk:
;	    - if the cluster has been found
;	      then get the next cluster in its chain
;		   if the cell was never pointed to by anyone (0)
;		   then get the contents of that cell from the fat
;			(the contents of the fat cell should be zero, too)
;			if the fat-cell is not zero
;			then (it should only be a bad sector)
;			     if it is a bad sector, inc the bad-sector-counter
;			     otherwise, we have found an orphan sector
;	  end-of-loop
;	- if there are any orphans,
;	  then recover them
;****************************************************************************
CHKMAP:
    push    es
    mov     es,fatmap		    ;get segment of the fatmap
    xor     si,si			;get the offset of the fatmap
    mov     si,2			;go past the first two (invalid) entries
;do for all the clusters on the disk
    mov     cx,[DSIZE]		    ;loop for the number of clusters on the disk
CHKMAPLP:
    mov     al,es:[si]			;move a byte from the fatmap to al
    or	    al,al			;is the cluster found already?
;   $IF     Z				;fatmap cell is zero
    JNZ $$IF22
	call	unpack			;get the contents of it
;	$IF	NZ			;is there something in the cell?
	JZ $$IF23
	    cmp     di,[badval] 	;is the fat cell pointing to a bad sector? fff7
;	    $IF     Z			; yes
	    JNZ $$IF24
		inc  [badsiz]		  ;inc the bad sector counter
		mov  byte ptr es:[si],4 	      ;Flag the map
;	    $ELSE			; no, not a bad sector
	    JMP SHORT $$EN24
$$IF24:
orphan: 	inc  [orphsiz]		; then its an orphan
		mov  byte ptr es:[si],8 	      ;Flag it
;	    $ENDIF
$$EN24:
;	$ENDIF
$$IF23:
;   $ENDIF
$$IF22:
CONTLP:
    inc     si				;point si to next cluster
    loop    chkmaplp
    cmp     [orphsiz],0
;   $IF     A		 ;if there are any orphans, go recover them
    JNA $$IF29
	call	recover
;   $ENDIF
$$IF29:
    pop  es
RET18:	ret

;*****************************************************************************
; PROMPTRECOVER - do the actual recovering of files
;
; inputs:   es - points to fatmap
;	    ax -
;	    bx -
;	    cx -
;	    dx -
;
; outputs:
; LOGIC
;	- ask the user if he wants to convert the orphans to files
;	-
;	-
;***************************************************************************
PromptRecover:
    mov     dx,OFFSET DG:FREEMES
    call    PROMPTYN			    ;Ask user
;   $IF     Z
    JNZ $$IF31
	jmp	CHAINREC
;   $ENDIF
$$IF31:
NOCHAINREC:
	mov	es,[fatmap]			;Free all orphans
	mov	si,2
	mov	cx,[dsize]
	xor	dx,dx	     ;dx is the new value (free)
CHKMAPLP2:
	mov	al,es:[si]	 ;get next byte from fatmap into al
	TEST	AL,8		 ; is it an orphan?
;	$IF	NZ		 ;yes
	JZ $$IF33
	    call    PACK	 ;si=cluster number dx=new value
;	$ENDIF
$$IF33:
NEXTCLUS:
       inc     si
	loop	CHKMAPLP2
	xor	ax,ax
	XCHG	ax,[ORPHSIZ]		;number of orphans = zero
	mov	cx,OFFSET DG:FREEBYMES1 ;print msg
	cmp	[DOFIX],0
;	$IF	Z
	JNZ $$IF35
	    mov     cx,OFFSET DG:FREEBYMES2
	    mov     [LCLUS],ax		 ;move number of lost clust would be
;	$ENDIF
$$IF35:
DISPFRB:				 ;ax=lost clusters (1-fff6)
	push	bx			 ;save it
	push	cx			 ;save it
	mov	cl,[csize]		 ;get sectors per cluster (1-32)
	xor	ch,ch			 ;zero out high byte
	xor	dx,dx			 ;zero out hi word for word mult
	mul	cx			 ;cx*ax=dx:ax  lost sectors (1-1ffec0)
	mov	bx,dx			 ;move high word for call
	mov	cx,ssize		 ;word to mult with
	call	multiply_32_bits	 ;bx:ax is result
	mov	word ptr rarg1,ax	 ;low word into low word
	mov	word ptr rarg1+2,bx	 ;hi  word into hi  word
	mov	[free_arg1],ax
	mov	[free_arg2],bx
	mov	[free_arg3],cx
	pop	cx
	pop	bx
	mov	dx,cx				;Point to right message
	call	printf_crlf
	ret




;*****************************************************************************
; FINDCHAIN  -
;
; called by - recover
;
; inputs:
;
; outputs:
; LOGIC - search thru entire fatmap
;	-
;	-
;***************************************************************************
lostdeb  equ	0	;set private build version on
lost_str db	'00000' ;max size of cluster number
FINDCHAIN:
;Do chain recovery on orphans
	mov	es,[FATMAP]		; point to fatmap
	mov	SI,2			; point to fatmap
	mov	dx,si			; point to fatmap
	mov	cx,[DSIZE]		;get total number of clusters on disk
CHKMAPLP3:
	mov	al,es:[si]		;get next fatmap entry
	inc	si			;point to next fatmap entry
			;has to be an orphan(08)
	TEST	AL,8				;Orphan?
	jz	NEXTCLUS2			;Nope
			;make sure its not a regular file entry
	TEST	AL,1				;Seen before ?
	jnz	NEXTCLUS2			;Yup
;recover this chain
	savereg <si,cx,dx>			;Save search environment
	dec	SI
	or	byte ptr es:[si],81H		;Mark as seen and head


	IF	LOSTDEB 		;is this private build version?
	    call lostdisp		;display lost cluster numbers
	 ENDIF

	add	word ptr orphcnt,1		;Found a chain
	adc	word ptr orphcnt+2,0		;Found a chain
	mov	SI,dx			;point to the next fatmap entry
CHAINLP:
	call	UNPACK			;si = fat cell
	XCHG	SI,DI			;si=contents, di=cell number
	cmp	SI,[EOFVAL]		;is this the end of the file?
	JAE	CHGOON			;yes, then we are done
	PUSH	DI			;no, not eof
;dont do this next part if any of two conditions:
;   1. invalid cluster number
;   2. points to itself
	cmp	SI,2			;well, is it a valid cluster number?
	JB	INSERTEOF			;Bad cluster number
	cmp	SI,[dsize]
	JA	INSERTEOF			;Bad cluster number
	cmp	SI,DI			;how bout if it points to itself?
	jz	INSERTEOF			;Tight loop
; find out what it points TO
	    call    CROSSCHK
	    TEST    AH,8			    ;Points to a non-orphan?
	    jnz     CHKCHHEAD			    ;Nope
			      ;orphan points to nothing
INSERTEOF:
; you come here if:
;   1. invalid cluster number
;   2. points to itself
;   3. points to nothing
	POP	SI			;the previous cluster number
	mov	dx,0FFFH		;get eof value (12-bit)
	cmp	[BIGFAT],0
	jz	FAT12_4
	mov	dx,0FFFFH		;get eof value (16-bit)
FAT12_4:
	call	PACK			;stick it in!
	jmp	SHORT CHGOON		;and we are done
; orphan point to a head entry
CHKCHHEAD:
	TEST	AH,80H				;Previosly marked head?
	jz	ADDCHAIN			;Nope
	AND	BYTE PTR es:[DI],NOT 80H	   ;Turn off head bit
	sub	word ptr orphcnt,1		;Wasn't really a head
	sbb	word ptr orphcnt+2,0		;Wasn't really a head
	POP	DI				;Clean stack
	jmp	SHORT CHGOON
ADDCHAIN:
	TEST	AH,1				;Previosly seen?
	jnz	INSERTEOF			;Yup, don't make a cross link
	or	BYTE PTR es:[DI],1		   ;Mark as seen
	POP	DI				;Clean stack
	jmp	CHAINLP 			;Follow chain
CHGOON:
	POP	dx				;Restore search
	POP	cx
	POP	SI
NEXTCLUS2:
	inc	dx
	loop	CHKMAPLP3
	ret



;*****************************************************************************
; CHAINREC - the user has requested us to recover the lost clusters
; inputs:
; note: although called from PROMPTRECOVER, this routine returns control to
;	recover via the ret instruction.
;*****************************************************************************
;*****************************************************************************
; CHAINREC - The user has requested us to recover the lost clusters
; WARNING!! NOTE!! --> the count of the number of lost cluster chains remains,
;		       for this proc, a single word.  More than 64k chains
;		       will cause this proc to fail.
; called by - PROCEDURE NAME
; inputs: AX - N/A
;	  bx -
;	  cx - N/A
;	  dx - N/A
;	  SP -
;	  BP - N/A
;	  SI - N/A
;	  DI - N/A
; data:   root_entries
;	  orphcnt
; output: AX -
;	  bx -
;	  cx -
;	  dx -
;	  SP -
;	  BP -
;	  SI -
;	  DI-
; Regs abused -
;logic: 1.
;*****************************************************************************
CHAINREC:
	push	es		;save es if it is used for anything
	push	ds		;make es point to data
	pop	es
;find the cluster number of the orphan
	mov	SI,2			;start at first cluster
	mov	DI,1			;point to previous cluster?
	call	NEXTORPH		;di points to orphan
;init for loop
	savereg <si,di> 		;save orphan, orphan+1
	mov	SI,DI			;si point to orphan
	xor	ax,ax		 ;set count of dir entries processed to zero
	mov	dx,word ptr orphcnt	;get low word of lost clusters
	mov	word ptr temp_dd,dx	;get low word of lost clusters
	mov	dx,word ptr orphcnt+2	;get hi  word of lost clusters
	mov	word ptr temp_dd+2,dx	;get hi  word of lost clusters
	mov	BP,OFFSET DG:PHONEY_STACK ;Set BP to point to "root"
;do for all dir entries:
MAKFILLP:
;   $DO 				;do for all root entries
$$DO37:
	savereg <ax>		  ;cnt of entries processed, num orphans
	call	GETENT			;DI points to entry
	cmp	BYTE PTR ds:[DI],0E5H	;is this dir entry erased?	     ;an;ac048;bgb005;bgb
;	$if	z,or
	JZ $$LL38
	cmp	BYTE PTR ds:[DI],0	;is this dir entry empty?	     ;an;ac048;bgb005;bgb
;	$if	z
	JNZ $$IF38
$$LL38:
GOTENT:     mov     [HAVFIX],1		;Making a fix
	    cmp     [DOFIX],0		;/f parameter specified?
;	    $if     NZ			;yes- do the fix
	    JZ $$IF39
		call	fix_entry
;	    $endif
$$IF39:
ENTMADE:    restorereg <ax,di,si>
	    sub     word ptr temp_dd,1	 ;finished with one orphan
	    sbb     word ptr temp_dd+2,0 ;finished with one orphan
	    cmp     word ptr temp_dd,0	;is that the last one?
;	    $IF     Z,AND		;no, check the hi word
	    JNZ $$IF41
	    cmp     word ptr temp_dd+2,0;is that the last one?
;	    $IF     Z			;neither are zero
	    JNZ $$IF41
		jmp	RET100		    ; yes,we are done
;	    $endif
$$IF41:
	    call    NEXTORPH		;get the cluster of the next one
	    savereg <si,di>
	    mov     SI,DI
;	$else				;dir entry was not erased or zero
	JMP SHORT $$EN38
$$IF38:
NEXTENT:    restorereg <ax>
;	$endif
$$EN38:
NXTORP: inc	ax
	cmp	ax,root_entries 	;do for 0 to (root_entries - 1)
;   $leave	z
    JZ $$EN37
;   $ENDDO
    JMP SHORT $$DO37
$$EN37:
	restorereg <ax,ax>			;Clean Stack from si,di
	sub	word ptr orphcnt,dx		;Couldn't make them all
	sbb	word ptr orphcnt+2,0		;Couldn't make them all
	mov	dx,OFFSET DG:CREATMES
	mov	byte ptr [arg_buf],0
	call	EPRINT
RET100: pop	es			;restore es
	ret

;*****************************************************************************
;*****************************************************************************
SUBTTL	AMDONE	- Finish up routine
PAGE
Public	AmDone
AMDONE:
ASSUME	DS:NOTHING
	cmp	[DIRTYFAT],0
	jz	NOWRITE 			;FAT not dirty
	cmp	[DOFIX],0
	jz	NOWRITE 			;Not supposed to fix
REWRITE:
	LDS	bx,[THISDPB]
ASSUME	DS:NOTHING
	mov	cx,[bx.dpb_FAT_size]		;Sectors for one fat (DCR)
	mov	DI,cx
	mov	CL,[bx.dpb_FAT_count]		;Number of FATs
	mov	dx,[bx.dpb_first_FAT]		;First sector of FAT
	PUSH	CS
	POP	DS
ASSUME	DS:DG
	mov	[ERRCNT],0
; set up to write to the disk
	xor	bx,bx		     ;offset of the fat-table
	mov	es,fattbl_seg	     ;segment of the fat-table
	mov	AL,[ALLDRV]
	dec	AL
	mov	AH,1
	PUSH	cx
WRTLOOP:
	XCHG	cx,DI
	PUSH	dx
	PUSH	cx
	PUSH	DI
	PUSH	ax

	call	Write_Disk			;Do relative sector write

	JNC	WRTOK
	inc	[ERRCNT]
						;mov	 [badrw_str],offset dg:writing
	POP	ax				; Get fat # in AH
	PUSH	ax				; Back on stack
	xchg	al,ah				; Fat # to AL
	xor	ah,ah				; Make it a word
	mov	[badrw_num],ax
	mov	dx,offset dg:badw_arg
	call	PRINTf_crlf
WRTOK:
	POP	ax
	POP	cx
	POP	DI
	POP	dx
	inc	AH
	ADD	dx,DI
	loop	WRTLOOP 			;Next FAT
	POP	cx				;Number of FATs
	cmp	CL,[ERRCNT]			;Error on all?
;	$if	e
	JNE $$IF47
	    jmp fatal
;	$endif
$$IF47:
; make sure that the data fields are always adressable, because
;we can come here after a ctl - break has happened. so point to them w/ cs:
NOWRITE:
	DOS_Call Disk_Reset			;
	mov	dx,OFFSET DG:USERDIR		;Recover users directory
	DOS_Call ChDir				;
	cmp	BYTE PTR cs:[FRAGMENT],1      ;Check for any fragmented files?
	jnz	DONE				;No -- we're finished
	call	CHECKFILES			;Yes -- report any fragments
Public	Done
DONE:
ASSUME	DS:NOTHING
	mov	DL,cs:[USERDEV] 		   ;Recover users drive
	DOS_Call Set_Default_Drive		;
	ret









	IF	LOSTDEB 		;is this private build version?
Procedure lostdisp,near
    savereg <ax,bx,cx,dx,si,di> 	     ;
	    mov  ax,dx	;save orig value

	    mov  cl,12	;shift 3 nibbles
	    shr  dx,cl	;remove al but last nibble
	    and  dx,000fh
	    cmp  dx,0ah
;	    $IF  B
	    JNB $$IF49
	       add  dx,30h ;make it char
;	    $ELSE
	    JMP SHORT $$EN49
$$IF49:
	       add  dx,37h
;	    $ENDIF
$$EN49:
	    push ax
	    mov  ah,2
	    int  21h
	    pop  ax

	    mov  dx,ax	;get orig value
	    mov  cl,8
	    shr  dx,cl
	    and  dx,000fh
	    cmp  dx,0ah
;	    $IF  B
	    JNB $$IF52
	       add  dx,30h ;make it char
;	    $ELSE
	    JMP SHORT $$EN52
$$IF52:
	       add  dx,37h
;	    $ENDIF
$$EN52:
	    push ax
	    mov  ah,2
	    int  21h
	    pop  ax

	    mov  dx,ax	;get orig value
	    mov  cl,4
	    shr  dx,cl
	    and  dx,000fh
	    cmp  dx,0ah
;	    $IF  B
	    JNB $$IF55
	       add  dx,30h ;make it char
;	    $ELSE
	    JMP SHORT $$EN55
$$IF55:
	       add  dx,37h
;	    $ENDIF
$$EN55:
	    push ax
	    mov  ah,2
	    int  21h
	    pop  ax

	    mov  dx,ax	;get orig value
	    and  dx,000fh
	    cmp  dx,0ah
;	    $IF  B
	    JNB $$IF58
	       add  dx,30h ;make it char
;	    $ELSE
	    JMP SHORT $$EN58
$$IF58:
	       add  dx,37h
;	    $ENDIF
$$EN58:
	    mov  ah,2
	    int  21h

	    mov  dl,' ' ;space after last number
	    mov  ah,2
	    int  21h

    restorereg <di,si,dx,bx,cx,ax>
  return
EndProc lostdisp
ENDIF


	pathlabl chkfat


CODE	ENDS
	END
