	PAGE	,132
	TITLE	DOS GRAPHICS Command  -	Profile Load Modules #2 
;; DOS - GRAPHICS Command
;; (C) Copyright 1988 Microsoft
;; File Name:  GRLOAD.ASM
;; ----------
;; Description:
;; ------------
;;   This file contains the modules used to load the
;;   GRAPHICS profile into resident memory.
;;   ************* The EGA Dynamic Save Area will be built (by
;;   **  NOTE	** CHAIN_INTERRUPTS in file GRINST.ASM) over top of these
;;   ************* modules to avoid having to relocate this save just before
;;   terminating.  This is safe since the maximum memory used is
;;   288 bytes and the profile loading modules are MUCH larger than
;;   this.  So GRLOAD.ASM MUST be linked before GRINST.ASM and after
;;   GRPRINT.ASM.
;; Documentation Reference:
;; ------------------------
;;	 PLACID Functional Specifications
;;	 OASIS High Level Design
;;	 OASIS GRAPHICS I1 Overview
;; Procedures Contained in This File:
;; ----------------------------------
;;	 LOAD_PROFILE - Main module for profile loading
;; Include Files Required:
;; -----------------------
;;	 ?????????? - Externals for profile loading modules
;; External Procedure References:
;; ------------------------------
;;	 None
;; Linkage Instructions:
;; ---------------------
;;	 Refer to GRAPHICS.ASM
CODE	SEGMENT PUBLIC 'CODE'          ;;
	INCLUDE STRUC.INC	       ;;
;; Public Symbols
	ASSUME	CS:CODE,DS:CODE        ;;
;-------------------------------------------------------------------------------
; Set assemble switches for parse code that is not required!!
;-------------------------------------------------------------------------------
DateSW	      EQU     0
TimeSW	      EQU     0
CmpxSW	      EQU     0
DrvSW	      EQU     0
QusSW	      EQU     0
KeySW	      EQU     0
;Val1SW        EQU     0
;Val2SW        EQU     0
       PUBLIC  SYSPARSE 	       ;;
       INCLUDE PARSE.ASM	       ;; parser code
CODE	ENDS			       ;;
	END
