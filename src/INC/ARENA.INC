;	SCCSID = @(#)arena.asm	1.1 85/04/09
BREAK <Memory arena structure>

;----+----+----+----+----+----+----+----+----+----+----+----+----+----+----;
;	     C	A  V  E  A  T	  P  R	O  G  R  A  M  M  E  R		   ;
;									   ;
;
; arena item
;
arena	STRUC
arena_signature     DB	?		; 4D for valid item, 5A for last item
arena_owner	    DW	?		; owner of arena item
arena_size	    DW	?		; size in paragraphs of item
arena_reserved	    DB	3 DUP(?)	; reserved
arena_name	    DB	8 DUP(?)	; owner file name
arena	ENDS

;
; CAUTION: The routines in ALLOC.ASM rely on the fact that arena_signature
; and arena_owner_system are all equal to zero and are contained in DI.  Change
; them and change ALLOC.ASM.

arena_owner_system  EQU 0		; free block indication
arena_owner_dos     EQU 8		; DOS-owned, nonallocatable block

arena_signature_normal	EQU 4Dh 	; valid signature, not end of arena
arena_signature_end	EQU 5Ah 	; valid signature, last block in arena

alloc_fit_mask		EQU 03h
alloc_domain_conventional EQU 20h ; internal: do not follow a linked UMB chain
alloc_domain_mask	EQU 0C0h
alloc_domain_upper	EQU 40h
alloc_domain_fallback	EQU 80h
;									   ;
;	     C	A  V  E  A  T	  P  R	O  G  R  A  M  M  E  R		   ;
;----+----+----+----+----+----+----+----+----+----+----+----+----+----+----;

