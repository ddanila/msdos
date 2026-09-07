	PAGE	,132
	TITLE	DOS GRAPHICS Command  -	Copy Shared Data
;; DOS - GRAPHICS Command
;; (C) Copyright 1988 Microsoft
;; File Name:  GRCPSD.ASM
;; ----------
;; Description:
;; ------------
;;	 This file contains the COPY_SHARED_DATA module.
;; Documentation Reference:
;; ------------------------
;;	 PLACID Functional Specifications
;;	 OASIS High Level Design
;;	 OASIS GRAPHICS I1 Overview
;; Procedures Contained in This File:
;; ----------------------------------
;;	 COPY_SHARED_DATA - Copy the Shared Data Area from temporary
;;			    build area to resident memory & exit to DOS
;; Include Files Required:
;; -----------------------
;;	 None
;; External Procedure References:
;; ------------------------------
;;	 None
;; Linkage Instructions:
;; ---------------------
;;	 Refer to GRAPHICS.ASM
CODE	SEGMENT PUBLIC 'CODE'          ;;
	ASSUME CS:CODE,DS:CODE	       ;;
	INCLUDE GRCTRL.EXT	       ;; Bring in external declarations
	INCLUDE GRCTRL.STR	       ;;  for transient command processing
;; Public Symbols
   PUBLIC COPY_SHARED_DATA	       ;;
;; Module Name:
;;   COPY_SHARED_DATA
;; Input Parameters:
;;   DS : SI - points to the Temporary Shared Data Area
;;   ES : DI - destination for resident Shared Data Area
;;   BP      - offset for new Shared Data Area (same as DI)
;;   AH    - Function code for exiting to DOS:
;;	     31H : Terminate & Stay Resident - if first time
;;	     4CH : Terminate - if already installed
;;   DX    - resident data segment size in paragraphs
;; Output Parameters:
;;   NONE
;; Data Structures Referenced:
;;   Control Variables
;; Description:
;;   Copy the Temporary Shared Data area over the installation modules
;;   and terminate (stay resident).  The data is copied immediately
;;   following this module.
;; Called By:
;;   GRAPHICS_INSTALL
;; External Calls:
;;   NONE
;; Logic:
;;   Copy Temporary Shared Data Area
;;   Set PRINT_SCREEN_ALLOWED to YES
;;   Exit to DOS (Function Code 31 or 4C setup by caller)
COPY_SHARED_DATA  PROC NEAR	       ;;
	REP	MOVSB		       ;; Copy Shared Data from temporary
				       ;;  build area to resident memory
				       ;; Allow print screens now
	MOV	ES:PRINT_SCREEN_ALLOWED,YES
	INT	21H		       ;; Exit
COPY_SHARED_DATA  ENDP		       ;;
CODE	ENDS
	END									;AN000; linked helper module, no program entry
