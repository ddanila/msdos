ifdef HIMEM_COMMON_XMS_TEST
bootstrap_move proc near
else
xms_move proc near
endif
ifndef HIMEM_COMMON_XMS_TEST
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp word ptr [bootstrap_stage_entry+2],0
        je staged_move_ready
        push bx
        push dx
        mov ax,8
        call xms_remote_owned
        pop dx
        pop bx
        jc staged_move_forward
        cmp word ptr [bootstrap_stage_entry+2],0
        je staged_move_ready
        xor ax,ax
        mov bl,ERR_GENERAL
        ret
staged_move_forward:
        mov ah,0bh
        call xms_stage_forward
        ret
staged_move_ready:
endif
endif
        push    bx
        push    dx
        push    bp
        push    es
        mov     es, [caller_ds]
        mov     di, [caller_si]
ifdef HIMEM_PROTECTED_COPY_TEST
        mov     word ptr [move_address_classes],0
        cmp     word ptr es:[di+4],0
        jne     short protected_source_handle
        or      word ptr [move_address_classes],1
protected_source_handle:
        cmp     word ptr es:[di+10],0
        jne     short protected_dest_handle
        or      word ptr [move_address_classes],2
protected_dest_handle:
endif
        mov     ax, word ptr es:[di]
        test    al, 1
        jnz     short move_bad_length
        mov     word ptr [move_length], ax
        mov     ax, word ptr es:[di+2]
        mov     word ptr [move_length+2], ax
        or      ax, word ptr [move_length]
        jz      short move_success

        mov     dx, word ptr es:[di+4]
        mov     ax, word ptr es:[di+6]
        mov     bp, word ptr es:[di+8]
        call    resolve_move_address
        jc      short move_bad_source
        mov     word ptr [move_source], ax
        mov     word ptr [move_source+2], dx

        mov     dx, word ptr es:[di+10]
        mov     ax, word ptr es:[di+12]
        mov     bp, word ptr es:[di+14]
        call    resolve_move_address
        jc      short move_bad_dest
        mov     word ptr [move_dest], ax
        mov     word ptr [move_dest+2], dx

move_copy:
        call    copy_move_blocks
        jc      short move_general_failure
move_success:
        pop     es
        pop     bp
        pop     dx
        pop     bx
        jmp     xms_success
move_bad_length:
        mov     bl, ERR_BAD_LENGTH
        jmp     short move_failure
move_bad_source:
        mov     bl, ERR_BAD_SOURCE
        jmp     short move_bad_address
move_bad_dest:
        mov     bl, ERR_BAD_DEST
move_bad_address:
ifdef HIMEM_AUTHORITATIVE_OWNER_TEST
        cmp     [move_offset_error],2
        je      short move_general_failure
endif
        cmp     [move_offset_error], 0
        je      short move_failure
        mov     bl, ERR_BAD_LENGTH
        jmp     short move_failure
move_general_failure:
        mov     bl, ERR_GENERAL
move_failure:
        pop     es
        pop     bp
        add     sp, 4
        jmp     xms_failure
ifdef HIMEM_COMMON_XMS_TEST
bootstrap_move endp
else
xms_move endp
endif
