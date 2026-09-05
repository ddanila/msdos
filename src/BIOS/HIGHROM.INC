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

BIOS_HMA_INT1A:
        int     1ah
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

; Caller has already pushed the interrupt-frame FLAGS word, then pushes the
; segment and offset of a mutable LOW far-vector slot, and FAR CALLs here.
; Preserve live input flags separately from the supplied frame word. MOV,
; PUSH, POP, LEA and RETF do not change those live flags before target entry.
BIOS_HMA_SAVED_VECTOR:
        push    bp
        mov     bp,sp
        push    ax
        push    bx
        push    ds
        mov     ds,ss:[bp+8]
        mov     bx,ss:[bp+6]
        mov     ax,ds:[bx]
        mov     ss:[bp+6],ax
        mov     ax,ds:[bx+2]
        mov     ss:[bp+8],ax
        pop     ds
        pop     bx
        mov     ax,ss:[bp+10]
        push    ax
        push    cs
        lea     ax,[BIOS_HMA_SAVED_RETURN]
        push    ax
        mov     ax,ss:[bp+8]
        push    ax
        mov     ax,ss:[bp+6]
        push    ax
        mov     ax,ss:[bp-2]
        mov     bp,ss:[bp]
        retf
BIOS_HMA_SAVED_RETURN:
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
        retf    6

; Tail chain: existing caller frame stays untouched. Caller pushes low vector
; slot segment/offset and FAR CALLs this gate, but execution never returns to
; that call site. Discard its high return address and slot arguments, restore
; all registers/live flags, and transfer to the current low-slot target.
; Any original return into HMA must already have its own low A20 return gate.
BIOS_HMA_CHAIN_VECTOR:
        push    bp
        mov     bp,sp
        push    ax
        push    bx
        push    ds
        mov     ds,ss:[bp+8]
        mov     bx,ss:[bp+6]
        mov     ax,ds:[bx]
        mov     ss:[bp+6],ax
        mov     ax,ds:[bx+2]
        mov     ss:[bp+8],ax
        pop     ds
        pop     bx
        pop     ax
        lea     sp,[bp+6]
        mov     bp,ss:[bp]
        retf

; Ordinary near helper in this LOW segment. Caller pushes its low offset and
; FAR CALLs here. The helper must return normally (RET), not discard frames,
; unwind SPSAV, or escape into another service continuation.
BIOS_HMA_NEAR_CALL:
        push    bp
        mov     bp,sp
        push    ax
        lea     ax,[BIOS_HMA_NEAR_RETURN]
        push    ax
        mov     ax,ss:[bp+6]
        push    ax
        mov     ax,ss:[bp-2]
        mov     bp,ss:[bp]
        ret
BIOS_HMA_NEAR_RETURN:
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
        retf    2
