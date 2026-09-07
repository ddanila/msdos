;
;******************************************************************************
; Message Macro Definitions
;******************************************************************************
;

      EXTRN Display_Interface:near


;-----------------------------------------------------------------------------

Message macro	Message_Name			;
						;
	mov	dx,offset dg:Message_Name     ;
	call	Display_Interface		;
	endm					;

;-----------------------------------------------------------------------------

Parse_Message macro				;

						;
	push	ds				;
	mov	dx,dg				;
	mov	ds,dx				;
	mov	word ptr Parse_Error_Msg,ax	;
	mov	dx,offset dg:Parse_Error_Msg	   ;
	call	Display_Interface		;
	pop	ds				;
	endm					;

;-----------------------------------------------------------------------------

Extended_Message macro				;
						;

	push	ds				;
	mov	dx,dg				;
	mov	ds,dx				;
	mov	word ptr Ext_Error_Msg,ax	;
	mov	dx,offset dg:Ext_Error_Msg    ;
	call	Display_Interface		;
	pop	ds				;
	endm					;

;
;*****************************************************************************
; General Macro's
;*****************************************************************************
;

Procedure	macro	Proc_Name		;
						;
Public	Proc_Name				;
Proc_Name    proc				;
						;
	endm					;
;-----------------------------------------------------------------------------

DOS_Call	macro	Function		;
						;
	mov	ah,Function			;
	int	21h				;
						;
	endm					;
;-----------------------------------------------------------------------------

Popff	macro

	jmp	$+3
	iret
	push	cs
	call	$-2

	endm


;-----------------------------------------------------------------------------

Set_Data_Segment     macro

	push	ax
	mov	ax,dg				;Point to data segment
	mov	ds,ax				;
assume	ds:dg,es:dg
	push	ds
	pop	es
	pop	ax


	endm



