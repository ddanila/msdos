;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;
;
;
INCLUDE MAC_EQU.INC
INCLUDE PANEL.MAC
INCLUDE STRUC.INC
INCLUDE MACROS.INC
INCLUDE MACROS8.INC
INCLUDE VARSTRUC.INC
INCLUDE EXT.INC
INCLUDE PAN-LIST.INC
INCLUDE CASEXTRN.INC
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
					  ;
EXTRN HANDLE_PANEL_CALL2:FAR
EXTRN HANDLE_PANEL_CALL3:FAR
EXTRN FIND_FILE_ROUTINE:FAR
EXTRN DISPLAY_MESSAGE_ROUTINE:FAR
EXTRN BEEP_ROUTINE:FAR
					  ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DATA	SEGMENT BYTE PUBLIC 'DATA'
NULl_DEVICE		DB	  'nul',0
CON_DEVICE		DB	  'con',0
SUB_PROGRAM		DB	  0
EXEC_ERR		DB	  0
	PUBLIC DSKCPY_WHICH,DSKCPY_PAN1,DSKCPY_PAN2
	PUBLIC DSKCPY_PAN3,DSKCPY_OPTION,DSKCPY_SOURCE
DSKCPY_WHICH		DB	  0
;DSKCPY_TO_A_720 EQU	0		  ;AN000;DT (MACROS8.INC for actual equates)
;DSKCPY_TO_A_360 EQU	1
;DSKCPY_TO_B	 EQU	2

DSKCPY_OPTION		DB	  0
;SOURCE1	 EQU	0
;NO_SOURCE1	 EQU	1

DSKCPY_SOURCE		DW	  0	  ;AN000;DT offset of filename to check for on diskette
DSKCPY_PAN1		DW	  0
DSKCPY_PAN2		DW	  0
DSKCPY_PAN3		DW	  0

	PUBLIC DSKCPY_ERR
DSKCPY_ERR		DB	  0
;DSKCPY_EXIT	 EQU	1

DATA	       ENDS			  ;AN000; DATA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	EXTRN	CHK_W_PROTECT_FLAG:BYTE
	EXTRN	W_PROTECT_FLAG:BYTE
	EXTRN	EXIT_SELECT:FAR
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CODE_FAR    SEGMENT PARA PUBLIC 'CODE'  ;AN000; Segment for far routine
	ASSUME	CS:CODE_FAR,DS:DATA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; The critical error handler.  This routine should be placed in the CODE segment.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
OLD_STACK_SEG	DW	?
OLD_STACK_OFF	DW	?
						;GHG
	PUBLIC	INT_24_VECTOR
INT_24_VECTOR:

    PUSHH     <BX,CX,DX,SI,DI,ES,DS>
    MOV     AX,SEG DATA
    MOV     DS,AX
    MOV     ES,AX
						;
    MOV     AX,CS			      ;AN002;S;GHG
    CLI 				      ;AN002;S;GHG
    MOV     OLD_STACK_SEG,SS		      ;AN002;S;GHG
    MOV     OLD_STACK_OFF,SP		      ;AN002;S;GHG
    MOV     SS,AX			      ;AN002;S;GHG
    LEA     SP,NEW_STACK_START		      ;AN002;S;GHG
    STI 				      ;AN002;S;GHG
						;
    AND  DI, 0FFH				;AN000; Mask off the high byte
    .IF < CHK_W_PROTECT_FLAG EQ TRUE >		;AN000; Is this a check for write protect?
	 .IF < DI EQ 0 >			;AN000; Is this a write protect error?
	      MOV  W_PROTECT_FLAG, TRUE 	;AN000; If so, indicate to the calling program
	 .ENDIF
	 MOV  AL, 3				;AN000; Get DOS to trash this call
	 JMP  EXIT_THE_INT			;AN000; Exit the interrupt
    .ENDIF
						;
    .IF < DI eq 0 >
	  HANDLE_ERROR	     PAN_WRITE_PROT,2
	  MOV	AL,1
    .ELSEIF < DI eq 2 >
	  HANDLE_ERROR	     PAN_DRIVE_ERROR,2
	  MOV	AL,1
    .ELSE
	 .IF < SUB_PROGRAM EQ TRUE >
	      JMP  END_SUB_PROGRAM
	 .ENDIF
	 MOV  AL, 3				;AN000; Fail this system call
    .ENDIF
EXIT_THE_INT:
    MOV    SS,OLD_STACK_SEG		      ;AN002;S;GHG
    MOV    SP,OLD_STACK_OFF		      ;AN002;S;GHG
    POPP   <DS,ES,DI,SI,DX,CX,BX>
    IRET					;AN000; Return from the interrupt
						;
END_SUB_PROGRAM:
    MOV    SS,OLD_STACK_SEG		      ;AN002;S;GHG
    MOV    SP,OLD_STACK_OFF		      ;AN002;S;GHG
    POPP      <DS,ES,DI,SI,DX,CX,BX>
    ADD  SP, 6
						;
    MOV  AH, 4CH
    MOV  AL, 01
    DOSCALL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; The DISKCOPY INT 2F INTERFACE
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
						;
		EVEN
NEW_STACK	DW   200 DUP('S')
NEW_STACK_START DW	0
						;GHG
FIRST_CALL	DB	0
						;GHG
	PUBLIC	INT_2F_VECTOR
INT_2F_VECTOR:
	.IF < AX EQ 0ADC1H > near
						;GHG
	   PUSHH   <BX,CX,DX,SI,DI,ES,DS>
	   MOV	   AX,SEG DATA
	   MOV	   DS,AX
	   MOV	   ES,AX
						   ;GHG
	   MOV	   AX,CS		      ;AN001;S;GHG
	   CLI				      ;AN001;S;GHG
	   MOV	   OLD_STACK_SEG,SS	      ;AN001;S;GHG
	   MOV	   OLD_STACK_OFF,SP	      ;AN001;S;GHG
	   MOV	   SS,AX		      ;AN001;S;GHG
	   LEA	   SP,NEW_STACK_START	      ;AN001;S;GHG
	   STI				      ;AN001;S;GHG
						   ;GHG

	   .IF < DSKCPY_WHICH eq DSKCPY_TO_B > near
						   ;
	      .IF < BX EQ 9 > and
		.IF < DSKCPY_PAN1 ne NOPANEL >
		    .REPEAT
			MOV	  BX,PAN_INSTALL_DOS
			MOV	  AX,DSKCPY_PAN1
			CALL	  HANDLE_PANEL_CALL2
			CALL	  HANDLE_KEYSTROKE
			MOV  DI, DSKCPY_SOURCE
			MOV  CX, 0
			CALL FIND_FILE_ROUTINE
		       .LEAVE < nc >
			   MOV	   BX,ERR_DOS_DISK
			   CALL    INT2F_ERROR
		   .UNTIL
		    MOV       BX,PAN_INSTALL_DOS
		    MOV       AX,DSKCPY_PAN2
		    CALL      HANDLE_PANEL_CALL2
	      .ELSEIF <BX eq 13 >
		 MOV	 BX,PAN_DRIVE_ERROR
		 CALL	 INT2F_ERROR
						   ;
	      .ELSEIF <BX eq 14 >		   ;AN001;GHG  write protect
		 MOV	 BX,PAN_WRITE_PROT
		 CALL	 INT2F_ERROR
						   ;
	      .ELSEIF <BX eq 23 > or
	      .IF <BX eq 11 > or
	      .IF <BX eq 12 > or
	      .IF <BX eq 18 > or
	      .IF <BX eq 20 >
		 MOV	 BX,PAN_BAD_DISKET	   ;AN004;JW Bad diskette in b:
		 CALL	 INT2F_ERROR
		 MOV	 N_DSKCPY_ERR,E_DSKCPY_RETRY
						   ;
	      .ELSEIF <BX eq 16 >
		 MOV	   FIRST_CALL,0
	      .ELSEIF <BX ne  2 > and
	      .IF <BX ne  7 > and
	      .IF <BX ne  8 > and
	      .IF <BX ne  9 > and
	      .IF <BX ne 10 > and
	      .IF <BX ne 15 > and
	      .IF <BX ne 17 > and
	      .IF <BX ne 21 > and
	      .IF <BX ne 26 >
		 MOV	 BX,ERR_GENERAL
		 CALL	 INT2F_ERROR
	      .ENDIF
	      MOV    AX,0FFFFH

	   .ELSEIF < DSKCPY_WHICH eq DSKCPY_TO_A_360 > near
	      .IF < BX EQ 8 >
		  .IF < DSKCPY_OPTION eq SOURCE1 > or
		  .IF  <FIRST_CALL ne 0 >
		    .REPEAT
		       MOV	 BX,PAN_INSTALL_DOS
		       MOV	 AX,DSKCPY_PAN1
		       CALL	 HANDLE_PANEL_CALL2
		       CALL	 HANDLE_KEYSTROKE
			MOV  DI, DSKCPY_SOURCE
			MOV  CX, 0
			CALL FIND_FILE_ROUTINE
		       .LEAVE < nc >
			   MOV	   BX,ERR_DOS_DISK
			   CALL    INT2F_ERROR
		    .UNTIL
		    .ENDIF
		    MOV       BX,PAN_INSTALL_DOS
		    MOV       AX,DSKCPY_PAN2
		    CALL      HANDLE_PANEL_CALL2
		    MOV       FIRST_CALL,1
	      .ELSEIF <BX eq 9 >
		    MOV       BX,PAN_INSTALL_DOS
		    MOV       AX,DSKCPY_PAN3
		    CALL      HANDLE_PANEL_CALL2
		    CALL      HANDLE_KEYSTROKE
		    MOV       BX,PAN_INSTALL_DOS
		    MOV       AX,DSKCPY_PAN2
		    CALL      HANDLE_PANEL_CALL2
	      .ELSEIF <BX eq 13 >
		 MOV	 BX,PAN_DRIVE_ERROR
		 CALL	 INT2F_ERROR
						   ;
	      .ELSEIF <BX eq 14 >		   ;AN001;GHG  write protect
		 MOV	 BX,PAN_WRITE_PROT
		 CALL	 INT2F_ERROR
						   ;
	      .ELSEIF <BX eq 23 > or
	      .IF <BX eq 11 > or
	      .IF <BX eq 12 > or
	      .IF <BX eq 18 > or
	      .IF <BX eq 20 >
		 MOV	 BX,PAN_BAD_DISKET	   ;AN004;JW Bad diskette in b:
		 CALL	 INT2F_ERROR
		 MOV	 N_DSKCPY_ERR,E_DSKCPY_RETRY
						   ;
	      .ELSEIF <BX eq 16 >
		 MOV	   FIRST_CALL,0
	      .ELSEIF <BX ne  2 > and
	      .IF <BX ne  7 > and
	      .IF <BX ne 10 > and
	      .IF <BX ne 15 > and
	      .IF <BX ne 17 > and
	      .IF <BX ne 21 > and
	      .IF <BX ne 26 >
		 MOV	 BX,ERR_GENERAL
		 CALL	 INT2F_ERROR
	      .ENDIF
						   ;
	      MOV    AX,0FFFFH
	   .ELSE near
	      .IF < BX EQ 9 >
		    MOV       AX,PAN_DSKCPY_SRC
		    CALL      HANDLE_PANEL_CALL
		    CALL      HANDLE_KEYSTROKE
		    MOV       AX,PAN_DSKCPY_CPY
		    CALL      HANDLE_PANEL_CALL
	      .ELSEIF <BX eq 8 >
		 .IF  <FIRST_CALL ne 0 >
		    MOV       AX,PAN_DSKCPY_TAR
		    CALL      HANDLE_PANEL_CALL
		    CALL      HANDLE_KEYSTROKE
		 .ELSE
		    MOV       FIRST_CALL,1
		 .ENDIF
		 MOV	   AX,PAN_DSKCPY_CPY
		 CALL	   HANDLE_PANEL_CALL
	      .ELSEIF <BX eq 16 >
		 MOV	   AX,0FFFFH
		 MOV	   FIRST_CALL,0
		 JMP	   INT2F_1
	      .ELSEIF <BX eq 13 >		   ;AN000;DT   drive not ready
		 MOV	 BX,PAN_DRIVE_ERROR
		 CALL	 INT2F_ERROR
	      .ELSEIF <BX eq 14 >		   ;AN001;GHG  write protect
		 MOV	 BX,PAN_WRITE_PROT
		 CALL	 INT2F_ERROR
	      .ELSEIF <BX eq 23 > or
	      .IF <BX eq 11 > or
	      .IF <BX eq 12 > or
	      .IF <BX eq 18 > or
	      .IF <BX eq 20 >
		 MOV	 BX,PAN_BAD_DISKET	   ;AN004;JW Bad diskette in b:
		 CALL	 INT2F_ERROR
		 MOV	 N_DSKCPY_ERR,E_DSKCPY_RETRY
						   ;
	      .ELSEIF <BX ne  2 > and
	      .IF <BX ne  7 > and
	      .IF <BX ne 10 > and
	      .IF <BX ne 15 > and
	      .IF <BX ne 17 > and
	      .IF <BX ne 21 > and
	      .IF <BX ne 26 >
		 MOV	 BX,ERR_GENERAL
		 CALL	 INT2F_ERROR
	      .ENDIF
						   ;
	      MOV    AX,0FFFFH

	   .ENDIF

INT2F_1:      MOV    SS,OLD_STACK_SEG		   ;AN001;S;GHG
	      MOV    SP,OLD_STACK_OFF		   ;AN001;S;GHG

						   ;
	   POPP    <DS,ES,DI,SI,DX,CX,BX>
						   ;
						   ;
	   IRET
	.ELSE
	    JMP     CS:OLD_INT_2F
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;   The FORMAT INT2F interrupt routine
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	INT_2F_FORMAT
INT_2F_FORMAT:
	.IF < AX EQ 0ADC1H > near
	   PUSHH   <BX,CX,DX,SI,DI,ES,DS>
	   MOV	   AX,SEG DATA
	   MOV	   DS,AX
	   MOV	   ES,AX
	   MOV	   AX,CS
	   CLI
	   MOV	   OLD_STACK_SEG,SS
	   MOV	   OLD_STACK_OFF,SP
	   MOV	   SS,AX
	   LEA	   SP,NEW_STACK_START
	   STI
	   .IF < FORMAT_WHICH eq STARTUP >
	      MOV	AX,SUB_INS_STARTT_S360
	   .ELSE
	      MOV	AX,SUB_INS_SHELL_S360
	   .ENDIF
	   MOV	     BX,PAN_INST_PROMPT
	   CALL      HANDLE_PANEL_CALL2
	   CALL      HANDLE_KEYSTROKE
	   .IF < FORMAT_WHICH eq STARTUP >
	      MOV	AX,FORMAT_STARTUP
	   .ELSE
	      MOV	AX,FORMAT_SHELL
	   .ENDIF
	   CALL      HANDLE_PANEL_CALL3
	   MOV	  SS,OLD_STACK_SEG
	   MOV	  SP,OLD_STACK_OFF
	   POPP    <DS,ES,DI,SI,DX,CX,BX>
	   IRET
	.ELSE
	    JMP     CS:OLD_INT_2F
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; The DISKCOPY INT 2F ERROR ROUTINE
;
; Input: BX = error panel
;
; Output: none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
INT2F_ERROR	PROC  NEAR
	MOV	CX,2			;AN000;DT allow ESC and ENTER
	CALL	HANDLE_ERROR_CALL	;AN000;DT display error panel
	JNC	INT2F_ERROR_EXIT	;AN000;DT if ENTER pressed, then ok
					;AN000;DT else ESC
	MOV	DSKCPY_ERR,DSKCPY_EXIT	;AN000;DT indicate user wants to exit
	MOV	AX,4C01H		;AN000;DT and error message already up	DOS
	INT	21H			;AN000;DT exit with error
INT2F_ERROR_EXIT:
	RET
INT2F_ERROR	ENDP
					;;;;;;;;;;;;
						   ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; The DISKCOPY INT 2F INTERFACE (256KB DISKCOPY)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	PUBLIC	INT_2F_256KB
INT_2F_256KB:
	.IF < AX EQ 0ADC1H > near
	   PUSHH   <BX,CX,DX,SI,DI,ES,DS>
	   MOV	   AX,SEG DATA
	   MOV	   DS,AX
	   MOV	   ES,AX
	   MOV	   AX,CS
	   CLI
	   MOV	   OLD_STACK_SEG,SS
	   MOV	   OLD_STACK_OFF,SP
	   MOV	   SS,AX
	   LEA	   SP,NEW_STACK_START
	   STI
	      .IF < BX EQ 9 >
		    CLEAR_SCREEN
		    DISPLAY_MESSAGE  14 	   ;AN000;DT insert INSTALL
		    CALL HANDLE_KEY256KB
		    CLEAR_SCREEN
		    DISPLAY_MESSAGE  15 	   ;AN000;DT Copying diskettes
	      .ELSEIF <BX eq 8 >
		 .IF  <FIRST_CALL ne 0 >
		    CLEAR_SCREEN
		    DISPLAY_MESSAGE  13 	   ;AN000;DT insert INSTALL COPY
		    CALL HANDLE_KEY256KB
		 .ELSE
		    MOV       FIRST_CALL,1
		 .ENDIF
		 CLEAR_SCREEN
		 DISPLAY_MESSAGE  15		   ;AN000;DT Copying diskettes
	      .ELSEIF <BX eq 16 >
		 MOV	   AX,0FFFFH
		 MOV	   FIRST_CALL,0
		 JMP	   INT2F_1_ALT
	      .ELSEIF <BX eq 13 >
		 CLEAR_SCREEN
		 DISPLAY_MESSAGE  16		   ;AN000;DT Drive door open
		 CALL	 INT2F_ERRALT
	      .ELSEIF <BX eq 14 >
		 CLEAR_SCREEN
		 DISPLAY_MESSAGE  17		   ;AN000;DT Write Protect error
		 CALL	 INT2F_ERRALT
	      .ELSEIF <BX ne  2 > and
	      .IF <BX ne  7 > and
	      .IF <BX ne 10 > and
	      .IF <BX ne 15 > and
	      .IF <BX ne 17 > and
	      .IF <BX ne 21 > and
	      .IF <BX ne 26 >
		 CLEAR_SCREEN
		 DISPLAY_MESSAGE  18		   ;AN000;DT General error
		 CALL	 INT2F_ERRALT
	      .ENDIF
	      MOV    AX,0FFFFH
INT2F_1_ALT:  MOV    SS,OLD_STACK_SEG
	      MOV    SP,OLD_STACK_OFF
	   POPP    <DS,ES,DI,SI,DX,CX,BX>
	   IRET 				;;AN000;;DT
	.ELSE
	    JMP     CS:OLD_INT_2F
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; The DISKCOPY INT 2F ERROR ROUTINE (256KB)
;
; Input: BX = error panel
;
; Output: none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
INT2F_ERRALT	PROC  NEAR
INT2F_AGN:
	MOV	AH,0
	INT	16H			;AN000;DT get keystroke
	CMP	AL,13			;AN000;DT If ENTER the continue
	JE	INT2F_ERRALT_EXIT
	CMP	AL,27			;AN000;DT If not ESC the again
	JE	INT2F_ALT_ABORT
	DISPLAY_MESSAGE  11		;AN000;DT BEEP
	JMP	INT2F_AGN
INT2F_ALT_ABORT:			;AN000;DT else ESC
	MOV	DSKCPY_ERR,DSKCPY_EXIT	;AN000;DT indicate user wants to exit
	MOV	AX,4C01H		;AN000;DT and error message already up	DOS
	INT	21H			;AN000;DT exit with error
INT2F_ERRALT_EXIT:
	RET
INT2F_ERRALT	ENDP
					;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;   The INT23 interrupt routine   (CTRL-BREAK)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
	PUBLIC	INT_23_VECTOR		       ;AN074;SEH
INT_23_VECTOR:				       ;AN074;SEH
					       ;
	IRET				       ;AN074;SEH ignore ctrl-break and return
					       ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; The DISKCOPY GET KEY ROUTINE (256KB)
;
; Input: none
;
; Output: none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
HANDLE_KEY256KB PROC NEAR
HAKEY_AGN:
	MOV	AH,0
	INT	16H			;AN000;DT get keystroke
	CMP	AL,13			;AN000;DT If ENTER the continue
	JE	HAKEY_EXIT
	DISPLAY_MESSAGE  11		;AN000;DT BEEP
	JMP	HAKEY_AGN
HAKEY_EXIT:
	RET
HANDLE_KEY256KB ENDP

CODE_FAR    ENDS
	    END
