

PAGE 55,132
NAME	SELQUIT
TITLE	SELQUIT - Exit Panel support for SELECT.EXE
SUBTTL	selquit.asm
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
; SELQUIT.ASM
;
;
; COMMENTS:
;
;
;	   Copyright 1988 Microsoft
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.LFCOND
.XLIST
	INCLUDE    PANEL.MAC
	INCLUDE    PCEQUATE.INC
	INCLUDE    PAN-LIST.INC
	INCLUDE    CASTRUC.INC
	INCLUDE    EXT.INC
	INCLUDE    STRUC.INC
	INCLUDE    MACROS.INC
.LIST
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Setup Environment
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	EXTRN	QM_ACTIVEPAN:WORD
					;
	EXTRN	GET_KEY:NEAR
	EXTRN	CURSOROFF:NEAR
	EXTRN	PCINPUT_CALL:NEAR
	EXTRN	PCDISPQ_CALL:NEAR
					;
	EXTRN	WR_DRETLEN:WORD
	EXTRN	WR_DRETOFF:WORD
	EXTRN	WR_DRETSEG:WORD
	EXTRN	GET_PCB:NEAR
	EXTRN	QM_OPT1:WORD
	EXTRN	QM_ID:WORD
	EXTRN	INC_KS:WORD
					;
	EXTRN	HANDLE_CHILDREN:NEAR
	EXTRN	ADJUST_UP:NEAR
	EXTRN	ADJUST_DOWN:NEAR
	EXTRN	INIT_PQUEUE_CALL:NEAR
	EXTRN	PREPARE_PANEL_CALL:NEAR
	EXTRN	DISPLAY_PANEL_CALL:NEAR
	EXTRN	GET_FUNCTION_CALL:NEAR
	EXTRN	QM_OPT2:WORD
	EXTRN	WR_REFIELDCNT:WORD
	EXTRN	ERROR_KEYS:BYTE
	EXTRN	ERROR_KEYS_LEN:ABS
	EXTRN	PCMBEEP_CALL:NEAR
	EXTRN	BIN_TO_CHAR_ROUTINE:FAR
					;
TRUE	EQU	1
FALSE	EQU	0
					;
SELECT	SEGMENT PARA PUBLIC 'SELECT'    ;AN000;segment for far routine
	ASSUME	CS:SELECT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; HANDLE_F3
;
;
;	CLC = return to SELECT
;	STC = quit SELECT.....
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
F3_ACTIVE    DB      FALSE
					;
	PUBLIC	HANDLE_F3
HANDLE_F3	PROC
	PUSHH  <AX,BX,DI,ES,WR_DRETLEN>
	PUSHH  <WR_DRETOFF,WR_DRETSEG>
	PUSHH  <WR_REFIELDCNT>
					;
	.IF < F3_ACTIVE eq FALSE > near
	   CALL    CURSOROFF		;;AN000;;;
					   ;
	   MOV	   AX,QM_PUSHPQU	   ;AN000;save parent queue
	   OR	   AX,QM_PUSHCQU	   ;AN000;save child queue
	   MOV	   QM_OPT1,AX
	   CALL    PCDISPQ_CALL 	   ;AN000;update display queue
					   ;
	   MOV	   QM_OPT1,QM_CLSPAN	   ;AN000;clear parent panel queue
	   OR	   QM_OPT1,QM_CLSCHD	   ;AN000;clear parent panel queue
	   CALL    PCDISPQ_CALL 	   ;AN000;update display queue
	   MOV	   QM_ACTIVEPAN,PAN_CONFIRM;AN000;current active parent panel
	   MOV	   AX,PAN_CONFIRM
	   MOV	   QM_OPT1,QM_PUSHPAN	   ;AN000;push parent panels
	   CALL    PREPARE_PANEL_CALL	   ;AN000;add panel to display queue

	   MOV	   WR_REFIELDCNT,0	   ;AN000;set for break = off
	   PREPARE_PANEL   PAN_HBAR
	   PREPARE_CHILDREN
	   DISPLAY_PANEL		   ;AN000;push parent panels
					   ;
	   MOV	   CX,FK_ENT_F3_LEN
	   LEA	   DX,FK_ENT_F3
	   MOV	   WR_DRETLEN,CX	   ;AN000;get return string length
	   MOV	   AX,DX		   ;AN000;get return string offset
	   MOV	   WR_DRETOFF,AX
	   MOV	   AX,DS		   ;AN000;get return string segment
	   MOV	   WR_DRETSEG,AX
	   CALL    GET_KEY
	   MOV	   AX,INC_KS
	   MOV	   N_USER_FUNC,AX
					   ;
	   MOV	   AX,QM_POPPQU
	   OR	   AX,QM_POPCQU
	   MOV	   QM_OPT1,AX
	   CALL    PCDISPQ_CALL
	   MOV	   AX,I_USER_INDEX	   ;AN000;get last current element
					   ;
	   .IF < N_USER_FUNC eq F3*256 >
	   .THEN
		STC
		MOV   F3_ACTIVE,TRUE	   ;AN000;DT Indicate exit selected
	   .ELSE
		POP   WR_REFIELDCNT
		PUSH  WR_REFIELDCNT
		DISPLAY_PANEL
		CLC
	   .ENDIF			   ;AN000;;;
					   ;
	.ELSE				   ;AN027;SEH Set carry flag to avoid
	   STC				   ;AN027;SEH	  endless loop in Get_Function_call
	.ENDIF
					   ;
	POPP   <WR_REFIELDCNT,WR_DRETSEG>
	POPP   <WR_DRETOFF,WR_DRETLEN,ES>
	POPP   <DI,BX,AX>
	RET
HANDLE_F3	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	 AX,input
;	 BX,action
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ERROR_PANEL	DW	?
ERROR_TYPE	DW	?
ERROR_CODE	DW	?
ERROR_STRING	DB	5 DUP(0)
					;
	PUBLIC ERROR_ACTIVE
ERROR_ACTIVE	DB	0
					;
	PUBLIC	HANDLE_ERROR_CALL
HANDLE_ERROR_CALL PROC	FAR
	PUSHH  <AX,BX,DI,ES,WR_DRETLEN>
	PUSHH  <WR_DRETOFF,WR_DRETSEG>
	PUSHH  <WR_REFIELDCNT>
					;
	MOV	ERROR_CODE,AX
	MOV	ERROR_PANEL,BX
	MOV	ERROR_TYPE,CX
	MOV	ERROR_ACTIVE,1
					;
	MOV	BX,ERR_BORDER		;AN000;DT current active parent panel
	CALL	GET_PCB 		;AN000;DT get the PCB for this
	MOV	ES:[DI].PCB_CHILDNUM,CX ;AN000;DT set the number of children
					;
	CALL	CURSOROFF
					;
	MOV	QM_OPT1,QM_PUSHPQU	;AN000;save parent queue
	OR	QM_OPT1,QM_PUSHCQU	;AN000;save child queue
	CALL	PCDISPQ_CALL		;AN000;update display queue
					;
	.IF < F3_ACTIVE eq TRUE >
	   MOV	   QM_OPT1,QM_CLSPAN	   ;AN000;clear parent panel queue
	   OR	   QM_OPT1,QM_CLSCHD	   ;AN000;clear parent panel queue
	   CALL    PCDISPQ_CALL 	   ;AN000;update display queue
	.ENDIF

	MOV	QM_OPT1,QM_PUSHPAN	;AN000;push parent panels
	OR	QM_OPT2,QM_BREAKON	;AN000;break on

	MOV	BX,ERR_BORDER		;AN000;current active parent panel
	MOV	QM_ID,BX		;AN000;current active parent panel
	MOV	QM_ACTIVEPAN,BX 	;AN000;current active parent panel
	MOV	AX,BX
	CALL	PREPARE_PANEL_CALL	;AN000;add panel to display queue
					;
	MOV	QM_OPT2,0
					;
;;;;;;;;MOV	WR_REFIELDCNT,0 	;set for break = off
	PREPARE_PANEL	ERROR_PANEL
	PREPARE_CHILDREN
	DISPLAY_PANEL			;AN000;push parent panels
					;
	CALL	PCMBEEP_CALL
					;
	MOV	CX,ERROR_TYPE
	INC	CX
	LEA	DX,ERROR_KEYS
	CALL	GET_FUNCTION_CALL
	MOV	ERROR_ACTIVE,0
					;
	MOV	QM_OPT1,QM_POPPQU
	OR	QM_OPT1,QM_POPCQU
	CALL	PCDISPQ_CALL
	MOV	AX,I_USER_INDEX 	;AN000;get last current element
					;
       .IF < N_USER_FUNC eq F3*256 > or ;AC000;DT F3 to exit SELECT
	   .IF < F3_ACTIVE eq TRUE >	;AN000;DT or already selected
	.THEN
	     STC
	.ELSE
	     POP   WR_REFIELDCNT
	     PUSH  WR_REFIELDCNT
	     DISPLAY_PANEL
	     CLC
	.ENDIF
					;
	POPP   <WR_REFIELDCNT,WR_DRETSEG>
	POPP   <WR_DRETOFF,WR_DRETLEN,ES>
	POPP   <DI,BX,AX>
	RET
HANDLE_ERROR_CALL ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	 AX,input
;	 BX,action
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	HANDLE_PANEL_CALL
HANDLE_PANEL_CALL PROC	FAR
	PUSH	AX
	PUSH	AX
	PUSH	AX
	MOV	AX,PAN_INSTALL_DOS
	CALL	INIT_PQUEUE_CALL
	POP	AX
	CALL	PREPARE_PANEL_CALL
	POP	AX
	.IF < AX ne PAN_DSKCPY_CPY >
	   MOV	   AX,PAN_HBAR
	   CALL    PREPARE_PANEL_CALL
	   CALL    HANDLE_CHILDREN
	.ENDIF
	CALL	DISPLAY_PANEL_CALL
	POP	AX
	RET
HANDLE_PANEL_CALL ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	 AX,input
;	 BX,action
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	HANDLE_PANEL_CALL2
HANDLE_PANEL_CALL2 PROC  FAR
	PUSH	AX
	PUSH	AX
	MOV	AX,BX
	CALL	INIT_PQUEUE_CALL
	POP	AX
	CALL	PREPARE_PANEL_CALL
	POP	AX
	PUSH	AX
	.IF < AX ne SUB_COPYING >
	   MOV	   AX,PAN_HBAR
	   CALL    PREPARE_PANEL_CALL
	   CALL    HANDLE_CHILDREN
	.ENDIF
	CALL	DISPLAY_PANEL_CALL
	POP	AX
	RET
HANDLE_PANEL_CALL2 ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	 AX,input
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	HANDLE_PANEL_CALL3
HANDLE_PANEL_CALL3 PROC  FAR
	CALL	INIT_PQUEUE_CALL
	CALL	DISPLAY_PANEL_CALL
	RET
HANDLE_PANEL_CALL3 ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	 AX,input
;	 BX,action
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	HANDLE_KEYSTROKE
HANDLE_KEYSTROKE  PROC	FAR
	MOV	CX,FK_ENT_LEN
	LEA	DX,FK_ENT
	CALL	GET_FUNCTION_CALL
	RET
HANDLE_KEYSTROKE  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	End of program code
;
;;;;;;;;;;;;;;;;;;;;;;;;;
SELECT	ENDS
	END
