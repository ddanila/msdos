; One initialization transaction: publish the complete upper data owner, then
; shrink the old resident allocation. No second live low copy is retained.
; Called at DRV0, before ENDINIT releases the memory covering initialization.
shell_data_allocation dw 0
shell_data_strategy dw 0
shell_data_link db 0

relocate_shell_data proc near
        pushf
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push ds
        push es
        push cs
        pop ds
        cmp byte ptr [shell_high_active],1
        jne shell_data_done
        mov ah,62h
        int 21h
        mov ax,cs
        cmp bx,ax
        jne shell_data_done          ; the allocation owner must be this PSP
        mov ax,5800h
        int 21h
        jc shell_data_done
        mov [shell_data_strategy],ax
        mov ax,5802h
        int 21h
        jc shell_data_done
        mov [shell_data_link],al
        mov ax,5803h
        mov bx,1
        int 21h
        jc shell_data_restore_policy
        mov ax,5801h
        mov bx,40h                  ; upper only, never consume conventional RAM
        int 21h
        jc shell_data_restore_policy
        mov bx,offset resgroup:shell_data_end
        mov dx,offset resgroup:shell_data_start
        and dx,0fff0h
        sub bx,dx
        add bx,15
        shr bx,1
        shr bx,1
        shr bx,1
        shr bx,1
        mov ah,48h
        int 21h
        jc shell_data_restore_policy
        mov [shell_data_allocation],ax
shell_data_restore_policy:
        mov bx,[shell_data_strategy]
        mov ax,5801h
        int 21h
        xor bx,bx
        mov bl,[shell_data_link]
        mov ax,5803h
        int 21h
        ; Restore policy before publication, including when no UMB was found.
        mov ax,5800h
        int 21h
        jc shell_data_free
        cmp ax,[shell_data_strategy]
        jne shell_data_free
        mov ax,5802h
        int 21h
        jc shell_data_free
        cmp al,[shell_data_link]
        jne shell_data_free
        mov ax,[shell_data_allocation]
        or ax,ax
        jz shell_data_done
        cmp ax,0a000h
        jb shell_data_free

        cli
        mov ax,[shell_data_allocation]
        mov es,ax
        mov dx,offset resgroup:shell_data_start
        mov di,dx
        and di,15
        shr dx,1
        shr dx,1
        shr dx,1
        shr dx,1
        sub ax,dx
        mov [MYDATASEG],ax
        mov si,offset resgroup:shell_data_start
        mov cx,offset resgroup:shell_data_end
        sub cx,si
        cld
        rep movsb
        call shell_data_publish
        push cs
        pop es
        mov bx,offset resgroup:shell_data_start+15
        shr bx,1
        shr bx,1
        shr bx,1
        shr bx,1
        mov ah,4ah
        int 21h
        jc shell_data_rollback
        cli
IFDEF COMMAND_HIGH_RESIDENT_POISON
        ; The new free MCB occupies the first paragraph after the break.
        ; Preserve that allocator-owned header while invalidating old payload.
        mov di,offset resgroup:shell_data_start+15
        and di,0fff0h
        add di,16
        mov cx,offset resgroup:shell_data_end
        sub cx,di
        mov al,0a5h
        cld
        rep stosb
ENDIF
        jmp short shell_data_done

shell_data_rollback:
        cli
        ; Shrink rejection leaves the old allocation intact. Copy back live
        ; state before restoring its bindings; do not resurrect a stale mirror.
        mov ax,[MYDATASEG]
        mov ds,ax
        push cs
        pop es
        mov si,offset resgroup:shell_data_start
        mov di,si
        mov cx,offset resgroup:shell_data_end
        sub cx,si
        cld
        rep movsb
        push cs
        pop ds
        mov ax,cs
        mov [MYDATASEG],ax
        call shell_data_publish
shell_data_free:
        cmp word ptr [shell_data_allocation],0
        je shell_data_recover_policy
        mov es,[shell_data_allocation]
        mov ah,49h
        int 21h
        jc shell_data_policy_fatal
        mov word ptr [shell_data_allocation],0
shell_data_recover_policy:
        ; One bounded cleanup retry, after abandoning the upper-data move.
        ; Read back both values: a carry result alone does not describe state.
        mov bx,[shell_data_strategy]
        mov ax,5801h
        int 21h
        xor bx,bx
        mov bl,[shell_data_link]
        mov ax,5803h
        int 21h
        mov ax,5800h
        int 21h
        jc shell_data_policy_fatal
        cmp ax,[shell_data_strategy]
        jne shell_data_policy_fatal
        mov ax,5802h
        int 21h
        jc shell_data_policy_fatal
        cmp al,[shell_data_link]
        jne shell_data_policy_fatal
        jmp short shell_data_done
shell_data_policy_fatal:
        ; Global allocator state or temporary-owner cleanup is unconfirmed.
        ; Do not enter AUTOEXEC with an unknown allocation domain/link state.
        mov dx,offset resgroup:shell_data_policy_message
        mov ah,09h
        int 21h
shell_data_policy_stop:
        sti
        hlt
        jmp short shell_data_policy_stop
shell_data_done:
        pop es
        pop ds
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        popf
        ret
relocate_shell_data endp
shell_data_policy_message db 13,10,'COMMAND memory-policy recovery failed. Restart required.',13,10,'$'

; AX is the biased data selector. Existing PSP/stack/code identities stay low.
shell_data_publish proc near
        push bx
        push di
        push es
        mov bx,0ffffh
        mov es,bx
        mov bx,[shell_high_destination]
        sub bx,offset resgroup:shell_service_start
SHELL_DATA_BIND MACRO slot
        mov di,offset resgroup:shell_binding_&slot
        add di,bx
        mov word ptr es:[di],ax
ENDM
        SHELL_DATA_BIND fatal_ds
        SHELL_DATA_BIND ret2e_ds
        SHELL_DATA_BIND int2e_es
        SHELL_DATA_BIND lodcom_ds
        SHELL_DATA_BIND lodcom_data
        SHELL_DATA_BIND headfix_ds
        SHELL_DATA_BIND savhand_es
        SHELL_DATA_BIND endinit_env_state
        SHELL_DATA_BIND endinit_flag_state
        SHELL_DATA_BIND exec_err_ds
        SHELL_DATA_BIND exec_msg_es
        SHELL_DATA_BIND exec_pre_ds
        SHELL_DATA_BIND exec_post_ds
        SHELL_DATA_BIND exec_wait_ds
        SHELL_DATA_BIND critical_ds
        SHELL_DATA_BIND contc_entry_ds
        SHELL_DATA_BIND contc_body_ds
        SHELL_DATA_BIND pipeoff_ds
        SHELL_DATA_BIND diskmsg_ds
        pop es
        pop di
        pop bx
        ret
shell_data_publish endp
