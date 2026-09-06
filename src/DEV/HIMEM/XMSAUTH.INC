; Paired development front end. Import once, then all handle mutations execute
; at the installed high owner. Move fetches one transient record, never a
; refreshed low handle table. The packet names the original bootstrap table;
; no duplicate import buffer is retained. Local allocator bodies and records
; occupy one tail for the loader to reclaim after handoff.
private_bootstrap_layout proc far
        cmp cx,XCP_LAYOUT_SIGNATURE
        jne short bootstrap_layout_bad
        cmp si,XCP_LAYOUT_VERSION
        jne short bootstrap_layout_bad
        or di,di
        jne short bootstrap_layout_bad
        mov bx,offset bootstrap_owner_start
ifdef HIMEM_BOOTSTRAP_BAD_LAYOUT
        add bx,16             ; negative control: plausible but false boundary
endif
        mov si,offset handles
        mov di,cs:[handle_limit]
        mov ax,di
        imul ax,HANDLE_SIZE
        add ax,si
        add ax,15
        and ax,0fff0h
        mov cx,ax
        mov dx,cs
        mov ax,XCP_LAYOUT_REPLY
        iret
bootstrap_layout_bad:
        xor ax,ax
        iret
private_bootstrap_layout endp

ifdef HIMEM_BOOTSTRAP_STAGE_TEST
; Serialized boot-only owner switch. HMA/A20/UMB remain in the original front;
; only allocator services and their private move scratch use the complete copy.
private_bootstrap_stage proc far
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
        push cs
        pop ds
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
        cmp bp,XCP_STAGE_RESTORE
        je stage_restore
        cmp word ptr [bootstrap_stage_entry+2],0
        jne stage_bad
        mov bx,cs
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
        repe cmpsb             ; reject stale/non-identical copies before writes
        jne stage_bad
        mov [bootstrap_stage_entry+2],dx
        mov [bootstrap_detached],1
        jmp short stage_good
stage_restore:
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
        iret
private_bootstrap_stage endp

xms_stage_forward proc near
        push ds
        push si
        mov si,[caller_si]
        mov ds,[caller_ds]
        call dword ptr cs:[bootstrap_stage_entry]
        pop si
        pop ds
        ret
xms_stage_forward endp
endif

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
        jne short auth_send
        mov ax,[handle_limit]
        mov [owner_limit],ax
        mov ax,[extended_kb]
        mov [owner_pool],ax
        ; No local mutation is allowed after attempting ownership publication,
        ; including an ambiguous transport failure after the high commit.
        mov [owner_query_active],1
auth_send:
        mov word ptr [owner_packet],4158h ; XAUT
        mov word ptr [owner_packet+2],5455h
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp word ptr [bootstrap_stage_entry+2],0
        je auth_packet_ready
        ; The transport header and live records must share the staged segment.
        ; Keep using it after ambiguous failures until a successful response.
        mov es,word ptr [bootstrap_stage_entry+2]
        mov si,offset owner_packet
        mov di,si
        mov cx,20
        cld
        rep movsb
auth_packet_ready:
endif
        mov si,offset owner_packet
        mov ah,87h
        int 15h
        jc short auth_failed
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        mov ax,es:[owner_largest]
        mov bx,es:[owner_bx]
        mov dx,es:[owner_total]
        mov [owner_largest],ax
        mov [owner_bx],bx
        mov [owner_total],dx
        mov word ptr [bootstrap_stage_entry+2],0
        push ds
        pop es
endif
ifdef HIMEM_AUTHORITATIVE_POISON_TEST
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp [bootstrap_detached],0
        jne auth_poison_done    ; caller may already have overwritten that tail
endif
        ; Destroy the entire local allocator tail, including all code and
        ; selected records. No active frame may remain there at publication.
        mov di,offset bootstrap_owner_start
        mov cx,[handle_limit]
        imul cx,HANDLE_SIZE
        add cx,offset handles-offset bootstrap_owner_start
        mov al,0f4h
        cld
        rep stosb
auth_poison_done:
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
; resident front end supplies transient scratch, not a live table mirror.
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
        mov word ptr [owner_record_scratch+HANDLE_BASE],bx
        mov word ptr [owner_record_scratch+HANDLE_LENGTH],dx
        mov byte ptr [owner_record_scratch+HANDLE_LOCK],0 ; resolver never reads locks
        mov si,offset owner_record_scratch
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

; Public entries stay in the permanent prefix. Bootstrap bodies are reached
; only before high ownership is attempted and can then be discarded together.
XMS_FRONT macro entry_name, bootstrap_target, operation
        local local_owner
entry_name proc near
        push ax
        mov ax,operation
        call xms_remote_owned
        jc short local_owner
        add sp,2
        ret
local_owner:
        pop ax
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp word ptr [bootstrap_stage_entry+2],0
        je @F
        mov ah,operation
        call xms_stage_forward
        ret
@@:
endif
        jmp bootstrap_target
entry_name endp
endm
        XMS_FRONT xms_gate_query,xms_query_free,08h
        XMS_FRONT xms_gate_allocate,xms_allocate,09h
        XMS_FRONT xms_gate_free,xms_free,0ah
        XMS_FRONT xms_gate_lock,xms_lock,0ch
        XMS_FRONT xms_gate_unlock,xms_unlock,0dh
        XMS_FRONT xms_gate_info,xms_handle_info,0eh
        XMS_FRONT xms_gate_reallocate,xms_reallocate,0fh
