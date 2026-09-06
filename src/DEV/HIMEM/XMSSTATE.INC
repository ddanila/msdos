; Read-only validation of an existing allocator owner before publication.
; DS supplies handle_limit, extended_kb and handles using XMSHANDLE.INC's
; record format. CX is the caller-proved readable record capacity (1..128).
; Caller must keep the owner stable throughout validation and later transfer;
; this routine does not freeze, copy, publish or reclaim any owner.
; CF clear = valid, set = invalid. All 16-bit general/segment registers survive.
; Free lengths may be stale. Live zero-length blocks and all lock counts are
; legal. Nonempty live blocks must be disjoint and above the reserved HMA.
; Startup-only pairwise scan: at most MAX_HANDLES squared record comparisons.

xms_validate_owner proc near
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        jcxz    owner_invalid
        cmp     cx, MAX_HANDLES
        ja      short owner_invalid
        mov     ax, [handle_limit]
        or      ax, ax
        jz      short owner_invalid
        cmp     ax, cx
        ja      short owner_invalid
        mov     cx, ax
        mov     si, offset handles
owner_bounds:
        mov     ax, [si+HANDLE_BASE]
        or      ax, ax
        jnz     short owner_live
        cmp     byte ptr [si+HANDLE_LOCK], 0
        jne     short owner_invalid
        jmp     short owner_next_bound
owner_live:
        cmp     ax, HMA_KB
        jb      short owner_invalid
        add     ax, [si+HANDLE_LENGTH]
        jc      short owner_invalid
        cmp     ax, [extended_kb]
        ja      short owner_invalid
owner_next_bound:
        add     si, HANDLE_SIZE
        loop    owner_bounds
        mov     cx, [handle_limit]
        mov     si, offset handles
owner_outer:
        mov     ax, [si+HANDLE_BASE]
        or      ax, ax
        jz      short owner_next
        mov     dx, [si+HANDLE_LENGTH]
        or      dx, dx
        jz      short owner_next
        add     dx, ax                 ; bounds pass proved no wrap
        mov     di, si
        mov     bp, cx
owner_inner:
        dec     bp
        jz      short owner_next
        add     di, HANDLE_SIZE
        mov     bx, [di+HANDLE_BASE]
        or      bx, bx
        jz      short owner_inner
        cmp     word ptr [di+HANDLE_LENGTH], 0
        je      short owner_inner
        cmp     bx, dx
        jae     short owner_inner
        add     bx, [di+HANDLE_LENGTH]
        cmp     ax, bx
        jae     short owner_inner
owner_invalid:
        stc
        jmp     short owner_return
owner_next:
        add     si, HANDLE_SIZE
        loop    owner_outer
        clc
owner_return:
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
xms_validate_owner endp
