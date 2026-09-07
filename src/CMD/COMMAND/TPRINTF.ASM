 page 80,132
TITLE	COMMAND Transient Printf routine

;****************************************************************
;*
;* ROUTINE:	STD_PRINTF/STD_EPRINTF
;*
;* FUNCTION:	Set up to print out a message using SYSDISPMSG.
;*		Set up substitutions if utility message.  Make
;*		sure any changes to message variables in TDATA
;*		are reset to avoid reloading the transient.
;*
;* INPUT:	Msg_Disp_Class	-  set to message class
;*		Msg_Cont_Flag	-  set to control flags
;*		DS	points to transient segment
;*
;*		if utility message:
;*		DX	points to a block with message number
;*			(word), number of substitutions (byte),
;*			followed by substitution list if there
;*			are substitutions.  If substitutions
;*			are not in transient segment they must
;*			be set.
;*		else
;*		AX	set to message number
;*
;* OUTPUT:	none
;*
;****************************************************************

.xlist
.xcref
	INCLUDE comsw.asm
	INCLUDE DOSSYM.INC
	INCLUDE comseg.asm
	INCLUDE comequ.asm
	INCLUDE SYSMSG.INC
.list
.cref

datares segment public
	extrn	pipeflag:byte
datares ends

TRANDATA	SEGMENT PUBLIC BYTE
	EXTRN	extend_buf_off:word
	EXTRN	Extend_Buf_ptr:word
	EXTRN	Extend_Buf_seg:word
	EXTRN	Msg_Cont_Flag:byte
	EXTRN	Msg_disp_Class:byte
	EXTRN	pipeemes_ptr:word
TRANDATA	ENDS

TRANSPACE	SEGMENT PUBLIC BYTE
	EXTRN	msg_flag:byte
	EXTRN	print_err_flag:word
	EXTRN	RESSEG:WORD
	EXTRN	String_ptr_2:word
	EXTRN	Subst_buffer:byte
;AD061; EXTRN	String_ptr_2_sb:word

	; include data area for message services

	MSG_UTILNAME <COMMAND>		;AN000; define utility name

	MSG_SERVICES <MSGDATA>

PRINTF_HANDLE	DW  ?

TRANSPACE	ENDS

TRANCODE	SEGMENT PUBLIC BYTE

	EXTRN	cerror:near
	EXTRN	crlf2:near
	EXTRN	tcommand:near

ASSUME	CS:TRANGROUP,DS:TRANGROUP,ES:NOTHING,SS:NOTHING

	PUBLIC	SETSTDINOFF
	PUBLIC	SETSTDINON
	PUBLIC	SETSTDOUTOFF
	PUBLIC	SETSTDOUTON
	PUBLIC	TSYSGETMSG
	PUBLIC	TSYSLOADMSG

PUBLIC Printf_Init
printf_init proc far
	call	std_printf
	ret
printf_init endp

Public	Printf_Crlf
PRINTF_CRLF:
	CALL	STD_PRINTF
	CALL	CRLF2
	RET

PUBLIC	Std_EPrintf
STD_EPRINTF:
	mov	Printf_Handle,2 		;AC000;Print to STDERR
	jmp	short NEW_PRINTF
PUBLIC	Std_Printf
STD_PRINTF:
	mov	Printf_Handle,1 		;AC000;Print to STDOUT

NEW_PRINTF:
	push	ax				;AN000;save registers
	push	bx
	push	cx
	push	es				;AN000;get local ES
	push	ds
	pop	es
	push	di
	push	si
	push	dx
	assume	es:trangroup
;AD061; mov	string_ptr_2_sb,0		;AN000;initialize
	mov	print_err_flag,0

UTILITY_SETUP:
	mov	si,dx				;AN000;Get offset of message number
	lodsw					;AN000;load message number
	push	ax				;AN000;save it
	lodsb					;AN000;get number of substitutions
	mov	cl,al				;AN000;set up CX as # of subst
	xor	ch,ch				;AN000;   SI now points to subst list
	pop	ax				;AN000;get message number back
	cmp	cx,0				;AN000;Any substitutions?
	jz	READY_TO_PRINT			;AN000;No - continue

;AD061;  add	 dx,Ptr_Seg_Pos 		 ;AN000;Point to position of first segment
;AD061;  push	 cx				 ;AN000;save substitution count

;AD061;SET_SUBST:
;AD061;  mov	 bx,dx				 ;AN000;get dx into base register
;AD061;  cmp	 word ptr [bx],0		 ;AN000;has segment been set?
;AD061;  jnz	 SUBST_SEG_SET			 ;AN000;if not 0, don't replace it
;AD061;  test	 word ptr [bx+3],date_type	 ;AN000;if date or time - don't set segment
;AD061;  jnz	 subst_seg_set			 ;AN000;yes - skip it
;AD061;  mov	 word ptr [bx],cs		 ;AN000;put segment of subst parm in list

;AD061;SUBST_SEG_SET:
;AD061;  add	 dx,Parm_Block_Size		 ;AN000;point to position of next segment
;AD061;  loop	 SET_SUBST			 ;AN000;keep replacing until complete
;AD061;  pop	 cx

;AD061;NO_REPLACEMENT:
;AD061;  mov	 bx,parm_off_pos [si]		 ;AN000;get subst offset
;AD061;  cmp	 bx,offset trangroup:string_ptr_2 ;AN000;this is used for double indirection
;AD061;  jnz	 ready_to_print 		 ;AN000;we already have address
;AD061;  mov	 dx,string_ptr_2		 ;AN000;get address in string_ptr_2
;AD061;  mov	 parm_off_pos [si],dx		 ;AN000;put proper address in table
;AD061;  mov	 string_ptr_2_sb,si		 ;AN000;save block changed

	mov	di,offset trangroup:subst_buffer;AN061; Get address of message subst buffer
	push	di				;AN061; save it
	push	cx				;AN061; save number of subst

MOVE_SUBST:
	push	cx				;AN061;save number of subst
	mov	bx,si				;AN061;save start of sublist
	mov	cx,parm_block_size		;AN061;get size of sublist
	rep	movsb				;AN061;move sublist
	test	byte ptr [bx.$M_S_FLAG],date_type ;AN061;are we doing date/time?
	jz	move_subst_cont 		;AN061;no - no need to reset
	mov	word ptr [bx.$M_S_VALUE],0	;AN061;reset original date or time to 0
	mov	word ptr [bx.$M_S_VALUE+2],0

MOVE_SUBST_CONT:
	pop	cx				;AN061;get number of subst back
	loop	move_subst			;AN061;move cx sublists

	pop	cx				;AN061;get number of subst
	push	ax				;AN061;save message number
	cmp	Msg_Disp_Class,Util_Msg_Class	;AN061;Is this a utility message
	jz	CHECK_FIX			;AN061;YES - go see if substitutions
	mov	msg_flag,ext_msg_class		;AN061;set message flag
	mov	di,offset trangroup:extend_buf_ptr ;AN061; Get address of extended message block
	xor	ax,ax				;AN061;clear ax register
	stosw					;AN061;clear out message number
	stosb					;AN061;clear out subst count

CHECK_FIX:
	pop	ax				;AN061;get message number back
	pop	di				;AN061;get start of sublists
	mov	si,di				;AN061;get into SI for msgserv
	mov	bx,si				;AN061;get into BX for addressing
	push	cx				;AN061;save number of subst

SET_SUBST:					;AN061;store the segment of the subst
	cmp	word ptr [bx.$M_S_VALUE+2],0	;AN061;was it set already?
	jnz	subst_seg_set			;AN061;if not 0, don't replace it
	test	byte ptr [bx.$M_S_FLAG],date_type ;AN061;don't replace if date or time
	jnz	subst_seg_set			;AN061;yes - skip it
	mov	word ptr [bx.$M_S_VALUE+2],cs	;AN061;set segment value

SUBST_SEG_SET:
	add	bx,parm_block_size		;AN061;go to next sublist
	loop	set_subst			;AN061;loop CX times
	pop	cx				;AN061;get number of subst back

	mov	bx,si				;AN061;get start of sublist to BX
	cmp	word ptr [bx.$M_S_VALUE],offset trangroup:string_ptr_2 ;AN061;are we using double indirection?
	jnz	ready_to_print			;AN061;no - we already have address
	mov	dx,string_ptr_2 		;AN061;get address in string_ptr_2
	mov	word ptr [bx.$M_S_VALUE],dx	;AN061;put it into the subst block

READY_TO_PRINT:
	mov	bx,Printf_Handle		;AN000;get print handle
	mov	dl,Msg_Cont_Flag		;AN000;set up control flag
	mov	dh,Msg_Disp_Class		;AN000;set up display class
	mov	Msg_Cont_Flag,No_Cont_Flag	;AN061;reset flags to avoid
	mov	Msg_Disp_Class,Util_Msg_Class	;AN061;   transient reload

;AD061; push	bx				;AN026; save registers
;AD061; push	cx
;AD061; push	dx
;AD061; push	si
;AD061; push	di
	push	ds
	push	es


	call	SYSDISPMSG			;AN000;call Rod

	pop	es				;AN026; restore registers
	pop	ds
;AD061; pop	di
;AD061; pop	si
;AD061; pop	dx
;AD061; pop	cx
;AD061; pop	bx

	jnc	Print_success			;AN000; everything went okay
	mov	print_err_flag,ax

print_success:
;AD061; cmp	Msg_Disp_Class,Util_Msg_Class	;AN000;Is this a utility message
;AD061; jz	CHECK_FIX			;AN000;YES - go see if substitutions
;AD061; mov	msg_flag,ext_msg_class		;AN022;set message flag
;AD061; mov	di,offset trangroup:extend_buf_ptr ;AN000; Get address of extended message block
;AD061; xor	ax,ax				;AN000;clear ax register
;AD061; stosw					;AN000;clear out message number
;AD061; stosb					;AN000;clear out subst count

;AD061;  CHECK_FIX:
;AD061;  pop	 dx				 ;AN000;restore dx
;AD061;  cmp	 cx,0				 ;AN000;Any substitutions?
;AD061;  jz	 NO_FIXUP			 ;AN000;No - leave

;AD061;  mov	 si,dx				 ;AN000;Reset changes so transient won't reload
;AD061;  add	 si,Ptr_Seg_Pos 		 ;AN000;Point to position of first segment

;AD061;FIX_SUBST:
;AD061;  mov	 word ptr [si],0		 ;AN000;reset segment to 0
;AD061;  add	 si,Parm_Block_Size		 ;AN000;point to position of next segment
;AD061;  loop	 FIX_SUBST			 ;AN000;keep replacing until complete
;AD061;  cmp	 string_ptr_2_sb,no_subst	 ;AN000;was double indirection used?
;AD061;  jz	 no_fixup			 ;AN000;no - we're finished
;AD061;  mov	 si,string_ptr_2_sb		 ;AN000;get offset changed
;AD061;  mov	 parm_off_pos [si],offset trangroup:string_ptr_2 ;AN000; set address back to string_ptr_2

;AD061;NO_FIXUP:
;AD061; mov	Msg_Cont_Flag,No_Cont_Flag	;AN000;reset flags to avoid
;AD061; mov	Msg_Disp_Class,Util_Msg_Class	;AN000;   transient reload
	pop	dx				;AN061;restore dx
	pop	si				;AN000;restore registers
	pop	di
	pop	es				;AN000;restore registers
	pop	cx
	pop	bx
	pop	ax
	cmp	print_err_flag,0		;AN000; if an error occurred - handle it
	jnz	print_err

	ret

print_err:
	push	cs
	pop	es
	cmp	Printf_Handle,2 		;AN026;Print to STDERR?
	jnz	not_stderr			;AN026;no - continue
	jmp	tcommand			;AN026;Yes - hopless - just exit

not_stderr:
	mov	ax,print_err_flag		;AN026;get extended error number back
	mov	es,[SHELL_DATA_SELECTOR]			; No, set up for error, load the
assume	es:resgroup				;  right error msg, and jmp to cerror.
	test	PipeFlag,-1
	jz	go_to_error
	invoke	PipeOff
	mov	dx,offset trangroup:pipeemes_ptr
	jmp	SHORT print_err_exit		;AC000; JWasm: preserve transient layout

go_to_error:
	mov	msg_disp_class,ext_msg_class	;AN000; set up extended error msg class
	mov	dx,offset TranGroup:Extend_Buf_ptr ;AC000; get extended message pointer
	mov	Extend_Buf_ptr,ax		;AN000; get message number in control block

PRINT_ERR_EXIT:
	push	cs
	pop	es
	JMP	CERROR

;****************************************************************
;*
;* ROUTINE:	TSYSLOADMSG
;*
;* FUNCTION:	Interface to call SYSLOADMSG to avoid duplicate
;*		names since these routines are also used in the
;*		resident.
;*
;* INPUT:	Inputs to SYSLOADMSG
;*
;* OUTPUT:	Outputs from SYSLOADMSG
;*
;****************************************************************


TSYSLOADMSG	PROC	NEAR

	push	bx
	call sysloadmsg 			;AN000; call routine
	pop	bx
	ret					;AN000; exit

TSYSLOADMSG	ENDP

;****************************************************************
;*
;* ROUTINE:	TSYSGETMSG
;*
;* FUNCTION:	Interface to call SYSGETMSG to avoid duplicate
;*		names since these routines are also used in the
;*		resident.
;*
;* INPUT:	Inputs to SYSGETMSG
;*
;* OUTPUT:	Outputs from SYSGETMSG
;*
;****************************************************************


TSYSGETMSG	PROC	NEAR

	push	cx
	call sysgetmsg				;AN000; call routine
	pop	cx
	ret					;AN000; exit

TSYSGETMSG	ENDP

MSG_SERVICES <COMT,NOVERCHECKmsg,NEARmsg,LOADmsg,NOCHECKSTDIN,NOCHECKSTDOUT,GETmsg> ;AC026; The message services
MSG_SERVICES <COMT,NEARmsg,SETSTDIO,DISPLAYmsg,CHARmsg,NUMmsg,TIMEmsg,DATEmsg>	    ;AC026; The message services

PRINTF_LAST LABEL   WORD

include msgdcl.inc


TRANCODE    ENDS
	    END
