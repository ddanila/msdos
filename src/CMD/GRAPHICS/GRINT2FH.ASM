	PAGE	,132
	TITLE	DOS - GRAPHICS Command  -	Interrupt 2FH Driver
;; DOS - GRAPHICS Command
;; (C) Copyright 1988 Microsoft
;; File Name:  GRINT2FH.ASM
;; ----------
;; Description:
;; ------------
;;	 This file contains the Interrupt 2FH driver.
;; Documentation Reference:
;; ------------------------
;;	 OASIS High Level Design
;;	 OASIS GRAPHICS I1 Overview
;; Procedures Contained in This File:
;; ----------------------------------
;;	 INT_2FH_DRIVER - Interrupt 2FH driver
;; Include Files Required:
;; -----------------------
;;	 GRLOAD.EXT - Externals for profile load
;;	 GRCTRL.EXT - Externals for print screen control
;;	 GRPRINT.EXT - Externals for print modules
;;	 GRCPSD.EXT - Externals for COPY_SHARED_DATA module
;; External Procedure References:
;; ------------------------------
;;	 Calls next Int 2FH handler in the chain.
;; Linkage Instructions:
;; --------------------
;;	 Refer to GRAPHICS.ASM
CODE	SEGMENT PUBLIC 'CODE'          ;;
	ASSUME	CS:CODE,DS:CODE        ;;
	PUBLIC	OLD_INT_2FH	       ;;
	PUBLIC	INT_2FH_DRIVER	       ;;
	PUBLIC	PRT_SCR_2FH_NUMBER     ;;
	PUBLIC	RESIDENT_CODE_SEG      ;;
	PUBLIC	SHARED_DATA_AREA_PTR   ;;
.XLIST
INCLUDE STRUC.INC
INCLUDE GRINST.EXT
INCLUDE GRCTRL.EXT
INCLUDE GRCPSD.EXT
.LIST
;; Module: INT_2FH_DRIVER
;; Description:
;;     Respond to GRAPHICS Int 2FH calls.
;;     The following calls are handled:
;;	AL = 0 ù Install Check
;; Invoked By:
;;     INT 2FH instruction.
;; Modules Called:
;;     Lower level INT 2FH handlers.
;; Input Registers:
;;     Install Check - AH=15H  AL=0
;; Output Registers:
;;     Install Check:  IF GRAPHICS installed
;;			  AH=FFH  AL=FFH
;;			  ES : DI points to Shared Data Area
;;		       ELSE
;;			  AH=15H  AL=0
;; Logic:
;;     IF AH=15H THEN
;;	  IF AL=0 THEN
;;	     AH,AL := -1
;;	     ES : DI := SHARED_DATA_AREA_PTR
;;	  ENDIF
;;	  IRET
;;     ELSE
;;	  IF OLD_INT_2FH is a valid pointer THEN
;;	      Jump to Old Int 2FH
;;	  ELSE
;;	      IRET
;;	  ENDIF
;;     ENDIF
INT_2FH_DRIVER	PROC  NEAR
	JMP	INT_2FH
PRT_SCR_2FH_NUMBER EQU		15H	; 2FH Multiplex interrupt number
					;  assigned to Print Screen.
OLD_INT_2FH	DD    ? 		; Pointer to next 2FH interrupt handler
RESIDENT_CODE_SEG	DW   ?	; Segment for installed stuff
SHARED_DATA_AREA_PTR	DW   ?	; Offset of the start of the
				;  Shared Data Area
INT_2FH:
;-------------------------------------------------------------------------------
; Verify if the 2FH Interrupt call is for our interrupt handler:
;-------------------------------------------------------------------------------
       .IF <AH EQ PRT_SCR_2FH_NUMBER> AND;If 2FH call is for us
       .IF <ZERO AL>			;  and request is "Get install state"
       .THEN				; then,
;-------------------------------------------------------------------------------
; Yes: return results
;-------------------------------------------------------------------------------
	MOV	DI,CS:SHARED_DATA_AREA_PTR ;  ES:DI :=	Pointer to shared
	PUSH	CS:RESIDENT_CODE_SEG	   ;		 data area
	POP	ES			;
	MOV	AH,0FFH 		; AL and AH := "We are installed"
	MOV	AL,AH			;
	IRET				; Return to interrupted process
;-------------------------------------------------------------------------------
; No, pass control to next 2FH interrupt handler:
;-------------------------------------------------------------------------------
       .ELSE				; else, this call is not for us:
	 .IF <<WORD PTR CS:OLD_INT_2FH> NE 0> AND ;if there is another
	 .IF <<WORD PTR CS:OLD_INT_2FH+2> NE 0> ;  2FH driver
	 .THEN				;	below us then,
	    JMP CS:OLD_INT_2FH		;	  pass control to it
	 .ELSE				;	else, there is nobody to pass
	    IRET			;	  control to, just return.
	 .ENDIF 			;     END If there is a driver below us.
      .ENDIF				;  END If this call is for us.
INT_2FH_DRIVER	ENDP
CODE   ENDS
       END
