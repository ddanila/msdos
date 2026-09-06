; DS owns the UMB table; caller supplies common success/failure returns.
; No dependency on adjacent XMS handle storage.
xms_umb_request proc near
        or      dx, dx
        jz      short umb_request_fail
        mov     si, offset umb_blocks
        mov     cx, [umb_count]
        xor     bp, bp                  ; largest free block
        mov     di, 0ffffh              ; first suitable block
        jcxz    umb_request_fail
umb_request_scan:
        test    word ptr [si+2], UMB_ALLOCATED
        jnz     short umb_request_next
        mov     ax, word ptr [si+2]
        cmp     ax, bp
        jbe     short umb_request_size
        mov     bp, ax
umb_request_size:
        cmp     di, 0ffffh
        jne     short umb_request_next
        cmp     ax, dx
        jb      short umb_request_next
        mov     di, si
umb_request_next:
        add     si, UMB_BLOCK_SIZE
        loop    umb_request_scan
        cmp     di, 0ffffh
        je      short umb_request_fail
        mov     bx, word ptr [di]
        cmp     word ptr [di+2], dx
        je      short umb_request_exact
        cmp     [umb_count], MAX_UMB_BLOCKS
        jae     short umb_request_fail
        call    insert_umb_after
        mov     ax, word ptr [di]
        add     ax, dx
        mov     word ptr [di+UMB_BLOCK_SIZE], ax
        mov     ax, word ptr [di+2]
        sub     ax, dx
        mov     word ptr [di+UMB_BLOCK_SIZE+2], ax
        mov     word ptr [di+2], dx
umb_request_exact:
        or      word ptr [di+2], UMB_ALLOCATED
        jmp     xms_success
umb_request_fail:
        mov     dx, bp
        or      bp, bp
        jz      short umb_none
        mov     bl, ERR_UMB_SMALL
        jmp     short umb_failure
umb_none:
        mov     bl, ERR_NO_UMBS
umb_failure:
        jmp     xms_failure
xms_umb_request endp

xms_umb_release proc near
        mov     si, offset umb_blocks
        mov     cx, [umb_count]
        jcxz    umb_release_bad
umb_release_find:
        cmp     word ptr [si], dx
        jne     short umb_release_next
        test    word ptr [si+2], UMB_ALLOCATED
        jnz     short umb_release_found
umb_release_next:
        add     si, UMB_BLOCK_SIZE
        loop    umb_release_find
umb_release_bad:
        mov     bl, ERR_BAD_UMB
        jmp     xms_failure
umb_release_found:
        and     word ptr [si+2], NOT UMB_ALLOCATED
        jmp     coalesce_umb_blocks
xms_umb_release endp

; Insert an empty UMB entry after DI, shifting later entries upward.
; The caller needs DI afterward, but this helper does not modify it. All other
; scratch registers are restored by the enclosing XMS dispatcher.
insert_umb_after proc near
        mov     cx, [umb_count]
        inc     word ptr [umb_count]
        mov     si, offset umb_blocks
        mov     ax, cx
        imul    ax, UMB_BLOCK_SIZE
        add     si, ax
insert_umb_shift:
        cmp     si, di
        jbe     short insert_umb_done
        mov     ax, word ptr [si-UMB_BLOCK_SIZE]
        mov     word ptr [si], ax
        mov     ax, word ptr [si-UMB_BLOCK_SIZE+2]
        mov     word ptr [si+2], ax
        sub     si, UMB_BLOCK_SIZE
        loop    insert_umb_shift
insert_umb_done:
        ret
insert_umb_after endp

; No register result from this internal helper survives xms_umb_release; the
; public dispatcher restores every scratch register used here.
coalesce_umb_blocks proc near
        mov     si, offset umb_blocks
        mov     cx, [umb_count]
        dec     cx
        jcxz    short coalesce_done
coalesce_scan:
        test    word ptr [si+2], UMB_ALLOCATED
        jnz     short coalesce_next
        test    word ptr [si+UMB_BLOCK_SIZE+2], UMB_ALLOCATED
        jnz     short coalesce_next
        mov     ax, word ptr [si]
        add     ax, word ptr [si+2]
        cmp     ax, word ptr [si+UMB_BLOCK_SIZE]
        jne     short coalesce_next
        mov     ax, word ptr [si+UMB_BLOCK_SIZE+2]
        add     word ptr [si+2], ax
        call    remove_next_umb
        dec     [umb_count]
        dec     cx
        jcxz    short coalesce_done
        jmp     short coalesce_scan
coalesce_next:
        add     si, UMB_BLOCK_SIZE
        loop    coalesce_scan
coalesce_done:
        jmp     xms_success
coalesce_umb_blocks endp

remove_next_umb proc near
        mov     di, si
        add     di, UMB_BLOCK_SIZE
remove_umb_shift:
        add     di, UMB_BLOCK_SIZE
ifdef HIMEM_UMB_LEGACY_BOUND_TEST
        cmp     di, offset handles
else
        ; The authoritative layout inserts bootstrap services before handles.
        ; Coalescing owns only the UMB records, never the following code/owner.
        cmp     di, offset umb_blocks_end
endif
        jae     short remove_umb_done
        mov     bp, word ptr [di]
        mov     word ptr [di-UMB_BLOCK_SIZE], bp
        mov     bp, word ptr [di+2]
        mov     word ptr [di-UMB_BLOCK_SIZE+2], bp
        jmp     short remove_umb_shift
remove_umb_done:
        ret
remove_next_umb endp
