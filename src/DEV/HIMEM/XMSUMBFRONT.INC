; Opt-in paired UMB front. DS is HIMEM; ES:SI is peer registration input.
; 0=local, 1=import attempted/unknown, 2=high committed; optional v2 state 3
; freezes subsequent calls when a service result cannot be confirmed. Import
; receipts may prove non-commit; v2 service receipts recover saved results or
; prove non-execution. Mutations are never replayed. Unknown service outcomes
; retain the pending packet and never permit low fallback.
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
ifdef HIMEM_UMB_RESULTS_TEST
ifdef HIMEM_UMB_SEQUENCE_WRAP_TEST
umb_remote_sequence dd 0fffffffeh
else
umb_remote_sequence dd 0
endif
umb_remote_recovered dw 0
umb_remote_not_executed dw 0
endif
umb_remote_packet db 'XUMB'
ifdef HIMEM_UMB_RESULTS_TEST
        dw 2
else
        dw 1
endif
        dw 0,0,0,0,0,offset umb_count,MAX_UMB_BLOCKS
ifdef HIMEM_UMB_RESULTS_TEST
        dd 0                    ; requested service sequence, separate from confirmed
endif

umb_gate_request proc near
ifdef HIMEM_UMB_HANDOFF_LOCAL_TEST
        cmp [umb_remote_state],2
        je xms_umb_request
endif
        mov ax,10h
        call umb_remote
        jnc umb_gate_done
ifdef HIMEM_COMMON_XMS_TEST
        mov ax,10h
        jmp umb_local_call
else
        jmp xms_umb_request
endif
umb_gate_request endp
umb_gate_release proc near
ifdef HIMEM_UMB_HANDOFF_LOCAL_TEST
        cmp [umb_remote_state],2
        je xms_umb_release
endif
        mov ax,11h
        call umb_remote
        jnc umb_gate_done
ifdef HIMEM_COMMON_XMS_TEST
        mov ax,11h
        jmp umb_local_call
else
        jmp xms_umb_release
endif
umb_gate_release endp
umb_gate_done:
        ret

ifdef HIMEM_COMMON_XMS_TEST
; Permanent rejection must precede any access to the disposable import body.
umb_remote proc near
        pushf
        cli
        cmp [umb_remote_state],2
        jae umb_import_gate_failed
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp [bootstrap_frozen],0
        jne umb_import_gate_failed
endif
        push bp
        sub sp,4
        mov bp,sp
        mov word ptr ss:[bp],offset bootstrap_umb_import
        push ds
        pop word ptr ss:[bp+2]
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp word ptr [bootstrap_stage_entry+2],0
        je umb_import_gate_call
        push word ptr [bootstrap_stage_entry+2]
        pop word ptr ss:[bp+2]
endif
umb_import_gate_call:
        call dword ptr ss:[bp]
        jc umb_import_gate_unavailable
        add sp,4
        pop bp
        popf
        clc
        ret
umb_import_gate_unavailable:
        add sp,4
        pop bp
        popf
        stc
        ret
umb_import_gate_failed:
        xor ax,ax
        mov bl,ERR_GENERAL
        popf
        clc
        ret
umb_remote endp
else
        include XMSUMBIMPORT.INC
endif
ifdef HIMEM_UMB_RESULTS_TEST
umb_next_sequence proc near
        mov ax,word ptr [umb_remote_sequence]
        mov dx,word ptr [umb_remote_sequence+2]
        add ax,1
        adc dx,0
        mov cx,ax
        or cx,dx
        jnz umb_sequence_ready
        inc ax                  ; reserve zero, including after FFFFFFFF
umb_sequence_ready:
        ret
umb_next_sequence endp
endif
