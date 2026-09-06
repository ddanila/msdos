; Executes from SYSINIT's immutable administrative image, DS=canonical front.
bootstrap_admin_finish proc near
        cmp cx,XCP_LAYOUT_SIGNATURE
        jne boot_finish_bad
        cmp si,XCP_LAYOUT_VERSION
        jne boot_finish_bad
        or di,di
        jne boot_finish_bad
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push ds
        push es
        cli
        cmp [owner_query_active],2
        jne boot_finish_failed
        cmp [common_busy],0
        jne boot_finish_failed
        cmp [umb_remote_busy],0
        jne boot_finish_failed
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp [bootstrap_frozen],0
        jne boot_finish_failed
endif
ifdef HIMEM_UMB_DEFER_TEST
        cmp [umb_remote_defer],0
        je boot_finish_import
        mov dx,0ffffh
        call boot_umb_largest
        or dx,dx
        jnz boot_umb_ranges
        mov si,offset umb_boot_registration
        mov ax,0e701h
        int 2fh
        cmp ax,1
        jne boot_finish_failed
        mov [umb_boot_synthetic],1
        mov dx,0ffffh
        call boot_umb_largest
boot_umb_ranges:
        cmp dx,2
        jb boot_finish_failed
        mov [umb_boot_before],dx
        mov dx,1
        mov ah,10h
        call admin_xms_call
        cmp ax,1
        jne boot_finish_failed
        mov [umb_boot_first],bx
        mov dx,1
        mov ah,10h
        call admin_xms_call
        cmp ax,1
        jne boot_finish_failed
        mov [umb_boot_second],bx
        mov ax,0e702h
        int 2fh
        or ax,ax
        jnz boot_finish_failed
        cmp bl,2
        jne boot_finish_failed
        cmp [umb_boot_synthetic],0
        jne boot_umb_filled
        mov es,[umb_boot_first]
        xor di,di
        mov cx,16
        mov al,5ah
        cld
        rep stosb
        mov es,[umb_boot_second]
        xor di,di
        mov cx,16
        mov al,0a5h
        rep stosb
boot_umb_filled:
        mov [umb_remote_defer],0
endif
boot_finish_import:
        mov cx,3
boot_finish_query:
        push cx
        inc [umb_boot_import_tries]
        mov dx,0ffffh
        mov ah,10h
        call admin_xms_call
        pop cx
        cmp [umb_remote_state],2
        je boot_finish_committed
        loop boot_finish_query ; query/receipt only, never replay a mutation
        jmp short boot_finish_failed
boot_finish_committed:
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        mov word ptr [bootstrap_stage_entry+2],0
endif
ifdef HIMEM_AUTHORITATIVE_POISON_TEST
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp [bootstrap_detached],0
        jne boot_finish_done
endif
        push ds
        pop es
        mov di,offset bootstrap_owner_start
        mov cx,[handle_limit]
        imul cx,HANDLE_SIZE
        add cx,offset handles-offset bootstrap_owner_start
        mov al,0f4h
        cld
        rep stosb
endif
boot_finish_done:
        mov ax,XCP_LAYOUT_REPLY
        jmp short boot_finish_return
boot_finish_failed:
        xor ax,ax
boot_finish_return:
        pop es
        pop ds
        pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        ret
boot_finish_bad:
        xor ax,ax
        ret
bootstrap_admin_finish endp
ifdef HIMEM_UMB_DEFER_TEST
boot_umb_largest proc near
        mov ah,10h
        call admin_xms_call
        ret
boot_umb_largest endp
endif
