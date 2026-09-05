; Retained-low interrupt entries for the high BIOS. IVT publication is a
; separate installer transaction, after all high targets and low slots bind.
; AH=13h exchanges the authoritative runtime and warm-boot vectors entirely
; low. Other multiplex requests chain low WITHOUT restoring A20: E705h itself
; must reach HIMEM through this chain, not recurse through a high entry gate.
BIOS_LOW_INT2F13:
        cmp     ah,13h
        je      BIOS_LOW_CHANGE13
        BIOS_MULTIPLEX_CHAIN
BIOS_LOW_CHANGE13:
        BIOS_SWAP_VECTOR dx,ORIG13
        push    ax
        mov     ax,ds
        BIOS_SWAP_VECTOR ax,ORIG13+2
        mov     ds,ax
        BIOS_SWAP_VECTOR bx,OLD13
        mov     ax,es
        BIOS_SWAP_VECTOR ax,OLD13+2
        mov     es,ax
        pop     ax
        iret

; Unlike device entries, this keeps the original interrupt-compatible frame.
; BLOCK13 returns with RETF 2 / IRET and supplies the disk result flags.
BIOS_LOW_BLOCK13:
        call    BIOS_HMA_ROM_RESTORE
        BIOS_INTERRUPT_JUMP
BIOS_HIGH_BLOCK13_ENTRY dd 0
