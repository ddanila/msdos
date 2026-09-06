; Shared steady-state frame and outcome handling. Bootstrap imports and their
; fallback bodies are separate; availability never grants a local fallback
; after an unknown common mutation. DS is the permanent front.
common_busy db 0
common_packet db 'XAPI'
        dw 2,0,0,0,0,0,0,0
        dd 0
; One mutually exclusive input snapshot: Move descriptor or peer registration.
; Never borrow the retired bootstrap UMB table after ownership commits.
        db (4+MAX_UMB_BLOCKS*UMB_BLOCK_SIZE) dup (0)
xms_common_ready proc near
ifdef HIMEM_BIND_ALWAYS_DISCOVER_TEST
        push ax
        push bx
        push cx
        push dx
        call xms_common_query
        cmp ax,XCP_REPLY
        pop dx
        pop cx
        pop bx
        pop ax
        jne common_not_ready
endif
        cmp word ptr [xms_bound_entry+2],0
        je common_not_ready
        cmp [owner_query_active],0
        je common_not_ready
        cmp [umb_remote_state],2
        jb common_not_ready
        clc
        ret
common_not_ready:
        stc
        ret
xms_common_ready endp

; AX=service, BX/DX inputs. Caller bindings are captured by xms_control;
; the peer wrapper has already staged its bounded registration input.
; CF always clear (handled), including errors: never retry a mutation low.
xms_common_invoke proc near
        pushf
        cli
        push cx
        push si
        push di
        push bp
        push es
        cmp [common_busy],0
        jne common_busy_error
        cmp [umb_remote_state],3
        je common_busy_error
        mov [common_busy],1
        mov di,ax
        mov bp,dx
        mov word ptr [common_packet+6],ax
        mov word ptr [common_packet+12],dx
        mov word ptr [common_packet+14],bx
        mov word ptr [common_packet+16],0
        mov word ptr [common_packet+18],0
        cmp ax,12h
        jne common_move_input
        mov word ptr [common_packet+16],offset common_packet+24
        mov word ptr [common_packet+18],MAX_UMB_BLOCKS
common_move_input:
        cmp di,0bh
        jne common_sequence
        mov si,[caller_si]
        cmp si,65536-16
        ja common_descriptor_bad
        mov es,[caller_ds]
        push di
        mov di,offset common_packet+24
        mov cx,16
common_snapshot:
        mov al,es:[si]
        mov [di],al
        inc si
        inc di
        loop common_snapshot
        pop di
        mov word ptr [common_packet+16],offset common_packet+24
        mov word ptr [common_packet+18],16
common_sequence:
        xor ax,ax
        xor dx,dx
        call common_readonly
        je common_sequence_ready
        call umb_next_sequence
common_sequence_ready:
        mov word ptr [common_packet+20],ax
        mov word ptr [common_packet+22],dx
        call common_send
        jc common_recover
        cmp word ptr [common_packet+8],1
        je common_confirm
common_recover:
        call common_readonly
        je common_failed
        mov word ptr [common_packet+6],2
        call common_send
        mov word ptr [common_packet+6],di ; keep pending operation identifiable
        jc common_unknown
        cmp word ptr [common_packet+8],1
        je common_recovered
        cmp word ptr [common_packet+8],0
        jne common_unknown
        call common_check_sequence
        jne common_unknown
        inc [umb_remote_not_executed]
        jmp short common_failed
common_recovered:
        inc [umb_remote_recovered]
common_confirm:
        call common_readonly
        je common_result
        call common_check_sequence
        jne common_unknown
        mov word ptr [umb_remote_sequence],ax
        mov word ptr [umb_remote_sequence+2],dx
common_result:
        mov ax,word ptr [common_packet+10]
        mov dx,word ptr [common_packet+12]
        mov bx,word ptr [common_packet+14]
        jmp short common_done
common_unknown:
ifndef HIMEM_UMB_RESULTS_NO_FREEZE_TEST
        mov [umb_remote_state],3
endif
common_failed:
        xor ax,ax
        mov bl,ERR_GENERAL
        mov dx,bp
        jmp short common_done
common_descriptor_bad:
        xor ax,ax
        mov bl,ERR_BAD_LENGTH
        mov dx,bp
common_done:
        mov [common_busy],0
common_return:
        pop es
        pop bp
        pop di
        pop si
        pop cx
        popf
        clc
        ret
common_busy_error:
        xor ax,ax
        mov bl,ERR_GENERAL
        jmp short common_return
xms_common_invoke endp
common_readonly proc near
        cmp di,8
        je @F
        cmp di,0eh
        je @F
        cmp di,14h
@@:
        ret
common_readonly endp
common_check_sequence proc near
        call umb_next_sequence
        cmp ax,word ptr [common_packet+20]
        jne @F
        cmp dx,word ptr [common_packet+22]
@@:
        ret
common_check_sequence endp
common_send proc near
        mov word ptr [common_packet+8],0
        push ds
        pop es
        mov si,offset common_packet
        mov ah,87h
        call xms_common_send
        ret
common_send endp

; Peer registration preserves its public wrapper and uses the same frame.
; Reject pending/reentrant calls before replacing any staged peer bytes.
xms_common_peer proc near
        pushf
        cli
        cmp [common_busy],0
        jne common_peer_busy
        cmp [umb_remote_state],3
        je common_peer_busy
        cmp ax,12h
        jne common_peer_invoke
        cmp si,65536-4
        ja common_peer_bad
        cmp word ptr es:[si],1
        jne common_peer_bad
        mov cx,es:[si+2]
        cmp cx,MAX_UMB_BLOCKS
        ja common_peer_bad
        shl cx,2
        add cx,4
        mov di,si
        add di,cx
        jnc common_peer_extent
        jnz common_peer_bad
common_peer_extent:
        mov di,offset common_packet+24
common_peer_copy:
        mov al,es:[si]
        mov [di],al
        inc di
        inc si
        loop common_peer_copy
        mov ax,12h
common_peer_invoke:
        call xms_common_invoke
        popf
        ret
common_peer_bad:
        xor ax,ax
        mov bl,1
        popf
        ret
common_peer_busy:
        xor ax,ax
        mov bl,ERR_GENERAL
        popf
        ret
xms_common_peer endp
