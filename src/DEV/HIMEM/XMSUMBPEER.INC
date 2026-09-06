; DS owns UMB state; ES:SI points to the registration packet. Callers supply
; saved-register and private_done/private_unregister_done return adapters.
HIMEM_UMB_REGISTER macro return_label:=<private_done>
ifdef UMB_TEST_REJECT
        jmp     short private_bad
endif
        cmp     [umb_count], 0
        jne     short private_bad
        cmp     word ptr es:[si], 1
        jne     short private_bad
        mov     cx, word ptr es:[si+2]
        or      cx, cx
        jz      short private_bad
        cmp     cx, MAX_UMB_BLOCKS
        ja      short private_bad
        add     si, 4
        xor     bp, bp
        mov     di, si
private_validate:
        mov     ax, word ptr es:[di]
        mov     dx, word ptr es:[di+2]
        or      dx, dx
        jz      short private_bad
        cmp     ax, 0a000h
        jb      short private_bad
        cmp     ax, bp
        jb      short private_bad
        add     ax, dx
        jc      short private_bad
        cmp     ax, 0f000h
        ja      short private_bad
        mov     bp, ax
        add     di, 4
        loop    private_validate

        mov     cx, word ptr es:[si-2]
        mov     [umb_count], cx
        mov     di, offset umb_blocks
private_copy:
        mov     ax, word ptr es:[si]
        mov     word ptr [di], ax
        mov     ax, word ptr es:[si+2]
        mov     word ptr [di+2], ax
        add     si, 4
        add     di, UMB_BLOCK_SIZE
        loop    private_copy
        mov     ax, 1
        xor     bx, bx
        jmp     short return_label
private_bad:
        xor     ax, ax
        mov     bl, 1
endm

HIMEM_UMB_UNREGISTER macro return_label:=<private_unregister_done>
        mov     si, offset umb_blocks
        mov     cx, [umb_count]
        jcxz    short private_unregister_clear
private_unregister_scan:
        test    word ptr [si+2], UMB_ALLOCATED
        jnz     short private_unregister_busy
        add     si, UMB_BLOCK_SIZE
        loop    private_unregister_scan
private_unregister_clear:
        mov     [umb_count], cx
        mov     ax, 1
        xor     bx, bx
        jmp     short return_label
private_unregister_busy:
        xor     ax, ax
        mov     bl, 2
endm
