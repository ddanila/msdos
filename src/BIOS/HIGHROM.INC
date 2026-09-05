; Prototype low ROM-return gate for the BIOS high-service split.
; Not installed in the resident BIOS yet. Include in a retained LOW segment.
; Entry: ordinary INT 13h registers; FAR CALL from low or high service code.
; Exit: preserve the ROM's registers and flags; SS must remain conventional.
; Activation requires the repository HIMEM E705h hardware-restore contract.
; Foreign-provider support must be established before enabling this gate there.
; This instruction-only include is shared by the MASM and NASM boundary probes.
BIOS_HMA_INT13:
        int     13h
        pushf
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     ax,0e705h
        int     2fh
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        popf
        retf
