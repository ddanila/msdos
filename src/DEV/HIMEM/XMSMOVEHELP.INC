; Resolve an XMS move endpoint. DX is a handle (zero means a packed
; segment:offset conventional address), BP:AX is its offset, and move_length
; is the transfer length. Returns DX:AX=physical address.
resolve_move_address proc near
        push    di
        mov     [move_offset_error], 0
        or      dx, dx
        jnz     short resolve_handle
        mov     dx, bp
        mov     bx, dx
        mov     cl, 12
        shr     dx, cl
        mov     cl, 4
        shl     bx, cl
        add     ax, bx
        adc     dx, 0
        pop     di
        clc
        ret
resolve_handle:
        push    dx
ifdef HIMEM_COMMON_XMS_TEST
        call    validate_handle
else
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
ifndef HIMEM_AUTHORITATIVE_LOCAL_LOOKUP
        call    xms_owner_handle
else
        call    validate_handle
endif
else
        call    validate_handle
endif
endif
        pop     dx
        jc      short resolve_bad_handle
        push    bp                     ; retain the start offset's high word
        mov     bx, ax
        add     bx, word ptr [move_length]
        adc     bp, word ptr [move_length+2]
        jc      short resolve_bad_offset
        mov     dx, word ptr [si+HANDLE_LENGTH]
        mov     di, dx
        mov     cl, 6
        shr     dx, cl
        mov     cl, 10
        shl     di, cl
        cmp     bp, dx
        ja      short resolve_bad_offset
        jb      short resolve_offset_valid
        cmp     bx, di
        ja      short resolve_bad_offset
resolve_offset_valid:
        pop     bp                     ; bounds checking used the end offset
        mov     bx, ax
        mov     ax, word ptr [si+HANDLE_BASE]
        call    kb_to_physical
        add     ax, bx
        adc     dx, bp
        pop     di
        clc
        ret
resolve_bad_offset:
        pop     bp
        mov     [move_offset_error], 1
resolve_bad_handle:
        pop     di
        stc
        ret
resolve_move_address endp

copy_move_blocks proc near
ifdef HIMEM_COMMON_XMS_TEST
        jmp     bootstrap_copy_move
else
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        cmp     [owner_query_active],0
        je      bootstrap_copy_move
endif
ifdef HIMEM_PROTECTED_COPY_TEST
        push    si
        push    es
        push    bx
        push    cx
        push    dx
ifndef HIMEM_SKIP_COPY_CAPABILITY_TEST
        mov     ax,XCP_QUERY
ifdef HIMEM_COMMON_XMS_TEST
        call    xms_common_query
else
        int     015h
endif
        cmp     ax,XCP_REPLY
        jne     short protected_copy_unavailable
        cmp     bx,XCP_SIGNATURE
        jne     short protected_copy_unavailable
        cmp     cx,XCP_VERSION
        jne     short protected_copy_unavailable
        and     dx,XCP_REQUIRED
        cmp     dx,XCP_REQUIRED
        jne     short protected_copy_unavailable
endif
        push    cs
        pop     es
        mov     si,offset protected_copy_packet
        mov     ah,087h
ifdef HIMEM_COMMON_XMS_TEST
        call    xms_common_send
else
        int     015h
endif
        pop     dx
        pop     cx
        pop     bx
        pop     es
        pop     si
        ret
protected_copy_unavailable:
        pop     dx
        pop     cx
        pop     bx
        pop     es
        pop     si
        stc
        ret
else
        HIMEM_BIOS_COPY
endif
endif
copy_move_blocks endp

ifndef HIMEM_AUTHORITATIVE_OWNER_TEST
        HIMEM_BIOS_DESCRIPTOR
endif

; Convert AX kilobytes above the XMS base to DX:AX physical bytes.
kb_to_physical proc near
        mov     dx, ax
        mov     cl, 6
        shr     dx, cl
        add     dx, 0010h
        mov     cl, 10
        shl     ax, cl
        ret
kb_to_physical endp
