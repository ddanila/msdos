PAGE	,132
TITLE	PRINTER.SYS INT2FH Code

;****************** START OF SPECIFICATIONS **************************
;
;  MODULE NAME: PRTINT2F.ASM
;
;  DESCRIPTIVE NAME: PERFORM THE INT2FH FUNCTION OF PRINTER.SYS
;
;  FUNCTION: THE INT2FH FUNCTION OF PRINTER.SYS WILL LOCK THE PRINTER
;	     DEVICE AND LOAD THE CODE PAGE SPECIFIED.  WHEN AN UNLOCK
;	     IS ENCOUNTERED, THE SAVED CODE PAGE WILL BE ACTIVATED.
;	     ATTACHED.
;
;  ENTRY POINT: INT2F_COM
;
;  INPUT: AX = AD40H (CALL IDENTIFIER)
;	  BX = REQUESTED CODE PAGE (-1 FOR UNLOCK)
;	  DX = 0 - LPT1
;	       1 - LPT2
;	       2 - LPT3
;
;  AT EXIT:
;     NORMAL: CARRY CLEAR
;
;     ERROR: CARRY SET - CODE PAGE NOT AVAILABLE OR DEVICE IS NOT CPSW.
;
;  INTERNAL REFERENCES:
;
;     ROUTINES: CHECK_FOR_CP - CHECKS TO SEE IF CODE PAGE REQUESTED IS
;			       AVAILABLE ON DEVICE REQUESTED.
;		FIND_ACTIVE_CP - FINDS THE ACTIVE CODE PAGE ON SPECIFIED
;				 DEVICE; IF AVAILABLE.
;		LOCK_CP - VERIFIES, LOADS, AND LOCKS DEVICE CODE PAGE.
;		UNLOCK_CP - UNLOCKS DEVICE.
;
;     DATA AREAS: INVOKE_BLOCK - PARAMETER BLOCK PASSED TO INVOKE PROC.
;
;
;  EXTERNAL REFERENCES:
;
;     ROUTINES: INVOKE - ACTIVATES FONT REQUESTED.
;
;     DATA AREAS: BUF1 - BUFFER FOR LPT1
;		  BUF2 - BUFFER FOR LPT2
;		  BUF3 - BUFFER FOR LPT3
;
;  NOTES:
;
;      Label: "DOS PRINTER.SYS Device Driver"
;	      "Version 4.00 (C) Copyright 1988 Microsoft
;	      "Licensed Material - Program Property of Microsoft"
;
;****************** END OF SPECIFICATIONS ****************************

.XLIST
INCLUDE  STRUC.INC
.LIST


INCLUDE   CPSPEQU.INC
PRIV_LK_CP   EQU    0AD40H	       ; multiplex number and function
LPT1	     EQU    0		       ;
LPT2	     EQU    1		       ;
LPT3	     EQU    2		       ;
UNLOCK	     EQU    -1		       ; unlock the device
UNDEFINED    EQU    -1		       ; undefined code page
NOT_CY	     EQU    0FFFEH	       ; clear the carry in flag register
CY	     EQU    1		       ; set the carry in flag register
FOUND	     EQU    1		       ; search flag
NOT_FOUND    EQU    0		       ;


PUBLIC	INT2F_COM
PUBLIC	ROM_INT2F
PUBLIC	ABORT


CSEG	SEGMENT PARA PUBLIC 'CODE'
	ASSUME CS:CSEG


EXTRN	INVOKE:NEAR
EXTRN	BUF0:BYTE
EXTRN	BUF1:BYTE
EXTRN	BUF2:BYTE
EXTRN	BUF3:BYTE

ROM_INT2F    DW     ?		       ; chaining point for INT2FH
	     DW     ?

COPY_BUF0    DW     0
PREV_LOCK    DB     OFF

INVOKE_BLOCK LABEL  BYTE	       ; parameter block passed to INVOKE
	     DB     3 DUP(0)	       ;
RET_STAT     DW     0		       ; returned status from INVOKE
	     DQ     0		       ;
	     DB     6 DUP(0)	       ;
	     DW     OFFSET PARA_BLOCK  ;
CODE_SEGB    DW     SEG CSEG	       ;
				       ;
PARA_BLOCK   LABEL  WORD	       ;
	     DW     TWO 	       ;
REQ_CP	     DW     ?		       ; requested code page to load
				       ;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: INT2F_COM
;
; FUNCTION:
; THIS IS THE INTERRUPT 2FH HANDLER TO CAPTURE THE FOLLOWING FUNCTIONS:
;
;   AX=AD40H PRIVELEGED LOCK CP SWITCHING
;
; AT ENTRY: AX = AD40H
;	    BX = CODEPAGE REQUESTED DURING LOCK.
;		 -1 = UNLOCK
;	    DX = 0 - LPT1
;		 1 - LPT2
;		 2 - LPT3
;
;
; AT EXIT:
;    NORMAL: CARRY CLEAR - DEVICE LOADED AND LOCKED
;
;    ERROR: CARRY SET - CODE PAGE NOT AVAILABLE OR DEVICE NOT CPSW.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


INT2F_COM  PROC   NEAR
	   STI
	   .IF <AX NE PRIV_LK_CP>		; is this for PRINTER?
	     JMP    DWORD PTR CS:ROM_INT2F	; no....jump to old INT2F
	   .ENDIF				;
	   PUSH   AX				;
	   PUSH   BP				;
	   PUSH   BX				; s    r
	   PUSH   CX				;  a	e
	   PUSH   DX				;   v	 g
	   PUSH   DI				;    e	  s
	   PUSH   SI				;
	   PUSH   DS				;
	   PUSH   ES				;
	   MOV	  CS:COPY_BUF0,ZERO		;
	   MOV	  CS:CODE_SEGB,CS		;
	   MOV	  BP,BX 			; move req. cp to bp
	   .SELECT				; depending on the lptx..
	   .WHEN <DX EQ LPT1>			; point to the appropriate
	     LEA   BX,BUF1			; buffer..
	     LEA   SI,BUF0			;
	     MOV   CS:COPY_BUF0,SI		;
	   .WHEN <DX EQ LPT2>			;
	     LEA   BX,BUF2			;
	   .WHEN <DX EQ LPT3>			;
	     LEA   BX,BUF3			;
	   .OTHERWISE				;
	     STC				; not a valid lptx..set flag
	   .ENDSELECT				;
	   .IF NC				; process
	     .IF <BP EQ UNLOCK> 		; if unlock requested
	       CALL   UNLOCK_CP 		; unlock code page.
	     .ELSE				; must be a lock request..
	       CALL   LOCK_CP			;
	     .ENDIF				;
	   .ENDIF				;
	   MOV	  SI,CS:COPY_BUF0		;
	   PUSHF				;
	   .IF <SI NE ZERO>			; if this is lpt1...
	     MOV    AX,CS:[BX].STATE		; copy data into prn
	     MOV    CS:[SI].STATE,AX		; buffer as well.
	     MOV    AX,CS:[BX].SAVED_CP 	;
	     MOV    CS:[SI].SAVED_CP,AX 	;
	   .ENDIF				;
	   POPF 				;
	   POP	  ES				;
	   POP	  DS				; restore
	   POP	  SI				;
	   POP	  DI				;    registers
	   POP	  DX				;
	   POP	  CX				;
	   POP	  BX				;
	   MOV	  BP,SP 			;
	   MOV	  AX,[BP+8]			; load flag onto..
	   .IF NC				;
	     AND    AX,NOT_CY			;
	   .ELSE				;    stack flags
	     OR     AX,CY			;
	   .ENDIF				;
	   MOV	  [BP+8],AX			;
	   POP	  BP				;
	   POP	  AX				;
	   XCHG   AH,AL 			; exchange ah and al to show that..
ABORT:	   IRET 				; printer.sys is present.
INT2F_COM  ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: UNLOCK_CP
;
; FUNCTION:
; THIS FUNCTION UNLOCKS THE DEVICE THAT IS LOCKED.
;
; AT ENTRY:
;	    BX - POINTS TO LPTx BUFFER
;
;
; AT EXIT:
;    NORMAL: CARRY CLEAR - DEVICE UNLOCKED.
;
;    ERROR: CARRY SET - ERROR DURING UNLOCK, ACTIVE CODE PAGE SET TO INACTIVE
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

UNLOCK_CP      PROC  NEAR
	       .IF <CS:[BX].STATE EQ LOCKED> NEAR ; is device locked?
		 MOV   CS:[BX].STATE,CPSW	  ; change status to unlocked..
		 MOV   BP,CS:[BX].SAVED_CP	  ; get saved code page
		 .IF <BP NE UNDEFINED>		  ; valid?.....
		   XOR	  AX,AX 		  ;
		   CALL   FIND_ACTIVE_CP	  ; find the active code page.
		   .IF <BP NE DX>		  ; are they the same..?
		     MOV    CS:REQ_CP,BP	  ; no...invoke the saved code page
		     PUSH   CS			  ;
		     POP    ES			  ;
		     LEA    DI,INVOKE_BLOCK	  ;
		     MOV    CS:[BX].RH_PTRO,DI	  ;
		     MOV    CS:[BX].RH_PTRS,ES	  ;
		     CALL   INVOKE		  ;
		     .IF <AL NE ZERO>		  ; error on invoke?
		       MOV    AX,ONE		  ; yes...change the active..
		       CALL   FIND_ACTIVE_CP	  ; to inactive.
		       .IF <CS:COPY_BUF0 NE ZERO> ; do likewise to PRN if this
			 PUSH	 BX		  ; is lpt1.
			 MOV	 BX,CS:COPY_BUF0  ;
			 CALL	 FIND_ACTIVE_CP   ;
			 POP	 BX		  ;
		       .ENDIF			  ;
		       STC			  ; set error flag.
		     .ELSE			  ;
		       CLC			  ; invoke ok...clear error flag
		     .ENDIF			  ;
		   .ELSE			  ;
		     CLC			  ; active = saved ..no invoke...
		   .ENDIF			  ; clear error
		 .ELSE				  ;
		   MOV	  AX,ONE		  ; saved cp was inactive...change..
		   CALL   FIND_ACTIVE_CP	  ; active to inactive.
		   .IF <CS:COPY_BUF0 NE ZERO>	  ; do likewise to PRN if this
		     PUSH    BX 		  ; is lpt1.
		     MOV     BX,CS:COPY_BUF0	  ;
		     CALL    FIND_ACTIVE_CP	  ;
		     POP     BX 		  ;
		   .ENDIF			  ;
		   CLC				  ;
		 .ENDIF 			  ;
		 MOV	CS:[BX].SAVED_CP,UNDEFINED; reset the saved cp
	       .ENDIF				  ;
	       RET
UNLOCK_CP      ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: LOCK_CP
;
; FUNCTION:
; THIS FUNCTION LOCKS THE DEVICE WITH THE CODE PAGE REQUESTED.
;
; AT ENTRY: BP - REQUESTED CODE PAGE
;	    BX - POINTS TO LPTx BUFFER
;
;
; AT EXIT:
;    NORMAL: CARRY CLEAR - DEVICE LOCKED.
;
;    ERROR: CARRY SET - ERROR, CODE PAGE NOT LOCKED.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

LOCK_CP        PROC   NEAR
	       .IF <CS:[BX].STATE EQ LOCKED>	; if this was previously locked..
		 MOV	CS:PREV_LOCK,ON 	; then...set flag and...
		 MOV	CS:[BX].STATE,CPSW	; change to unlock for this proc
	       .ELSEIF <CS:[BX].STATE EQ CPSW>	; if this is unlocked...
		 MOV	CS:PREV_LOCK,OFF	; then set flag off.
	       .ELSE				;
		 STC				; neither...set error
	       .ENDIF				;
	       .IF NC				;
		 CALL	CHECK_FOR_CP		; yes..see if req cp is available.
		 .IF NC 			; yes...
		   XOR	   AX,AX		;
		   CALL    FIND_ACTIVE_CP	; find the active code page
		   .IF <BP NE DX>		; is it the same as requested?..
		     MOV    CS:REQ_CP,BP	; no..invoke the requested cp
		     PUSH   CS			;
		     POP    ES			;
		     LEA    DI,INVOKE_BLOCK	;
		     MOV    CS:[BX].RH_PTRO,DI	;
		     MOV    CS:[BX].RH_PTRS,ES	;
		     PUSH   DX			;
		     CALL   INVOKE		;
		     POP    DX			;
		     .IF <AL NE ZERO>		; error on invoke?
		       STC			; yes...set error flag.
		     .ELSE			;
		       MOV    CS:[BX].STATE,LOCKED ; no, 'lock' the printer device
		       .IF <CS:PREV_LOCK EQ OFF> ; if we were not locked..
			 MOV	CS:[BX].SAVED_CP,DX ; and..save the old code page.
		       .ENDIF			;
		       CLC			; clear error flag.
		     .ENDIF			;
		   .ELSE			;
		     MOV    CS:[BX].STATE,LOCKED ; 'lock' the printer device
		     .IF <CS:PREV_LOCK EQ OFF>	; if we were not locked..
		       MOV    CS:[BX].SAVED_CP,DX ; and..save the old code page.
		     .ENDIF			;
		     CLC			; clear the error flag
		   .ENDIF			;
		 .ENDIF 			;
	       .ENDIF				;
	       RET
LOCK_CP        ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: CHECK_FOR_CP
;
; FUNCTION:
; THIS FUNCTION SEARCHES FOR THE CODE PAGE REQUESTED TO SEE IF IT HAS
; BEEN PREPARED OR IS A HARDWARE CODE PAGE
;
;
; AT ENTRY: BP = CODE PAGE REQUESTED
;	    BX - POINTS TO LPTx BUFFER
;
;
; AT EXIT:
;    NORMAL: CARRY CLEAR - CODE PAGE IS VALID.
;
;    ERROR: CARRY SET - CODE PAGE NOT AVAILABLE.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


CHECK_FOR_CP  PROC   NEAR
	      PUSH   DX
	      MOV    DX,NOT_FOUND		; initialize flag
	      MOV    CX,CS:[BX].RSLMX		; load number of RAM slots
	      MOV    DI,CS:[BX].RAMSO		; load DI with table offset
	      .WHILE <DX EQ NOT_FOUND> AND	; whil not found and....
	      .WHILE <CX NE ZERO>		; while  still slots to check..
		.IF <CS:[DI].SLT_CP EQ BP>	; is it this one??
		  MOV	 DX,FOUND		; yes....set flag
		.ELSE				;
		  ADD	 DI,TYPE SLTS		; no..point to next entry
		  DEC	 CX			; decrement the count
		.ENDIF				;
	      .ENDWHILE 			;
	      .IF <DX EQ NOT_FOUND>		; if we didn't find it then..
		MOV    CX,CS:[BX].HSLMX 	; check hardware
		MOV    DI,CS:[BX].HARDSO	; load regs as before.
		.WHILE <DX EQ NOT_FOUND> AND	; while not found and..
		.WHILE <CX NE ZERO>		; still have slots to check..
		  .IF <CS:[DI].SLT_CP EQ BP>	; is it this one?
		    MOV    DX,FOUND		; yes...set flag.
		  .ELSE 			;
		    ADD    DI,TYPE SLTS 	; no ..point to next entry
		    DEC    CX			; and decrement count.
		  .ENDIF			;
		.ENDWHILE			;
	      .ENDIF				;
	      .IF <DX EQ NOT_FOUND>		;
		STC				; set flag appropriately
	      .ELSE				;
		CLC				;
	      .ENDIF				;
	      POP    DX 			;
	      RET				;
CHECK_FOR_CP  ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; PROCEDURE_NAME: FIND_ACTIVE_CP
;
; FUNCTION:
; THIS FUNCTION SEARCHES FOR THE ACTIVE CODE PAGE. IF REQUESTED, THE
; CODE PAGE IS MADE INACTIVE.
;
;
; AT ENTRY:
;	    BX - POINTS TO LPTx BUFFER
;	    AX = 0 - LEAVE AS ACTIVE
;	    AX = 1 - DE-ACTIVATE
;
;
; AT EXIT:
;    NORMAL: DX - ACTIVE CODE PAGE.  (NO ACTIVE = -1)
;
;    ERROR: N/A
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


FIND_ACTIVE_CP PROC   NEAR
	       MOV    DX,UNDEFINED		 ; initialize register
	       MOV    CX,CS:[BX].RSLMX		 ; load number of RAM slots
	       MOV    DI,CS:[BX].RAMSO		 ; load DI with table offset
	       .WHILE <DX EQ UNDEFINED> AND	 ; whil not found and....
	       .WHILE <CX NE ZERO>		 ; while still slots to check..
		 .IF <BIT CS:[DI].SLT_AT AND AT_ACT> ; is it this one??
		   MOV	  DX,CS:[DI].SLT_CP	 ; yes....load value
		   .IF <AX EQ ONE>		 ; is deactivate requested?
		     MOV    CS:[DI].SLT_AT,AT_OCC; yes...change attrib. to occupied
		   .ENDIF			 ;
		 .ELSE				 ;
		   ADD	  DI,TYPE SLTS		 ; no..point to next entry
		   DEC	  CX			 ; decrement the count
		 .ENDIF 			 ;
	       .ENDWHILE			 ;
	       .IF <DX EQ UNDEFINED>		 ; if we didn't find it then..
		 MOV	CX,CS:[BX].HSLMX	 ; check hardware
		 MOV	DI,CS:[BX].HARDSO	 ; load regs as before.
		 .WHILE <DX EQ UNDEFINED> AND	 ; while not found and..
		 .WHILE <CX NE ZERO>		 ; still have slots to check..
		   .IF <BIT CS:[DI].SLT_AT AND AT_ACT> ; is it this one??
		     MOV    DX,CS:[DI].SLT_CP	 ; yes....load value
		     .IF <AX EQ ONE>		 ; is deactivate requested?
		       MOV    CS:[DI].SLT_AT,AT_OCC; yes...change attrib to occupied
		     .ENDIF			 ;
		   .ELSE			 ;
		     ADD    DI,TYPE SLTS	 ; no ..point to next entry
		     DEC    CX			 ; and decrement count.
		   .ENDIF			 ;
		 .ENDWHILE			 ;
	       .ENDIF				 ;
	       RET				 ;
FIND_ACTIVE_CP ENDP

CSEG	   ENDS
	   END
