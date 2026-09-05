; Prototype low ROM-return gate for the BIOS high-service split.
; Not installed in the resident BIOS yet. Include in a retained LOW segment.
; Entry: ordinary INT 13h registers; FAR CALL from low or high service code.
; Exit: preserve the ROM's registers and flags; SS must remain conventional.
; Activation requires the repository HIMEM E705h hardware-restore contract.
; Foreign-provider support must be established before enabling this gate there.
; This instruction-only include is shared by the MASM and NASM boundary probes.
BIOS_HMA_INT13:
        int     13h
        call    BIOS_HMA_ROM_RESTORE
        retf

; Saved interrupt-vector variant (ORIG13-style target returning with IRET
; or RETF 2). Caller pushes target segment, then offset, then FAR CALLs here.
; Build an interrupt-compatible frame without lending input BP or AX to the
; target. All temporary storage is on the low stack, so calls may nest.
BIOS_HMA_VECTOR:
        push    bp
        mov     bp,sp
        push    ax
        pushf
        push    cs
        lea     ax,[BIOS_HMA_VECTOR_RETURN]
        push    ax
        mov     ax,ss:[bp+8]
        push    ax
        mov     ax,ss:[bp+6]
        push    ax
        mov     ax,ss:[bp-2]
        mov     bp,ss:[bp]
        retf
BIOS_HMA_VECTOR_RETURN:
        ; Remove the two saved input words without changing returned BP, AX,
        ; or FLAGS: move FLAGS over the last discarded word before POPF.
        pushf
        push    ax
        push    bp
        mov     bp,sp
        mov     ax,ss:[bp+4]
        mov     ss:[bp+8],ax
        pop     bp
        pop     ax
        add     sp,4
        popf
        call    BIOS_HMA_ROM_RESTORE
        retf    4

BIOS_HMA_ROM_RESTORE:
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
        ret
