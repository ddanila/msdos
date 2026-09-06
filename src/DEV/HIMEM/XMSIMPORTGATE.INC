; Permanent entry inside xms_remote_owned. Bootstrap import code may execute
; from LAST scratch, but DS and the caller's return address remain low.
ifdef HIMEM_COMMON_OLD_HANDLE_TEST
        cmp ax,9
        je import_gate_bootstrap
endif
        call xms_common_handles_ready
        jc import_gate_bootstrap
        cmp ax,0bh
        jne import_gate_common
        mov ax,14h
import_gate_common:
        call xms_common_invoke
        ret
import_gate_bootstrap:
        pushf
        cli
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        ; The stage itself may be overwritten between freeze and retarget.
        ; This guard must execute in the permanent front, before any far call.
        cmp [bootstrap_frozen],0
        jne import_gate_failed
endif
        ; State 1 is an unknown publication, not permission to replay. State
        ; 2 cannot use bootstrap code again, even if binding later rejects.
        cmp [owner_query_active],0
        jne import_gate_failed
        push bp
        sub sp,4
        mov bp,sp
        mov word ptr ss:[bp],offset bootstrap_remote_owned
        push cs
        pop word ptr ss:[bp+2]
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp word ptr [bootstrap_stage_entry+2],0
        je import_gate_call
        push word ptr [bootstrap_stage_entry+2]
        pop word ptr ss:[bp+2]
endif
import_gate_call:
        call dword ptr ss:[bp]
        jc import_gate_call_unavailable
        add sp,4
        pop bp
ifdef HIMEM_AUTHORITATIVE_POISON_TEST
        cmp [owner_query_active],2
        jne import_gate_done
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp [bootstrap_detached],0
        jne import_gate_done
endif
        ; No frame remains in the original tail when it is poisoned here.
        push ax
        push es
        push ds
        pop es
        mov di,offset bootstrap_owner_start
        mov cx,[handle_limit]
        imul cx,HANDLE_SIZE
        add cx,offset handles-offset bootstrap_owner_start
        mov al,0f4h
        cld
        rep stosb
        pop es
        pop ax
endif
import_gate_done:
        popf
        clc
        ret
import_gate_failed:
        xor ax,ax
        xor dx,dx
        mov bl,ERR_GENERAL
        jmp short import_gate_done
import_gate_call_unavailable:
        add sp,4
        pop bp
import_gate_unavailable:
        popf
        stc
        ret
