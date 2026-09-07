page	,132	;
; CHKDSK message display.
	EXTRN	command_line_buffer:byte
;*****************************************************************************
; Include Files
;*****************************************************************************
.xlist
include pathmac.inc
include chkseg.inc
INCLUDE CPMFCB.INC
INCLUDE CHKEQU.INC
.list
INCLUDE CHKMSG.INC
.xlist
INCLUDE SYSMSG.INC
.list
cstack	 segment para stack 'STACK'
	db	62 dup ("-Stack!-")      ; (362-80h) is the additional IBM ROM
cstack	 ends
;*****************************************************************************
; Message Services
;*****************************************************************************
MSG_UTILNAME  <CHKDSK>
;.xlist
data	segment public para 'DATA'
Msg_Services	<MSGDATA>
data	ends
code	segment public para 'CODE'
pathlabl	msgret
Msg_Services	<NEARmsg>
Msg_Services	<LOADmsg>
Msg_Services	<DISPLAYmsg,CHARmsg,NUMmsg,TIMEmsg,DATEmsg>
pathlabl	msgret
Msg_Services	<CHKDSK.CLA,CHKDSK.CLB,CHKDSK.CLC,CHKDSK.CLD,CHKDSK.CL1,CHKDSK.CL2,CHKDSK.CTL>
code	ends
.list
;*****************************************************************************
; Public Declarations
;*****************************************************************************
	Public	SysLoadMsg
	Public	SysDispMsg
;***************************************************************************
; Message Structures
;***************************************************************************
Message_Table struc				;
Entry1	dw	0				;
Entry2	dw	0				;
Entry3	dw	0				;
Entry4	dw	0				;
Entry5	db	0				;
Entry6	db	0				;
Entry7	dw	0				;
Message_Table ends				;
code	segment public para 'CODE'              ;
;*****************************************************************************
;Routine name&gml Display_Interface
;*****************************************************************************
;DescriptioN&gml Save all registers, set up registers required for SysDispMsg
;	      routine. This information is contained in a message description
;	      table pointed to by the DX register. Call SysDispMsg, then
;	      restore registers. This routine assumes that the only time an
;	      error will be returned is if an extended error message was
;	      requested, so it will ignore error returns
;Called Procedures: Message (macro)
;Input&gml ES&gmlDX = pointer to message description
;Output&gml None
;Psuedocode
;----------
;	Save all registers
;	Setup registers for SysDispMsg from Message Description Tables
;	CALL SysDispMsg
;	Restore registers
;	ret
;*****************************************************************************
Public	Display_Interface
Display_Interface   proc			;
	push	ds
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	mov	di,dx				;Change pointer to table
	mov	dx,dg				;Point to group
	mov	ds,dx				;
	mov	ax,[di].Entry1			;Message number
	mov	bx,[di].Entry2			;Handle
	mov	si,[di].Entry3			;Sublist
	mov	cx,[di].Entry4			;Count
	mov	dh,[di].Entry5			;Class
	mov	dl,[di].Entry6			;Function
	mov	di,[di].Entry7			;Input
	call	SysDispMsg			;Display the message
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	pop	ds
	ret					;All done
Display_Interface      endp			;
include msgdcl.inc

code	ends
	end
