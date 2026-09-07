
include MSBDS.INC				;include BDS struc




;=========================================================================
; I13_Handler			- This routine is the main driver of the
;				  INT 13h hook.
;=========================================================================

I13_Handler	proc	far			;

	jmp	I13_Handler_Start


I13_Max_Head		db	?		;max head count on drive
I13_SPT 		db	?		;max sectors/track count
I13_BPS 		dw	?		;max number bytes/sector
I13_Bytes_Per_Para	dw	10h		;number of bytes per paragraph
I13_Bytes_Per_EMS_Page	dw	4000h		;bytes per EMS page
I13_Paras_Per_Sector	dw	?		;paras per sector
I13_DD_Per_Sector	dw	?		;double words per sector
I13_Operation		db	?		;INT 13h function
I13_Sector_Count	db	?		;sector count
I13_Track_Number	dw	?		;track number
I13_Sector_Number	db	?		;sector number
I13_Head_Number 	db	?		;head number
I13_Drive_Number	db	?		;drive number
I13_Sectors_To_Trf	db	1		;current sectors to trf
I13_Curr_Trf_Cnt	db	?		;total transfer count in secs
I13_Trf_Off		dw	?		;current address for trf
I13_Trf_Seg		dw	?
I13_512_Byte_Buffer	db	512 dup(0)	;buffer for sector

I13_Handler_Start:

	sti					;ints on
	cmp	ah,02h				;read operation?
	je	I13_Handler_Get_Parms		;yes - get drive parms

	cmp	ah,03h				;write operation?
	je	I13_Handler_Get_Parms		;yes - get drive parms

	jmp	cs:IntV13			;neither - go to old INT 13h

I13_Handler_Get_Parms:

	call	I13_Get_Dev_Parms		;get device parms for this drive
	jnc	I13_Handler_Range_Ck		;we have device data
	jmp	cs:IntV13			;go to old INT 13h vector

I13_Handler_Range_Ck:

	call	I13_Target_Source_Range_Ck	;crosses the 640k boundary?
	jc	I13_Handler_Request_Break	;break up the request
	jmp	cs:IntV13			;go to old INT 13h vector

I13_Handler_Request_Break:

	call	I13_Request_Break_Up		;break up I13 request

	ret 2					;return to caller
						;clear the flags from the stack
						;  and pass back ours
I13_Handler	endp				;



;=========================================================================
; I13_Target_Source_Range_Ck	- This routine determines if the
;				  target or source resides in an EMS
;				  page.
;
;	Inputs	: ES:BX - Source/target address
;
;	Outputs : CY	- if address resides in an EMS page
;		  NC	- address not in an EMS page
;=========================================================================


I13_Target_Source_Range_Ck	proc	near	;

	push	ax				;save regs
	push	bx				;
	push	cx				;
	push	si				;
	push	ds				;

	mov	ax,cs				;get cs addressibility
	mov	ds,ax				;
	mov	si,offset cs:Map_Table		;point to the map table

	mov	cx,cs:Map_Count 		;get the number of phys. pages

I13_Target_Source_Loop:

	cmp	cx,0				;at end?
	je	I13_Target_Source_Not_EMS_Page	;yes - source/target not in pg

	mov	ax,ds:[si].Phys_Page_Segment	;get the segment value
	mov	bx,es				;
	cmp	bx,ax				;source/target > EMS page?
	jb	I13_Target_Source_Not_EMS_Page	;no - we are OK for old INT 13
						;must be >= EMS page

	add	ax,400h 			;get end address of EMS page
	cmp	bx,ax				;source/target < end of EMS pg?
	jb	I13_Target_Source_In_EMS_Page	;yes - we are in a page

	add	si,type Mappable_Phys_Page_Struct ;adjust pointer to next page
	dec	cx				;dec counter

	jmp	I13_Target_Source_Loop		;continue loop

I13_Target_Source_Not_EMS_Page:

	clc					;flag not in EMS page
	jmp	I13_Target_Source_Exit		;exit routine

I13_Target_Source_In_EMS_Page:

	stc					;flag in an EMS page

I13_Target_Source_Exit:

	pop	ds				;restore regs
	pop	si				;
	pop	cx				;
	pop	bx				;
	pop	ax				;

	ret					;

I13_Target_Source_Range_Ck	endp		;


;=========================================================================
; I13_Request_Break_Up		- Break up the INT 13h request onto 16k
;				  boundaries.
;
;	Inputs	: AH	- 02 (Read)
;			  03 (Write)
;		  AL	- Sector count
;		  CH	- Track number
;		  CL	- Sector number
;		  DH	- Head number
;		  DL	- Drive number
;		  ES:BX - Buffer address
;
;	Outputs : Data transferred
;=========================================================================


I13_Request_Break_Up	proc	near		;

	push	bx				;save regs
	push	cx				;
	push	dx				;
	push	di				;
	push	si				;
	push	ds				;
	push	es				;


	mov	cs:I13_Trf_Seg,es		;save segment
	mov	cs:I13_Trf_Off,bx		;save offset
	mov	cs:I13_Curr_Trf_Cnt,0		;init transfer count
	mov	cs:I13_Operation,ah		;save operation
	mov	cs:I13_Sector_Count,al		;save sector count


	mov	byte ptr cs:I13_Track_Number,ch ;save starting track number
	mov	ch,cl				;xchg bytes
	shr	ch,1				;shift 6 bits
	shr	ch,1				;
	shr	ch,1				;
	shr	ch,1				;
	shr	ch,1				;
	shr	ch,1				;

	mov	byte ptr cs:I13_Track_Number[+1],ch	;high byte for cylinder
	and	cl,00111111b			;get bits 0-5 for sector number

	mov	cs:I13_Sector_Number,cl 	;save starting sector number
	mov	cs:I13_Head_Number,dh		;save starting head number
	mov	cs:I13_Drive_Number,dl		;save drive number

	mov	cl,cs:I13_Sector_Count		;while sectors

	cmp	cs:I13_Operation,02h		;read?
	jne	I13_Request_Write		;must be a write

I13_Request_Read:

	cmp	cl,0				;at end?
	je	I13_Request_Success		;exit we are done

	lea	bx,cs:I13_512_Byte_Buffer	;point to 512 byte buffer
	mov	ax,cs				;pass cs to es
	mov	es,ax				;

	call	I13_Invoke			;do the INT 13h to our buffer
	jc	I13_Request_Failed		;signal failure
	mov	ax,cs				;point to our buffer to the
	mov	ds,ax				;  transfer
	mov	si,offset cs:I13_512_Byte_Buffer;

	mov	es,cs:I13_Trf_Seg		;restore seg to target
	mov	di,cs:I13_Trf_Off		;restore off to target

	push	cx				;save cx across move
	cld					;do a forward move
	mov	cx,cs:I13_DD_Per_Sector 	;  for 128 dd's
	db	66h				;op code for dd word move
	rep	movsw				;do the move - wow that was fast
	pop	cx				;restore it

	call	I13_Adjust			;adjust our pointers

	dec	cl				;decrease sector counter
	jmp	I13_Request_Read		;continue loop

I13_Request_Write:

	cmp	cl,0				;at end?
	je	I13_Request_Success		;exit we are done

	mov	ax,cs				;point to 512 byte buffer
	mov	es,ax				;
	mov	di,offset cs:I13_512_Byte_Buffer;

	mov	ds,cs:I13_Trf_Seg		;get source segment
	mov	si,cs:I13_Trf_Off		;get source offset

	push	cx				;save cx across move
	cld					;do a forward move
	mov	cx,cs:I13_DD_Per_Sector 	;  for 128 dd's
	db	66h				;op code for dd word move
	rep	movsw				;do the move - wow that was fast
	pop	cx				;restore it

	lea	bx,cs:I13_512_Byte_Buffer	;point to 512 byte buffer
	mov	ax,cs				;pass cs to es
	mov	es,ax				;

	call	I13_Invoke			;do the INT 13h to our buffer
	jc	I13_Request_Failed		;signal failure
	call	I13_Adjust			;adjust our pointers

	dec	cl				;decrease sector counter
	jmp	I13_Request_Write		;continue loop

I13_Request_Failed:

	jmp	I13_Request_Exit		;exit on error


I13_Request_Success:

	xor	ax,ax				;clear status byte

I13_Request_Exit:

	pop	es				;restore regs
	pop	ds				;
	pop	si				;
	pop	di				;
	pop	dx				;
	pop	cx				;
	pop	bx				;


	ret					;

I13_Request_Break_Up	endp			;



;=========================================================================
; I13_Adjust		- This routine adjusts the needed fields for
;			  the next iteration of INT 13h.
;
;	Inputs	: I13_Sectors_To_Trf	- Sectors just read/written
;		  I13_Sector_Number	- Starting sector number for trf
;		  I13_Head_Number	- Starting head number for trf
;		  I13_Track_Number	- Starting track number for trf
;
;	Outputs : I13_Sector_Number	- New starting sector for trf
;		  I13_Head_Number	- New starting head for trf
;		  I13_Track_Number	- New starting track for trf
;=========================================================================


I13_Adjust	proc	near			;adjust values

	push	ax				;save regs

	inc	cs:I13_Sector_Number		;next sector
	mov	al,cs:I13_Sector_Number 	;
	cmp	al,cs:I13_SPT			;> sectors on track?
	jna	I13_Adjust_Exit 		;no
		mov	cs:I13_Sector_Number,1	;yes - start at next
		inc	cs:I13_Head_Number	;next head
		mov	al,cs:I13_Head_Number	;
		cmp	al,cs:I13_Max_Head	;> head count
		jb	I13_Adjust_Exit 	;no
			 mov	 cs:I13_Head_Number,0	 ;yes - head 0
			 inc	 cs:I13_Track_Number	 ;next track

I13_Adjust_Exit:

	mov	ax,cs:I13_Paras_Per_Sector	;get bytes per sector
	add	cs:I13_Trf_Seg,ax		;adjust segment

	pop	ax				;restore regs

	ret					;

I13_Adjust	endp				;


;=========================================================================
; I13_Invoke		- This routine sets up the regs for the INT 13h
;			  and invokes it for the sector we need.
;
;	Inputs	: I13_Operation 	- read/write
;		  I13_Track_Number	- cylinder to read/write
;		  I13_Sector_Number	- starting sector for read/write
;		  I13_Head_Number	- starting head
;		  I13_Drive_Number	- starting drive
;
;	Outputs : NC			- good read/write
;		  CY			- bad read/write
;=========================================================================

I13_Invoke	proc	near			;invoke INT 13h

	push	bx				;save regs
	push	cx				;
	push	dx				;

	mov	ah,cs:I13_Operation		;get function call
	mov	al,cs:I13_Sectors_To_Trf	;get sectors to transfer

	mov	ch,byte ptr cs:I13_Track_Number ;get track number
	mov	cl,byte ptr cs:I13_Track_Number[+1]	;get high 2 bits
	shl	cl,1				;put bit is positions 6&7
	shl	cl,1				;
	shl	cl,1				;
	shl	cl,1				;
	shl	cl,1				;
	shl	cl,1				;
	or	cl,cs:I13_Sector_Number 	;place the sector number in cl

	mov	dh,cs:I13_Head_Number		;get head number
	mov	dl,cs:I13_Drive_Number		;get drive number
	pushf
	call	cs:IntV13			;go to old vector
	inc	cs:I13_Curr_Trf_Cnt		;increment counter

	pop	dx				;restore regs
	pop	cx				;
	pop	bx				;

	ret					;

I13_Invoke	endp				;


;=========================================================================
; I13_Get_Dev_Parms	- This routine obtains the device parameters for
;			  the drive being accessed for the INT 13h.
;
;	Inputs	: DL - drive number
;
;	Outputs : I13_Max_Head		- max head count on drive
;		  I13_SPT		- max sectors/track count for drive
;		  CY			- error
;		  NC			- no error
;=========================================================================



I13_Get_Dev_Parms	proc	near		;get sectors/track & head cnt.

	push	ax				;save regs
	push	bx				;
	push	cx				;
	push	dx				;
	push	di				;
	push	ds				;

	mov	ax,0803h			;get the BDS table
	int	2fh				;

I13_Get_Dev_Next_Entry:

	cmp	ds:[di].Drivenum,dl		;do we have our drive?
	je	I13_Get_Dev_Save_Parms		;yes get data
	cmp	word ptr ds:[di].Link[+0],-1	;last entry in list?
	je	I13_Get_Dev_Parms_Error_Exit	;yes - did not find drive
	mov	ax,word ptr ds:[di].Link[+0]	;get offset of next entry
	mov	bx,word ptr ds:[di].Link[+2]	;get segment of next entry
	mov	ds,bx				;stuff into ds:di
	mov	di,ax				;
	jmp	I13_Get_Dev_Next_Entry		;continue

I13_Get_Dev_Save_Parms:

	mov	ax,ds:[di].BytePerSec		;get byte count per sector
	mov	cs:I13_BPS,ax			;

	xor	dx,dx				;clear high word
	div	cs:I13_Bytes_Per_Para		;get number of paras in sector
	mov	cs:I13_Paras_Per_Sector,ax	;save it
	shl	ax,1				;get DD's per sector
	shl	ax,1				;
	mov	cs:I13_DD_Per_Sector,ax 	;

	mov	ax,ds:[di].SecLim		;get sectors per track
	mov	cs:I13_SPT,al			;

	mov	ax,ds:[di].HdLim		;get max head count
	mov	cs:I13_Max_Head,al		;

	clc					;flag data found

	jmp	I13_Get_Dev_Parms_Exit		;


I13_Get_Dev_Parms_Error_Exit:

	stc					;flag no data found

I13_Get_Dev_Parms_Exit:

	pop	ds				;restore regs
	pop	di				;
	pop	dx				;
	pop	cx				;
	pop	bx				;
	pop	ax				;

	ret					;

I13_Get_Dev_Parms	endp			;


