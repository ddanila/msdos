; Canonical local UMB state follows the staged image once the original tail
; is unavailable. Freeze/ownership checks must precede every staged-code read.
umb_local_call proc near
        pushf
        cli
        cmp [umb_remote_state],0
        jne umb_local_failed
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp [bootstrap_frozen],0
        jne umb_local_failed
endif
        push bp
        push ds
        sub sp,4
        mov bp,sp
        mov word ptr ss:[bp],offset bootstrap_umb_service
        push ds
        pop word ptr ss:[bp+2]
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp word ptr [bootstrap_stage_entry+2],0
        je umb_local_enter
        push word ptr [bootstrap_stage_entry+2]
        pop word ptr ss:[bp+2]
endif
umb_local_enter:
        mov ds,word ptr ss:[bp+2]
        call dword ptr ss:[bp]
        add sp,4
        pop ds
        pop bp
        popf
        clc
        ret
umb_local_failed:
        xor ax,ax
        mov bl,ERR_GENERAL
        popf
        clc
        ret
umb_local_call endp
