; HIGH-side entry adapter for an ordinary near service. The LOW caller must
; restore A20 first, push the relocated service offset, then FAR CALL here.
; Target receives original registers/flags and returns with near RET. Do not
; use for interrupt frames or device entries that exit via the low epilogue.
BIOS_HMA_ENTER_NEAR:
        push    bp
        mov     bp,sp
        push    ax
        lea     ax,[BIOS_HMA_ENTER_RETURN]
        push    ax
        mov     ax,ss:[bp+6]
        push    ax
        mov     ax,ss:[bp-2]
        mov     bp,ss:[bp]
        ret
BIOS_HMA_ENTER_RETURN:
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
        retf    2
