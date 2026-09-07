
	page
;=========================================================================
; This module contains all the EQU's, STRUC's, data, and routines necessary
; for LIMDMS.INC.
; This module is to be INCLUDE'd as part of LIMDMS.INC.
;
;=========================================================================

;=========================================================================
;========== Begin EQUate Definitions =====================================
;=========================================================================

AAJ_Option_Max		equ	1h			;max option value
AAJ_Segment		equ	1h			;segment request value
AAJ_No_Pages_To_Map	equ	0h			;0 page map request

MAC_Stack_Status_Request	equ	02h		;stack size request

ER_Conv_Memory		equ	00h			;conv. memory request
ER_EMS_Memory		equ	01h			;EMS memory request
EMS_Page_Size_In_Bytes	equ	(16*1024)-1		;page size in bytes
ER_Max_Type		equ	01h			;max type possible
ER_Max_Function 	equ	01h			;max function possible
ER_Move 		equ	00h			;move data
ER_Exchange		equ	01h			;exchange data
ER_EMS_Page_FE		equ	0FEh			;phys. page FEh
ER_EMS_Page_FF		equ	0FFh			;phys. page FFh
ER_Dest_EMS_Memory	equ	01h			;bit 0 set
ER_Source_EMS_Memory	equ	02h			;bit 1 set
ER_Up			equ	00h			;signal forward move
ER_Down 		equ	0ffh			;signal reverse move
ER_10H			equ	10h			;equ for 10h

AR_Sub_Max		equ	01h			;5ah max. sub functions

;=========================================================================
;========== End EQUate Definitions =======================================
;=========================================================================

	page
;=========================================================================
;========== Begin STRUC Definitions ======================================
;=========================================================================

Log_Phys_Map_Struc	struc				;page structure

	Log_Page_Number 	dw	?		;logical page number
	Phys_Page_Number_Seg	dw	?		;physical page or seg
							;  determined by AL
Log_Phys_Map_Struc	ends


Map_And_Jump_Struc	struc				;carries jump info.

	Target_Address		dd	?		;jump address
	Log_Phys_Map_Len	db	?		;entry count in
							;  Log_Phys_Map_Struct
	Log_Phys_Map_Ptr	dd	?		;Log_Phys_Map_Struct ptr

Map_And_Jump_Struc	ends


Map_And_Call_Struc	struc				;carries jump info.

	MAC_Target_Address	dd	?		;jump address
	MAC_New_Page_Map_Len	db	?		;entry count in
							;  Log_Phys_Map_Struct
							;  for new map scheme
	MAC_New_Page_Map_Ptr	dd	?		;Log_Phys_Map_Struc ptr
							;  for new map scheme
	MAC_Old_Page_Map_Len	db	?		;entry count in
							;  Log_Phys_Map_Struc
							;  for old map scheme
	MAC_Old_Page_Map_Ptr	dd	?		;Log_Phys_Map_Struc ptr
							;  for old map scheme
	MAC_Reserved		dw	4	DUP (?) ;Used to restore map
							;  context

Map_And_Call_Struc	ends


Move_Source_Dest_Struc	struc				;structure for move

	Region_Length_Low_Word	dw	?		;
	Region_Length_High_Word dw	?		;length of region

	Source_Memory_Type	db	?		;conv/EMS
	Source_Handle		dw	?		;handle if EMS, else 0
	Source_Initial_Offset	dw	?		;offset of source region
	Source_Initial_Seg_Page dw	?		;logical page if EMS
							;  seg if conv.
	Dest_Memory_Type	db	?		;conv/EMS
	Dest_Handle		dw	?		;handle if EMS, else 0
	Dest_Initial_Offset	dw	?		;offset of source region
	Dest_Initial_Seg_Page	dw	?		;logical page if EMS
							;  seg if conv.
Move_Source_Dest_Struc	ends				;end structure

Realloc_Struc	Struc				;BP addressible struc

	Realloc_Reserved	db size Instance_Entry_Struc dup (?)
	Realloc_Alloc_Byte	db	?	;reserved
	Realloc_Reg_DI		dw	?	;reserved
	Realloc_Handle		dw	?	;handle

	Realloc_Page_Count	dw	?	;new page count
	Realloc_Page_Alloc	dw	?	;pages to be allocated
	Realloc_Page_Dealloc	dw	?	;pages to be deallocated

	Realloc_Handle_Xref_Index dw	?	;index to end of handle table
	Realloc_LookUp_Index	  dw	?	;index to applicable handle
	Realloc_Mult		  dw	?	;multiplier

Realloc_Struc	Ends				;end structure

AAJ_Struc	Struc				;BP addressible struc

	AAJ_Reserved		db size Instance_Entry_Struc dup (?)
	AAJ_Xref_Pages		dw	?	;save logical page count
	AAJ_Handle		dw	?	;saved handle
	AAJ_Option		db	?	;saved selector state
	AAJ_LookUp_Index	dw	?	;save index
	AAJ_Mult		dw	?	;multiplier

AAJ_Struc	Ends				;end structure

MAC_Struc	Struc				;BP addressible struc

	MAC_Reserved_Area	db size Instance_Entry_Struc dup (?)
	MAC_LookUp_Index	dw	?	;save index
	MAC_Xref_Pages		dw	?	;save logical page count
	MAC_Option		db	?	;saved selector state

	EMS_Reg_ES		dw	?		;ES reg
	EMS_Reg_DS		dw	?		;DS reg
	EMS_Reg_FL		dw	?		;FL reg
	EMS_Reg_SI		dw	?		;SI reg
	EMS_Reg_DI		dw	?		;DI reg
	EMS_Reg_DX		dw	?		;DX reg
	EMS_Reg_CX		dw	?		;CX reg
	EMS_Reg_BX		dw	?		;BX reg

	MAC_M_C_Data		db	size Map_And_Call_Struc dup (?)
	MAC_M_C_Log		db	size Log_Phys_Map_Struc*Map_Count_Def dup (?)
	MAC_Map_Table		db	size Mappable_Phys_Page_Struct*Map_Count_Def dup (?)
	MAC_Mult		dw	?	;multiplier

MAC_Struc	Ends				;end structure


ER_Struc	Struc					;BP addressible struc

	ER_Reserved		db size Instance_Entry_Struc dup (?)
	ER_Direction_Flag	db	ER_Up		;default to forward move

	ER_Sub_Function 	db	?		;save subfunction byte

	ER_Src_Abs_Beg_Low	dw	?		;abs add of src EMS page
	ER_Src_Abs_Beg_High	dw	?		;  beginning of trf area
	ER_Src_Abs_End_Low	dw	?		;abs add of src EMS page
	ER_Src_Abs_End_High	dw	?		;  end of trf area

	ER_Dst_Abs_Beg_Low	dw	?		;abs add of src EMS page
	ER_Dst_Abs_Beg_High	dw	?		;  beginning of trf area
	ER_Dst_Abs_End_Low	dw	?		;abs add of src EMS page
	ER_Dst_Abs_End_High	dw	?		;  end of trf area

	ER_Current_Move_Count	dw	?		;bytes moved this time

	ER_Move_Xchg_Buffer1	db	10h	dup (?) ;buffer for move/xchg
	ER_Move_Xchg_Buffer2	db	10h	dup (?) ;buffer for move/xchg

	ER_Move_Count_Low	dw	?		;low word of count
	ER_Move_Count_High	dw	?		;high word of count

	ER_Source_Phys_Page	dw	?		;page number of source
	ER_Dest_Phys_Page	dw	?		;page number of dest

	ER_Source_Page		dw	?		;active source page
	ER_Dest_Page		dw	?		;active dest page

	ER_Source_Handle	dw	?		;active handle
	ER_Dest_Handle		dw	?		;active handle
							;  10h byte moves

	ER_Save_Context_Buffer	dw	2*Type Mappable_Phys_Page_Struct  dup (0) ;room for 2 pgs

	ER_Dest_Seg		dw	?		;seg value of dest
	ER_Source_Seg		dw	?		;seg value of source

	ER_Dest_Off		dw	?		;off value of dest
	ER_Source_Off		dw	?		;off value of source

	ER_Mem_Type		dw	?		;memory type


ER_Struc	Ends					;end structure

;=========================================================================
;========== End STRUC Definitions ========================================
;=========================================================================

	page
;=========================================================================
;========== Begin Macro Definitions ======================================
;=========================================================================


;=========================================================================
; MAC_Expand_Stack_And_Copy	: This routine will place data in the
;				  instance table by copying the data pointed
;				  at by ES:DI.
;
;	Inputs	: AX - Size of stack adjustment
;		  ES:DI - Pointer to data to be copied to stack
;
;	Outputs : BP - data place in instance table
;
;=========================================================================

MAC_Expand_Stack_And_Copy	proc

	mov	cx,ax					;get adjustment factor
	shr	cx,1					;convert to word move
	mov	ax,es					;get data source seg
	mov	ds,ax					;place in ds
	mov	si,di					;get data source off

	mov	ax,cs					;get dest. seg
	mov	es,ax					;place in es
	mov	di,bx					;get dest. off

	cli						;ints off
	rep	movsw					;move data to stack
	sti						;ints on

	ret						;end routine

MAC_Expand_Stack_And_Copy	endp

	page
;=========================================================================
; MAC_Shrink_Stack_And_Copy	: This routine move data from the instance
;				  table and place it at ES:DI.
;
;	Inputs	: AX - Size of stack adjustment
;		  ES:DI - Pointer to where data is to be copied
;
;	Outputs : BP - data removed from instance table
;
;=========================================================================

MAC_Shrink_Stack_And_Copy	proc

	mov	cx,ax					;get adjustment factor
	mov	ax,cs					;get data source seg
	mov	ds,ax					;place in ds
	mov	si,bx					;get data source off
	mov	ax,cx					;save count across move
	shr	cx,1					;convert to word move

	cli						;ints off
	rep	movsw					;move data from stack
	sti						;ints on

	ret						;end routine

MAC_Shrink_Stack_And_Copy	endp


;=========================================================================
;========== End Macro Definitions ========================================
;=========================================================================

	page
;=========================================================================
;========== Begin Generic PROC Definitions ===============================
;=========================================================================

;=========================================================================
; Map_Pages			: This routine will map the pages being
;				  requested in the struc pointed to by
;				  DS:SI.
;
;	Inputs	: ES:DI - Pointer to data in Log_Phys_Map_Struc format
;		  CX - Count of data iterations in ES:DI
;		  DX - handle
;		  BX - page count for handle
;		  AL - option
;
;	Outputs : Revised map
;		  AH - 0   = no error
;		       > 0 = error
;=========================================================================

Map_Pages	proc					;

	push	si					;save reg

	mov	si,ax					;save option
	cmp	cx,AAJ_No_Pages_To_Map			;no pages?
	je	Map_Error_Exit				;yes - exit loop

Map_Loop_Continue:

	cmp	[di].Log_Page_Number,bx 		;logical page out of
							;  range?
	jbe	Map_Get_Segment 			;no - in range
		mov	ah,EMS_Code8A			;yes - out of range
		jmp	Map_Error_Exit			;exit routine

Map_Get_Segment:

	cmp	si,AAJ_Segment				;segment request?
	mov	ax,[di].Phys_Page_Number_Seg		;get physical page
	jne	Map_Page_Request			;no - page request
		push	dx				;save handle
		mov	dx,[di].Phys_Page_Number_Seg	;get segment
		call	Get_Phys_Seg_Page		;get the associated
							;  page for the segment
		mov	ax,dx				;place page in ax
		pop	dx				;restore handle
		jnc	Map_Page_Request		;no error - continue
			mov	ah,EMS_Code8B		;phys page not found
			jmp	Map_Error_Exit		;exit routine

Map_Page_Request:

	push	bx					;save bx across call
	mov	bx,[di].Log_Page_Number 		;logical page to map
	call	Map_L_To_P				;map the page
	pop	bx					;restore bx
	or	ah,ah					;error?
	jnz	Map_Error_Exit				;pass error on & exit
	add	di,Type Log_Phys_Map_Struc		;adjust pointer
	loop	Map_Loop_Continue			;continue loop
	xor	ax,ax					;signal good finish

Map_Error_Exit:

	pop	si					;restore reg

	ret						;return to caller

Map_Pages	endp					;end proc


	page
;=========================================================================
; Get_Phys_Seg_Page	: This routine will obtain the physical page
;			  number for a given segment.
;
;	Inputs	: DX - Segment value
;	Outputs : DX - Physical page number
;		  CY - Error
;		  NC - No error
;=========================================================================

Get_Phys_Seg_Page	proc				;begin routine

	push	ax					;save regs
	push	cx					;
	push	di					;

	cli						;ints off
	mov	di,offset Map_Table			;point to table map
	mov	cx,Map_Count				;number of table entries
	sti						;ints on

GPSP_Loop:

	cli						;ints off
	cmp	dx,cs:[di].Phys_Page_Segment		;segment match?
	je	GPSP_Got_Segment			;yes
	add	di,Type Mappable_Phys_Page_Struct	;adjust pointer
	loop	GPSP_Loop				;continue search

GPSP_Got_Segment:

	sti						;ints on
	cmp	cx,0					;data found?
	je	GPSP_Not_Found				;exit with error
	mov	dx,cs:[di].Phys_Page_Number		;exit with page number
	clc						;clear cy
	jmp	GPSP_Found				;exit

GPSP_Not_Found:

	stc						;signal error

GPSP_Found:						;exit

	pop	di					;restore regs
	pop	cx					;
	pop	ax					;

	ret						;return to caller

Get_Phys_Seg_Page	endp				;end proc


;=========================================================================
;========== End Generic PROC Definitions =================================
;=========================================================================



	page

;-------------------------------------------------------------------
; Reallocate Pages	- Function 18
;
;	Entry	- AX = 51??
;		  BX = count of new allocation pages
;		  DX = handle
;
;	Exit	- AH = status
;		  BX = new page count
;		       if error - original page count
;-------------------------------------------------------------------
reallocate	proc

	push	cx					;save affected regs
	push	dx					;
	push	di					;
	push	si					;

	push	ds					;save segments
	push	es					;

	mov	ax,cs					;get code segment
	mov	ds,ax					;put int ds and
	mov	es,ax					;  es


	mov	cs:[bp].Realloc_Page_Count,bx		;new page count
	mov	cs:[bp].Realloc_Handle,dx		;handle



	mov	ax,cs:[bp].Realloc_Handle		;get handle for search
	mov	cs:[bp].Realloc_Mult,Type H_LookUp_Struc;handle lookup table
	mul	cs:[bp].Realloc_Mult			;obtain index position
	mov	cs:[bp].Realloc_LookUp_Index,ax 	;index to handle
	mov	di,ax					;place index in si
	mov	dx,cs:[bp].Realloc_Handle		;get handle number


	cmp	dx,Num_Handles-1			;dx > handle count?
	jbe	Realloc_Handle_Search			;handle within range
		mov	ah,EMS_Code83			;EMS handle non-existent
		jmp	Realloc_Error_Exit		;exit program

Realloc_Handle_Search:

	cmp	Handle_LookUp_Table.H_Pages[di],Reusable_Handle ;handle allocated
	jne	Realloc_Status_Of_Handle		;handle good
		mov	ah,EMS_Code83			;EMS handle not alloc
		jmp	Realloc_Error_Exit		;exit program

Realloc_Status_Of_Handle:


	mov	ax,Handle_LookUp_Table.H_Pages[di]	;get current page count
	sub	ax,cs:[bp].Realloc_Page_Count		;more or less pages?
	jc	Realloc_More_Pages			;more pages to alloc

Realloc_Less_Pages:

	mov	bx,ax					;pages to deallocate
	mov	cs:[bp].Realloc_Page_Dealloc,ax 	;save dealloc value

	mov	si,Handle_LookUp_Table.H_Pal_Ptr[di]	;get start of links
	mov	cx,Handle_LookUp_Table.H_Pages[di]	;current pages allocated
	sub	cx,bx					;pages to remain alloc


Realloc_Dealloc_Loop1:

	cmp	cx,0					;pages?
	je	Realloc_Dealloc_Loop1_Exit		;no - exit
	shl	si,1
	mov	si,Page_Alloc_List[si]			;get next pointer
	dec	cx					;dec loop count
	jmp	Realloc_Dealloc_Loop1			;continue

Realloc_Dealloc_Loop1_Exit:

;***** Adjust pointers *****

	mov	cx,cs:[bp].Realloc_Page_Dealloc 	;get dealloc count
	mov	ax,cs:PAL_Free_Ptr			;get the free ptr
	cmp	cx,0					;0 pages to dealloc?
	je	Realloc_Dealloc_Loop2_Exit1		;yes - bypass dealloc
	mov	cs:PAL_Free_Ptr,si			;no - set new free ptr
	dec	cx					;don't loop past last pg

Realloc_Dealloc_Loop2:

	cmp	cx,0					;end of deallocate?
	je	Realloc_Dealloc_Loop2_Exit		;yes - exit
	shl	si,1					;get index entry
	mov	si,Page_Alloc_List[si]			;get next ptr
	dec	cx					;decrement counter
	jmp	Realloc_Dealloc_Loop2

Realloc_Dealloc_Loop2_Exit:

	shl	si,1					;get index entry
	mov	Page_Alloc_List[si],ax			;pt. last page to orig.
							;  free ptr.

Realloc_Dealloc_Loop2_Exit1:

	mov	ax,cs:[bp].Realloc_Page_Count		;new page count
	mov	Handle_LookUp_Table.H_Pages[di],ax	;

	mov	ax,cs:[bp].Realloc_Page_Dealloc 	;adj. value
	add	cs:Free_Pages,ax			;free up page

	mov	bx,cs:[bp].Realloc_Page_Count		;pass back page request
	xor	ah,ah					;clear error
	jmp	Realloc_Exit				;exit

Realloc_More_Pages:

	mov	cx,cs:[bp].Realloc_Page_Count		;get page request count
	mov	di,cs:[bp].Realloc_LookUp_Index 	;get LookUp Table ptr
	mov	ax,Handle_LookUp_Table.H_Pages[di]	;get current page count
	sub	cx,ax					;get additional pages
	mov	cs:[bp].Realloc_Page_Alloc,cx		;new pages to alloc
	cmp	cx,Free_Pages				;> pages remaining?
	jbe	Realloc_Pages				;reallocate pages
		mov	ah,EMS_Code87			;Too few pages avail
		jmp	Realloc_Error_Exit		;exit prog

Realloc_Pages:

	mov	cx,Handle_LookUp_Table.H_Pages[di]	;current pages allocated
	cmp	cx,0					;any pages?
	jne	Realloc_More_Pages_Cont 		;yes
	cmp	cs:[bp].Realloc_Page_Alloc,0		;any pages requested?
	je	Realloc_Alloc_Loop1_Exit		;continue

	mov	cx,cs:[bp].Realloc_Page_Alloc		;get new page count
	cli						;ints off
	call	EMS_Page_Contig_Chk			;contig pages avail?
	jnc	Realloc_New_Pages
		mov	ah,EMS_Code87			;Too few pages avail
		sti					;ints on
		jmp	Realloc_Error_Exit		;exit prog

Realloc_New_Pages:

	call	EMS_Link_Set				;set up page list

	mov	Handle_LookUp_Table.H_Pal_Ptr[di],si	;set table to pointer
	mov	Handle_LookUp_Table.H_Pages[di],cx	;new page count
	mov	bx,cs:[bp].Realloc_Page_Count		;return new page count
	sub	cs:Free_Pages,bx			;new free count
	sti						;ints on
	xor	ax,ax					;clear error flag

	jmp	Realloc_Exit				;exit routine


Realloc_More_Pages_Cont:

	dec	cx
	mov	si,Handle_LookUp_Table.H_Pal_Ptr[di]	;get start of links

Realloc_Alloc_Loop1:
	cmp	cx,0					;at end
	je	Realloc_Alloc_Loop1_Exit		;yes
	shl	si,1					;word entry
	mov	si,Page_Alloc_List[si]			;get next pointer
	dec	cx					;decrement loop count
	jmp	Realloc_Alloc_Loop1			;continue

Realloc_Alloc_Loop1_Exit:

	mov	cx,cs:[bp].Realloc_Page_Alloc		;new pages to alloc
	cmp	cx,0					;pages requested?
	je	Realloc_Alloc_Exit			;no - exit routine

	mov	bx,si					;save si
	cli						;ints off
	call	EMS_Page_Contig_Chk			;contig pages?
	jnc	Realloc_Next_Pages			;yes
		mov	ah,EMS_Code87			;Too few pages avail
		sti					;ints on
		jmp	Realloc_Error_Exit		;exit prog

Realloc_Next_Pages:

;;;;	mov	ax,si					;ptr to new list
;;;;	inc	ax					;contig to new links?
;;;;	cmp	ax,bx					;
;;;;	je	Realloc_Next_Pages1			;yes continue
;;;;		mov	ah,EMS_Code87			;Too few pages avail
;;;;		sti					;ints on
;;;;		jmp	Realloc_Error_Exit		;exit prog

Realloc_Next_Pages1:

	call	EMS_Link_Set				;set up page list
	mov	ax,si					;ptr to new list
	mov	si,bx					;end of old list
	shl	si,1					;index entry
	mov	Page_Alloc_List[si],ax			;pick up new links

Realloc_Alloc_Exit:

	mov	bx,cs:[bp].Realloc_Page_Alloc		;additional pages
	sub	cs:Free_Pages,bx			;new free count
	mov	bx,cs:[bp].Realloc_Page_Count		;pass back page request
	mov	Handle_LookUp_Table.H_Pages[di],bx	;new page count
	sti						;ints on
	xor	ah,ah					;clear ah
	jmp	Realloc_Exit				;exit


Realloc_Error_Exit:

	cli						;ints off
	mov	si,cs:[bp].Realloc_LookUp_Index 	;get handle index
	mov	bx,Handle_LookUp_Table.H_Pages[si]	;get orig. count
	mov	Handle_LookUp_Table.H_Pages[si],bx	;new page count
	sti						;ints on

Realloc_Exit:

	pop	es					;restore segments
	pop	ds					;

	pop	si					;restore regs
	pop	di					;
	pop	dx					;
	pop	cx					;

	ret						;return to caller

reallocate	endp



	page
;=========================================================================
;=============== Function 55h Logic -  Alter Page Map & Jump =============
;=========================================================================
;=========================================================================
; Alter_And_Jump	- This routine alters the page map and jumps
;			  to the specified address.
;
;	Inputs	: AH - 55h (Alter page map & jump)
;		  AL - Physical page number/segment selector
;		       0 = Physical page numbers specified
;		       1 = Segment addresses specified in lieu of
;			   physical page numbers
;		  DX - handle number
;		  DS:SI - Pointer to map and jump structure
;		       (see Map_And_Jump_Struct above)
;
;	Outputs : Revised map
;		  AH - Non-zero if error
;
;=========================================================================
Alter_And_Jump	proc					;modify map

	push	bx					;save regs for jump
	push	cx					;
	push	di					;
	push	si					;

	pushf						;save flags
	push	ds					;save segments
	push	es					;

	mov	bx,cs					;get code segment
	mov	es,bx					;  es

	mov	cs:[bp].AAJ_Handle,dx			;save handle
	mov	cs:[bp].AAJ_Option,al			;save selector option



	cmp	dx,Num_Handles-1			;dx > handle count
	jbe	AAJ_Check_Reusable			;continue test
		mov	ah,EMS_Code83			;EMS handle bad
		jmp	AAJ_Error_Exit			;exit routine

AAJ_Check_Reusable:

	mov	ax,dx					;get handle
	mov	cs:[bp].AAJ_Mult,Type H_LookUp_Struc	;handle lookup table
	mul	cs:[bp].AAJ_Mult			;obtain index position
	mov	cs:[bp].AAJ_LookUp_Index,ax		;index to handle
	mov	di,ax					;place index in di

	cli						;ints off
	mov	ax,Handle_LookUp_Table.H_Pages[di]	;get logical page count
	mov	cs:[bp].AAJ_Xref_Pages,ax		;save logical page count
	sti						;ints on
	cmp	Handle_LookUp_Table.H_Pages[di],Reusable_Handle ;handle allocated
	jne	AAJ_Good_Handle 			;handle good
		mov	ah,EMS_Code83			;EMS handle bad
		jmp	AAJ_Error_Exit			;exit routine

AAJ_Good_Handle:

	cmp	cs:[bp].AAJ_Option,AAJ_Option_Max	;option in range?
	jbe	AAJ_Good_Option 			;option good
		mov	ah,EMS_Code8F			;bad option
		jmp	AAJ_Error_Exit			;exit routine

AAJ_Good_Option:

	les	di,[si].Log_Phys_Map_Ptr		;point to map data
	xor	cx,cx					;clear loop counter
	mov	cl,[si].Log_Phys_Map_Len		;get loop count
	mov	dx,cs:[bp].AAJ_Handle			;get handle for call
	mov	bx,cs:[bp].AAJ_Xref_Pages		;logical page count
	xor	ah,ah					;clear high word
	mov	al,cs:[bp].AAJ_Option			;option selected
	call	Map_Pages				;map the pages requested
	or	ah,ah					;error?
	jnz	AAJ_Error_Exit				;exit with error cond.

AAJ_Loop_Exit:

	pop	es					;restore regs
	pop	ds					;
	popf						;
	pop	si					;
	pop	di					;
	pop	cx					;
	pop	bx					;

	mov	cs:[bp].IE_Alloc_Byte,Unallocated	;deallocate instance

	jmp	dword ptr [si].Target_Address		;jump to address & run

AAJ_Error_Exit:

	pop	es					;restore regs
	pop	ds					;
	popf						;
	pop	si					;
	pop	di					;
	pop	cx					;
	pop	bx					;


	ret						;return to caller

Alter_And_Jump	endp					;end proc



	page
;=========================================================================
;=============== Function 56h Logic -  Alter Page Map & Call =============
;=========================================================================



;=========================================================================
; Alter_And_Call	- This routine alters the page map and calls
;			  the specified address.  The mapping context
;			  is saved on entry to the routine and restored
;			  on exit from the routine.
;
;	Inputs	: AH - 56h (Alter page map & call)
;		  AL - Physical page number/segment selector
;		       0 = Physical page numbers specified
;		       1 = Segment addresses specified in lieu of
;			   physical page numbers
;		       2 = Give minimum required stack size
;		  DX - handle number
;		  DS:SI - Pointer to map and jump structure
;		       (see Map_And_Call_Struc above)
;
;	Outputs : Revised map
;		  AH - Non-zero if error
;		  BX - Function 2 = size in bytes needed for stack
;
;=========================================================================


Alter_And_Call	proc					;modify map & call

	cmp	al,MAC_Stack_Status_Request		;stack report?
	je	MAC_Calc_Stack_Status			;yes
	jb	MAC_Alter_And_Call			;no - new mapping
		mov	ah,EMS_Code8F			;error occurred
		jmp	MAC_Stack_Exit			;exit routine

MAC_Calc_Stack_Status:

	mov	bx,8h					;room for call address
							;  and return address
	xor	ax,ax					;signal no error
	jmp	MAC_Stack_Exit				;exit routine

MAC_Alter_And_Call:

	cli						;ints off
	mov	cs:[bp].EMS_Reg_BX,bx			;
	mov	bx,ax					;save ax across flags
	lahf						;move flags to ah
	mov	cs:[bp].EMS_Reg_FL,ax			;save flags
	mov	ax,bx					;restore ax
	mov	cs:[bp].EMS_Reg_CX,cx			;
	mov	cs:[bp].EMS_Reg_DX,dx			;
	mov	cs:[bp].EMS_Reg_DI,di			;
	mov	cs:[bp].EMS_Reg_SI,si			;
	mov	cs:[bp].EMS_Reg_DS,ds			;
	mov	cs:[bp].EMS_Reg_ES,es			;

	mov	cs:[bp].MAC_Option,al			;save option
	sti						;ints on
	cmp	dx,Num_Handles-1			;dx > handle count
	jbe	MAC_Check_Reusable			;continue test
		mov	ah,EMS_Code83			;EMS handle bad
		jmp	MAC_Error_Exit			;exit routine

MAC_Check_Reusable:

	mov	ax,dx					;get handle
	mov	cs:[bp].MAC_Mult,Type H_LookUp_Struc	;handle lookup table
	mul	cs:[bp].MAC_Mult			;obtain index position
	mov	cs:[bp].MAC_LookUp_Index,ax		;index to handle
	mov	di,ax					;place index in di

	cli						;ints off
	mov	ax,Handle_LookUp_Table.H_Pages[di]	;get logical page count
	mov	cs:[bp].MAC_Xref_Pages,ax		;save logical page count
	cmp	Handle_LookUp_Table.H_Pages[di],Reusable_Handle ;handle allocated
	sti						;ints on
	jne	MAC_Verify_New_Count			;handle good
		mov	ah,EMS_Code83			;EMS handle bad
		jmp	MAC_Error_Exit			;exit routine

MAC_Verify_New_Count:

	cli						;ints off
	mov	ax,Map_Count				;get phys. page count
	sti						;ints on
	cmp	[si].MAC_New_Page_Map_Len,al		;> physical pages
	jbe	MAC_Verify_Old_Count			;no - continue
		mov	ah,EMS_Code8B			;out of range
		jmp	MAC_Error_Exit			;exit routine

MAC_Verify_Old_Count:

	cli						;ints off
	mov	ax,Map_Count				;get phys. page count
	sti						;ints on
	cmp	[si].MAC_Old_Page_Map_Len,al		;> physical pages
	jbe	MAC_Do_Alter_and_Call			;no - continue
		mov	ah,EMS_Code8B			;yes - error
		jmp	MAC_Error_Exit			;exit routine

MAC_Do_Alter_And_Call:

	jmp	MAC_Build_Stack_And_Map 		;build stack and map
							;  new pages
MAC_Return_Routine:

	jmp	MAC_Strip_Stack_And_Map 		;restore data strucs
							;  and map old pages

MAC_Exit:
MAC_Error_Exit:

	cli						;ints off
	mov	bx,ax					;save ax
	mov	ax,cs:[bp].EMS_Reg_FL			;obtain entry flag stat
	sahf						;put in flags reg
	mov	ax,bx					;restore ax
	mov	bx,cs:[bp].EMS_Reg_BX			;
	mov	cx,cs:[bp].EMS_Reg_CX			;
	mov	dx,cs:[bp].EMS_Reg_DX			;
	mov	di,cs:[bp].EMS_Reg_DI			;
	mov	si,cs:[bp].EMS_Reg_SI			;
	mov	ds,cs:[bp].EMS_Reg_DS			;
	mov	es,cs:[bp].EMS_Reg_ES			;
	sti						;ints on

MAC_Stack_Exit:

	ret						;return to caller


;=========================================================================
; MAC_Build_Stack_And_Map	: This routine will build the required
;				  stack structure for a re-entrant
;				  routine and map the new pages.
;
;	Inputs	: DS:SI - Pointer to data in Map_And_Call_Struc format
;
;	Outputs : BP - Instance table to reflect data copyied to it
;		  New mapped pages
;		  AH -	0 = no error
;		       >0 = error	(determined by Map_Pages)
;
;	Instance Table carries this data: Old Map Data
;					  New Map Data
;					  Map & Call Data
;					  Context
;=========================================================================

MAC_Build_Stack_And_Map:

	mov	cs:[bp].EMS_Reg_DS,ds			;save DS
	mov	cs:[bp].EMS_Reg_SI,si			;save SI

	mov	ax,word ptr [si].MAC_Old_Page_Map_Ptr[+2];get the segment
	mov	es,ax					;  of the old map
	mov	di,word ptr [si].MAC_Old_Page_Map_Ptr[+0];get its offset

	mov	al,[si].MAC_Old_Page_Map_Len		;get length of data
	cbw						;convert to word
	xor	dx,dx					;clear high word
	mov	bx,Type Log_Phys_Map_Struc		;struc size
	mul	bx					;get total byte count
	cli						;ints off
	mov	bx,offset MAC_M_C_Log			;offset in struc
	sti						;ints on
	add	bx,bp					;actual offset
	call	MAC_Expand_Stack_And_Copy		;set up stack for
							;  copy of data and
							;  copy the data
	mov	ds,cs:[bp].EMS_Reg_DS			;restore ds
	mov	si,cs:[bp].EMS_Reg_SI			;restore si

	mov	ax,word ptr [si].MAC_New_Page_Map_Ptr[+2];get the segment
	mov	es,ax					;  of the old map
	mov	di,word ptr [si].MAC_New_Page_Map_Ptr[+0];get its offset

	mov	al,[si].MAC_New_Page_Map_Len		;get length of data
	cbw						;conver to word
	xor	dx,dx					;clear high word
	mov	bx,Type Log_Phys_Map_Struc		;struc size
	mul	bx					;get total byte count
	cli						;ints off
	mov	bx,offset MAC_M_C_Log			;Ptr in struc
	add	bx,size MAC_M_C_Log/2			;next entry
	sti						;ints on
	add	bx,bp					;offset BP relative
	call	MAC_Expand_Stack_And_Copy		;set up stack for
							;  copy of data and
							;  copy the data
	mov	ds,cs:[bp].EMS_Reg_DS			;restore ds
	mov	si,cs:[bp].EMS_Reg_SI			;restore si

	mov	ax,ds					;move seg of data to
	mov	es,ax					;  es
	mov	di,si					;move off of data
	mov	ax,Type Map_And_Call_Struc		;get size of structure
	cli						;ints off
	mov	bx,offset MAC_M_C_Data
	sti						;ints on
	add	bx,bp					;offset BP relative
	call	MAC_Expand_Stack_And_Copy		;set up stack for
							;  copy of data and
							;  copy the data
	mov	ds,cs:[bp].EMS_Reg_DS			;restore ds
	mov	si,cs:[bp].EMS_Reg_SI			;restore si

	mov	ax,cs					;get seg of context
	mov	es,ax					;  in es
	cli						;ints off
	mov	di,offset cs:Map_Table			;get offset of context
	mov	ax,Map_Count				;get context entry count
	sti						;ints on
	xor	dx,dx					;clear dx
	mov	bx,Type Mappable_Phys_Page_Struct	;get struc size
	mul	bx					;get size in bytes
	cli						;ints off
	mov	bx,offset cs:MAC_Map_Table
	sti						;ints on
	add	bx,bp					;offset BP relative
	call	MAC_Expand_Stack_And_Copy		;set up stack for
							;  copy of data and
							;  copy the data
	mov	ds,cs:[bp].EMS_Reg_DS			;restore ds
	mov	si,cs:[bp].EMS_Reg_SI			;restore si

	push	cs					;save return segment
	mov	ax,offset MAC_Return_Routine		;save return offset
	push	ax					;

	mov	ax,word ptr [si].MAC_Target_Address[+2] ;get seg of call far
	mov	bx,word ptr [si].MAC_Target_Address[+0] ;get offset of call far
	push	ax					;put on stack
	push	bx					;

	les	di,[si].MAC_New_Page_Map_Ptr		;set up for call
	xor	cx,cx					;clear cx
	mov	cl,[si].MAC_New_Page_Map_Len		;get array size
	mov	dx,cs:[bp].EMS_Reg_DX			;get handle for call
	mov	bx,cs:[bp].MAC_Xref_Pages		;get handle page count
	xor	ah,ah					;clear high word
	mov	al,cs:[bp].MAC_Option			;get option

	call	Map_Pages				;map the new pages
	or	ah,ah					;error?
	jnz	MAC_Error_Strip_Stack			;take data off stack

	cli						;ints off
	mov	ax,cs:[bp].EMS_Reg_FL			;obtain entry flag stat
	sahf						;put in flags reg
	mov	bx,cs:[bp].EMS_Reg_BX			;
	mov	cx,cs:[bp].EMS_Reg_CX			;
	mov	dx,cs:[bp].EMS_Reg_DX			;
	mov	di,cs:[bp].EMS_Reg_DI			;
	mov	si,cs:[bp].EMS_Reg_SI			;
	mov	ds,cs:[bp].EMS_Reg_DS			;
	mov	es,cs:[bp].EMS_Reg_ES			;
	sti						;ints on

Retf_Fake_Out	Proc	Far				;this proc is to
							;  simulate a RETF
							;  instruction
	ret						;performs a far return

Retf_Fake_Out	Endp					;end of retf fake out


MAC_Error_Strip_Stack:

	add	sp,8h					;adjust for return add.
							;  and target add. on
							;  error
	jmp	MAC_Error_Exit				;exit routine


;=========================================================================
; MAC_Strip_Stack_And_Map	: This routine will strip the stack of all
;				  the data placed on by MAC_Build_Stack_And_Map.
;
;	Inputs	: CS:BP - Pointer to data on the instance table
;
;	Outputs : All data area restored
;		  Pages remapped to original
;		  AH -	0 = no error
;		       >0 = error	(determined by Map_Pages)
;
;	Instance Table carries this data: Old Map Data
;					  New Map Data
;					  Map & Call Data
;					  Context
;=========================================================================

MAC_Strip_Stack_And_Map:

	mov	ax,cs					;seg of context
	mov	es,ax					;place in es
	cli						;ints off
	mov	di,offset cs:Map_Table			;get off of context
	mov	ax,Map_Count				;get entries in context
	sti						;ints on
	xor	dx,dx					;clear dx
	mov	bx,Type Mappable_Phys_Page_Struct	;struc size
	mul	bx					;get byte count
	cli						;ints off
	mov	bx,offset MAC_Map_Table
	sti						;ints on
	add	bx,bp					;offset BP relative
	call	MAC_Shrink_Stack_And_Copy		;restore context

	mov	si,cs:[bp].EMS_Reg_SI			;restore pointer
	mov	ds,cs:[bp].EMS_Reg_DS			;  to data struc

	mov	ax,ds					;transfer seg of struc
	mov	es,ax					;  to dest. segment
	mov	di,si					;di=dest. offset
	mov	ax,Type Map_And_Call_Struc		;get size to move
	cli						;ints off
	mov	bx,offset MAC_M_C_Data
	sti						;ints on
	add	bx,bp					;offset BP relative
	call	MAC_Shrink_Stack_And_Copy		;restore Map & Call buf

	mov	ds,cs:[bp].EMS_Reg_DS			;restore ds
	mov	si,cs:[bp].EMS_Reg_SI			;restore si

	mov	ax,word ptr [si].MAC_New_Page_Map_Ptr[+2];get the segment
	mov	es,ax					;  of the old map
	mov	di,word ptr [si].MAC_New_Page_Map_Ptr[+0];get its offset

	mov	al,[si].MAC_New_Page_Map_Len		;get length of data
	cbw						;convert to word
	xor	dx,dx					;clear high word
	mov	bx,Type Log_Phys_Map_Struc		;struc size
	mul	bx					;get total byte count
	cli						;ints off
	mov	bx,offset MAC_M_C_Log
	sti						;ints on
	add	bx,size MAC_M_C_Log/2
	add	bx,bp					;offset BP relative
	call	MAC_Shrink_Stack_And_Copy		;restore new page data

	mov	ds,cs:[bp].EMS_Reg_DS			;restore ds
	mov	si,cs:[bp].EMS_Reg_SI			;restore si

	mov	ax,word ptr [si].MAC_Old_Page_Map_Ptr[+2];get the segment
	mov	es,ax					;  of the old map
	mov	di,word ptr [si].MAC_Old_Page_Map_Ptr[+0];get its offset

	mov	al,[si].MAC_Old_Page_Map_Len		;get length of data
	cbw						;convert to word
	xor	dx,dx					;clear high word
	mov	bx,Type Log_Phys_Map_Struc		;struc size
	mul	bx					;get total byte count
	cli						;ints off
	mov	bx,offset MAC_M_C_Log
	sti						;ints on
	add	bx,bp					;offset BP relative
	call	MAC_Shrink_Stack_And_Copy		;set up stack for

	mov	ds,cs:[bp].EMS_Reg_DS			;restore ds
	mov	si,cs:[bp].EMS_Reg_SI			;restore si

	mov	dx,cs:[bp].EMS_Reg_DX			;get DX reg

	les	di,[si].MAC_Old_Page_Map_Ptr		;set up for call
	xor	cx,cx					;clear cx
	mov	cl,[si].MAC_Old_Page_Map_Len		;get array size
	mov	bx,cs:[bp].MAC_Xref_Pages		;get handle page count
	xor	ah,ah					;clear high byte
	mov	al,cs:[bp].MAC_Option			;get option

	call	Map_Pages				;map the new pages

	jmp	MAC_Exit				;exit the program


Alter_And_Call	endp					;end proc


	page
;=========================================================================
;=============== Function 57h Logic -  Move/Exchange Memory Region =======
;=========================================================================

;=========================================================================
; Exchng_Region 	- This routine moves/exchanges memory regions
;			  specified by the user.  The following types of
;			  moves/exchanges are possible:
;
;			Source			Destination
;			-------------------	----------------------
;			Conventional Memory	Expanded Memory
;			Expanded Memory 	Conventional Memory
;			Expanded Memory 	Expanded Memory
;
;	Inputs	: AH - 57h (Move/Exchange Memory Region)
;		  AL - Type of transfer
;		       0 = Move memory
;		       1 = Exchange memory
;		  DS:SI - Pointer to Move_Source_Dest Structure
;
;	Outputs : Revised map
;		  AH - Non-zero if error
;=========================================================================


Exchng_Region	proc

	push	bx					;save regs
	push	cx					;
	push	dx					;
	push	di					;
	push	si					;
	push	ds					;
	push	es					;

	mov	cs:[bp].ER_Sub_Function,al		;save subfunction
	cmp	al,ER_Max_Function			;valid function?
	jbe	ER_Valid_Sub_Function			;yes - continue
		mov	ah,EMS_Code8F			;no - error
		jmp	ER_Error_Exit			;exit routine

ER_Valid_Sub_Function:

	call	ER_Type_Check				;Proper types &
	or	ah,ah					;  type combinations?
	jnz	ER_Error_Exit				;no - exit routine

	call	ER_Handle_Check 			;valid handles?
	or	ah,ah					;
	jnz	ER_Error_Exit				;no - exit routine

	call	ER_Length_Check 			;Region fits in page
	or	ah,ah					;  and <= 1Mb?
	jnz	ER_Error_Exit				;no - exit routine

	call	ER_Wrap_Check				;> 1Mb wrap on move?
	or	ah,ah					;
	jnz	ER_Error_Exit				;yes - exit routine

	call	ER_Overlap_Check			;conv. memory overlaps
	or	ah,ah					;  EMS page frame?
	jnz	ER_Error_Exit				;yes - exit routine

	call	ER_Log_Page_Test			;offset valid for log.
	or	ah,ah					;  page?
	jnz	ER_Error_Exit				;no - exit routine

	cmp	cs:[bp].ER_Sub_Function,ER_Move 	;move?
	je	ER_Move_Call				;yes - perform move
		call	ER_EMS_Overlap_Check		;EMS pages overlap?
		or	ah,ah				;
		jz	ER_Exchange_No_Overlap		;no  - exit with error
			mov	ah,EMS_Code97		;signal error
			jmp	ER_Error_Exit		;exit with error code

ER_Exchange_No_Overlap:

		call	ER_Exchange_Data		;no  - perform exchange
		jmp	ER_Exit 			;exit the routine

ER_Move_Call:

		call	ER_EMS_Overlap_Check		;see if we had a move
							;  overlap
		push	ax				;save result across call
		call	ER_Move_Data			;perform the move
		pop	ax				;restore result

	ER_Exit:
	ER_Error_Exit:

	pop	es					;restore regs
	pop	ds					;
	pop	si					;
	pop	di					;
	pop	dx					;
	pop	cx					;
	pop	bx					;

	ret						;return to caller

Exchng_Region	endp


;=========================================================================
; ER_Handle_Check	: This routine checks to see if the EMS handles
;			  specified are valid.
;
;	Inputs	: DS:SI - Pointer to Move_Source_Dest_Struc data
;
;	Outputs : AH - Non-zero on error
;			Possible error codes: 83h
;=========================================================================

ER_Handle_Check 	proc				;check requested handles

	push	dx					;save regs
	push	di					;

	cmp	[si].Source_Memory_Type,ER_Conv_Memory	;Conv memory for source?
	je	ER_Handle_Check_Dest			;yes - ck dest. handle

	push	dx					;save dx
	xor	dx,dx					;clear it
	mov	ax,[si].Source_Handle			;get handle requested
	mov	dx,Type H_LookUp_Struc			;handle lookup table
	mul	dx					;obtain index position
	mov	di,ax					;place index in di
	pop	dx					;restore dx

	cmp	Handle_LookUp_Table.H_Pages[di],Reusable_Handle ;handle allocated
	je	ER_Handle_Check_Error_Exit		;handle not allocated

ER_Handle_Check_Dest:

	cmp	[si].Dest_Memory_Type,ER_Conv_Memory	;Conv memory for dest?
	je	ER_Handle_Check_Good_Exit		;yes - exit routine

	push	dx					;save dx
	xor	dx,dx					;clear it
	mov	ax,[si].Dest_Handle			;get handle requested
	mov	dx,Type H_LookUp_Struc			;handle lookup table
	mul	dx					;obtain index position
	mov	di,ax					;place index in di
	pop	dx					;restore dx

	cmp	Handle_LookUp_Table.H_Pages[di],Reusable_Handle ;handle allocated
	je	ER_Handle_Check_Error_Exit		;handle not allocated

ER_Handle_Check_Good_Exit:

	xor	ah,ah					;signal no error
	jmp	ER_Handle_Check_Exit			;exit program

ER_Handle_Check_Error_Exit:

	mov	ah,EMS_Code83				;signal error

ER_Handle_Check_Exit:

	pop	di					;restore regs
	pop	dx					;

	ret						;return to caller

ER_Handle_Check 	endp				;end proc



;=========================================================================
; ER_Length_Check	: This routine checks to see if the region length
;			  specified exceeds the page count of either the
;			  source or destination EMS handle pages allocated.
;			  It also checks to determine if the region length
;			  exceeds 1 Mb.
;
;	Inputs	: DS:SI - Pointer to Move_Source_Dest_Struc data
;
;	Outputs : AH - Non-zero on error
;			Possible error codes: 93h
;					      96h
;					      8Ah
;=========================================================================

ER_Length_Check 	proc				;check region length

	push	bx					;save regs
	push	cx					;
	push	dx					;
	push	di					;

	mov	cx,[si].Region_Length_High_Word 	;get size of the region
	mov	bx,[si].Region_Length_Low_Word		;  in CX:BX
	cmp	cx,ER_10H				;> 1Mb
	ja	ER_Length_Check_Error96 		;exit with error
	cmp	cx,ER_10H				;high word = 10h?
	jne	ER_Length_Check_Cont			;no - continue
	cmp	bx,0					;low word other than 0?
	je	ER_Length_Check_Cont			;no - good value

ER_Length_Check_Error96:

	mov	ah,EMS_Code96				;signal error
	jmp	ER_Length_Check_Exit			;exit routine

ER_Length_Check_Cont:

	cmp	[si].Source_Memory_Type,ER_Conv_Memory	;Conv memory for source?
	je	ER_Length_Check_Dest			;yes - ck dest. length

	push	dx					;save dx
	xor	dx,dx					;clear it
	mov	ax,[si].Source_Handle			;get handle requested
	mov	dx,Type H_LookUp_Struc			;handle lookup table
	mul	dx					;obtain index position
	mov	di,ax					;place index in di
	pop	dx					;restore dx

	mov	ax,Handle_LookUp_Table.H_Pages[di]   ;get logical page count
							;  for source handle
	sub	ax,[si].Source_Initial_Seg_Page 	;pages in EMS to fill
	push	ax					;save ax
	dec	ax					;make it 0 based
	pop	ax					;restore ax
	js	ER_Length_Check_Error8A_Exit		;page out of range

	xor	dx,dx					;clear it
	mov	dx,EMS_Page_Size_In_Bytes+1		;page size in bytes
	mul	dx					;get total bytes to trf
	sub	ax,[si].Source_Initial_Offset		;get byte count in 1st
	sbb	dx,0

	mov	bx,ax					;prepare for DWORD comp
	mov	ax,dx					;

	mov	cx,[si].Region_Length_High_Word 	;get size of the region
	mov	dx,[si].Region_Length_Low_Word		;  in CX:BX

	call	ER_Dword_Compare			;region > target?
	jc	ER_Length_Check_Error93_Exit		;CY = region > target


ER_Length_Check_Dest:

	cmp	[si].Dest_Memory_Type,ER_Conv_Memory	;Conv memory for dest?
	je	ER_Length_Check_Good_Exit		;yes - exit routine

	push	dx					;save dx
	xor	dx,dx					;clear it
	mov	ax,[si].Dest_Handle			;get handle requested
	mov	dx,Type H_LookUp_Struc			;handle lookup table
	mul	dx					;obtain index position
	mov	di,ax					;place index in di
	pop	dx					;restore dx

	mov	ax,Handle_LookUp_Table.H_Pages[di]   ;get logical page count

	sub	ax,[si].Dest_Initial_Seg_Page		;pages in EMS to fill
	push	ax					;save ax
	dec	ax					;make it 0 based
	pop	ax					;restore ax
	js	ER_Length_Check_Error8A_Exit		;page out of range

	xor	dx,dx					;clear high word
	mov	dx,EMS_Page_Size_In_Bytes+1		;page size in bytes
	mul	dx					;get total bytes to trf
	sub	ax,[si].Dest_Initial_Offset		;get byte count in 1st
	sbb	dx,0

	mov	bx,ax					;prepare for DWORD comp
	mov	ax,dx					;

	mov	cx,[si].Region_Length_High_Word 	;get size of the region
	mov	dx,[si].Region_Length_Low_Word		;  in CX:BX

	call	ER_Dword_Compare			;region > target?
	jc	ER_Length_Check_Error93_Exit		;CY = region > target


ER_Length_Check_Good_Exit:

	xor	ah,ah					;signal no error
	jmp	ER_Length_Check_Exit			;exit routine

ER_Length_Check_Error93_Exit:

	mov	ah,EMS_Code93				;signal error
	jmp	ER_Length_Check_Exit			;exit routine

ER_Length_Check_Error8A_Exit:

	mov	ah,EMS_Code8A				;signal error

ER_Length_Check_Exit:					;main exit

	pop	di					;restore regs
	pop	dx					;
	pop	cx					;
	pop	bx					;

	ret						;return to caller

ER_Length_Check 	endp				;end proc


;=========================================================================
; ER_Type_Check 	: This routine checks the source/destination type
;			  specified to determine if they are within the
;			  proper range.
;
;	Inputs	: DS:SI - Pointer to Move_Source_Dest_Struc data
;
;	Outputs : AH - Non-zero on error
;			Possible error codes: 98h
;=========================================================================

ER_Type_Check		proc				;check type

	cmp	[si].Source_Memory_Type,ER_Max_Type	;type within range?
	ja	ER_Type_Check_Error_Exit		;no - error exit

	cmp	[si].Dest_Memory_Type,ER_Max_Type	;type within range?
	ja	ER_Type_Check_Error_Exit		;no - error exit


ER_Type_Check_Good_Exit:

	xor	ah,ah					;signal no error
	jmp	ER_Type_Check_Exit			;exit routine

ER_Type_Check_Error_Exit:

	mov	ah,EMS_Code98				;signal error

ER_Type_Check_Exit:

	ret						;return to caller

ER_Type_Check		endp				;end proc


;=========================================================================
; ER_Wrap_Check 	: This routine checks to determine if there will be
;			  a wrap of conventional memory beyond 1Mb.
;
;	Inputs	: DS:SI - Pointer to Move_Source_Dest_Struc data
;
;	Outputs : AH - Non-zero on error
;			Possible error codes: A2h
;=========================================================================

ER_Wrap_Check		proc				;cks. conv. mem. wrap

	push	dx					;save regs
	push	bx					;

	cmp	[si].Source_Memory_Type,ER_Conv_Memory	;conv. memory?
	jne	ER_Wrap_Check_Dest			;no -check dest.

	mov	ax,[si].Source_Initial_Seg_Page 	;get segment
	xor	dx,dx					;clear high word
	mov	bx,ER_10H				;adjust segment to
							;  absolute address
	mul	bx					;
	add	ax,[si].Source_Initial_Offset		;add in offset
	adc	dx,0					;pick up carry if any

	add	ax,[si].Region_Length_Low_Word		;add in low word of
							;  trf size
	adc	dx,[si].Region_Length_High_Word 	;add in high word of
							;  trf size
	cmp	dx,ER_10H				;> 1Mb?
	jae	ER_Wrap_Check_Error_Exit		;yes - signal error
	jmp	ER_Wrap_Check_Good_Exit 		;no - signal no error

ER_Wrap_Check_Dest:

	cmp	[si].Dest_Memory_Type,ER_Conv_Memory	;conv. memory?
	jne	ER_Wrap_Check_Good_Exit 		;no - exit routine

	mov	ax,[si].Dest_Initial_Seg_Page		;get segment
	xor	dx,dx					;clear high word
	mov	bx,ER_10H				;adjust segment to
							;  absolute address
	mul	bx					;
	add	ax,[si].Dest_Initial_Offset		;add in offset
	adc	dx,0					;pick up carry if any

	add	ax,[si].Region_Length_Low_Word		;add in low word of
							;  trf size
	adc	dx,[si].Region_Length_High_Word 	;add in high word of
							;  trf size
	cmp	dx,ER_10H				;> 1Mb?
	jae	ER_Wrap_Check_Error_Exit		;yes - signal error

ER_Wrap_Check_Good_Exit:

	xor	ah,ah					;signal no error
	jmp	ER_Wrap_Check_Exit			;exit routine

ER_Wrap_Check_Error_Exit:

	mov	ah,EMS_CodeA2				;signal error

ER_Wrap_Check_Exit:

	pop	bx					;restore regs
	pop	dx					;

	ret						;return to caller

ER_Wrap_Check		endp				;end proc


;=========================================================================
; ER_Overlap_Check	: This routine checks to determine if the conventional
;			  memory region and expanded memory region overlap.
;			  Specifically, does the conventional memory region
;			  overlap the physical page addresses used for
;			  expanded memory?
;
;	Inputs	: DS:SI - Pointer to Move_Source_Dest_Struc data
;
;	Outputs : AH - Non-zero on error
;			Possible error codes: 94h
;
;	Algorithm :
;
;	If Beg.Src.Add. < Beg.Dst.Add
;		If (End.Src.Add - Beg.Dst.Add) > 0
;			signal OVERLAP
;		Else
;			signal NO-OVERLAP
;		EndIf
;	Else
;		If (End.Dst.Add - Beg.Src.Add) > 0
;			signal OVERLAP
;		Else
;			signal NO-OVERLAP
;		EndIf
;	EndIf
;=========================================================================

ER_Overlap_Check	proc				;check for overlap

	push	dx					;save regs
	call	ER_Save_Context 			;save context

	cmp	[si].Source_Memory_Type,ER_Conv_Memory	;conventional memory?
	je	ER_Overlap_Check_Source 		;yes - check overlap
							;no - see if dest is
							;  conv. memory

	cmp	[si].Dest_Memory_Type,ER_Conv_Memory	;conventional memory?
	jne	ER_Overlap_Jump_Good			;no - exit routine

ER_Overlap_Check_Dest:

	mov	di,offset cs:ER_Save_Context_Buffer	;get addressibility to
							;  the page frame save
							;buffer
	add	di,bp					;offset BP relative
	cli						;ints off
	cmp	Map_Count,2				;>= 2 page frames
	sti						;ints on
	jb	ER_Overlap_Check_Dest_1_Frame		;no - use 1st. frame
	add	di,Type Mappable_Phys_Page_Struct	;yes - adjust ptr to
							;  next frame for dest.
ER_Overlap_Check_Dest_1_Frame:

		;**** calc abs address of the bottom of EMS transfer area

	mov	ax,cs:[di].Phys_Page_Segment		;get seg value
	xor	dx,dx					;clear high word
	mov	bx,ER_10H				;para size
	mul	bx					;make abs address
	mov	cs:[bp].ER_Src_Abs_Beg_Low,ax		;save abs. address of
	mov	cs:[bp].ER_Src_Abs_Beg_High,dx		;  phys page beg.

		;**** calc abs address of the top of EMS transfer area

	add	ax,EMS_Page_Size_In_Bytes		;make abs address
	adc	dx,0					;
	mov	cs:[bp].ER_Src_Abs_End_Low,ax		;save abs. address
	mov	cs:[bp].ER_Src_Abs_End_High,dx		;  of phys page end

		;**** calc abs address of the bottom of CONV transfer area

	mov	ax,[si].Dest_Initial_Seg_Page		;get segment
	xor	dx,dx					;clear high word
	mov	bx,ER_10H				;para size
	mul	bx					;make abs address
	add	ax,[si].Dest_Initial_Offset		;get offset
	adc	dx,0					;pick up carry
	mov	cs:[bp].ER_Dst_Abs_Beg_Low,ax		;save initial seg start
	mov	cs:[bp].ER_Dst_Abs_Beg_High,dx		;save initial off start

		;**** calc abs address of the top of CONV transfer area

	add	ax,[si].Region_Length_Low_Word		;add in low word of
							;  trf size
	adc	dx,[si].Region_Length_High_Word 	;add in high word of
	mov	cs:[bp].ER_Dst_Abs_End_Low,ax		;save initial seg start
	mov	cs:[bp].ER_Dst_Abs_End_High,dx		;save initial off start

	call	ER_General_Overlap_Test 		;test for overlap

	jc	ER_Overlap_Error_Exit			;exit with error

ER_Overlap_Jump_Good:

	jmp	ER_Overlap_Good_Exit			;exit good

ER_Overlap_Check_Source:

	mov	di,offset cs:ER_Save_Context_Buffer	;get addressibility to
							;  the page frame save
							;buffer
	add	di,bp					;offset BP relative

		;**** calc abs address of the bottom of EMS transfer area

	mov	ax,cs:[di].Phys_Page_Segment		;get seg value
	xor	dx,dx					;clear high word
	mov	bx,ER_10H				;para size
	mul	bx					;make abs address
	mov	cs:[bp].ER_Src_Abs_Beg_Low,ax		;save abs. address of
	mov	cs:[bp].ER_Src_Abs_Beg_High,dx		;  phys page beg.

		;**** calc abs address of the top of EMS transfer area

	mov	ax,cs:[di].Phys_Page_Segment		;get seg value
	mov	dx,EMS_Page_Size_In_Bytes		;get end of phys page
	mov	bx,ER_10H				;para size
	mul	bx					;make abs address
	mov	cs:[bp].ER_Src_Abs_End_Low,ax		;save abs. address
	mov	cs:[bp].ER_Src_Abs_End_High,dx		;  of phys page end

		;**** calc abs address of the bottom of CONV transfer area

	mov	ax,[si].Source_Initial_Seg_Page 	;get segment
	xor	dx,dx					;clear high word
	mov	bx,ER_10H				;para size
	mul	bx					;make abs address
	add	ax,[si].Source_Initial_Offset		;get offset
	adc	dx,0					;pick up carry
	mov	cs:[bp].ER_Dst_Abs_Beg_Low,ax		;save initial seg start
	mov	cs:[bp].ER_Dst_Abs_Beg_High,dx		;save initial off start

		;**** calc abs address of the top of CONV transfer area

	add	ax,[si].Region_Length_Low_Word		;add in low word of
							;  trf size
	adc	dx,[si].Region_Length_High_Word 	;add in high word of
	mov	cs:[bp].ER_Dst_Abs_End_Low,ax		;save initial seg start
	mov	cs:[bp].ER_Dst_Abs_End_High,dx		;save initial off start

	call	ER_General_Overlap_Test 		;test for overlap

	jnc	ER_Overlap_Good_Exit			;exit good
	jmp	ER_Overlap_Error_Exit			;exit bad

ER_Overlap_Good_Exit:

	xor	ah,ah					;signal no error
	jmp	ER_Overlap_Exit 			;exit

ER_Overlap_Error_Exit:

	mov	ah,EMS_Code94				;signal error

ER_Overlap_Exit:

	call	ER_Restore_Context			;restore context

	pop	dx					;restore regs

	ret						;return to caller

ER_Overlap_Check	endp				;end proc


;=========================================================================
; ER_EMS_Overlap_Check	: This routine determines if the source and target
;			  EMS regions overlap when both the source and target
;			  reside in EMS.
;
;	Inputs	: DS:SI - Pointer to Move_Source_Dest_Struc data
;
;	Outputs : AH - Non-zero on error
;			Possible error codes: 92h
;
;	Algorithm :
;
;	If Beg.Src.Add. < Beg.Dst.Add
;		If (End.Src.Add - Beg.Dst.Add) > 0
;			signal OVERLAP
;		Else
;			signal NO-OVERLAP
;		EndIf
;	Else
;		If (End.Dst.Add - Beg.Src.Add) > 0
;			signal OVERLAP
;		Else
;			signal NO-OVERLAP
;		EndIf
;	EndIf
;=========================================================================

ER_EMS_Overlap_Check	proc				;check for overlap

	push	bx					;save regs
	push	dx					;

	cmp	[si].Source_Memory_Type,ER_EMS_Memory	;Source EMS?
	jne	ER_EMS_Overlap_Exit			;no - exit routine

	cmp	[si].Dest_Memory_Type,ER_EMS_Memory	;Dest. EMS?
	jne	ER_EMS_Overlap_Exit			;no - exit routine

	mov	bx,[si].Source_Handle			;get source handle
	cmp	bx,[si].Dest_Handle			;source = dest?
	jne	ER_EMS_Overlap_Good_Exit		;no - exit routine

ER_EMS_Overlap_Calc_N_Ck:

		;**** calc absolute beginning address of source page

	mov	ax,[si].Source_Initial_Seg_Page 	;get start page
	xor	dx,dx					;clear high word
	mov	bx,EMS_Page_Size_In_Bytes		;get page size
	mul	bx					;convert page to abs
							;  address
	add	ax,[si].Source_Initial_Offset		;add in offset value
	adc	dx,0					;pick up carry

	mov	cs:[bp].ER_Src_Abs_Beg_Low,ax		;save low word of add
	mov	cs:[bp].ER_Src_Abs_Beg_High,dx		;save high word of add

		;**** calc absolute ending address of source page

	add	ax,[si].Region_Length_Low_Word		;add in low word of
							;  length
	adc	dx,[si].Region_Length_High_Word 	;add in high word of
							;  length
	mov	cs:[bp].ER_Src_Abs_End_Low,ax		;save low word of end
	mov	cs:[bp].ER_Src_Abs_End_High,dx		;save high word of end

		;**** calc absolute beginning address of dest. page

	mov	ax,[si].Dest_Initial_Seg_Page		;get start page
	xor	dx,dx					;clear high word
	mov	bx,EMS_Page_Size_In_Bytes		;get page size
	mul	bx					;convert page to abs
							;  address
	add	ax,[si].Dest_Initial_Offset		;add in offset value
	adc	dx,0					;pick up carry

	mov	cs:[bp].ER_Dst_Abs_Beg_Low,ax		;save low word of add
	mov	cs:[bp].ER_Dst_Abs_Beg_High,dx		;save high word of add

		;**** calc absolute ending address of dest. page

	add	ax,[si].Region_Length_Low_Word		;add in low word of
							;  length
	adc	dx,[si].Region_Length_High_Word 	;add in high word of
							;  length
	mov	cs:[bp].ER_Dst_Abs_End_Low,ax		;save low word of end
	mov	cs:[bp].ER_Dst_Abs_End_High,dx		;save high word of end

		;**** Actual test for overlap - corresponds to algorithm above

	call	ER_General_Overlap_Test 		;test for overlap
	jnc	ER_EMS_Overlap_Good_Exit		;no error

ER_EMS_Overlap_Error_Exit:

	mov	ah,EMS_Code92				;signal error
	jmp	ER_EMS_Overlap_Exit			;exit

ER_EMS_Overlap_Good_Exit:

	xor	ah,ah					;no error

ER_EMS_Overlap_Exit:

	pop	dx					;restore regs
	pop	bx					;

	ret						;return to caller

ER_EMS_Overlap_Check	endp				;end proc


;=========================================================================
; ER_General_Overlap_Test:This routine determines if the source and target
;			  EMS regions overlap when both the source and target
;			  reside in EMS.
;
;	Inputs	: ER_Src_Abs_Beg_Low  -  Low word of beginning trf area of source
;		  ER_Src_Abs_Beg_High -  High word of beginning trf area of source
;
;		  ER_Src_Abs_End_Low  -  Low word of ending trf area of source
;		  ER_Src_Abs_End_High -  High word of ending trf area of source
;
;		: ER_Dst_Abs_Beg_Low  -  Low word of beginning trf area of dest.
;		  ER_Dst_Abs_Beg_High -  High word of beginning trf area of dest.
;
;		  ER_Dst_Abs_End_Low  -  Low word of ending trf area of dest.
;		  ER_Dst_Abs_End_High -  High word of ending trf area of dest.
;
;	Outputs : NC - no overlap
;		  CY - overlap
;
;	Algorithm :
;
;	If Beg.Src.Add. < Beg.Dst.Add
;		If (End.Src.Add - Beg.Dst.Add) > 0
;			signal OVERLAP
;		Else
;			signal NO-OVERLAP
;		EndIf
;	Else
;		If (End.Dst.Add - Beg.Src.Add) > 0
;			signal OVERLAP
;		Else
;			signal NO-OVERLAP
;		EndIf
;	EndIf
;=========================================================================

ER_General_Overlap_Test 	proc			;

	push	ax					;save regs
	push	bx					;
	push	cx					;
	push	dx					;

	mov	ax,cs:[bp].ER_Src_Abs_Beg_High		;get source beg. add.
	mov	bx,cs:[bp].ER_Src_Abs_Beg_Low		;
	mov	cx,cs:[bp].ER_Dst_Abs_Beg_High		;get dest. beg. add.
	mov	dx,cs:[bp].ER_Dst_Abs_Beg_Low		;
	call	ER_Dword_Compare			;
;	$if	c					;< dest. beg. add.?
	JNC ER_IF1
	     mov  ax,cs:[bp].ER_Src_Abs_End_Low 	;get end address
	     mov  dx,cs:[bp].ER_Src_Abs_End_High	;
	     sub  ax,cs:[bp].ER_Dst_Abs_Beg_Low 	;End.Src.Add-Beg.Dst.Add
	     sbb  dx,cs:[bp].ER_Dst_Abs_Beg_High	;
;	     $if  ns					;yes - overlap
	     JS ER_IF2
		  stc					;signal error
		  mov cs:[bp].ER_Direction_Flag,ER_Down ;signal reverse move
;	     $else					;no - not sure yet
	     JMP SHORT ER_EN2
ER_IF2:
		  clc					;signal no overlap
		  mov cs:[bp].ER_Direction_Flag,ER_Up	;forward move
;	     $endif					;
ER_EN2:
;	$else						;not sure if src < dst
	JMP SHORT ER_EN1
ER_IF1:
	     mov  ax,cs:[bp].ER_Dst_Abs_End_Low 	;get end address
	     mov  dx,cs:[bp].ER_Dst_Abs_End_High	;
	     sub  ax,cs:[bp].ER_Src_Abs_Beg_Low 	;End.Dst.Add-Beg.Src.Add
	     sbb  dx,cs:[bp].ER_Src_Abs_Beg_High	;
;	     $if  ns					;yes - overlap
	     JS ER_IF6
		  stc					;signal error
		  mov cs:[bp].ER_Direction_Flag,ER_Up	;forward move
;	     $else					;no - not sure yet
	     JMP SHORT ER_EN6
ER_IF6:
		  clc					;signal no overlap
		  mov cs:[bp].ER_Direction_Flag,ER_Up	;forward move
;	     $endif					;
ER_EN6:
;	$endif						;
ER_EN1:

	pop	dx					;restore regs
	pop	cx					;
	pop	bx					;
	pop	ax					;

	ret						;return to caller

ER_General_Overlap_Test 	endp			;end proc


;=========================================================================
; ER_Dword_Compare	: This routine determines whether or not a dword
;			  value is greater than another dword value.
;
;	Inputs	: AX - Source high word
;		  BX - Source low word
;		  CX - Destination high word
;		  DX - Destination low word
;
;	Outputs : NC - source >= destination
;		  CY - source < destination
;=========================================================================

ER_Dword_Compare	proc				;

	cmp	ax,cx					;src high < dest high?
;	$if	b					;yes
	JNB ER_IF10
		stc					;signal less than
;	$else						;no
	JMP SHORT ER_EN10
ER_IF10:
		cmp	ax,cx				;src high > dest high?
;		$if	a				;yes
		JNA ER_IF12
			clc				;signal greater than
;		$else					;no
		JMP SHORT ER_EN12
ER_IF12:
			cmp	bx,dx			;src low < dest low?
;			$if	b			;yes
			JNB ER_IF14
				stc			;signal less than
;			$else				;no
			JMP SHORT ER_EN14
ER_IF14:
				cmp	bx,dx		;src low > dest low?
;				$if	a		;yes
				JNA ER_IF16
					clc		;signal greater than
;				$else			;no
				JMP SHORT ER_EN16
ER_IF16:
					clc		;
;				$endif			;
ER_EN16:
;			$endif				;
ER_EN14:
;		$endif					;
ER_EN12:
;	$endif						;
ER_EN10:

	ret						;

ER_Dword_Compare	endp				;



;=========================================================================
; ER_Segment_Adjust	: This routine adjusts the segment:offset to a value
;			  with an offset less than 16.
;
;	Inputs	: AX:DX - Segment:Offset to be adjusted
;
;	Outputs : AX:DX - New Segment:Offset value
;=========================================================================

ER_Segment_Adjust	proc				;adjust segment value

	push	bx					;save bx
	push	cx					;

	mov	bx,ax					;save segment value
	mov	ax,dx					;get offset
	xor	dx,dx					;clear high word
	mov	cx,ER_10h				;divide by 10h
	div	cx					;get seg adjustment
							;  factor
	add	ax,bx					;adjust segment up
							;  dx contains new off.
	pop	cx					;restore regs
	pop	bx					;restore bx

	ret						;return to caller

ER_Segment_Adjust	endp				;end proc


;=========================================================================
; ER_Log_Page_Test	: This routine checks the offset specified for
;			  the logical page to determine if the offset is
;			  within the valid ranges for the page size.
;
;	Inputs	: DS:SI - Pointer to Move_Source_Dest_Struc data
;
;	Outputs : AH - Non-zero on error
;			Possible error codes: 95h
;=========================================================================

ER_Log_Page_Test	proc				;

	mov	ax,EMS_Page_Size_In_Bytes		;get page size

	cmp	[si].Source_Memory_Type,ER_EMS_Memory	;EMS memory specified?
	jne	ER_Log_Dest_Test			;no - check dest.

	cmp	ax,[si].Source_Initial_Offset		;> EMS page size
	jae	ER_Log_Good_Exit			;good exit
	jmp	ER_Log_Error_Exit			;error - bad exit

ER_Log_Dest_Test:

	cmp	[si].Dest_Memory_Type,ER_EMS_Memory	;EMS memory specified?
	jne	ER_Log_Good_Exit			;good exit

	cmp	ax,[si].Dest_Initial_Offset		;> EMS page size
	jae	ER_Log_Good_Exit			;good exit

ER_Log_Error_Exit:

	mov	ah,EMS_Code95				;signal error
	jmp	ER_Log_Exit				;exit routine

ER_Log_Good_Exit:

	xor	ah,ah					;signal no error

ER_Log_Exit:

	ret						;return to caller

ER_Log_Page_Test	endp				;end proc

;=========================================================================
; ER_Save_Context	: This routine saves the context for page frames
;			  needed for the move/exchange.
;
;	Inputs	: none
;
;	Outputs : ER_Save_Context_Buffer - save context for the needed page frames
;=========================================================================

ER_Save_Context 	proc				;save contexts

	push	ax					;save regs
	push	cx					;
	push	di					;
	push	si					;
	push	ds					;
	push	es					;

	mov	ax,cs					;make ds/es = cs
	mov	ds,ax					;
	mov	es,ax					;

	mov	si,offset cs:Map_Table			;ptr to page frame table
	mov	di,offset cs:ER_Save_Context_Buffer	;get dest. offset
	add	di,bp					;offset BP relative

	mov	cx,2					;default frame save
	cli						;ints off
	cmp	Map_Count,2				;2 page frames?
	jae	ER_Save_Context_Loop			;< = 2 - continue
	mov	cx,Map_Count				;max frame count to save

ER_Save_Context_Loop:

	sti						;ints on
	push	cx					;save cx
	mov	cx,Type Mappable_Phys_Page_Struct	;get byte count to trf
	cli						;ints off
	rep	movsb					;perform save
	sti						;ints on
	pop	cx					;restore cx
	loop	ER_Save_Context_Loop			;continue

ER_Save_Exit:

	pop	es					;restore regs
	pop	ds					;
	pop	si					;
	pop	di					;
	pop	cx					;
	pop	ax					;

	ret						;return to caller

ER_Save_Context 	endp				;end proc


;=========================================================================
; ER_Restore_Context	: This routine restores the context for page frames
;			  saved.  These pages were used for the
;			  move/exchange requested.
;
;	Inputs	: ER_Save_Context_Buffer - contains saved context
;
;	Outputs : restored context for the saved page frames
;=========================================================================

ER_Restore_Context	proc				;restore contexts

	push	ax					;save regs
	push	cx					;
	push	di					;
	push	si					;
	push	ds					;
	push	es					;

	mov	ax,cs					;make ds/es = cs
	mov	ds,ax					;
	mov	es,ax					;

	mov	di,offset cs:Map_Table			;ptr to page frame table
	mov	si,offset cs:ER_Save_Context_Buffer	;get dest. offset
	add	si,bp					;offset BP relative

	mov	cx,2					;default frame restore
	cli						;ints off
	cmp	Map_Count,2				;2 page frames?
	jae	ER_Restore_Context_Loop 		;< = 2 - continue
	mov	cx,Map_Count				;max frame count to rest

ER_Restore_Context_Loop:

	sti						;ints on
	mov	al,byte ptr ds:[si].Phys_Page_Number	;get physical page num.
	mov	bx,word ptr ds:[si].PPM_Log_Page	;get logical page num.
	mov	dx,word ptr ds:[si].PPM_Handle		;get handle number
	call	Map_L_To_P				;map in orig. page

	push	cx					;save cx
	mov	cx,Type Mappable_Phys_Page_Struct	;get byte count to trf
	cli						;ints off
	rep	movsb					;perform save
	sti						;ints on
	pop	cx					;restore cx
	loop	ER_Restore_Context_Loop 		;continue

ER_Restore_Exit:

	pop	es					;restore regs
	pop	ds					;
	pop	si					;
	pop	di					;
	pop	cx					;
	pop	ax					;

	ret						;return to caller

ER_Restore_Context	endp				;end proc



;=========================================================================
; ER_Det_Src_Dest_Seg	: This routine determines the applicable segment,
;			  offset, and page to be used for the move/exchange.
;			  This routine sets the pages/addresses to the end
;			  of the area to be moved/exchanged, if the move
;			  is to be a reverse move.  If the move is to be
;			  a forward move, the pages/addresses are set to
;			  the beginning of the area to be moved/exchanged.
;			  In this way an overlapping move can be
;			  performed without overlaying data it is to move.
;
;	Inputs	: DS:SI - Pointer to Move_Source_Dest_Struc data
;
;	Outputs : ER_Source_Seg 	- Segment value of source
;		  ER_Dest_Seg		- Segment value of destination
;
;		  ER_Source_Off 	- Offset value of source
;		  ER_Dest_Off		- Offset value of destination
;
;		  ER_Source_Page	- Source EMS page
;		  ER_Dest_Page		- Destination EMS page
;
;		  ER_Source_Handle	- Source handle
;		  ER_Dest_Handle	- Destination handle
;
;		  ER_Source_Phys_Page	- Physical page number
;		  ER_Dest_Phys_Page	- Physical page number
;=========================================================================

ER_Det_Src_Dest_Seg	proc				;

	push	ax					;save regs
	push	bx					;
	push	cx					;
	push	dx					;
	push	di					;
	push	ds					;
	push	es					;


	cmp	[si].Source_Memory_Type,ER_EMS_Memory	;EMS?
	jne	ER_Det_Source_Conv			;no - conventional mem.

	mov	di,offset cs:ER_Save_Context_Buffer	;get addressibility to
							;  the page frame save
							;buffer
	add	di,bp					;offset BP relative
	mov	ax,cs:[di].Phys_Page_Segment		;get seg value
	mov	cs:[bp].ER_Source_Seg,ax		;save it in variable

	mov	ax,[si].Source_Handle			;get source handle
	mov	cs:[bp].ER_Source_Handle,ax		;save handle

	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF22
		mov	ax,[si].Region_Length_Low_Word	;get low word of move
		mov	dx,[si].Region_Length_High_Word ;get high word
		add	ax,[si].Source_Initial_Offset	;pick up offset value
		adc	dx,0				;pick up carry
		mov	bx,4000h			;get page size
		div	bx				;get end logical page
		add	ax,[si].Source_Initial_Seg_Page ;adjust it for 1st.
		mov	cs:[bp].ER_Source_Page,ax	;save log. page
		dec	dx				;adjust to end point
		mov	cs:[bp].ER_Source_Off,dx	;save offset in last pg

;	$else						;forward move
	JMP SHORT ER_EN22
ER_IF22:
		mov	ax,[si].Source_Initial_Seg_Page ;get page
		mov	dx,[si].Source_Initial_Offset	;get offset
		mov	cs:[bp].ER_Source_Page,ax	;save page
		mov	cs:[bp].ER_Source_Off,dx	;save offset
;	$endif						;
ER_EN22:
	mov	ax,cs:[di].Phys_Page_Number		;get phys. page
	mov	cs:[bp].ER_Source_Phys_Page,ax		;save it
	jmp	ER_Det_Dest_Check			;jump to dest check

ER_Det_Source_Conv:

	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF25
		mov	ax,[si].Region_Length_Low_Word	;get low word of move
		mov	dx,[si].Region_Length_High_Word ;get high word
		mov	bx,ER_10h			;get bytes/para
		div	bx				;get para count
							;  AX = para's
							;  DX = offset
		mov	bx,ax				;save across adjust call
		mov	cx,dx				;
		mov	ax,[si].Source_Initial_Seg_Page ;get seg value
		mov	dx,[si].Source_Initial_Offset	;get off value
		dec	dx				;adjust to end byte
		call	ER_Segment_Adjust		;adjust it downward
		add	ax,bx				;new segment value
		add	dx,cx				;new offset value

		mov	cs:[bp].ER_Source_Seg,ax	;save it in variable
		mov	cs:[bp].ER_Source_Off,dx	;save offset in var
;	$else						;forward move
	JMP SHORT ER_EN25
ER_IF25:
		mov	ax,[si].Source_Initial_Seg_Page ;get seg value
		mov	dx,[si].Source_Initial_Offset	;get off value
		mov	cs:[bp].ER_Source_Seg,ax	;save it in variable
		mov	cs:[bp].ER_Source_Off,dx	;save offset in var
;	$endif						;
ER_EN25:


ER_Det_Dest_Check:

	cmp	[si].Dest_Memory_Type,ER_EMS_Memory	;Dest. EMS?
	jne	ER_Det_Dest_Conv			;no - conventional mem.

	mov	di,offset cs:ER_Save_Context_Buffer	;save frame buffer
	add	di,bp					;offset BP relative
	cli						;ints off
	cmp	Map_Count,1				;> 1 page frame?
	sti						;ints on
	jb	ER_Det_Dest_Check1			;don't adjust pointer
	add	di,Type Mappable_Phys_Page_Struct	;next entry in save buf

ER_Det_Dest_Check1:

	mov	ax,cs:[di].Phys_Page_Segment		;get seg value
	mov	cs:[bp].ER_Dest_Seg,ax			;save it in variable

	mov	ax,[si].Dest_Handle			;get dest. handle
	mov	cs:[bp].ER_Dest_Handle,ax		;save handle

	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF28
		mov	ax,[si].Region_Length_Low_Word	;get low word of move
		mov	dx,[si].Region_Length_High_Word ;get high word
		add	ax,[si].Dest_Initial_Offset	;pick up offset value
		adc	dx,0				;pick up carry

		mov	bx,4000h			;get page size
		div	bx				;get end logical page
		add	ax,[si].Dest_Initial_Seg_Page	;adjust it for 1st.
		mov	cs:[bp].ER_Dest_Page,ax 	;save log. page
		dec	dx				;adjust to end point
		mov	cs:[bp].ER_Dest_Off,dx		;save off. in last page

;	$else						;forward move
	JMP SHORT ER_EN28
ER_IF28:
		mov	ax,[si].Dest_Initial_Seg_Page		;get page
		mov	dx,[si].Dest_Initial_Offset		;get offset
		mov	cs:[bp].ER_Dest_Page,ax 		;save log. page
		mov	cs:[bp].ER_Dest_Off,dx			;save off. in last page
;	$endif							;
ER_EN28:
	mov	ax,cs:[di].Phys_Page_Number			;get phys page number
	mov	cs:[bp].ER_Dest_Phys_Page,ax			;save it
	jmp	ER_Det_Exit				;exit routine

ER_Det_Dest_Conv:

	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF31
		mov	ax,[si].Region_Length_Low_Word	;get low word of move
		mov	dx,[si].Region_Length_High_Word ;get high word
		mov	bx,ER_10H			;get bytes/para
		div	bx				;get para count
							;  AX = para's
							;  DX = offset
		mov	bx,ax				;save across adjust call
		mov	cx,dx				;
		mov	ax,[si].Dest_Initial_Seg_Page	;get seg value
		mov	dx,[si].Dest_Initial_Offset	;get off value
		dec	dx				;adjust to end byte
		call	ER_Segment_Adjust		;adjust it downward
		add	ax,bx				;new segment value
		add	dx,cx				;new offset value

		mov	cs:[bp].ER_Dest_Seg,ax		;save it in variable
		mov	cs:[bp].ER_Dest_Off,dx		;save offset in var
;	$else						;forward move
	JMP SHORT ER_EN31
ER_IF31:
		mov	ax,[si].Dest_Initial_Seg_Page	;get seg value
		mov	dx,[si].Dest_Initial_Offset	;get off value
		mov	cs:[bp].ER_Dest_Seg,ax		;save it in variable
		mov	cs:[bp].ER_Dest_Off,dx		;save offset in var
;	$endif						;
ER_EN31:


ER_Det_Exit:

	pop	es					;restore regs
	pop	ds					;
	pop	di					;
	pop	dx					;
	pop	cx					;
	pop	bx					;
	pop	ax					;

	ret						;return to caller

ER_Det_Src_Dest_Seg	endp				;end proc


;=========================================================================
; ER_Det_Move_Count	: This initializes the count variables for the
;			  loop iteration counter of the move/exchange.
;
;	Inputs	: DS:SI - Pointer to Move_Source_Dest_Struc data
;
;	Outputs : ER_Move_Count_Low  - low word value of move count
;		  ER_Move_Count_High - high word value of move count
;=========================================================================


ER_Det_Move_Count	proc				;

	push	ax					;save regs
	push	dx					;

	mov	ax,[si].Region_Length_Low_Word		;get low word count
	mov	dx,[si].Region_Length_High_Word 	;get high word count
	mov	cs:[bp].ER_Move_Count_Low,ax		;save low word
	mov	cs:[bp].ER_Move_Count_High,dx		;save high word

	pop	dx					;restore regs
	pop	ax					;

	ret						;return to caller

ER_Det_Move_Count	endp				;end proc

;=========================================================================
; ER_Move_Source_To_Buffer	: This routine moves the source data to
;				  the buffer before it is transferred to
;				  its final destination.
;
;	Inputs	: BP - carries type of memory for source/dest
;		  Bit 0 - Destination (EMS if set)
;		  Bit 1 - Source (EMS if set)
;
;	Outputs : ER_Move_Xchg_Buffer1 - Source data
;=========================================================================

ER_Move_Source_To_Buffer	proc			;

	push	ax					;save regs
	push	bx					;
	push	dx					;
	push	di					;
	push	es					;

	test	cs:[bp].ER_Mem_Type,ER_Source_EMS_Memory;Source EMS?
	jz	ER_Move_Source_Conv_Mem 		;no - adjust seg:off
	jmp	ER_Move_Source_EMS_Mem			;yes- continue move

ER_Move_Source_Conv_Mem:

	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF34
		mov	ax,ds				;adjust segment:off
		dec	ax				;segment - 1 para
		mov	ds,ax				;
		add	si,ER_10H			;adjust offset for 1
;	$else						;forward move
	JMP SHORT ER_EN34
ER_IF34:
		mov	ax,ds				;get segment value
		mov	dx,si				;get offset value
		call	ER_Segment_Adjust		;adjust the seg:off
		mov	ds,ax				;restore ds
		mov	si,dx				;restore offset
;	$endif						;
ER_EN34:
	jmp	ER_Move_Source_Count			;determine count

ER_Move_Source_EMS_Mem:


	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF37
		cmp	si,0ffffh			;beginning of log page
;		$if	e				;yes
		JNE ER_IF38
			dec	cs:[bp].ER_Source_Page	;adjust page ptr
			mov	si,EMS_Page_Size_In_Bytes;get page size
;		$endif					;
ER_IF38:
;	$else						;forward move
	JMP SHORT ER_EN37
ER_IF37:
		cmp	si,4000h			;wrap beyond page
;		$if	e				;yes
		JNE ER_IF41
			inc	cs:[bp].ER_Source_Page	;adjust page ptr
			xor	si,si			;clear si
;		$endif					;
ER_IF41:
;	$endif						;
ER_EN37:
	mov	bx,cs:[bp].ER_Source_Page		;pass page to map
	call	ER_Map_Next_Src_Page			;no  - map in current pg

ER_Move_Source_Count:

	mov	cx,ER_10H				;default count
	cmp	cs:[bp].ER_Move_Count_High,0		;high word set
	jne	ER_Move_Source_High_Set 		;yes - use default
	cmp	cs:[bp].ER_Move_Count_Low,cx		;>= 10h bytes
	jae	ER_Move_Source_High_Set 		;yes - use default
	mov	cx,cs:[bp].ER_Move_Count_Low		;no - use last few bytes

ER_Move_Source_High_Set:

	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF44
		cmp	si,di				;source >= dest?
;		$if	b				;no
		JNB ER_IF45
			cmp	si,ER_10H		;source >= 10h?
;			$if	b			;no
			JNB ER_IF46
				mov	cx,si		;get move count
				inc	cx		;always 1 byte off
;			$endif				;
ER_IF46:
;		$else					;source >= dest
		JMP SHORT ER_EN45
ER_IF45:
			cmp	di,ER_10H		;dest >= 10h?
;			$if	b			;no
			JNB ER_IF49
				mov	cx,di		;get move count
				inc	cx		;always 1 byte off
;			$endif				;
ER_IF49:
;		$endif					;
ER_EN45:
;	$else						;forward move
	JMP SHORT ER_EN44
ER_IF44:
		cmp	si,di				;source >= dest?
;		$if	a				;yes
		JNA ER_IF53
			mov	ax,4000h		;get end of page
			sub	ax,si			;get bytes remaining
			cmp	ax,ER_10H		;source >= 10h
;			$if	b			;no
			JNB ER_IF54
				mov	cx,ax		;get remaining count
;			$endif				;
ER_IF54:
;		$else					;source >= dest
		JMP SHORT ER_EN53
ER_IF53:
			mov	ax,4000h		;get end of page
			sub	ax,di			;get bytes remaining
			cmp	ax,ER_10H		;dest >= 10h
;			$if	b			;no
			JNB ER_IF57
				mov	cx,ax		;get remaining count
;			$endif				;
ER_IF57:
;		$endif					;
ER_EN53:
;	$endif						;
ER_EN44:

	jmp	ER_Move_Source_Default_Count		;continue routine

ER_Move_Source_Default_Count:

	mov	cs:[bp].ER_Current_Move_Count,cx	;save current move cnt

	sub	cs:[bp].ER_Move_Count_Low,cx		;get new count
	sbb	cs:[bp].ER_Move_Count_High,0		;pick up borrow

	mov	ax,cs					;get seg for buffer
	mov	es,ax					;put into es
	mov	di,offset cs:ER_Move_Xchg_Buffer1	;offset of buffer
	add	di,bp					;offset BP relative

	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF61
		add	di,ER_10H			;end of buffer	+ 1
		dec	di				;end of buffer
;	$endif						;
ER_IF61:


	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF63
		std					;reverse move
;	$else						;forward move
	JMP SHORT ER_EN63
ER_IF63:
		cld					;
;	$endif						;
ER_EN63:
	cli						;ints off
	rep	movsb					;move the data
	sti						;ints on

ER_Move_Source_Exit:

	pop	es					;restore regs
	pop	di					;
	pop	dx					;
	pop	bx					;
	pop	ax					;

	ret						;return to caller

ER_Move_Source_To_Buffer	endp			;end proc


;=========================================================================
; ER_Move_Buffer_To_Dest	: This routine moves the data in the buffer
;				  to the destination specified by the user.
;
;	Inputs	: BP - carries type of memory for source/dest
;		  Bit 0 - Destination (EMS if set)
;		  Bit 1 - Source (EMS if set)
;		  ER_Move_Xchg_Buffer1 - Source data
;
;	Outputs : Adjusted segment:offset or page/offset
;=========================================================================

ER_Move_Buffer_To_Dest		proc			;

	push	ax					;save regs
	push	bx					;
	push	dx					;
	push	si					;
	push	ds					;

	test	cs:[bp].ER_Mem_Type,ER_Dest_EMS_Memory	;Source EMS?
	jz	ER_Move_Buffer_Conv_Mem 		;no - adjust seg:off
	jmp	ER_Move_Buffer_EMS_Mem			;yes- continue move

ER_Move_Buffer_Conv_Mem:

	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF66
		mov	ax,es				;adjust segment:off
		dec	ax				;segment - 1 para
		mov	es,ax				;
		add	di,ER_10H			;adjust offset for 1
;	$else						;forward move?
	JMP SHORT ER_EN66
ER_IF66:
		mov	ax,es				;adjust seg:off
		mov	dx,di				;
		call	ER_Segment_Adjust		;
		mov	es,ax				;new seg:off
		mov	di,dx				;
;	$endif						;
ER_EN66:
							;  para
	jmp	ER_Move_Buffer_Count			;determine count

ER_Move_Buffer_EMS_Mem:

	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF69
		cmp	di,0ffffh			;beginning of log page
;		$if	e				;yes
		JNE ER_IF70
			dec	cs:[bp].ER_Dest_Page	;next page
			mov	di,EMS_Page_Size_In_Bytes;end of page
;		$endif					;
ER_IF70:
;	$else						;forward move
	JMP SHORT ER_EN69
ER_IF69:
		cmp	di,4000h			;end of page?
;		$if	e				;yes
		JNE ER_IF73
			inc	cs:[bp].ER_Dest_Page	;next page
			xor	di,di			;clear di
;		$endif					;
ER_IF73:
;	$endif						;
ER_EN69:
	mov	bx,cs:[bp].ER_Dest_Page 		;pass page to map
	call	ER_Map_Next_Dest_Page			;map in the page

ER_Move_Buffer_Count:

	mov	cx,cs:[bp].ER_Current_Move_Count	;get move from source

	mov	ax,cs					;get seg for buffer
	mov	ds,ax					;put into es
	mov	si,offset cs:ER_Move_Xchg_Buffer1	;offset of buffer
	add	si,bp					;offset BP relative
	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF76
		add	si,ER_10H			;end of buffer	+ 1
		dec	si				;end of buffer
;	$endif						;
ER_IF76:

	cmp	cs:[bp].ER_Direction_Flag,ER_Down	;reverse move?
;	$if	e					;yes
	JNE ER_IF78
		std					;reverse move
;	$else						;forward move
	JMP SHORT ER_EN78
ER_IF78:
		cld					;
;	$endif						;
ER_EN78:
	cli						;ints off
	rep	movsb					;move the data
	sti						;ints on

ER_Move_Dest_Exit:

	pop	ds					;restore regs
	pop	si					;
	pop	dx					;
	pop	bx					;
	pop	ax					;

	ret						;return to caller

ER_Move_Buffer_To_Dest		endp			;end proc


;=========================================================================
; ER_Xchg_Source_To_Buffer	: This routine moves the source data to
;				  the buffer before it is exchanged with
;				  the destination data.
;
;	Inputs	: BP - carries type of memory for source/dest
;		  Bit 0 - Destination (EMS if set)
;		  Bit 1 - Source (EMS if set)
;
;	Outputs : ER_Move_Xchg_Buffer1 - Source data
;=========================================================================

ER_Xchg_Source_To_Buffer	proc			;

	push	ax					;save regs
	push	bx					;
	push	dx					;
	push	di					;
	push	si					;
	push	ds					;
	push	es					;

	test	cs:[bp].ER_Mem_Type,ER_Source_EMS_Memory;Source EMS?
	jz	ER_Xchg_Source_Conv_Mem 		;no - adjust seg:off
	jmp	ER_Xchg_Source_EMS_Mem			;yes- continue move

ER_Xchg_Source_Conv_Mem:

	mov	ax,ds					;adjust segment:off
	mov	dx,si					;
	call	ER_Segment_Adjust			;
	mov	ds,ax					;new segment:off
	mov	si,dx					;
	jmp	ER_Xchg_Source_Count			;determine count

ER_Xchg_Source_EMS_Mem:

	cmp	si,4000h				;beginning of log page
	je	ER_Xchg_Source_EMS_Next 		;yes - get next page
	mov	bx,cs:[bp].ER_Source_Page		;pass log. page to call
	call	ER_Map_Next_Src_Page			;no  - map in current pg
	jmp	ER_Xchg_Source_Count			;get count for move

ER_Xchg_Source_EMS_Next:

	mov	bx,cs:[bp].ER_Source_Page		;pass log. page to call
	inc	bx					;  adjusted upward
	call	ER_Map_Next_Src_Page			;map in the page
	xor	si,si					;reinit pointer

ER_Xchg_Source_Count:

	mov	cx,ER_10H				;default count
	cmp	cs:[bp].ER_Move_Count_High,0		;high word set
	jne	ER_Xchg_Source_High_Set 		;yes - use default
	cmp	cs:[bp].ER_Move_Count_Low,cx		;>= 10h bytes
	jae	ER_Xchg_Source_High_Set 		;yes - use default
	mov	cx,cs:[bp].ER_Move_Count_Low		;no - use last few bytes

ER_Xchg_Source_High_Set:

	cmp	si,di					;source >= dest?
;	$if	b					;no
	JNB ER_IF81
		mov	ax,4000h			;get end of page
		sub	ax,si				;get bytes remaining
		cmp	ax,ER_10H			;source >= 10h
;		$if	b				;no
		JNB ER_IF82
			mov	cx,ax			;get remaining count
;		$endif					;
ER_IF82:
;	$else						;source >= dest
	JMP SHORT ER_EN81
ER_IF81:
		mov	ax,4000h			;get end of page
		sub	ax,di				;get bytes remaining
		cmp	ax,ER_10H			;dest >= 10h
;		$if	b				;no
		JNB ER_IF85
			mov	cx,ax			;get remaining count
;		$endif					;
ER_IF85:
;	$endif						;
ER_EN81:

ER_Xchg_Source_Default_Count:

	mov	cs:[bp].ER_Current_Move_Count,cx	;save current move cnt

	sub	cs:[bp].ER_Move_Count_Low,cx		;get new count
	sbb	cs:[bp].ER_Move_Count_High,0		;pick up borrow

	mov	ax,cs					;get seg for buffer
	mov	es,ax					;put into es
	mov	di,offset cs:ER_Move_Xchg_Buffer1	;offset of buffer
	add	di,bp					;offset BP relative

	cld						;forward move
	cli						;ints off
	rep	movsb					;move the data
	sti						;ints on

ER_Xchg_Source_Exit:

	pop	es					;restore regs
	pop	ds					;
	pop	si					;
	pop	di					;
	pop	dx					;
	pop	bx					;
	pop	ax					;

	ret						;return to caller

ER_Xchg_Source_To_Buffer	endp			;end proc


;=========================================================================
; ER_Xchg_Dest_To_Buffer	: This routine moves the destination data to
;				  the buffer before it is exchanged with
;				  the source data.
;
;	Inputs	: BP - carries type of memory for source/dest
;		  Bit 0 - Destination (EMS if set)
;		  Bit 1 - Source (EMS if set)
;
;	Outputs : ER_Move_Xchg_Buffer2 - Destination data
;=========================================================================

ER_Xchg_Dest_To_Buffer		proc			;

	push	ax					;save regs
	push	bx					;
	push	dx					;
	push	di					;
	push	si					;
	push	ds					;
	push	es					;

	test	cs:[bp].ER_Mem_Type,ER_Dest_EMS_Memory	;Dest EMS?
	jz	ER_Xchg_Dest_Conv_Mem			;no - adjust seg:off
	jmp	ER_Xchg_Dest_EMS_Mem			;yes- continue move

ER_Xchg_Dest_Conv_Mem:

	mov	ax,es					;adjust segment:off
	mov	dx,di					;
	call	ER_Segment_Adjust			;
	mov	es,ax					;new segment:off
	mov	di,dx					;
	jmp	ER_Xchg_Dest_Count			;determine count

ER_Xchg_Dest_EMS_Mem:

	cmp	di,4000h				;beginning of log page
	je	ER_Xchg_Dest_EMS_Next			;yes - get next page
	mov	bx,cs:[bp].ER_Dest_Page 		;pass log. page to call
	call	ER_Map_Next_Dest_Page			;no  - map in current pg
	jmp	ER_Xchg_Dest_Count			;get count for move

ER_Xchg_Dest_EMS_Next:

	mov	bx,cs:[bp].ER_Dest_Page 		;pass log. page to call
	inc	bx					;  adjusted upward
	call	ER_Map_Next_Dest_Page			;map in the page
	xor	di,di					;reinit pointer

ER_Xchg_Dest_Count:

	mov	cx,cs:[bp].ER_Current_Move_Count	;get move count
	mov	ax,es					;get destination seg
	mov	ds,ax					;put into ds for buffer
							;  transfer
	mov	si,di					;get destination off
	mov	ax,cs					;get seg for buffer
	mov	es,ax					;put into es
	mov	di,offset cs:ER_Move_Xchg_Buffer2	;offset of buffer
	add	di,bp					;offset BP relative

	cld						;forward move
	cli						;ints off
	rep	movsb					;move the data
	sti						;ints on

ER_Xchg_Dest_Exit:

	pop	es					;restore regs
	pop	ds					;
	pop	si					;
	pop	di					;
	pop	dx					;
	pop	bx					;
	pop	ax					;

	ret						;return to caller

ER_Xchg_Dest_To_Buffer		endp			;end proc




;=========================================================================
; ER_Xchg_Buffer_To_Source	; This routine performs the actual exchange
;				  from the destination buffer to the source
;				  buffer.
;
;	Inputs	: BP - carries type of memory for source/dest
;		  Bit 0 - Destination (EMS if set)
;		  Bit 1 - Source (EMS if set)
;		  ER_Move_Xchg_Buffer2 - Destination data
;
;	Outputs : Adjusted segment:offset or page/offset
;=========================================================================

ER_Xchg_Buffer_To_Source	proc			;

	push	ax					;save regs
	push	bx					;
	push	dx					;
	push	di					;
	push	es					;

	test	cs:[bp].ER_Mem_Type,ER_Source_EMS_Memory;Source EMS?
	jz	ER_Xchg_Buf2_Conv_Mem			;no - adjust seg:off
	jmp	ER_Xchg_Buf2_EMS_Mem			;yes- continue move

ER_Xchg_Buf2_Conv_Mem:

	mov	ax,ds					;adjust segment:off
	mov	dx,si					;
	call	ER_Segment_Adjust			;
	mov	ds,ax					;new segment:off
	mov	si,dx					;
	jmp	ER_Xchg_Buf2_Count			;determine count

ER_Xchg_Buf2_EMS_Mem:

	cmp	si,4000h				;beginning of log page
	je	ER_Xchg_Buf2_EMS_Next			;yes - get next page
	mov	bx,cs:[bp].ER_Source_Page		;pass log. page to call
	call	ER_Map_Next_Src_Page			;no  - map in current pg
	jmp	ER_Xchg_Buf2_Count			;get count for move

ER_Xchg_Buf2_EMS_Next:

	inc	cs:[bp].ER_Source_Page			;adjust log page
	mov	bx,cs:[bp].ER_Source_Page		;pass log. page to call
	call	ER_Map_Next_Src_Page			;map in the page
	xor	si,si					;reinit pointer

ER_Xchg_Buf2_Count:

	mov	cx,cs:[bp].ER_Current_Move_Count	;get move count

	mov	ax,ds					;get destination seg
	mov	es,ax					;put into ds for buffer
							;  transfer
	mov	di,si					;get destination off
	add	si,cx					;adjust source ptr
	push	si					;save across xchg
	push	ds					;

	mov	ax,cs					;get seg for buffer
	mov	ds,ax					;put into es
	mov	si,offset cs:ER_Move_Xchg_Buffer2	;offset of buffer
	add	si,bp					;offset BP relative

	cld						;forward move
	cli						;ints off
	rep	movsb					;move the data
	sti						;ints on

	pop	ds					;restore ptr
	pop	si					;

ER_Xchg_Buf2_Exit:

	pop	es					;restore regs
	pop	di					;
	pop	dx					;
	pop	bx					;
	pop	ax					;

	ret						;return to caller

ER_Xchg_Buffer_To_Source	endp			;end proc



;=========================================================================
; ER_Xchg_Buffer_To_Dest	; This routine performs the actual exchange
;				  from the source buffer to the destination.
;
;	Inputs	: BP - carries type of memory for source/dest
;		  Bit 0 - Destination (EMS if set)
;		  Bit 1 - Source (EMS if set)
;		  ER_Move_Xchg_Buffer1 - Source data
;
;	Outputs : Adjusted segment:offset or page/offset
;=========================================================================

ER_Xchg_Buffer_To_Dest		proc			;

	push	ax					;save regs
	push	bx					;
	push	dx					;
	push	si					;
	push	ds					;

	test	cs:[bp].ER_Mem_Type,ER_Dest_EMS_Memory	;Dest EMS?
	jz	ER_Xchg_Buf1_Conv_Mem			;no - adjust seg:off
	jmp	ER_Xchg_Buf1_EMS_Mem			;yes- continue move

ER_Xchg_Buf1_Conv_Mem:

	mov	ax,es					;adjust segment:off
	mov	dx,di					;
	call	ER_Segment_Adjust			;
	mov	es,ax					;new segment:off
	mov	di,dx					;
	jmp	ER_Xchg_Buf1_Count			;determine count

ER_Xchg_Buf1_EMS_Mem:

	cmp	di,4000h				;beginning of log page
	je	ER_Xchg_Buf1_EMS_Next			;yes - get next page
	mov	bx,cs:[bp].ER_Dest_Page 		;pass log. page to call
	call	ER_Map_Next_Dest_Page			;no  - map in current pg
	jmp	ER_Xchg_Buf1_Count			;get count for move

ER_Xchg_Buf1_EMS_Next:

	inc	cs:[bp].ER_Dest_Page			;adjust log page
	mov	bx,cs:[bp].ER_Dest_Page 		;pass log. page to call
	call	ER_Map_Next_Dest_Page			;map in the page
	mov	di,EMS_Page_Size_In_Bytes		;reinit pointer

ER_Xchg_Buf1_Count:

	mov	cx,cs:[bp].ER_Current_Move_Count	;get move count
	mov	ax,cs					;get seg for buffer
	mov	ds,ax					;put into es
	mov	si,offset cs:ER_Move_Xchg_Buffer1	;offset of buffer
	add	si,bp					;offset BP relative

	cld						;forward move
	cli						;ints off
	rep	movsb					;move the data
	sti						;ints on

ER_Xchg_Buf1_Exit:

	pop	ds					;restore regs
	pop	si					;
	pop	dx					;
	pop	bx					;
	pop	ax					;

	ret						;return to caller

ER_Xchg_Buffer_To_Dest		endp			;end proc



;=========================================================================
; ER_Map_Next_Src_Page		: This routine maps in the page needed by
;				  the source of the move/exchange.
;
;	Inputs	: ER_Source_Phys_Page - Physical page of source
;		  ER_Source_Handle    - Handle of source
;		  BX		      - logical page
;
;	Outputs : newly mapped page
;=========================================================================

ER_Map_Next_Src_Page	proc				;map next src. page

	mov	ax,cs:[bp].ER_Source_Phys_Page		;map the source page
	mov	dx,cs:[bp].ER_Source_Handle		;handle to use
	call	Map_L_To_P				;map the page

	ret						;return to caller

ER_Map_Next_Src_Page	endp				;end proc

;=========================================================================
; ER_Map_Next_Dest_Page 	: This routine maps in the page needed by
;				  the destination of the move/exchange.
;
;	Inputs	: ER_Dest_Phys_Page - Physical page of source
;		  ER_Dest_Handle    - Handle of source
;		  BX		    - logical page to map
;
;	Outputs : newly mapped page
;=========================================================================

ER_Map_Next_Dest_Page	proc				;map next dest. page

	mov	ax,cs:[bp].ER_Dest_Phys_Page		;map the dest. page
	mov	dx,cs:[bp].ER_Dest_Handle		;handle to use
	call	Map_L_To_P				;map the page

	ret						;return to caller

ER_Map_Next_Dest_Page	endp				;end proc

;=========================================================================
; ER_Move_Data		: This routine will perform the actual move of the
;			  data for the function 5700h.
;
;	Inputs	: DS:SI - Pointer to Move_Source_Dest_Struc data
;
;	Outputs : AH - Non-zero on error
;=========================================================================

ER_Move_Data	proc					;move the data

	push	bx					;save regs
	push	cx					;
	push	dx					;
	push	di					;
	push	si					;
	push	ds					;
	push	es					;

	call	ER_Save_Context 			;save off max of 2 pages
	call	ER_Det_Src_Dest_Seg			;determine segs
	call	ER_Det_Move_Count			;ER_10h_Move_Count =
							;  # of 10h moves
							;ER_10h_Move_Remainder =
							;  # of bytes remaining

ER_Move_Data_Now:

							;set the flags to signal
							;the memory type in use
							;for Source/Destination.

	xor	al,al					;al signals type of mem
	or	al,[si].Source_Memory_Type		;get source memory type
	shl	al,1					;put into bit 1
	or	al,[si].Dest_Memory_Type		;get dest. memory type
	cbw						;make it a word value
	mov	cs:[bp].ER_Mem_Type,ax			;put flags in var
							;bp = bit 0 - dest mem
							;     bit 1 - src mem

	mov	di,cs:[bp].ER_Dest_Off			;get dest. offset
	mov	es,cs:[bp].ER_Dest_Seg			;get dest. seg

	mov	si,cs:[bp].ER_Source_Off		;get src. offset
	mov	ds,cs:[bp].ER_Source_Seg		;get src. seg

ER_Move_Data_Loop:

	call	ER_Move_Source_To_Buffer		;move data to buffer
	call	ER_Move_Buffer_To_Dest			;move buffer to dest.

	cmp	cs:[bp].ER_Move_Count_High,0		;end of move?
	jne	ER_Move_Data_Loop			;no - continue loop
	cmp	cs:[bp].ER_Move_Count_Low,0		;end of move?
	jne	ER_Move_Data_Loop			;no - continue loop
							;yes - end of loop

ER_Move_Data_Error_Exit:

	call	ER_Restore_Context			;restore the context

	pop	es					;restore regs
	pop	ds					;
	pop	si					;
	pop	di					;
	pop	dx					;
	pop	cx					;
	pop	bx					;

	ret						;return to caller

ER_Move_Data	endp					;end proc



;=========================================================================
; ER_Exchange_Data	: This routine will perform the actual exchange of
;			  data for the function 5701h.
;
;	Inputs	: DS:SI - Pointer to Move_Source_Dest_Struc data
;
;	Outputs : AH - Non-zero on error
;=========================================================================

ER_Exchange_Data	proc				;xchg the data

	push	bx					;save regs
	push	cx					;
	push	dx					;
	push	di					;
	push	si					;
	push	ds					;
	push	es					;

	call	ER_Save_Context 			;save off max of 2 pages
	call	ER_Det_Src_Dest_Seg			;determine segs
	call	ER_Det_Move_Count			;ER_10h_Move_Count =
							;  # of 10h moves
							;ER_10h_Move_Remainder =
							;  # of bytes remaining

ER_Xchg_Data_Now:

							;set the flags to signal
							;the memory type in use
							;for Source/Destination.

	xor	al,al					;al signals type of mem
	or	al,[si].Source_Memory_Type		;get source memory type
	shl	al,1					;put into bit 1
	or	al,[si].Dest_Memory_Type		;get dest. memory type
	cbw						;make it a word value
	mov	cs:[bp].ER_Mem_Type,ax			;put flags in var
							;bp = bit 0 - dest mem
							;     bit 1 - src mem

	mov	di,cs:[bp].ER_Dest_Off			;get dest. offset
	mov	es,cs:[bp].ER_Dest_Seg			;get dest. seg

	mov	si,cs:[bp].ER_Source_Off		;get src. offset
	mov	ds,cs:[bp].ER_Source_Seg		;get src. seg

ER_Xchg_Data_Loop:

	call	ER_Xchg_Source_To_Buffer		;move source to buf 1
	call	ER_Xchg_Dest_To_Buffer			;move dest. to buf 2
	call	ER_Xchg_Buffer_To_Source		;move buf2 to source
	call	ER_Xchg_Buffer_To_Dest			;move buf1 to dest.

	cmp	cs:[bp].ER_Move_Count_High,0		;end of move?
	jne	ER_Xchg_Data_Loop			;no - continue loop
	cmp	cs:[bp].ER_Move_Count_Low,0		;end of move?
	jne	ER_Xchg_Data_Loop			;no - continue loop
							;yes - end of loop

ER_Xchg_Data_Error_Exit:

	call	ER_Restore_Context			;restore the context

	pop	es					;restore regs
	pop	ds					;
	pop	si					;
	pop	di					;
	pop	dx					;
	pop	cx					;
	pop	bx					;

	ret						;return to caller

ER_Exchange_Data	endp				;end proc



	page

;=========================================================================
;=============== Function 5Ah Logic -  Allocate Raw Pages    =============
;=========================================================================


;=========================================================================
; Alloc_Raw		- This routine allocates raw EMS pages, pages
;			  less than the standard 16k page.  These pages
;			  are a sub-multiple of 16k.  In the IBM version
;			  of this implementation the raw page is defined
;			  as 16k, thus we do not need to do anything
;			  special here.  We map this call to the proc
;			  GET_HANDLE (function 43h) to allocate a handle.
;
;	Inputs	: AH - 5Ah (Allocate Raw Pages)
;		  BX - Number of raw pages to allocate
;
;	Outputs : AH - Non-zero if error (Determined by Get_Handle proc)
;		  DX - Handle if no error
;=========================================================================

Alloc_Raw	proc					;Allocate raw pages

	PUSH	BX
	PUSH	CX
	PUSH	DI
	PUSH	SI
	PUSH	DS			;save these registers

	PUSH	CS			;get cs
	POP	DS			;into ds

					;Remove test for BX = 0. This is   @RH4
					; valid under LIM 4.0

	cmp	al,AR_Sub_Max		;sub function out of range?
	jna	AR_OKSub		;no
		mov	ah,EMS_Code8F	;yes-signal error
		jmp	AR_Exit 	;exit routine

AR_OKSub:

	CMP	BX,TOTAL_EMS_PAGES	;Enough total EMS pages?
	JNA	AR_OKTOTAL
	MOV	AH,EMS_CODE87
	JMP	AR_EXIT

AR_OKTOTAL:
	cli				;ints off
	CMP	BX,FREE_PAGES		;Enough unallocated pages?
	sti				;ints on
	JNA	AR_OKFREE
	MOV	AH,EMS_CODE88
	JMP	AR_EXIT
			;-----------------------------------------------------
			; Search for a free handle			 @RH1 º
			;-----------------------------------------------------
AR_OKFREE:
	MOV	CX,NUM_HANDLES		;loop counter is #handles
	DEC	CX			;handle 0 reserved for op. sys.   @RH1
	MOV	DX,1			;handle assignment set to 1	  @RH1
	MOV	DI,TYPE H_LOOKUP_STRUC	;init table index to 1st entry	  @RH1
;--------------------------------
	CLI				;interrupts OFF during allocation
;--------------------------------
AR_FREEHSRCH:
	CMP	HANDLE_LOOKUP_TABLE.H_PAGES[DI],REUSABLE_HANDLE
					;Is this handle available?	  @RH1
	JE	AR_HFREE		;yes end search  dx=handle id	  @RH1
	INC	DX			;next handle assignment
	ADD	DI,TYPE H_LOOKUP_STRUC	;next entry in handle lookup	  @RH1
					;repeat for all table entries
	LOOP AR_FREEHSRCH
	    MOV     AH,EMS_CODE85	;no available handles
	    JMP     AR_EXIT		;go to exit					 ;GGA

			;-----------------------------------------------------
			; If here then there's enough pages for request. @RH1 º
			;   DX = handle #, DI = ptr to hndl lookup entry @RH1 º
AR_HFREE:

	MOV	CX,NUM_HANDLES		;loop counter
	DEC	CX			;handle 0 reserved for op. sys.    @RH1
					;si = index to hndl lookup tbl	   @RH1
	MOV	SI,TYPE H_LOOKUP_STRUC	; for adding pages (skip 0 entry)  @RH1
	XOR	AX,AX			;clear page counter
	CLC				;clear carry for addition
AR_PAGESUM:
	CMP	HANDLE_LOOKUP_TABLE.H_PAGES[SI],REUSABLE_HANDLE
	JE	AR_PGSUM_BOT		;If handle is free don't add       @RH4
	ADD	AX,HANDLE_LOOKUP_TABLE.H_PAGES[SI]
					;add lengths (pages) of PALs	  @RH1
	ADD	SI,TYPE H_LOOKUP_STRUC	; next entry in handle lookup	  @RH1
AR_PGSUM_BOT:
	LOOP	AR_PAGESUM
	CMP	AX,TOTAL_EMS_PAGES	;pages in handle lookup > total?  @RH1
	JNA	AR_CALCHLUP		;no OK				  @RH1
	    MOV     AH,EMS_CODE80	;software error..we screwed up	  @RH1
	    JMP     AR_EXIT		;go to exit			  @RH1		 ;GGA

AR_CALCHLUP:				;calculate entry in hndl lkup tbl @RH1
	cmp	bx,0			;page request?
	jne	AR_Alloc_Cont		;yes continue
		cli			;ints off
		mov	Handle_LookUp_Table.H_Pages[di],bx	;new page count
		sti			;ints on
		xor	ah,ah		;clear flag
		jmp	AR_Exit 	;exit routine

AR_Alloc_Cont:

	cli						;ints off
	mov	cx,bx					;alloc count
	call	EMS_Page_Contig_Chk			;do we have contig pgs.
	jnc	AR_Alloc				;yes continue process
		mov	ah,EMS_Code88			;no  signal error
		sti					;ints on
		jmp	AR_Exit 			;exit routine

AR_Alloc:

	call	EMS_Link_Set				;set up links


	sub	Free_Pages,bx		;free = free - requested pages
	mov	Handle_LookUp_Table.H_Pages[di],bx	;page count
	mov	Handle_LookUp_Table.H_Pal_Ptr[di],si	;initialize to ptr for
							;  pages
	sti						;ints on
	xor	ah,ah					;clear flag


AR_EXIT:										 ;GGA

	POP	DS
	POP	SI
	POP	DI
	POP	CX
	POP	BX

	ret						;return to caller

Alloc_Raw	endp					;end proc

	page
;=========================================================================
;=============== Function 5Ch Logic -  Prepare for Warm Boot =============
;=========================================================================


;=========================================================================
; Prepare_Boot		- This routine prepares the hardware for a
;			  warm boot.  Since we have no special hardware
;			  requirements at this time, this routine sets
;			  a good error level and returns to the caller.
;
;	Inputs	: AH - 5Ch (Prepare for Warm Boot)
;
;	Outputs : AH - Non-zero if error (Determined by Get_Handle proc)
;=========================================================================

Prepare_Boot	proc					;prepare for warm boot

	xor	ah,ah					;signal no error

	ret						;return to caller

Prepare_Boot	endp					;end proc



