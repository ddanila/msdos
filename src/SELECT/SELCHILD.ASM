PAGE 55,132
NAME	SELCHILD
TITLE	SELCHILD - CHILD processing for SELECT.EXE
SUBTTL	selchild.asm
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	HANDLE_CHILDREN
;
; Entry:
;
;
;
; Exit:
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	EXTRN	QM_ID:WORD
	EXTRN	QM_OPT1:WORD
	EXTRN	QM_ACTIVEPAN:WORD
					;
SELECT	SEGMENT PARA PUBLIC 'SELECT'    ;AN000;segment for far routine
	ASSUME	CS:SELECT
					;
	EXTRN	GET_PCB:NEAR
	EXTRN	PCDISPQ_CALL:NEAR
					;
	INCLUDE PCEQUATE.INC
	INCLUDE CASTRUC.INC
	INCLUDE MACROS.INC
					;
	PUBLIC	HANDLE_CHILDREN
HANDLE_CHILDREN PROC
	PUSHH	<AX,BX,CX,DI,ES>
	MOV	QM_OPT1,QM_PUSHCHD	;AN000; push child panels
					;
	MOV	BX,QM_ACTIVEPAN
	CALL	GET_PCB 		;AN000; get panel control block
					; for active parent panel
	MOV	CX,ES:[DI]+PCB_CHILDNUM
	OR	CX,CX
	JZ	HC_1
					;
	PUSH	ES:[DI]+PCB_CHILDSEG	;AN000; get address of first child panel
	PUSH	ES:[DI]+PCB_CHILDOFF
	POP	DI
	POP	ES
					;
HC_0:	MOV	AX,ES:[DI]+CHD_PCB
	MOV	QM_ID,AX
	PUSHH	<ES,DI>
	CALL	PCDISPQ_CALL		;AN000; push next child on the stack
	POPP	<DI,ES>
					;
	ADD	DI,TYPE CHD_PB		;AN000; get next child control block
	LOOP	HC_0
					;
HC_1:	POPP	<ES,DI,CX,BX,AX>
	RET
HANDLE_CHILDREN ENDP
SELECT	ENDS
	END
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

