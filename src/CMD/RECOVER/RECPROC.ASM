page	,132					;
TITLE	RECPROC.SAL
;*****************************************************************************
; Include files
;*****************************************************************************
.xlist
	include recseg.inc
 include dossym.inc
 INCLUDE SYSCALL.INC
 INCLUDE RECMACRO.INC
 include recequ.inc
	include pathmac.inc
.xcref
BREAK	MACRO	subtitle
	SUBTTL	subtitle
	PAGE
ENDM
.cref
;
;*****************************************************************************
; Extrn Declarations
;*****************************************************************************
data	segment PUBLIC para 'DATA'
	EXTRN	secs_per_64k:word
	EXTRN	paras_per_fat:word
	EXTRN	paras_per_64k:word
	EXTRN	bytes_per_sector:word
	EXTRN	sec_count:word
	EXTRN	OFMSG_PTR:WORD
	EXTRN	y_value_lo:WORD
	EXTRN	y_value_hi:WORD
	EXTRN	x_value_lo:WORD
	EXTRN	x_value_hi:WORD
	EXTRN	dbcs_vector:byte
	EXTRN	dbcs_vector_off:word
	EXTRN	dbcs_vector_seg:word
	EXTRN	filsiz:WORD
	EXTRN	read_write_relative:byte
data	ends

;*****************************************************************************
; recproc procedures
;*****************************************************************************
code	segment public para 'CODE'
	pathlabl recproc
public report
public Read_Disk
public Write_Disk
public Build_String
public ChANge_BlANks
public Check_DBCS_CharACter
.list

;******************************************
; Prints the XXX of YYY bytes recovered message.
; The XXX value is a dword at di+16 on entry.
; The YYY value is a dword (declared as a word) at filsiz.
;*************************************************************
Procedure report,near				;
	lea	dx,ofmsg_ptr
	mov	si,[di+16]			;Get the XXX value
	mov	x_value_lo,si
	mov	di,[di+18]
	mov	x_value_hi,di
	mov	si,filsiz			;Get the YYY value
	mov	y_value_lo,si
	mov	di,filsiz+2
	mov	y_value_hi,di
	call	display_interface
	ret
report endp

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
;	DS:BX = Transfer address
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
	mov	Read_Write_Relative.Start_Sector_High,bp;		       ;
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
	ret
write_disk	endp
;*****************************************************************************
;Routine name: Write_Once
;*****************************************************************************
;
;description: Write Data using int 26
;
;Called Procedures: None
;
;
;Input: AL = Drive number (0=A)
;	DS:BX = Transfer address
;	CX = Number of sectors
;	Read_Write_Relative.Start_Sector_High = Number of sectors high
;	DX = logical sector number low
;
;Output: CY if error
;	 AH = INT 26h error code
;
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
; SECS_PER_64K	:	This routine calculates how many sectors, for this
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
	div	bx				;an000;sector count
	mov	secs_per_64k,ax 		;an000;save sector count
	mov	ax,bytes_per_sector		;an000;get bytes/sector
	mov	bx,010h 			; divide by paras
	xor	dx,dx				;an000;clear dx
	div	bx				; paras per sector
	mul	secs_per_64k			; times sectors
	mov	paras_per_64k,ax		; = paras per 64k
	restorereg <dx,cx,bx,ax>		;an000;restore dx
	ret
calc_sp64k	endp


;*****************************************************************************
;Routine name: Build_String
;*****************************************************************************
;
;Description: Build AN ASCIIZ string from the FCB filename input.
;
;Called Procedures: None
;
;ChANge History: Created	6/29/87 	MT
;
;Input: DS:SI = String containing FCB input
;	ES:DI = Where to build string
;
;Output: ES:DI = Input string starting at first non-blANk charACter
;
;Psuedocode
;----------
;
;	Save regs
;	DO
;	LEAVE Next charACter is 0,OR
;	LEAVE 12th charACter,OR
;	   Get charACter
;	LEAVE BlANk
;	   Inc counter
;	ENDDO
;	Set next charACter to 0
;	Restore regs
;
;*****************************************************************************

Procedure Build_String				;
	cld					;Set string ops to up
	push	ax				;Save registers
	push	cx				;  "  "    "  "
	push	si				;Save pointer reg
	xor	cx,cx				;Init the counter
;	$DO					;Loop until entire string found
$$DO9:
	   cmp	   byte ptr [si],ASCIIZ_END	;Is next charACter 0?
;	$LEAVE	E,OR				;Yes, end loop
	JE $$EN9
	   cmp	   cx,FCB_Filename_Length	;Looked at 11 chars?
;	$LEAVE	E,OR				;Yes, end of string
	JE $$EN9
	   lodsb				;Nope, get charACter
	   cmp	   al,BlANk			;Find end of filename?
;	$LEAVE	E				;Yes, quit looping
	JE $$EN9
	   stosb				;Move the char
	   inc	   cx				;No, inc counter ANd try next
;	$ENDDO					;
	JMP SHORT $$DO9
$$EN9:
	mov	byte ptr [di],ASCIIZ_END	;Make ASCIIZ string
	pop	si				;Get bACk pointer to string
	pop	cx				;Restore regsisters
	pop	ax				; "  "	  "  "
	ret					;
Build_String endp				;

;*****************************************************************************
;Routine name: ChANge_BlANks
;*****************************************************************************
;
;Description: ReplACe all DBCS blANks with SBCS blANks
;
;Called Procedures: Check_DBCS_CharACter
;
;ChANge History: Created	6/12/87 	MT
;
;Input: DS:SI = ASCIIZ string containing volume label input
;
;Output: DS:SI = ASCIIZ string with all DBCS blANks replACed with 2 SBCS blANks
;
;
;Psuedocode
;----------
;
;	Save pointer to string
;	DO
;	LEAVE End of string (0)
;	   See if DBCS charACter (Check_DBCS_CharACter)
;	   IF CY (DBCS char found)
;	      IF first byte DBCS blANk, AND
;	      IF second byte DBCS blANk
;		 Convert to SBCS blANks
;	      ENDIF
;	      Point to next byte to compensate for DBCS charACter
;	   ENDIF
;	ENDDO
;	Restore pointer to string
;
;*****************************************************************************
Procedure ChANge_BlANks 			;
;	$DO					;Do while not CR
$$DO12:
	   cmp	   byte ptr [si],Asciiz_End	;Is it end of string?
;	$LEAVE	E				;All done if so
	JE $$EN12
	   call    Check_DBCS_CharACter 	;Test for dbcs lead byte
;	   $IF	   C				;We have a lead byte
	   JNC $$IF14
	      cmp     byte ptr [si],DBCS_Lead	;Is it a lead blANk?
;	      $IF     E,AND			;If a dbcs char
	      JNE $$IF15
	      cmp     byte ptr [si+1],DBCS_BlANk ;Is it AN AsiAN blANk?
;	      $IF     E 			;If AN AsiAN blANk
	      JNE $$IF15
		 mov	 byte ptr [si+1],BlANk	;set up moves
		 mov	 byte ptr [si],BlANk	;  to replACe
;	      $ENDIF				;
$$IF15:
	      inc     si			;Point to dbcs char
;	   $ENDIF				;End lead byte test
$$IF14:
	   inc	   si				;Point to si+1
;	$ENDDO					;End do while
	JMP SHORT $$DO12
$$EN12:
	ret					;return to caller
ChANge_BlANks endp				;


;*****************************************************************************
;Routine name: Check_DBCS_CharACter
;*****************************************************************************
;
;Description: Check if specified byte is in rANges of DBCS vectors
;
;Called Procedures: None
;
;ChANge History: Created	6/12/87 	MT
;
;Input: AL = CharACter to check for DBCS lead charACter
;	DBCS_Vector = YES/NO
;
;Output: CY set if DBCS charACter
;	 DBCS_VECTOR = YES
;
;
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
Procedure	Check_DBCS_CharACter		      ;
	push	ds				;Save registers
	push	si				; "  "	  "  "
	push	ax				; "  "	  "  "
	push	ds				; "  "	  "  "
	pop	es				;Establish addressability
	cmp	byte ptr es:DBCS_VECTOR,Yes	;Have we set this yet?
	push	ax				;Save input charACter
;	$IF	NE				;Nope
	JE $$IF19
	   mov	   al,0 			;Get DBCS environment vectors
	   DOS_Call Hongeul			;  "  "    "  "
	   mov	   byte ptr es:DBCS_VECTOR,YES	;Indicate we've got vector
	   mov	   es:DBCS_Vector_Off,si	;Save the vector
	   mov	   ax,ds			;
	   mov	   es:DBCS_Vector_Seg,ax	;
;	$ENDIF					; for next time in
$$IF19:
	pop	ax				;Restore input charACter
	mov	si,es:DBCS_Vector_Seg		;Get saved vector pointer
	mov	ds,si				;
	mov	si,es:DBCS_Vector_Off		;
;	$SEARCH 				;Check all the vectors
$$DO21:
	   cmp	   word ptr ds:[si],End_Of_Vector ;End of vector table?
;	$LEAVE	E				;Yes, done
	JE $$EN21
	   cmp	   al,ds:[si]			;See if char is in vector
;	$EXITIF AE,AND				;If >= to lower, ANd
	JNAE $$IF21
	   cmp	   al,ds:[si+1] 		; =< thAN higher rANge
;	$EXITIF BE				; then DBCS charACter
	JNBE $$IF21
	   stc					;Set CY to indicate DBCS
;	$ORELSE 				;Not in rANge, check next
	JMP SHORT $$SR21
$$IF21:
	   add	   si,DBCS_Vector_Size	     ;Get next DBCS vector
;	$ENDLOOP				;We didn't find DBCS char
	JMP SHORT $$DO21
$$EN21:
	   clc					;Clear CY for exit
;	$ENDSRCH				;
$$SR21:
	pop	ax				;Restore registers
	pop	si				; "  "	  "  "
	pop	ds				;Restore data segment
	ret					;
Check_DBCS_CharACter endp			;

	pathlabl recproc
code	ends
	end
