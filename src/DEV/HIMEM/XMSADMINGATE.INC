; SYSINIT owns this immutable code image until the gate has been revoked.
admin_state db 0              ; 0=uninstalled, 1=bound, 2=revoked
admin_entry dw offset bootstrap_admin,0
umb_boot_import_tries db 0
ifdef HIMEM_UMB_DEFER_TEST
umb_boot_first dw 0
umb_boot_second dw 0
umb_boot_before dw 0
umb_boot_synthetic db 0
umb_boot_registration dw 1,2,0a000h,10h,0b000h,20h
endif

private_bootstrap_admin proc far
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
        jne admin_gate_bad
        cmp si,XCP_LAYOUT_VERSION
        jne admin_gate_bad
        or di,di
        jne admin_gate_bad
        cmp [admin_state],2
        jne admin_gate_live
        cmp ax,XCP_ADMIN_ABORT
        jne admin_gate_bad
        mov ax,XCP_LAYOUT_REPLY
        jmp admin_gate_done
admin_gate_live:
        mov bp,ax
        cmp [admin_state],0
        jne admin_gate_bound
        cmp ax,XCP_ADMIN_PREPARE
        jne admin_gate_bad
        cmp [owner_query_active],0
        jne admin_gate_bad
ifdef HIMEM_BOOTSTRAP_STAGE_TEST
        cmp word ptr [bootstrap_stage_entry+2],0
        jne admin_gate_bad
endif
        push ds
        pop word ptr [admin_entry+2]
        call dword ptr [admin_entry]
        cmp ax,XCP_LAYOUT_REPLY
        je admin_gate_done
        mov word ptr [admin_entry+2],0
        jmp short admin_gate_done
admin_gate_bound:
        cmp ax,XCP_ADMIN_PREPARE
        je admin_gate_bad
        call dword ptr [admin_entry]
        cmp ax,XCP_LAYOUT_REPLY
        jne admin_gate_done
        cmp bp,XCP_BOOTSTRAP_FINISH
        je admin_gate_revoke
        cmp bp,XCP_ADMIN_ABORT
        je admin_gate_revoke
        cmp bp,XCP_STAGE_RESTORE
        jne admin_gate_done
admin_gate_revoke:
        mov [admin_state],2
        mov word ptr [admin_entry+2],0
        jmp short admin_gate_done
admin_gate_bad:
        xor ax,ax
admin_gate_done:
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
private_bootstrap_admin endp
