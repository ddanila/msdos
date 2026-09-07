

;******************************************************************************
;
;   (C) Copyright MICROSOFT Corp. 1986
;
;   Title:    MEMM - MICROSOFT Expanded Memory Manager 386
;
;   Module:   PAGE.INC - Definitions for paging on 386
;
;******************************************************************************
;
ifndef INC_LIST
.xlist
endif

P_SIZE		equ	1000h		; page size

P_PRES		equ	01h		; page present bit
P_WRITE 	equ	02h		; write access bit
P_USER		equ	04h		; access bit for User mode
P_ACC		equ	10h		; page accessed bit
P_DIRTY 	equ	20h		; page dirty bit


P_AVAIL 	equ	(P_PRES+P_WRITE+P_USER) ; avail to everyone & present

PAGE_ENTRY	macro	addr,stat
		dd	addr		; access & status in low 12
					; address in high 20
endm

.list		; end of PAGE.INC
