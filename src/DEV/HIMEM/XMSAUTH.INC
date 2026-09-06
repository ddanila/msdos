; Paired development front end. Import once, then all handle mutations execute
; at the installed high owner. Low handles are a refreshed read-only view for
; the existing move/extended-info validators, not a second allocator.
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
        ; input records. The returned low view must come from the high owner.
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
        mov cx,[handle_limit]
        imul cx,HANDLE_SIZE
        mov si,offset owner_records
        mov di,offset handles
        cld
        rep movsb
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

; Refresh read-only consumers without changing their original request regs.
; A transport failure rejects the operation rather than using stale handles.
xms_owner_refresh proc near
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        call xms_query_free
        cmp bl,ERR_GENERAL
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        je short auth_refresh_failed
        clc
        ret
auth_refresh_failed:
        mov bl,ERR_GENERAL
        stc
        ret
xms_owner_refresh endp
