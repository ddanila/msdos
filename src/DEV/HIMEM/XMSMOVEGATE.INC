; The local Move implementation belongs to the bootstrap tail. Never enter
; that tail after handle publication: it may already contain the moved EMM.
xms_move proc near
        push bx
        push dx
        mov ax,8
        call xms_remote_owned
        jc move_gate_local
        call xms_common_handles_ready
        jc move_gate_failed
move_gate_high:
        pop dx
        pop bx
ifdef HIMEM_COMMON_LOW_MOVE_TEST
        ; The retired path is unavailable, not executable resident storage.
        xor ax,ax
        mov bl,ERR_GENERAL
        ret
else
        mov ax,0bh
        call xms_common_invoke
        ret
endif
move_gate_local:
        pop dx
        pop bx
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp word ptr [bootstrap_stage_entry+2],0
        je @F
        mov ah,0bh
        call xms_stage_forward
        ret
@@:
endif
        jmp bootstrap_move
move_gate_failed:
        pop dx
        pop bx
        xor ax,ax
        mov bl,ERR_GENERAL
        ret
xms_move endp
