;
page	,132				;
;;*****************************************************************************
; Include files
;*****************************************************************************
;
.xlist
	include pathmac.inc
	include recseg.inc
	include dossym.inc
	INCLUDE SYSMSG.INC
	INCLUDE RECEQU.INC
	INCLUDE RECMSG.INC
.list
;
;*****************************************************************************
; external data
;*****************************************************************************
data	segment public para 'DATA'
	EXTRN	command_line_buffer:byte
	extrn	DrvLet1:Byte
	extrn	DrvLet:Byte
	extrn	rec_num:word
	Extrn	Drive_Letter_Msg:Byte
	extrn	fname_buffer:byte
	EXTRN	x_value_lo:WORD
	EXTRN	x_value_hi:WORD
	EXTRN	y_value_lo:WORD
	EXTRN	y_value_hi:WORD
	extrn	DriveLetter:Byte

;*****************************************************************************
; Message Services
;*****************************************************************************
.xlist
MSG_UTILNAME  <RECOVER>
Msg_Services	<MSGDATA>
data	ends


;
;***************************************************************************
; Message Structures
;***************************************************************************
;
code	segment PUBLIC para 'CODE'
Message_Table struc				;
						;
Entry1	dw	0				;
Entry2	dw	0				;
Entry3	dw	0				;
Entry4	dw	0				;
Entry5	db	0				;
Entry6	db	0				;
Entry7	dw	0				;
Message_Table ends				;

pathlabl	msgret
Msg_Services	<NEARmsg>
Msg_Services	<LOADmsg>
Msg_Services	<DISPLAYmsg,CHARmsg,NUMmsg>
pathlabl	msgret
Msg_Services	<RECOVER.CLA,RECOVER.CL1,RECOVER.CL2,RECOVER.CTL>
.list
;
;*****************************************************************************
; Public Routines
;*****************************************************************************
	Public	SysDispMsg
	Public	SysLoadMsg
	Public	Display_Interface

;*****************************************************************************
;Routine name&gml Display_Interface
;*****************************************************************************
;
;DescriptioN&gml Save all registers, set up registers required for SysDispMsg
;	      routine. This information is contained in a message description
;	      table pointed to by the DX register. Call SysDispMsg, then
;	      restore registers. This routine assumes that the only time an
;	      error will be returned is if an extended error message was
;	      requested, so it will ignore error returns
;
;Called Procedures: Message (macro)
;
;Input&gml ES&gmlDX = pointer to message description
;
;Output&gml None
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

Display_Interface   proc			;

	 push	 ds				 ;
	 push	 ax				 ;Save registers
	 push	 bx				 ; "  "    "  "
	 push	 cx				 ; "  "    "  "
	 push	 dx				 ; "  "    "  "
	 push	 si				 ; "  "    "  "
	 push	 di				 ; "  "    "  "
	 mov	 di,dx				 ;Change pointer to table
	 mov	 dx,DG				 ;Point to data segment
	 mov	 ds,dx				 ;
	 mov	 ax,[di].Entry1 		 ;Message number
	 mov	 bx,[di].Entry2 		 ;Handle
	 mov	 si,[di].Entry3 		 ;Sublist
	 mov	 cx,[di].Entry4 		 ;Count
	 mov	 dh,[di].Entry5 		 ;Class
	 mov	 dl,[di].Entry6 		 ;Function
	 mov	 di,[di].Entry7 		 ;Input
	 call	 SysDispMsg			 ;Display the message
	 pop	 di				 ;Restore registers
	 pop	 si				 ; "  "    "  "
	 pop	 dx				 ; "  "    "  "
	 pop	 cx				 ; "  "    "  "
	 pop	 bx				 ; "  "    "  "
	 pop	 ax				 ; "  "    "  "
	 pop	 ds				 ;
	 ret					 ;All done
Display_Interface      endp			;

include msgdcl.inc

code	ends
	end


;code	 segment public PARA 'CODE'
;code	 ends
;
;const	 segment public para
;const	 ends
;
;cstack  segment stack word 'stack'
;cstack  ends
;
;
;data	 segment public para 'DATA'
;data	 ends
;
;dg	 group	 code,const,data,cstack
;
;code	 segment public para 'code'
;code	 ends
;	 assume  cs:dg,ds:dg,es:dg,ss:cstack
;
;
;;;;;;;;;;code	  segment PUBLIC para 'CODE'
;;;;;;;;;;;;;code    ends
