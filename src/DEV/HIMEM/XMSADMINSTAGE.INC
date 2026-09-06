bootstrap_admin_stage proc near
        pushf
        cli
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push ds
        push es
        cmp cx,XCP_LAYOUT_SIGNATURE
        jne stage_bad
        cmp si,XCP_LAYOUT_VERSION
        jne stage_bad
        or di,di
        jne stage_bad
        cmp [owner_query_active],0
        jne stage_bad
        mov bp,ax
        mov ax,[handle_limit]
        imul ax,HANDLE_SIZE
        add ax,offset handles+15
        and ax,0fff0h
        mov cx,ax
        cmp bp,XCP_STAGE_FREEZE
        je stage_freeze
        cmp bp,XCP_STAGE_RESTORE
        je stage_restore
        cmp bp,XCP_STAGE_RETARGET
        jne stage_bind_check
        cmp [bootstrap_frozen],1
        jne stage_bad
        or bx,bx
        jz stage_bad
        cmp bx,[bootstrap_stage_entry+2]
        jne stage_bad
        cmp bx,dx
        je stage_bad
        jmp short stage_bounds
stage_bind_check:
        cmp word ptr [bootstrap_stage_entry+2],0
        jne stage_bad
stage_bounds:
        mov bx,ds
        shr ax,4
        add bx,ax
        jc stage_bad
        cmp dx,bx
        jb stage_bad
        add ax,dx
        jc stage_bad
        cmp ax,0a000h
        ja stage_bad
        mov es,dx
        xor si,si
        xor di,di
        cld
        cmp bp,XCP_STAGE_RETARGET
        jne stage_compare
        ; The loader owns proof of the whole copied image; only peer metadata
        ; can be checked here without reading the overwritten old stage.
        cmp byte ptr es:[owner_query_active],0
        jne stage_bad
        cmp word ptr es:[bootstrap_stage_entry+2],0
        jne stage_bad
        cmp byte ptr es:[bootstrap_detached],0
        jne stage_bad
        cmp byte ptr es:[bootstrap_frozen],0
        jne stage_bad
        mov ax,[handle_limit]
        cmp es:[handle_limit],ax
        jne stage_bad
        mov ax,[extended_kb]
        cmp es:[extended_kb],ax
        jne stage_bad
        mov cx,18             ; same device header and entry offsets
stage_compare:
        repe cmpsb             ; reject stale/non-identical copies before writes
        jne stage_bad
        mov [bootstrap_stage_entry+2],dx
        mov [bootstrap_detached],1
        mov [bootstrap_frozen],0
        jmp short stage_good
stage_freeze:
        cmp word ptr [bootstrap_stage_entry+2],0
        je stage_bad
        cmp [bootstrap_frozen],0
        jne stage_bad
        mov [bootstrap_frozen],1
        jmp short stage_good
stage_restore:
        cmp [bootstrap_frozen],0
        jne stage_bad
        cmp dx,word ptr [bootstrap_stage_entry+2]
        jne stage_bad
        or dx,dx
        jz stage_bad
        mov es,dx
        cmp byte ptr es:[owner_query_active],0
        jne stage_bad          ; never restore a snapshot after high publication
        push ds
        pop es
        mov ds,dx
        mov si,offset bootstrap_owner_start
        mov di,si
        sub cx,si
        cld
        rep movsb
        mov word ptr es:[bootstrap_stage_entry+2],0
        mov byte ptr es:[bootstrap_detached],0
        mov byte ptr es:[bootstrap_frozen],0
stage_good:
        mov ax,XCP_LAYOUT_REPLY
        jmp short stage_done
stage_bad:
        xor ax,ax
stage_done:
        pop es
        pop ds
        pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        popf
        ret
bootstrap_admin_stage endp
