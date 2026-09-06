; Paired development front end. Import once, then all handle mutations execute
; at the installed high owner. Move fetches one transient record, never a
; refreshed low handle table. Bootstrap table and import staging are retained
; only until the loader can reclaim their complete allocation.
xms_remote_owned proc near
        pushf
        cli
        push es
        mov [owner_operation],ax
        mov [owner_bx],bx
        mov [owner_total],dx
        mov ax,XCP_QUERY
        int 15h
        cmp ax,XCP_REPLY
        jne auth_unavailable
        cmp bx,XCP_SIGNATURE
        jne auth_unavailable
        cmp cx,XCP_VERSION
        jne auth_unavailable
        and dx,XCP_REQUIRED OR XCP_OWNER_ACTIVE
        cmp dx,XCP_REQUIRED OR XCP_OWNER_ACTIVE
        jne auth_unavailable
        push ds
        pop es
        cmp [owner_query_active],0
        jne short auth_poison_view
        mov ax,[handle_limit]
        mov [owner_limit],ax
        mov ax,[extended_kb]
        mov [owner_pool],ax
        mov cx,[handle_limit]
        imul cx,HANDLE_SIZE
        mov si,offset handles
        mov di,offset owner_records
        cld
        rep movsb
        ; No local mutation is allowed after attempting ownership publication,
        ; including an ambiguous transport failure after the high commit.
        mov [owner_query_active],1
        jmp short auth_send
auth_poison_view:
ifdef HIMEM_AUTHORITATIVE_POISON_TEST
        ; Prove the high table is authoritative: later requests carry invalid
        ; input records. No later call is allowed to import them.
        mov di,offset owner_records
        mov cx,MAX_HANDLES*HANDLE_SIZE
        mov al,0a5h
        cld
        rep stosb
endif
auth_send:
        mov word ptr [owner_packet],4158h ; XAUT
        mov word ptr [owner_packet+2],5455h
        mov si,offset owner_packet
        mov ah,87h
        int 15h
        jc short auth_failed
ifdef HIMEM_AUTHORITATIVE_POISON_TEST
        ; Destroy the old allocator table after the first successful import.
        ; Limit the write to the selected resident /NUMHANDLES allocation.
        mov di,offset handles
        mov cx,[handle_limit]
        imul cx,HANDLE_SIZE
        mov al,0a5h
        cld
        rep stosb
endif
        mov ax,[owner_largest]
        mov bx,[owner_bx]
        mov dx,[owner_total]
auth_return:
        pop es
        popf
        clc
        ret
auth_unavailable:
        cmp [owner_query_active],0
        jne short auth_failed
        mov bx,[owner_bx]
        mov dx,[owner_total]
        pop es
        popf
        stc
        ret
auth_failed:
        xor ax,ax
        xor dx,dx
        mov bl,ERR_GENERAL
        jmp short auth_return
xms_remote_owned endp

; Move's existing bounds checker consumes SI -> one five-byte record. Fetch
; its base/length from the high owner without changing lock counts. The import
; staging area supplies transient scratch, not a live mirror of all handles.
; Preserve the caller's offset AX/BP and packet DI; CF means invalid/unavailable.
xms_owner_handle proc near
        push ax
        push bx
        push cx
        push dx
        push di
        push bp
        mov ax,0bh
        call xms_remote_owned
        jc short auth_handle_bootstrap
        or ax,ax
        jz short auth_handle_failed
        mov word ptr [owner_records+HANDLE_BASE],bx
        mov word ptr [owner_records+HANDLE_LENGTH],dx
        mov byte ptr [owner_records+HANDLE_LOCK],0 ; resolver never reads locks
        mov si,offset owner_records
        pop bp
        pop di
        pop dx
        pop cx
        pop bx
        pop ax
        clc
        ret
auth_handle_failed:
        cmp bl,ERR_GENERAL
        jne short auth_handle_restore
        mov [move_offset_error],2
auth_handle_restore:
        pop bp
        pop di
        pop dx
        pop cx
        pop bx
        pop ax
        stc
        ret
auth_handle_bootstrap:
        pop bp
        pop di
        pop dx
        pop cx
        pop bx
        pop ax
        jmp validate_handle
xms_owner_handle endp
