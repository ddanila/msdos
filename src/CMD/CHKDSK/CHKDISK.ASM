TITLE	CHKDISK  - procedures that read or write to the disk
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
	EXTRN	BADW_ARG:word
	EXTRN	badrw_num:word,BADRW_STR:WORD,HAVFIX:byte
	EXTRN	DIRTYFAT:byte,DOFIX:byte,SECONDPASS:byte
	EXTRN	HECODE:byte,USERDIR:byte,FRAGMENT:byte
	EXTRN	ORPHEXT:byte,ALLDRV:byte,FIXMFLG:byte,DIRCHAR:byte
	EXTRN	EOFVAL:word,BADVAL:word
	extrn	fTrunc:BYTE
CONST	ENDS

DATA	SEGMENT PUBLIC PARA 'DATA'
	EXTRN	THISDPB:dword,NUL_ARG:byte
	EXTRN	NAMBUF:byte,SRFCBPT:word,FATMAP:word
	EXTRN	USERDEV:byte,HARDCH:dword,CONTCH:dword
	EXTRN	ExitStatus:Byte,Read_Write_Relative:Byte
	extrn	bytes_per_sector:word
	extrn	sec_count:word, paras_per_64k:word, secs_per_64k:word
	extrn	fattbl_seg:word, paras_per_fat:word
DATA	ENDS

CODE	SEGMENT PUBLIC PARA 'CODE'
ASSUME	CS:DG,DS:DG,ES:DG,SS:DG
	EXTRN	FCB_TO_ASCZ:NEAR
	EXTRN	EPRINT:NEAR
	EXTRN	PROMPTYN:NEAR,DIRPROC:NEAR
	EXTRN	DOCRLF:NEAR,UNPACK:NEAR,PACK:NEAR
	EXTRN	CHECKNOFMES:NEAR
public read_disk, Read_once, write_disk, Write_once
public ReadFt, seg_adj, calc_sp64k
	.list


	pathlabl chkdisk
;=========================================================================
; READ_DISK	:	This routine reads the logical sector count requested.
;			It will read a maximum of 64k in one read.  If more
;			than 64k exists it will continue looping until
;			all sectors have been read.
;	Inputs	:	AL - Drive letter
;			ES:BX - Segment:offset of transfer address
;			CX - Sector count
;			DX - 1st  sector
;	Outputs :	Logical sectors read
; LOGIC
; *****
;    adjust es:bx to es:00
;    calcluate sectors-per-64k (how many sectors are there that can fit within a 64k segment?)
;    DO while there are more sectors to read than sectors-per-64k
;	set sector-count to sectors-per-64k
;	perform the disk read
;	bump the seg addr to the new addr
;	dec  the number of sectors to read by sectors-per-64k
;	bump the starting sector number by the sectors-per-64k
;    ENDDO
;    perform a disk read for less than sectors-per-64k
;=========================================================================
procedure	read_disk
	savereg <ax,bx,cx,dx,es>
	call	seg_adj 			;an000;calc new seg:off
	call	calc_sp64k			;an000;secs/64k
;	$DO				; do while more than 64k
$$DO1:
	    cmp     cx,secs_per_64k	    ;an000;exceed 64k
;	$LEAVE	LE			    ;an000;yes
	JLE $$EN1
	    mov     sec_count,cx	;an000;save cx
	    mov     cx,secs_per_64k	;an000;get maximum read
	    call    read_once		;an000;read it
;	$LEAVE	C
	JC $$EN1
	    mov     cx,es
	    add     cx,paras_per_64k	; adjust transfer area
	    mov     es,cx
	    mov     cx,sec_count	; restore sector count
	    sub     cx,secs_per_64k	;an000;get sectors remaining
	    add     dx,secs_per_64k	;an000;adjust starting sector
;	$ENDDO
	JMP SHORT $$DO1
$$EN1:
	call	read_once	    ;an000;read it
	restorereg <es,dx,cx,bx,ax>
	ret
read_disk	endp
;*****************************************************************************
;Routine name: Read_once
;*****************************************************************************
;description: Read in data using Generic IOCtl
;Called Procedures: None
;Input: AL = Drive number (0=A)
;	es:BX = Transfer address
;	CX = Number of sectors
;	Read_Write_Relative.Start_Sector_High = Number of sectors high
;	DX = logical sector number low
;Output: CY if error
;	 AH = INT 25h error code
;Psuedocode
;----------
;	Save registers
;	Setup structure for function call
;	Read the disk (AX=440Dh, CL = 6Fh)
;	Restore registers
;	ret
;*****************************************************************************
Procedure Read_once				;
	savereg  <ax,bx,cx,dx,si,di,bp,es,ds>	;Change it to Read relative sect
	mov	Read_Write_Relative.Buffer_Offset,bx ;Get transfer buffer add
	mov	bx,es				;
	mov	Read_Write_Relative.Buffer_Segment,bx ;Get segment
	mov	Read_Write_Relative.Number_Sectors,cx ;Number of sec to read
	mov	Read_Write_Relative.Start_Sector_Low,dx ;Start sector
	mov	bx,offset Read_Write_Relative	;
	mov	cx,0FFFFh			;Read relative sector
	INT	25h				;Do the read
	pop dx					;Throw away flags on stack
	restorereg <ds,es,bp,di,si,dx,cx,bx,ax>
	return
 Read_once endp
;=========================================================================
; WRITE-DISK	:	This routine reads the logical sector count requested.
;			It will read a maximum of 64k in one read.  If more
;			than 64k exists it will continue looping until
;			all sectors have been read.
;	Inputs	:	AL - Drive letter
;			ES:BX - Segment:offset of transfer address
;			CX - Sector count
;			DX - 1st  sector
;	Outputs :	Logical sectors read
; LOGIC
; *****
;    adjust es:bx to es:00
;    calcluate sectors-per-64k (how many sectors are there that can fit within a 64k segment?)
;    DO while there are more sectors to read than sectors-per-64k
;	set sector-count to sectors-per-64k
;	perform the disk read
;	bump the seg addr to the new addr
;	dec  the number of sectors to read by sectors-per-64k
;	bump the starting sector number by the sectors-per-64k
;    ENDDO
;    perform a disk read for less than sectors-per-64k
;=========================================================================
procedure      write_disk
	savereg <ax,bx,cx,dx,es>
	call	seg_adj 		;an000;calc new seg:off
;	$DO				; do while more than 64k
$$DO5:
	    cmp     cx,secs_per_64k	;an000;exceed 64k
;	$LEAVE	LE			;an000;yes
	JLE $$EN5
	    mov     sec_count,cx	;an000;save cx
	    mov     cx,secs_per_64k	;an000;get maximum read
	    call   write_once		;an000;read it
;	$LEAVE	C
	JC $$EN5
	    mov     cx,es
	    add     cx,paras_per_64k	; adjust transfer area
	    mov     es,cx
	    mov     cx,sec_count	; restore sector count
	    sub     cx,secs_per_64k	;an000;get sectors remaining
	    add     dx,secs_per_64k	;an000;adjust starting sector
;	$ENDDO
	JMP SHORT $$DO5
$$EN5:
	call	write_once		;an000;read it
	restorereg <es,dx,cx,bx,ax>
	ret
write_disk	endp
;*****************************************************************************
;Routine name: Write_once
;*****************************************************************************
;description: Write Data using int 26
;Called Procedures: None
;Input: AL = Drive number (0=A)
;	DS:BX = Transfer address
;	CX = Number of sectors
;	Read_Write_Relative.Start_Sector_High = already set up
;	DX = logical sector number low
;Output: CY if error
;	 AH = INT 26h error code
;Psuedocode
;----------
;	Save registers
;	Setup structure for function call
;	Write to disk (AX=440Dh, CL = 4Fh)
;	Restore registers
;	ret
;*****************************************************************************
Procedure Write_once				 ;
    savereg <ax,bx,cx,dx,di,si,bp,es,ds>	 ;This is setup for INT 26h right
    mov  Read_Write_Relative.Buffer_Offset,bx	 ;Get transfer buffer add
    mov  bx,es					 ;
    mov  Read_Write_Relative.Buffer_Segment,bx	 ;Get segment
    mov  Read_Write_Relative.Number_Sectors,cx	 ;Number of sec to write
    mov  Read_Write_Relative.Start_Sector_Low,dx ;Start sector
    mov  cx,0FFFFh				 ;Write relative sector
    lea  bx,read_write_relative 		 ;
    INT  026h					 ;Do the write
    pop  dx					 ;flags is returned on the stack
    restorereg <ds,es,bp,si,di,dx,cx,bx,ax>	 ;
	ret					 ;
Write_once endp 				 ;
;=========================================================================
; SEG_ADJ	:	This routine adjusts the segment:offset to prevent
;			address wrap.
;	Inputs	:	bx - Offset to adjust segment with
;			es - Segment to be adjusted
;	Outputs :	bx - New offset
;			es - Adjusted segment
;=========================================================================
procedure	seg_adj
	savereg <ax,cx,dx>
	mov	ax,bx				;an000;get offset
	mov	bx,0010h			;divide by 16
	xor	dx,dx				;an000;clear dx
	div	bx				;an000;get para count
	mov	bx,es				;an000;get seg
	add	bx,ax				;an000;adjust for paras
	mov	es,bx				;an000;save new seg
	mov	bx,dx				;an000;new offset
	restorereg <dx,cx,ax>
	ret
seg_adj 	endp
;=========================================================================
; CALC_SP64K	:	This routine calculates how many sectors, for this
;			particular media, will fit into 64k.
;	Inputs	:	DPB_SECTOR_SIZE - bytes/sector
;	Outputs :	SECS_PER_64K	- Sectors / 64k
;			PARAS_PER_64K	- paragraphs per 64k
;=========================================================================
procedure	calc_sp64k
	savereg <ax,bx,cx,dx>
	mov	ax,0ffffh			;an000;64k
	mov	bx,bytes_per_sector		;an000;get bytes/sector
	xor	dx,dx				;an000;clear dx
	div	bx				;an000;sector count	    ;an022;bgb;bgb
	mov	secs_per_64k,ax 		;an000;save sector count
	mov	ax,bytes_per_sector		;an000;get bytes/sector
	mov	bx,010h 			; divide by paras
	xor	dx,dx				;an000;clear dx
	div	bx				; paras per sector	    ;an022;bgb;bgb
	mul	secs_per_64k			; times sectors
	mov	paras_per_64k,ax		; = paras per 64k
	restorereg <dx,cx,bx,ax>		;an000;restore dx
	ret
calc_sp64k	endp
	Break	<ReadFT - read in the entire fat>
;******************************************************************************
;   ReadFt - attempt to read in the fat.  If there are errors, step to
;   successive fats until no more.
;   Inputs:	none.
;   Outputs:	Fats are read until one succeeds.
;		Carry set indicates no Fat could be read.
;   Registers modified: all
; LOGIC
; *****
;  DO for each of the fats on the disk:
;     read - all the sectors in the fat
;     increase the starting sector by the number of sectors in each fat
; LARGE FAT SUPPORT - the big change here is in read disk.  since the fat must
;     be within the first 32M, then the starting sector number of 65535 is ok,
;     as is a larger number of sectors to read/write.
;******************************************************************************
Procedure ReadFt,NEAR
    clc 				;Clear CY so we will loop
    mov     Read_Write_Relative.Start_Sector_High,0 ;
    call    Read_Disk			;	Read_Disk ();		    ;AC0
;   $IF     C
    JNC $$IF9
	add	dx,cx			;	fatstart += fatsize
	call	Read_Disk		;	Read_Disk ();		    ;AC0
;   $ENDIF
$$IF9:
bad_read: ret
EndProc ReadFt


	pathlabl chkdisk
CODE	ENDS
	END
