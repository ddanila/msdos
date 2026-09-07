	page 58,132
;******************************************************************************
	title	EMMINC.ASM - lists all EMMLIB.LIB include files
;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp. 1986
;
;   Title:	CEMM.EXE - COMPAQ Expanded Memory Manager 386 Driver
;		EMMLIB.LIB - Expanded Memory Manager Functions Library
;
;   Module:	EMMINC.ASM - lists all EMMLIB.LIB include files
;
;******************************************************************************
;
;******************************************************************************
;   Functional Description:
;		This module includes all CEMM include files used by EMMLIB
;   and will provide a listing of all when assembled to produce a listing file.
;
;******************************************************************************
.lfcond
.386p

;******************************************************************************
;	I N C L U D E S
;******************************************************************************
INC_LIST	EQU	1		; list include files

	page
	include	DESC.INC
	page
	include	EMMDEF.INC
	page
;	include	INSTR386.INC
;	page
	include	OEMDEP.INC
	page
	include	PAGE.INC
	page
	include	VDMSEG.INC
	page
	include	VDMSEL.INC

	end
