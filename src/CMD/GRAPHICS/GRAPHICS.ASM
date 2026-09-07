	PAGE	,132
	TITLE	DOS GRAPHICS Command  -	Command Entry Point
;; MS DOS GRAPHICS Command
;; (C) Copyright 1988 Microsoft
;; File Name:  GRAPHICS.ASM
;; ----------
;; Description:
;; ------------
;;	 This file contains the GRAPHICS command entry point.
;;	 A jump is made to the GRAPHICS_INSTALL procedure
;;	 in file GRINST.ASM to begin installation processing.
;; Documentation Reference:
;; ------------------------
;;	 OASIS High Level Design
;;	 OASIS GRAPHICS I1 Overview
;; Procedures Contained in This File:
;; ----------------------------------
;;	 None
;; Include Files Required:
;; -----------------------
;;	 GRINST.EXT - Externals for GRINST.ASM
;; External Procedure References:
;; ------------------------------
;;	 FROM FILE  GRINST.ASM:
;;	      GRAPHICS_INSTALL - Main module for installation.
;; Linkage Instructions:
;; --------------------
;;	 LINK GRAPHICS GRINT2FH GRPATTRN GRCTRL GRCPSD GRCOLPRT GRBWPRT
;;	      GRINST GRPARSE grparms GRLOAD GRLOAD2 GRLOAD3;
;;	 EXE2BIN GRAPHICS.EXE GRAPHICS.COM
CODE	SEGMENT PUBLIC 'CODE'          ;;
	ASSUME	CS:CODE,DS:CODE        ;;
	ORG   100H		       ;; required for .COM
	INCLUDE GRINST.EXT	       ;; Bring in external declarations
				       ;;  for transient command processing
START:				       ;;
	MOV   SI, 081H		       ;; point to command-line args
GR_SKIP_SP:			       ;;
	CMP   BYTE PTR [SI], ' '      ;; skip leading spaces
	JNE   GR_CHK_SL	       ;;
	INC   SI		       ;;
	JMP   SHORT GR_SKIP_SP	       ;;
GR_CHK_SL:			       ;;
	CMP   BYTE PTR [SI], '/'      ;; check for /
	JNE   GR_NO_HELP	       ;;
	CMP   BYTE PTR [SI+1], '?'    ;; check for ?
	JNE   GR_NO_HELP	       ;;
	MOV   DX, OFFSET GR_HELP_STR  ;;
	MOV   AH, 09H		       ;;
	INT   21H		       ;;
	MOV   AX, 4C00H	       ;;
	INT   21H		       ;;
GR_NO_HELP:			       ;;
	JMP   GRAPHICS_INSTALL	       ;;
GR_HELP_STR DB "GRAPHICS [type] [[drive:][path]filename] [/R] [/B] [/LCD] [/PB:id]",0Dh,0Ah
	    DB 0Dh,0Ah
	    DB "  type      Printer type",0Dh,0Ah
	    DB "  filename  Graphics profile file",0Dh,0Ah
	    DB "  /R        Print black/white reversed",0Dh,0Ah
	    DB "  /B        Print background colour",0Dh,0Ah
	    DB "  /LCD      Use LCD aspect ratio",0Dh,0Ah
	    DB "  /PB:id    Print box id",0Dh,0Ah,"$"
;;
				       ;;
;	INCLUDE COPYRIGH.INC	       ;; included in message services
CODE   ENDS
       END    START
