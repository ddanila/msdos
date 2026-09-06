; Shared XMS handle validation and free-space scans. DS selects the same
; authoritative handle records, limit and pool bound as XMSALLOC.INC.
; HANDLE_* and HMA_KB are supplied by that owner. These are internal near
; services; callers must preserve the public register contract themselves.

validate_handle proc near
        or      dx, dx
        jz      short validate_bad
        cmp     dx, [handle_limit]
        ja      short validate_bad
        mov     si, dx
        dec     si
        imul    si, HANDLE_SIZE
        add     si, offset handles
        cmp     word ptr [si+HANDLE_BASE], 0
        je      short validate_bad
        clc
        ret
validate_bad:
        stc
        ret
validate_handle endp

; Find a first-fit gap of BX KiB. Returns AX=base KiB.  Handle offsets are
; relative to physical 1 MiB, so the first 64 KiB must remain reserved for the
; separately managed HMA and must never be returned as an ordinary XMS block.
find_gap proc near
        mov     ax, HMA_KB
find_gap_retry:
        mov     di, ax
        add     di, bx
        jc      short find_gap_fail
        cmp     di, [extended_kb]
        ja      short find_gap_fail
        mov     si, offset handles
        mov     cx, [handle_limit]
find_gap_scan:
        cmp     word ptr [si+HANDLE_BASE], 0
        je      short find_gap_next
        cmp     word ptr [si+HANDLE_LENGTH], 0
        je      short find_gap_next       ; live identity, no occupied interval
        mov     bp, word ptr [si+HANDLE_BASE]
        cmp     di, bp
        jbe     short find_gap_next
        add     bp, word ptr [si+HANDLE_LENGTH]
        cmp     ax, bp
        jae     short find_gap_next
        mov     ax, bp
        jmp     short find_gap_retry
find_gap_next:
        add     si, HANDLE_SIZE
        loop    find_gap_scan
        clc
        ret
find_gap_fail:
        stc
        ret
find_gap endp

; Verify that growing SI's block to DX KiB does not overlap another handle.
gap_after_handle proc near
        mov     ax, word ptr [si+HANDLE_BASE]
        add     ax, dx
        jc      short gap_after_fail
        cmp     ax, [extended_kb]
        ja      short gap_after_fail
        mov     di, offset handles
        mov     cx, [handle_limit]
gap_after_loop:
        cmp     di, si
        je      short gap_after_next
        cmp     word ptr [di+HANDLE_BASE], 0
        je      short gap_after_next
        cmp     word ptr [di+HANDLE_LENGTH], 0
        je      short gap_after_next
        mov     bp, word ptr [di+HANDLE_BASE]
        cmp     bp, word ptr [si+HANDLE_BASE]
        jbe     short gap_after_next
        cmp     bp, ax
        jb      short gap_after_fail
gap_after_next:
        add     di, HANDLE_SIZE
        loop    gap_after_loop
        clc
        ret
gap_after_fail:
        stc
        ret
gap_after_handle endp

; Return the largest unallocated interval in AX (KiB).
; The XMS dispatcher owns CX, SI, DI, and BP across every public call, so this
; internal scanner need not save the same registers a second time.
largest_gap proc near
        xor     ax, ax                  ; largest
        mov     bx, HMA_KB              ; candidate base after the HMA
        cmp     [extended_kb], bx
        jbe     short largest_done       ; avoid underflow below the HMA bound
largest_retry:
        mov     dx, [extended_kb]       ; next used base, or pool end
        mov     di, 0ffffh              ; next handle offset
        mov     si, offset handles
        mov     cx, [handle_limit]
largest_scan:
        cmp     word ptr [si+HANDLE_BASE], 0
        je      short largest_next
        cmp     word ptr [si+HANDLE_LENGTH], 0
        je      short largest_next       ; otherwise retry cannot advance
        mov     bp, word ptr [si+HANDLE_BASE]
        cmp     bp, bx
        jb      short largest_next
        cmp     bp, dx
        jae     short largest_next
        mov     dx, bp
        mov     di, si
largest_next:
        add     si, HANDLE_SIZE
        loop    largest_scan
        mov     bp, dx
        sub     bp, bx
        cmp     bp, ax
        jbe     short largest_keep
        mov     ax, bp
largest_keep:
        cmp     di, 0ffffh
        je      short largest_done
        mov     bx, word ptr [di+HANDLE_BASE]
        add     bx, word ptr [di+HANDLE_LENGTH]
        jmp     short largest_retry
largest_done:
        ret
largest_gap endp

; Return total unallocated extended memory in DX (KiB), leaving the largest
; interval in AX when called after largest_gap. CX and SI are covered by the
; enclosing XMS dispatcher.
total_free proc near
        mov     dx, [extended_kb]
        cmp     dx, HMA_KB
        jae     short total_free_has_xms
        xor     dx, dx
        jmp     short total_free_scan
total_free_has_xms:
        sub     dx, HMA_KB
total_free_scan:
        mov     si, offset handles
        mov     cx, [handle_limit]
total_free_loop:
        cmp     word ptr [si+HANDLE_BASE], 0
        je      short total_free_next
        sub     dx, word ptr [si+HANDLE_LENGTH]
total_free_next:
        add     si, HANDLE_SIZE
        loop    total_free_loop
        ret
total_free endp
