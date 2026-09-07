;m
PRINTF_CODE SEGMENT PUBLIC

ASSUME CS:PRINTF_CODE, DS:PRINTF_CODE, ES:PRINTF_CODE, SS:PRINTF_CODE


;ÉÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  P U B L I C S  ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ»
;º											  º

PUBLIC	 initialize_sublists

;º											  º
;ÈÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ  P U B L I C S  ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼

;*****************************************************************************
; External Declarations
;*****************************************************************************
;

EXTRN	 first_sublist:BYTE
EXTRN	 number_of_sublists:ABS
EXTRN	 SysDispMsg:Near






;
;***************************************************************************
; Message Structures
;***************************************************************************
;


Message_Table struc				;
						;
Entry1	dw	0				;
Entry2	dw	0				;
Entry3	dw	0				;
Entry4	dw	0				;
Entry5	db	0				;
Entry6	db	0				;
Entry7	dw	0				;
						;
Message_Table ends				;

include common.stc	      ;contains the following structure

;sublist_def  STRUC

;	      db  ?  ;Sublist Length, fixed
;	      db  ?  ;Reserved, not used yet
;	      dw  ?  ;offset
;sublist_seg  dw  ?  ;segment part of pointer to piece of message
;	      db  ?  ;ID, special end of message format
;	      db  ?  ;flags
;	      db  ?
;	      db  ?
;	      db  ?

;sublist_def  ENDS

;ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;³
;³ INITIALIZE_SUBLISTS
;³ -------------------
;³ A .COM file cannot have references to segments in it at EXE2BIN time so
;³ the segment part of pointers to pieces of messages in sublist blocks must
;³ be done at execution time.  This routine does that for all sublists.
;³
;³
;³ INPUT:
;³
;³
;³
;³
;³
;³
;³
;³ RETURN:
;³
;³
;³  MESSAGES:	 none
;³
;³
;³
;³  REGISTER
;³  USAGE AND
;³  COMVENTIONS:
;³
;³
;³
;³  ASSUMPTIONS:
;³
;³
;³  SIDE EFFECT:
;³
;³
;³   ùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùùù
;³
;³ BEGIN
;³										³
;³ END										³
;³
;ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ

initialize_sublists  PROC  NEAR

MOV   CX,number_of_sublists
MOV   SI,OFFSET first_sublist	       ;address first sublist
repeat_loop:
   MOV	 [SI].sublist_seg,DS	       ;set up the segment part of the pointer field in the sublist block
   ADD	 SI,TYPE sublist_def	       ;point to next sublist block
LOOPNZ	repeat_loop
RET
initialize_sublists  ENDP

;*****************************************************************************
;PRINTF
;*****************************************************************************
;
;Description: Save all registers, set up registers required for SysDispMsg
;	      routine. This information is contained in a message description
;	      table pointed to by the DX register. Call SysDispMsg, then
;	      restore registers. This routine assumes that the only time an
;	      error will be returned is if an extended error message was
;	      requested, so it will ignore error returns
;
;Called Procedures: sysdispmsg
;
;Input:    ES:DX = pointer to message description
;
;Output:   None
;
;Psuedocode
;----------
;
;	Save all registers
;	Setup registers for SysDispMsg from Message Description Tables
;	CALL SysDispMsg
;	Restore registers
;	ret
;*****************************************************************************

Public	PRINTF
PRINTF	 PROC  NEAR		     ;

;	push	ax
						;Save registers
	push	bx				; "  "    "  "
	push	cx				; "  "    "  "
	push	dx				; "  "    "  "
	push	si				; "  "    "  "
	push	di				; "  "    "  "
	mov	di,dx				;Change pointer to table
	mov	ax,[di].Entry1			  ;Message number
	mov	bx,[di].Entry2			  ;Handle
	mov	si,[di].Entry3			  ;Sublist
	mov	cx,[di].Entry4			  ;Count
	mov	dh,[di].Entry5			  ;Class
	mov	dl,[di].Entry6			  ;Function
	mov	di,[di].Entry7			  ;Input
	call	SysDispMsg			;Display the message
	pop	di				;Restore registers
	pop	si				; "  "    "  "
	pop	dx				; "  "    "  "
	pop	cx				; "  "    "  "
	pop	bx				; "  "    "  "
;	pop	ax				; "  "    "  "
	ret					;All done

PRINTF	ENDP			 ;

PRINTF_CODE ENDS

	end
