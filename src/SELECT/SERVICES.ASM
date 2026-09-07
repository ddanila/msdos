

PAGE	60,132
NAME	SERVICES
TITLE	SERVICES - DOS - SELECT.EXE
SUBTTL	services.asm
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	SERVICES.ASM:  Copyright 1988 Microsoft
;
;
	EXTRN	INC_KS:WORD
	EXTRN	IN_ICBID:WORD
	EXTRN	CRD_CCBVECOFF:WORD
	EXTRN	CRD_CCBVECSEG:WORD
	EXTRN	IN_CCBVECSEG:WORD
	EXTRN	IN_CCBVECOFF:WORD
	EXTRN	WR_HLPOPT:WORD
	EXTRN	WR_HLPROW:WORD
	EXTRN	WR_HCBCONT:WORD
	EXTRN	WR_SCBID:WORD
	EXTRN	WR_DRETLEN:WORD
	EXTRN	WR_DRETOFF:WORD
	EXTRN	WR_DRETSEG:WORD
	EXTRN	QM_ID:WORD
	EXTRN	QM_OPT1:WORD
	EXTRN	QM_ACTIVEPAN:WORD
	EXTRN	S_USER_STRING:WORD
	EXTRN	P_USER_STRING:BYTE
	EXTRN	I_USER_INDEX:WORD
	EXTRN	N_USER_FUNC:WORD
	EXTRN	WR_REFBUF:WORD
	EXTRN	WR_REFIELDCNT:WORD
	EXTRN	WR_REFID:WORD
	EXTRN	QM_OPT2:WORD
	EXTRN	WR_MAXREFID:ABS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SELECT	SEGMENT PARA PUBLIC 'SELECT'    ;AN000;segment for far routine
	ASSUME	CS:SELECT
					;
	INCLUDE MACROS.INC
	INCLUDE PCEQUATE.INC
	INCLUDE CASTRUC.INC
	INCLUDE CASVAR.INC
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	INIT_PQUEUE_CALL
;
; Entry:
;	AX = panel id
;
;
; Exit:
;	none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	EXTRN	PCDISPQ_CALL:NEAR
					;
	PUBLIC	INIT_PQUEUE_CALL
INIT_PQUEUE_CALL   PROC
	MOV	QM_OPT1,QM_CLSPAN	;AN000;clear parent panel queue
	OR	QM_OPT1,QM_CLSCHD	;AN000;clear parent panel queue
	CALL	PCDISPQ_CALL		;AN000;update display queue
	MOV	QM_ACTIVEPAN,AX 	;AN000;current active parent panel
	MOV	QM_OPT1,QM_PUSHPAN	;AN000;push parent panels
	OR	QM_OPT2,QM_BREAKON	;AN000;break on
	CALL	PREPARE_PANEL_CALL	;AN000;add panel to display queue
	MOV	WR_REFBUF,AX		;AN000;update the field refresh buffer!
	XOR	AX,AX
	MOV	WR_REFIELDCNT,AX
	MOV	QM_OPT2,AX		;AN000;set options back off...
	RET
INIT_PQUEUE_CALL   ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	AX=panel
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
					;
	PUBLIC	PREPARE_PANEL_CALL
PREPARE_PANEL_CALL  PROC
	PUSH	AX
	PUSH	BX
	MOV	BX,AX
	MOV	QM_ID,AX		;AN000;parent PCB number
	MOV	AX, 0ADC0H		;AN000; SELECT PANEL INTERFACE
	INT	2FH
	CALL	PCDISPQ_CALL		;AN000;update display queue
	POP	BX
	POP	AX
	RET
PREPARE_PANEL_CALL  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	AX=input
;	BX=index
;	CX=f_keys&_LEN
;	DX=offset f_keys
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
					;
	EXTRN	GET_SCB:NEAR
	EXTRN	ADJUST_UP:NEAR
	EXTRN	ADJUST_DOWN:NEAR
	EXTRN	GET_SCROLL_CALL:NEAR
	EXTRN	HANDLE_F3:NEAR
					;
	PUBLIC	EXEC_SCROLL_CALL
EXEC_SCROLL_CALL  PROC
	PUSH	ES
	MOV	WR_SCBID,AX		;AN000;get current scrolling field ID
					;
	MOV	WR_DRETLEN,CX		;AN000;get dynamic return string length
	MOV	WR_DRETOFF,DX
	MOV	CX,DS	      ;AN000;*********;get dynamic return string segment
	MOV	WR_DRETSEG,CX
					;
	PUSH	BX
	MOV	BX,WR_SCBID
	CALL	GET_SCB
	POP	BX
					;
	MOV	AX,BX			;AN000;initialize at list top
	PUSH	BX
	MOV	BX,WR_SCBID
	CALL	ADJUST_UP
	POP	BX
					;
ESC_0:	PUSH	ES:[DI]+SCB_OPT1
	PUSH	ES:[DI]+SCB_OPT2
	PUSH	ES:[DI]+SCB_OPT3
	PUSH	ES:[DI]+SCB_NUMLINE
					;
	CALL	GET_SCROLL_CALL 	;AN000;display and process scroll field
					;
	POP	ES:[DI]+SCB_NUMLINE	;AN000;GHG CAS BUG.............
	POP	ES:[DI]+SCB_OPT3
	POP	ES:[DI]+SCB_OPT2
	POP	ES:[DI]+SCB_OPT1
	MOV	AX,ES:[DI]+SCB_CURELE
					;
	CMP	ES:[DI]+SCB_KS,F3*256	;AN000;get last keystroke
	JNE	ESC_1
					;
	CALL	HANDLE_F3
	JNC	ESC_0
					;
ESC_1:	PUSH	BX
	MOV	BX,WR_SCBID
	CALL	ADJUST_DOWN
	POP	BX
	MOV	I_USER_INDEX,AX
					;
	MOV	AX,ES:[DI]+SCB_KS	;AN000;get last keystroke
	MOV	N_USER_FUNC,AX
	POP	ES
	RET
EXEC_SCROLL_CALL  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	AX=input
;	BX=index
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	EXTRN	PCSLCTP_CALL:NEAR
	EXTRN	GET_PCB:NEAR
					;
	PUBLIC	INIT_SCROLL_CALL
INIT_SCROLL_CALL  PROC
	PUSH ES
	MOV  WR_SCBID,AX		;AN000;get current scrolling field ID
					;
	PUSH BX
	MOV  BX,AX
	CALL GET_SCB
	POP  BX
					;
	MOV  AX,BX
	OR   AX,AX
	JNZ  ISC_0
	OR   ES:[DI]+SCB_OPT2,SCB_ROTN
					;
ISC_0:	PUSH	BX
	MOV	BX,WR_SCBID
	CALL ADJUST_UP
	POP	BX
	MOV	ES:[DI]+SCB_TOPELE,1	;AN000;intialize parameters
	MOV	ES:[DI]+SCB_CURELE,AX
	MOV	BX,QM_ACTIVEPAN 	;AN000;get the active panel number
	CALL	GET_PCB 		;AN000;ES:DI address of panel PCB
					;
	PUSH	ES:[DI]+PCB_UROW	;AN000;    ;get active panel row
	PUSH	ES:[DI]+PCB_UCOL	;AN000;    ;get active panel column
	PUSH	ES:[DI]+PCB_CCBID	;AN000;get active panel color index
					;
	MOV	BX,WR_SCBID		;AN000;get PCSLCTP field
	CALL	GET_SCB 		;AN000;ES:DI points to SCB
					;
	POP	ES:[DI]+SCB_CCBID	;AN000;get the panel's current color ind
	POP	ES:[DI]+SCB_RELCOL	;AN000;set the panel's relative column
	POP	ES:[DI]+SCB_RELROW	;AN000;set the panel's relative row
					;
	MOV	AX,SCROLLOBJID		;AN000; scroll_object type
	MOV	BX,WR_SCBID		;AN000; scroll_id
	CALL	ADD_REFRESH
	POP	ES
	RET
INIT_SCROLL_CALL  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	AX=input
;	BX=index
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	INIT_SCROLL_W_LIST_CALL
INIT_SCROLL_W_LIST_CALL  PROC
	PUSH	ES
	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	SI
	PUSH	DI
					;
	MOV  WR_SCBID,AX		;AN000;get current scrolling field ID
	MOV  BX,AX
	CALL GET_SCB
					;
	POP  ES:[DI]+SCB_OAPOFF
	POP  ES:[DI]+SCB_OAPSEG
	POP  ES:[DI]+SCB_OASLEN
	POP  ES:[DI]+SCB_NUMELE
	POP  ES:[DI]+SCB_WIDTH
					;
	PUSH ES:[DI]+SCB_OAPSEG
	POP  ES:[DI]+SCB_OASSEG
	POP  ES
	RET
INIT_SCROLL_W_LIST_CALL  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	AX=input
;	CX=num_ele
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	INIT_SCROLL_W_NUM_CALL
INIT_SCROLL_W_NUM_CALL	PROC
	PUSH	ES
	PUSH	AX			;AN000;save current scroll field ID
	MOV	BX,AX
	MOV	AX,CX			;AN000;initialize at list top
	CALL	ADJUST_UP
					;
	POP	BX			;AN000;restore scroll field ID
	PUSH	AX
	CALL	GET_SCB
	POP	ES:[DI]+SCB_NUMELE
	POP	ES
	RET
INIT_SCROLL_W_NUM_CALL	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	AX=input
;	BX=index
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	SET_SCROLL_COLOUR
SET_SCROLL_COLOUR  PROC
	PUSH	ES
	CALL	GET_SCB 		;AN000;ES:DI points to SCB
	MOV	ES:[DI]+SCB_CCBID,AX	;AN000;set the panel's current color ind
	POP	ES
	RET
SET_SCROLL_COLOUR  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	AX=input
;	BX=index
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
					;
	PUBLIC	SET_SCROLL_CALL
SET_SCROLL_CALL  PROC
	PUSH	ES
	MOV  WR_SCBID,AX		;AN000;get current scrolling field ID
					;
	PUSH BX
	MOV  BX,AX
	CALL GET_SCB
	POP  BX
					;
	PUSH ES:[DI]+SCB_OPT1
	PUSH ES:[DI]+SCB_OPT2
					;
	OR   ES:[DI]+SCB_OPT1,SCB_RD
	MOV  AX,BX
	OR   AX,AX
	JNZ  SSC_0
	OR   ES:[DI]+SCB_OPT2,SCB_ROTN
					;
SSC_0:	PUSH	BX
	MOV	BX,WR_SCBID
	CALL ADJUST_UP
	POP	BX
	MOV	ES:[DI]+SCB_TOPELE,1	;AN000;intialize parameters
	MOV	ES:[DI]+SCB_CURELE,AX
	MOV	BX,QM_ACTIVEPAN 	;AN000;get the active panel number
	CALL	GET_PCB 		;AN000;ES:DI address of panel PCB
					;
	PUSH	ES:[DI]+PCB_UROW	;AN000;    ;get active panel row
	PUSH	ES:[DI]+PCB_UCOL	;AN000;    ;get active panel column
	PUSH	ES:[DI]+PCB_CCBID	;AN000;get active panel color index
					;
	MOV	BX,WR_SCBID		;AN000;get PCSLCTP field
	CALL	GET_SCB 		;AN000;ES:DI points to SCB
					;
	POP	ES:[DI]+SCB_CCBID	;AN000;get the panel's current color ind
	POP	ES:[DI]+SCB_RELCOL	;AN000;set the panel's relative column
	POP	ES:[DI]+SCB_RELROW	;AN000;set the panel's relative row
	INC	ES:[DI]+SCB_CCBID	;AN000;INCREMENT COLOUR INDEX TO MAKE IT DIFFERENT **************
					;
	AND	ES:[DI]+SCB_OPT1,NOT SCB_UKS
	CALL	PCSLCTP_CALL		;AN000;display scroll field
					;
	POP	ES:[DI]+SCB_OPT2
	POP	ES:[DI]+SCB_OPT1
	POP	ES
	RET
SET_SCROLL_CALL ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;
;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	EXTRN	PCPANEL_CALL:NEAR
					;
	PUBLIC	DISPLAY_PANEL_CALL
DISPLAY_PANEL_CALL  PROC
	MOV	BX,0
	MOV	AX,0ADC0H
	INT	2FH
	XOR	AX,AX			;AN000;turn break option OFF
	CMP	WR_REFIELDCNT,0
	JE	DP_10
	INC	AX			;AN000;turn break option ON
DP_10:	CALL	PCPANEL_CALL		;AN000;display panel
	RET
DISPLAY_PANEL_CALL  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	EXTRN	GET_KEY:NEAR
					;
	PUBLIC	GET_FUNCTION_CALL
GET_FUNCTION_CALL  PROC
	MOV	WR_DRETLEN,CX		;AN000;get return string length
	MOV	AX,DX			;AN000;get return string offset
	MOV	WR_DRETOFF,AX
	MOV	AX,DS			;AN000;get return string segment
	MOV	WR_DRETSEG,AX
GFC_0:	CALL	GET_KEY
					;
	MOV	AX,INC_KS
	MOV	N_USER_FUNC,AX
					;GHG
	CMP	AX,F3*256
	JNE	GFC_1
					;GHG
	CALL	HANDLE_F3
	JNC	GFC_0
	MOV	N_USER_FUNC,F3*256	;AN003;GHG set last keystroke to exit!
					;
GFC_1:	RET
GET_FUNCTION_CALL  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	 AX,input
;	 BX,string
;	 CX,fkeys&_LEN
;	 DX,fkeys
;	 SI,field_length
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	EXTRN	CURSOROFF:NEAR
	EXTRN	GET_ICB:NEAR
	EXTRN	GET_INPUT_CALL:NEAR
					;
	PUBLIC	GET_STRING_CALL
GET_STRING_CALL PROC
	PUSH	ES
	CALL	CLEAR_USER_STRING
					;
	MOV	IN_ICBID,AX		;AN000; process input field x
					;
	PUSH	BX
	MOV	BX,AX
	CALL	GET_ICB
	POP	BX
					;
	MOV	WR_DRETLEN,CX		;AN000; SET RETURN KEYS
	MOV	WR_DRETOFF,DX
	MOV	AX,DS
	MOV	WR_DRETSEG,AX
					;
	MOV	ES:[DI]+ICB_WIDTH,SI
	MOV	AX,SI
	ADD	AX,ES:[DI]+ICB_COL
	CMP	AX,75
	JB	GSC_10
	MOV	AX,70
	SUB	AX,ES:[DI]+ICB_COL
	MOV	ES:[DI]+ICB_WIDTH,AX
GSC_10:
	MOV	ES:[DI]+ICB_FIELDLEN,SI ;AN000; size specified by si
	MOV	AX,[BX]
	MOV	ES:[DI]+ICB_DEFLEN,AX
	INC	AX
	MOV	ES:[DI]+ICB_CURCHAR,AX
	MOV	AX,BX
	INC	AX
	INC	AX
	MOV	ES:[DI]+ICB_DEFOFF,AX
	MOV	AX,DS
	MOV	ES:[DI]+ICB_DEFSEG,AX
					;
	LEA	AX,P_USER_STRING
	MOV	ES:[DI]+ICB_FIELDOFF,AX
	MOV	AX,DS
	MOV	ES:[DI]+ICB_FIELDSEG,AX
					;
	PUSH	CRD_CCBVECOFF
	PUSH	CRD_CCBVECSEG
	POP	IN_CCBVECSEG
	POP	IN_CCBVECOFF
					;
GSC_0:	CALL	GET_INPUT_CALL
	MOV	AX,ES:[DI]+ICB_KEYRET
	MOV	N_USER_FUNC,AX
					;
	CMP	AX,F3*256		;AN000;get last keystroke
	JNE	GSC_1
					;
	CALL	HANDLE_F3
	JNC	GSC_0
	MOV	N_USER_FUNC,F3*256	;AN000;set last keystroke to exit!
					;
GSC_1:;;AN000;MOV     AX,ES:[DI]+ICB_ENDBYTE  ;
					;
	MOV	ax,ES:[DI]+ICB_FIELDLEN ;AN000; size specified by si
	MOV	S_USER_STRING,AX
	call	unpad_user_string
					;
	CALL	CURSOROFF
	POP	ES
	RET
GET_STRING_CALL ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	 AX,input
;	 BX,string
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	INIT_STRING_CALL
INIT_STRING_CALL  PROC
	PUSH	ES
	CALL	CLEAR_USER_STRING
					;
	MOV	IN_ICBID,AX		;AN000; process input field x
					;
	PUSH	BX
	MOV	BX,AX
	CALL	GET_ICB
	POP	BX
					;
	MOV	ES:[DI]+ICB_WIDTH,SI
	MOV	AX,SI
	ADD	AX,ES:[DI]+ICB_COL
	CMP	AX,75
	JB	ISC_10
	MOV	AX,70
	SUB	AX,ES:[DI]+ICB_COL
	MOV	ES:[DI]+ICB_WIDTH,AX
					;
ISC_10: MOV	ES:[DI]+ICB_FIELDLEN,SI ;AN000; size specified by si
	MOV	AX,[BX] 		;AN000; SETUP TO DISPLAY DEFAULT STRING
	MOV	ES:[DI]+ICB_DEFLEN,AX
	INC	AX
	MOV	ES:[DI]+ICB_CURCHAR,AX
	MOV	AX,BX
	INC	AX
	INC	AX
	MOV	ES:[DI]+ICB_DEFOFF,AX
	MOV	AX,DS
	MOV	ES:[DI]+ICB_DEFSEG,AX
					;
	LEA	AX,P_USER_STRING	;AN000; SETUP RETURN STRING ADDRESS
	MOV	ES:[DI]+ICB_FIELDOFF,AX
	MOV	AX,DS
	MOV	ES:[DI]+ICB_FIELDSEG,AX
					;
	PUSH	CRD_CCBVECOFF
	PUSH	CRD_CCBVECSEG
	POP	IN_CCBVECSEG
	POP	IN_CCBVECOFF
					;
	MOV	AX,INPUTOBJID		;AN000; input_object type
	MOV	BX,IN_ICBID		;AN000; scroll_id
	CALL	ADD_REFRESH
	POP	ES
	RET
INIT_STRING_CALL  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	 AX,input
;	 BX,string
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ENTER_KEY	  DB	  13
ENTER_KEY_LEN	  EQU ($-ENTER_KEY)
					;
	PUBLIC	SET_STRING_CALL
SET_STRING_CALL PROC
	PUSH	ES
	CALL	CLEAR_USER_STRING
					;
	MOV	IN_ICBID,AX		;AN000; process input field x
					;
	PUSH	BX
	MOV	BX,AX
	CALL	GET_ICB
	POP	BX
					;
	MOV	ES:[DI]+ICB_WIDTH,SI
	MOV	AX,SI
	ADD	AX,ES:[DI]+ICB_COL
	CMP	AX,75
	JB	SSC_10
	MOV	AX,70
	SUB	AX,ES:[DI]+ICB_COL
	MOV	ES:[DI]+ICB_WIDTH,AX
					;
SSC_10: MOV	ES:[DI]+ICB_FIELDLEN,SI ;AN000; size specified by si
	MOV	AX,[BX] 		;AN000; SETUP TO DISPLAY DEFAULT STRING
	MOV	ES:[DI]+ICB_DEFLEN,AX
	INC	AX
	MOV	ES:[DI]+ICB_CURCHAR,AX
	MOV	AX,BX
	INC	AX
	INC	AX
	MOV	ES:[DI]+ICB_DEFOFF,AX
	MOV	AX,DS
	MOV	ES:[DI]+ICB_DEFSEG,AX
					;
	LEA	AX,P_USER_STRING	;AN000; SETUP RETURN STRING ADDRESS
	MOV	ES:[DI]+ICB_FIELDOFF,AX
	MOV	AX,DS
	MOV	ES:[DI]+ICB_FIELDSEG,AX
					;
	MOV	WR_DRETLEN,ENTER_KEY_LEN;AN000;  SET AUTO RETURN KEYS
	LEA	AX,ENTER_KEY
	MOV	WR_DRETOFF,AX
	MOV	AX,CS
	MOV	WR_DRETSEG,AX
					;
	PUSH	CRD_CCBVECOFF
	PUSH	CRD_CCBVECSEG
	POP	IN_CCBVECSEG
	POP	IN_CCBVECOFF
					;
	PUSH	ES:[DI]+ICB_OPT2
	OR	ES:[DI]+ICB_OPT2,ICB_UFK
	MOV	ES:[DI]+ICB_KEYRET,ENTER
					;
	CALL	GET_INPUT_CALL
					;
	POP	ES:[DI]+ICB_OPT2
					;
	CALL	CURSOROFF
	POP	ES
	RET
SET_STRING_CALL  ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	 AX,input
;	 SI,status_id
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	INIT_SCROLL_STATUS_CALL
INIT_SCROLL_STATUS_cALL   PROC
	PUSH	ES
	MOV	BX,AX
	CALL	GET_SCB
					;
	MOV	ES:[DI]+SCB_SELOFF,SI
	MOV	AX,DS
	MOV	ES:[DI]+SCB_SELSEG,AX
	POP	ES
	RET
INIT_SCROLL_STATUS_CALL   ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	BX,index
;	DX,table
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	EXTRN	PCMBEEP_CALL:NEAR
					;
	PUBLIC	TOGGLE_SUPPORT_CALL
TOGGLE_SUPPORT_CALL PROC
	PUSH	SI
	DEC	BX
	SHL	BX,1
	MOV	SI,DX
	MOV	AX,[SI+BX]
	CMP	AX,SCB_ACTIVEON
	JNE	TS_1
	MOV	AX,SCB_SELECTON
	MOV	[SI+BX],AX
	JMP	TS_4
					;
TS_1:	CMP	AX,SCB_SELECTON
	JNE	TS_3
	MOV	AX,SCB_ACTIVEON
	MOV	[SI+BX],AX
	JMP	TS_4
					;
TS_3:	CALL	PCMBEEP_CALL
TS_4:	POP	SI
	RET
TOGGLE_SUPPORT_CALL ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	UNPAD_USER_STRING
UNPAD_USER_STRING	PROC
	PUSH	SI
	PUSH	CX
	LEA	SI,P_USER_STRING
	MOV	CX,S_USER_STRING
	ADD	SI,CX
	DEC	SI
	MOV	AL,20H
					;
UUS_1:	CMP	[SI],AL
	JA	UUS_3
	DEC	SI
	LOOP	UUS_1
					;
UUS_3:	MOV	S_USER_STRING,CX
	POP	CX
	POP	SI
	RET
UNPAD_USER_STRING	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	CLEAR_USER_STRING
CLEAR_USER_STRING	PROC
	PUSH	SI
	PUSH	CX
	PUSH	AX
	LEA	SI,P_USER_STRING
	MOV	CX,110
	MOV	AL,20H
					;
CUS_1:	MOV	[SI],AL
	INC	SI
	LOOP	CUS_1
					;
	POP	AX
	POP	CX
	POP	SI
	RET
CLEAR_USER_STRING	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	BX,minimum
;	CX,maximum
;	AX=input
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	CHECK_MIN_MAX
CHECK_MIN_MAX	PROC
	CMP	AX,BX
	JB	CMM_3
	CMP	AX,CX
	JA	CMM_3
	CLC
	JMP	CMM_5
CMM_3:	CALL	PCMBEEP_CALL
	STC
CMM_5:	RET
CHECK_MIN_MAX	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;	MOV	AX,value
;	LEA	BX,P_USER_STRING
;	CALL	CONVERT_ASCII
;	MOV	S_USER_STRING,AX
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
TEN	DW	10
					;
	PUBLIC	CONVERT_ASCII
CONVERT_ASCII	PROC
	PUSH	BX
	PUSH	CX
	XOR	CX,CX
					;
	OR	AX,AX			;AN000;test if input value is 0
	JNE	CA_1
					;
	MOV	CX,1
	MOV	AX,1
	MOV	DX,'0'                  ;AN000;if input=0, then put '0' on stack
	PUSH	DX
	JMP	CA_6
					;
CA_1:	OR	AX,AX
	JE	CA_5
					;
	XOR	DX,DX
	DIV	TEN
	ADD	DX,'0'
	PUSH	DX
	INC	CX
	JMP	CA_1
					;
CA_5:	MOV	AX,CX
	OR	AX,AX
	JZ	CA_8
					;
CA_6:	POP	[BX]
	INC	BX
	LOOP	CA_6
					;
CA_8:	POP	CX
	POP	BX
	RET
CONVERT_ASCII	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	LEA	BX,P_USER_STRING
;	MOV	CX,S_USER_STRING
;	CALL	CONVERT_NUMERIC
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	CONVERT_NUMERIC
CONVERT_NUMERIC PROC
	PUSH	SI
	PUSH	CX
	PUSH	DX
	XOR	DX,DX
	XOR	AX,AX
					;
	OR	CX,CX
	JZ	CN_8
					;
CN_3:	MUL	TEN
	PUSH	CX
	MOV	CL,[BX]
	CMP	CL,'0'
	JB	CN_4
	CMP	CL,'9'
	JA	CN_4
	JMP	CN_5
CN_4:	MOV	CL,'0'
CN_5:	SUB	CL,'0'
	XOR	CH,CH
	ADD	AX,CX
	POP	CX
	INC	BX
	LOOP	CN_3
					;
CN_8:	POP	DX
	POP	CX
	POP	SI
	RET
CONVERT_NUMERIC ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	AX = OBJECT ID
;	BX = FIELD ID
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	ADD_REFRESH
ADD_REFRESH	PROC
	PUSH	SI
	LEA	SI,WR_REFID
	ADD	SI,WR_REFIELDCNT
	ADD	SI,WR_REFIELDCNT
	ADD	SI,WR_REFIELDCNT
	ADD	SI,WR_REFIELDCNT
	MOV	[SI],AX
	MOV	[SI+2],BX
	CMP	WR_REFIELDCNT,WR_MAXREFID
	JAE	AD_10
	INC	WR_REFIELDCNT
AD_10:	POP	SI
	RET
ADD_REFRESH	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	 AX,input
;	 DX,maximum DESTINATION buffer size
;	 SI,field_length
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	RETURN_STRING_CALL
RETURN_STRING_CALL PROC
	PUSHH  <ES,DI,DS,SI,BX,CX>
					;
	MOV	BX,AX
	CALL	GET_ICB
					;
	PUSH	ES:[DI]+ICB_DEFSEG
	MOV	CX,ES:[DI]+ICB_DEFLEN
	CMP	DX,CX			;AN000;check if DEFAULT string > buffer
	JAE	RS_10
	MOV	CX,DX			;AN000;only copy as much as possible
RS_10:	MOV	DI,ES:[DI]+ICB_DEFOFF
	POP	ES
					;
	PUSH	DS
	PUSH	SI
	PUSH	ES
	PUSH	DI
	POP	SI
	POP	DS
	POP	DI
	POP	ES
	CLD
	REP	MOVSB
					;
	POPP   <CX,BX,SI,DS,DI,ES>
	RET
RETURN_STRING_CALL ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	AX,row
;	BX,panid
;	CX,col
;	DL,character
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
PUBLIC	INIT_CHAR_CALL
INIT_CHAR_CALL	PROC
	PUSH DX
	CALL GET_PCB
	MUL  ES:[DI]+PCB_WIDTH
	ADD  AX,CX
	MOV  SI,ES:[DI]+PCB_EXPANDOFF
	ADD  SI,AX
	PUSH ES:[DI]+PCB_EXPANDSEG
	POP  ES
	POP  DX
	MOV  ES: BYTE PTR [SI],DL
	RET
INIT_CHAR_CALL	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
					;
					;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SELECT	ENDS
	END
