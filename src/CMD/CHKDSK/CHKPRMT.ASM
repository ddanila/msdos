TITLE	CHKPRMT - Procedures called from chkdsk which prompt
page	,132					;
	.xlist
	include chkseg.inc
	INCLUDE CHKCHNG.INC
	INCLUDE SYSCALL.INC
	INCLUDE CHKEQU.INC
	INCLUDE CHKMACRO.INC
	include pathmac.inc
	.list
CONST	SEGMENT PUBLIC PARA 'DATA'
	EXTRN	YES_BYTE:BYTE,NO_BYTE:BYTE
	EXTRN	YN_ARG:WORD
	EXTRN	HECODE:byte,CONBUF:byte
CONST	ENDS
CODE	SEGMENT PUBLIC PARA 'CODE'
ASSUME	CS:DG,DS:DG,ES:DG,SS:DG
	EXTRN	PRINTF_CRLF:NEAR,DOCRLF:NEAR
	pathlabl chkprmt
;*****************************************************************************
;Routine name:PromptYN
;*****************************************************************************
;description: Validate that input is valid Y/N for the country dependent info
;	     Return Z flag if 'Y' entered
;Called Procedures: Message (macro)
;		    User_String
;Input: DX = offset to message
;Output: Z flag if 'Y' entered
;Psuedocode
;----------
;	DO
;	   Display prompt and input character
;	   IF got character
;	      Check for country dependent Y/N (INT 21h, AX=6523h Get Ext Country;an000;bgb)
;	      IF NC (Yes or No)
;		 Set Z if Yes, NZ if No
;	      ENDIF
;	   ELSE  (nothing entered)
;	      stc
;	   ENDIF
;	ENDDO NC
;	ret
;*****************************************************************************
Procedure PromptYN				;
	push	si				;Save reg
;	$DO					;
$$DO1:
	   Call    Display_Interface		;Display the message
	   MOV	   DX,OFFSET DG:CONBUF		;Point at input buffer
	   DOS_Call Std_Con_String_Input	;Get input
	   CALL    DOCRLF			;
	   MOV	   SI,OFFSET DG:CONBUF+2	;Point at contents of buffer
	   CMP	   BYTE PTR [SI-1],0		;Was there input?
;	   $IF	   NE				;Yep
	   JE $$IF2
	      mov     al,23h			;See if it is Y/N
	      mov     dl,[si]			;Get character
	      DOS_Call GetExtCntry		;Get country info call
;	      $IF     NC			;Yes or No entered
	      JC $$IF3
		 cmp	 ax,Yes_Found		;Set Z if Yes, NZ if No
		 clc				;CY=0 means Y/N found
;	      $ENDIF				;CY set if neither
$$IF3:
;	   $ELSE				;No characters input
	   JMP SHORT $$EN2
$$IF2:
	      stc				;CY means not Y/N
;	   $ENDIF				;
$$EN2:
;	$ENDDO	NC				;
	JC $$DO1
	pop	si				;
	ret					;
PromptYN endp					;
	pathlabl chkprmt
CODE	ENDS
	END
