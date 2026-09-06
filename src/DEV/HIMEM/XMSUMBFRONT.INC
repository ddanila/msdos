; Opt-in paired UMB front. DS is HIMEM; ES:SI is peer registration input.
; 0=local, 1=import attempted/unknown, 2=high committed. Once import is
; attempted there is no local fallback. Only an import can be resolved by a
; later receipt; failed mutating services are never replayed here.
ifndef HIMEM_AUTHORITATIVE_OWNER_TEST
        .err <UMB handoff requires the paired authoritative provider>
endif
umb_remote_state db 0
ifdef HIMEM_UMB_DEFER_TEST
; Test-only boot latch. The guest creates real public allocations under the
; original owner, then clears this latch before requesting normal handoff.
umb_remote_defer db 1
endif
umb_remote_busy db 0
umb_remote_op dw 0
umb_remote_dx dw 0
umb_remote_bx dw 0
umb_remote_packet db 'XUMB'
        dw 1,0,0,0,0,0,offset umb_count,MAX_UMB_BLOCKS

umb_gate_request proc near
ifdef HIMEM_UMB_HANDOFF_LOCAL_TEST
        cmp [umb_remote_state],2
        je xms_umb_request
endif
        mov ax,10h
        call umb_remote
        jnc umb_gate_done
        jmp xms_umb_request
umb_gate_request endp
umb_gate_release proc near
ifdef HIMEM_UMB_HANDOFF_LOCAL_TEST
        cmp [umb_remote_state],2
        je xms_umb_release
endif
        mov ax,11h
        call umb_remote
        jnc umb_gate_done
        jmp xms_umb_release
umb_gate_release endp
umb_gate_done:
        ret

umb_remote proc near
        pushf
        cli
        push cx
        push si
        push di
        push bp
        push es
        cmp [umb_remote_busy],0
        jne umb_remote_reentrant
        mov [umb_remote_busy],1
        mov [umb_remote_op],ax
        mov [umb_remote_dx],dx
        mov [umb_remote_bx],bx
ifdef HIMEM_UMB_DEFER_TEST
        cmp [umb_remote_defer],0
        jne umb_remote_unavailable
endif
        mov ax,XCP_QUERY
        int 15h
        cmp ax,XCP_REPLY
        jne umb_remote_unavailable
        cmp bx,XCP_SIGNATURE
        jne umb_remote_unavailable
        cmp cx,XCP_VERSION
        jne umb_remote_unavailable
        and dx,XCP_REQUIRED OR XCP_UMB_OWNER
        cmp dx,XCP_REQUIRED OR XCP_UMB_OWNER
        jne umb_remote_unavailable
        push es
        push si
        push ds
        pop es
        cmp [umb_remote_state],2
        je umb_remote_ready
        mov word ptr [umb_remote_packet+6],0
        call umb_remote_send
        jc umb_remote_prepare_failed
        cmp [umb_remote_state],1
        je umb_remote_confirm
        cmp word ptr [umb_remote_packet+10],0
        jne umb_remote_prepare_failed
        cmp word ptr [umb_remote_packet+14],0
        jne umb_remote_prepare_failed
        ; Freeze before attempting import, not after receiving its reply.
        mov [umb_remote_state],1
        mov word ptr [umb_remote_packet+6],1
        mov word ptr [umb_remote_packet+16],offset umb_count
        mov word ptr [umb_remote_packet+18],MAX_UMB_BLOCKS
        call umb_remote_send
        jc umb_remote_prepare_failed
umb_remote_confirm:
        cmp word ptr [umb_remote_packet+10],0
        jne umb_remote_confirm_high
        cmp word ptr [umb_remote_packet+14],0
        jne umb_remote_prepare_failed
        cmp word ptr [umb_remote_packet+12],0
        jne umb_remote_prepare_failed
        ; A read-only receipt proves the attempted import never published.
        ; Unfreeze the intact low owner, but do not replay the caller's service.
        mov [umb_remote_state],0
        jmp umb_remote_prepare_failed
umb_remote_confirm_high:
        cmp word ptr [umb_remote_packet+10],1
        jne umb_remote_prepare_failed
        cmp word ptr [umb_remote_packet+14],1
        jne umb_remote_prepare_failed
        mov ax,[umb_count]
        cmp word ptr [umb_remote_packet+12],ax
        jne umb_remote_prepare_failed
        mov [umb_remote_state],2
umb_remote_ready:
        pop si
        pop es
        cmp [umb_remote_op],12h
        jne umb_remote_service
        ; ES:SI is the trusted peer's version/count/ranges. Bound the complete
        ; input before copying into retired low storage. High validates ranges.
        cmp si,0fffch
        ja umb_peer_bad
        cmp word ptr es:[si],1
        jne umb_peer_bad
        mov cx,es:[si+2]
        cmp cx,MAX_UMB_BLOCKS
        ja umb_peer_bad
        shl cx,2
        add cx,4
        mov ax,si
        add ax,cx
        jnc umb_peer_extent_ok
        or ax,ax
        jnz umb_peer_bad
umb_peer_extent_ok:
        mov di,offset umb_peer_version
umb_peer_copy:
        mov al,es:[si]
        mov [di],al
        inc si
        inc di
        loop umb_peer_copy
        mov word ptr [umb_remote_packet+16],offset umb_peer_version
        mov word ptr [umb_remote_packet+18],MAX_UMB_BLOCKS
umb_remote_service:
        push ds
        pop es
        mov ax,[umb_remote_op]
        mov word ptr [umb_remote_packet+6],ax
        mov ax,[umb_remote_dx]
        mov word ptr [umb_remote_packet+12],ax
        mov ax,[umb_remote_bx]
        mov word ptr [umb_remote_packet+14],ax
        call umb_remote_send
        jc umb_remote_failed
        mov ax,word ptr [umb_remote_packet+10]
        mov dx,word ptr [umb_remote_packet+12]
        mov bx,word ptr [umb_remote_packet+14]
        jmp short umb_remote_handled
umb_peer_bad:
        xor ax,ax
        mov bl,1
        jmp short umb_remote_handled
umb_remote_prepare_failed:
        pop si
        pop es
umb_remote_failed:
        xor ax,ax
        mov dx,[umb_remote_dx]
        mov bl,ERR_GENERAL
umb_remote_handled:
        mov [umb_remote_busy],0
umb_remote_restore:
        pop es
        pop bp
        pop di
        pop si
        pop cx
        popf
        clc
        ret
umb_remote_reentrant:
        xor ax,ax
        mov bl,ERR_GENERAL
        jmp short umb_remote_restore
umb_remote_unavailable:
        cmp [umb_remote_state],0
        jne umb_remote_failed
        mov [umb_remote_busy],0
        mov bx,[umb_remote_bx]
        mov dx,[umb_remote_dx]
        pop es
        pop bp
        pop di
        pop si
        pop cx
        popf
        stc
        ret
umb_remote endp

umb_remote_send proc near
        mov si,offset umb_remote_packet
        mov ah,87h
        int 15h
        ret
umb_remote_send endp
