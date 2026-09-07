

PAGE 55,132
NAME	SELSERV
TITLE	SELSERV - SELECT Services
SUBTTL	selserv.asm
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	ADJUST_CURELE
;
;
; Entry:
;	AX = index on entry
;
; Exit:
;	AX = adjusted index
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SELECT	SEGMENT PARA PUBLIC 'SELECT'    ;AN000;segment for far routine
	ASSUME	CS:SELECT
					;
	EXTRN	WR_SCBID:WORD
					;
SCROLL_ADJUST	LABEL	BYTE
	DB	1		 ;AN000;SCR_DOS_SUPPORT
	DB	1		 ;AN000;SCR_CTY_KYB
	DB	0		 ;AN000;SCR_CTY_1
	DB	0		 ;AN000;SCR_CTY_2
	DB	0		 ;AN000;SCR_KYB_1
	DB	0		 ;AN000;SCR_KYB_2
	DB	1		 ;AN000;SCR_FR_KYB
	DB	1		 ;AN000;SCR_IT_KYB
	DB	1		 ;AN000;SCR_UK_KYB
	DB	1		 ;AN000;SCR_DEST_DRIVE
	DB	0		 ;AN000;SCR_PRT_TYPE
	DB	1		 ;AN000;SCR_PARALLEL
	DB	0		 ;AN000;SCR_SERIAL
	DB	0		 ;AN000;SCR_PRT_REDIR
	DB	1		 ;AN000;SCR_REVIEW
	DB	0		 ;AN000;SCR_FUNC_DISK
	DB	0		 ;AN000;SCR_FUNC_DISKET
	DB	1		 ;AN000;SCR_FIXED_FIRST
	DB	1		 ;AN000;SCR_FIXED_BOTH
	DB	1		 ;AN000;SCR_FORMAT
	DB	0		 ;AC000;SCR_CONTEXT_HLP / SCR_INDEX_HLP JW
	DB	0		 ;AN000;SCR_TITLE_HLP
	DB	0		 ;AN000;SCR_ACC_CTY   JW
	DB	0		 ;AN000;SCR_ACC_KYB   JW
	DB	0		 ;AN000;SCR_ACC_PRT   JW
	DB	1		 ;AC035;SCR_COPY_DEST SEH
	DB	0		 ;AN035;SCR_DEST_A_C; SEH
	DB	1		 ;mrw  ;scr_choose_shell
SCROLL_ADJUST_LEN  EQU	($-SCROLL_ADJUST)
ADJUST_ON	EQU	1
ADJUST_OFF	EQU	0
					;
	PUBLIC	ADJUST_UP,ADJUST_DOWN
					;
ADJUST_UP	PROC
	PUSH	BX
	PUSH	CX
	OR	AX,AX
	JZ	AC_1
					;
	MOV	CL,ADJUST_ON
	CMP	CS:[BX-1]+SCROLL_ADJUST,CL
	JNE	AC_1
					;
	SHL	AX,1
	DEC	AX
AC_1:	POP	CX
	POP	BX
	RET
ADJUST_UP	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	ADJUST_INDEX
;
;	AX = index on entry
;
;	AX = adjusted index
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ADJUST_DOWN	PROC
	PUSH	BX
	PUSH	CX
	OR	AX,AX
	JZ	AI_1
					;
	MOV	CL,ADJUST_ON
	CMP	CS:[BX-1]+SCROLL_ADJUST,CL
	JNE	AC_1
					;
	SHR	AX,1
	INC	AX
AI_1:	POP	CX
	POP	BX
	RET
ADJUST_DOWN	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SELECT	ENDS
	END
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
