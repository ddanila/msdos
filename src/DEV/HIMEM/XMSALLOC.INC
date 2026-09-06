; Shared XMS allocation/lock/reallocation services, emitted in the caller's code segment.
; DS selects the authoritative owner: handles, handle_limit, extended_kb and
; move_length/source/dest. No CS-relative data or hardware/interrupt entry here.
; Requires XMSHANDLE.INC helpers, kb_to_physical and copy_move_blocks, plus
; xms_success/failure/bad_handle/no_memory near return adapters and error equates.
; The caller owns register/stack preservation, serialization and backend policy.
; copy_move_blocks consumes physical move_* byte ranges, preserves DS and SI,
; and returns CF. The development typed-copy variant additionally owns
; move_address_classes; none of these fields are implicit code-segment state.

xms_query_free proc near
ifdef HIMEM_PROTECTED_OWNER_TEST
        jmp     xms_remote_query
endif
xms_query_free_local label near
        call    largest_gap
        call    total_free
        ; The gap scanner leaves a physical-pool offset in BX. It is not
        ; an XMS status: clients also inspect BL when AX/DX are nonzero.
        xor     bl, bl
        or      dx, dx
        jnz     short query_free_done
        mov     bl, ERR_NO_MEMORY
query_free_done:
        clc
        ret
xms_query_free endp

ifdef HIMEM_PROTECTED_OWNER_TEST
; Development public AH=08h adapter. Snapshot under CLI; never publish a new
; allocator. Retain the old public entry and map transport failure to 8Eh.
xms_remote_query proc near
        pushf
        cli
        push    es
        mov     ax, XCP_QUERY
        int     15h
        cmp     ax, XCP_REPLY
        jne     short owner_query_unavailable
        cmp     bx, XCP_SIGNATURE
        jne     short owner_query_unavailable
        cmp     cx, XCP_VERSION
        jne     short owner_query_unavailable
        and     dx, XCP_REQUIRED OR XCP_OWNER_QUERY
        cmp     dx, XCP_REQUIRED OR XCP_OWNER_QUERY
        jne     short owner_query_unavailable
        mov     byte ptr [owner_query_active],1
        push    ds
        pop     es
        mov     cx, [handle_limit]
        mov     [owner_limit], cx
        mov     ax, [extended_kb]
        mov     [owner_pool], ax
        imul    cx, HANDLE_SIZE
        mov     si, offset handles
        mov     di, offset owner_records
        cld
        rep     movsb
        mov     si, offset owner_packet
        mov     ah, 87h
        int     15h
        jc      short owner_query_failed
        mov     ax, [owner_largest]
        mov     dx, [owner_total]
        xor     bl, bl
        or      dx, dx
        jnz     short owner_query_done
        mov     bl, ERR_NO_MEMORY
        jmp     short owner_query_done
owner_query_unavailable:
        ; EMM's own INIT queries this same allocator before its entry exists.
        ; Bootstrap locally, but never silently fall back after activation.
        cmp     byte ptr [owner_query_active],0
        jne     short owner_query_failed
        pop     es
        popf
        jmp     xms_query_free_local
owner_query_failed:
        xor     ax, ax
        xor     dx, dx
        mov     bl, ERR_GENERAL
owner_query_done:
        pop     es
        popf
        clc
        ret
xms_remote_query endp
endif

xms_allocate proc near
        mov     bx, dx
        mov     si, offset handles
        mov     cx, [handle_limit]
allocate_handle_scan:
        cmp     word ptr [si+HANDLE_BASE], 0
        je      short allocate_handle_found
        add     si, HANDLE_SIZE
        loop    allocate_handle_scan
        jmp     short allocate_no_handle
allocate_handle_found:
        mov     dl, byte ptr [handle_limit]
        sub     dl, cl
        xor     dh, dh
        inc     dx
        push    si
        call    find_gap
        pop     si
        jnc     short allocate_found
        mov     dx, bx
        jmp     xms_no_memory
allocate_found:
        ; A free record is already unlocked: release rejects nonzero locks.
        ; Its old length is ignored while base is zero and is replaced below.
        mov     word ptr [si+HANDLE_BASE], ax
        mov     word ptr [si+HANDLE_LENGTH], bx
        jmp     xms_success
allocate_no_handle:
        mov     bl, ERR_NO_HANDLES
        jmp     xms_failure
xms_allocate endp

xms_free proc near
        call    validate_handle
        jc      xms_bad_handle
        cmp     byte ptr [si+HANDLE_LOCK], 0
        jne     short free_locked
        mov     word ptr [si+HANDLE_BASE], 0
        jmp     xms_success
free_locked:
        mov     bl, ERR_LOCKED
        jmp     xms_failure
xms_free endp

xms_lock proc near
        call    validate_handle
        jc      xms_bad_handle
        cmp     byte ptr [si+HANDLE_LOCK], 0ffh
        je      short lock_overflow
        inc     byte ptr [si+HANDLE_LOCK]
        mov     bx, word ptr [si+HANDLE_BASE]
        mov     dx, bx
        mov     cl, 6
        shr     dx, cl
        add     dx, 0010h
        mov     cl, 10
        shl     bx, cl
        jmp     xms_success
lock_overflow:
        mov     bl, ERR_LOCK_OVER
        jmp     xms_failure
xms_lock endp

xms_unlock proc near
        call    validate_handle
        jc      xms_bad_handle
        cmp     byte ptr [si+HANDLE_LOCK], 0
        je      short unlock_underflow
        dec     byte ptr [si+HANDLE_LOCK]
        jmp     xms_success
unlock_underflow:
        mov     bl, ERR_NOT_LOCKED
        jmp     xms_failure
xms_unlock endp

xms_handle_info proc near
        call    validate_handle
        jc      xms_bad_handle
        push    si
        xor     bx, bx
        mov     si, offset handles
        mov     cx, [handle_limit]
handle_info_count_loop:
        cmp     word ptr [si+HANDLE_BASE], 0
        jne     short handle_info_count_used
        inc     bl
handle_info_count_used:
        add     si, HANDLE_SIZE
        loop    handle_info_count_loop
        pop     si
        mov     bh, byte ptr [si+HANDLE_LOCK]
        mov     dx, word ptr [si+HANDLE_LENGTH]
        jmp     xms_success
xms_handle_info endp

xms_reallocate proc near
        call    validate_handle
        jc      xms_bad_handle
        cmp     byte ptr [si+HANDLE_LOCK], 0
        jne     short realloc_locked
        mov     ax, word ptr [si+HANDLE_LENGTH]
        cmp     bx, ax
        jbe     short realloc_resize
        push    dx
        mov     dx, bx
        call    gap_after_handle
        pop     dx
        jc      short realloc_move
realloc_resize:
        mov     word ptr [si+HANDLE_LENGTH], bx
        jmp     xms_success
realloc_move:
ifdef HIMEM_PROTECTED_COPY_TEST
        mov     word ptr [move_address_classes],0 ; both owners are XMS backing
endif
        push    si
        push    bx
        call    find_gap
        pop     bx
        pop     si
        jc      xms_no_memory
        push    bx
        push    ax
        mov     ax, word ptr [si+HANDLE_LENGTH]
        mov     dx, ax
        mov     cl, 6
        shr     dx, cl
        mov     cl, 10
        shl     ax, cl
        mov     word ptr [move_length], ax
        mov     word ptr [move_length+2], dx
        mov     ax, word ptr [si+HANDLE_BASE]
        call    kb_to_physical
        mov     word ptr [move_source], ax
        mov     word ptr [move_source+2], dx
        pop     ax
        push    ax
        call    kb_to_physical
        mov     word ptr [move_dest], ax
        mov     word ptr [move_dest+2], dx
        call    copy_move_blocks
        pop     ax
        pop     bx
ifdef HIMEM_EARLY_REALLOC_TEST
        ; Negative control: publish the new size before observing copy failure.
        mov     word ptr [si+HANDLE_LENGTH],bx
endif
        jc      xms_no_memory
        mov     word ptr [si+HANDLE_BASE], ax
        mov     word ptr [si+HANDLE_LENGTH], bx
        jmp     xms_success
realloc_locked:
        mov     bl, ERR_LOCKED
        jmp     xms_failure
xms_reallocate endp
