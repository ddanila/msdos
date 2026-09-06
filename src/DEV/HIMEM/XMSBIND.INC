; Shared transport binding for the common-core candidate. Bootstrap can still
; discover the old unbound transport. Once bound, never adopt another entry or
; fall back through the interrupt chain after a failed bound call.
; DS selects the front; callers serialize publication with interrupts excluded.
xms_bound_entry dd 0
xms_bound_features dw 0
public xms_common_query, xms_common_send
xms_common_query proc near
        push es
        push di
        push si
ifndef HIMEM_BIND_ALWAYS_DISCOVER_TEST
        cmp word ptr [xms_bound_entry+2],0
        jne bound_query_cached
endif
        mov ax,XCP_BIND_QUERY
        int 15h
        cmp ax,XCP_REPLY
        jne bound_query_bootstrap
        cmp bx,XCP_SIGNATURE
        jne bound_query_bootstrap
        cmp cx,XCP_VERSION
        jne bound_query_bootstrap
        mov ax,dx
        and ax,XCP_REQUIRED OR XCP_OWNER_ACTIVE OR XCP_OWNER_RECEIPT OR XCP_UMB_OWNER OR XCP_UMB_RESULTS OR XCP_PUBLIC_MOVE OR XCP_COMMON_FRAME
        cmp ax,XCP_REQUIRED OR XCP_OWNER_ACTIVE OR XCP_OWNER_RECEIPT OR XCP_UMB_OWNER OR XCP_UMB_RESULTS OR XCP_PUBLIC_MOVE OR XCP_COMMON_FRAME
        jne bound_query_bootstrap
        mov ax,es
        or ax,ax
        jz bound_query_bootstrap
        cmp ax,0a000h
        jae bound_query_bootstrap
        mov [xms_bound_features],dx
        mov word ptr [xms_bound_entry],di
        mov word ptr [xms_bound_entry+2],ax ; publish only after fields are ready
bound_query_cached:
        mov ax,XCP_REPLY
        mov bx,XCP_SIGNATURE
        mov cx,XCP_VERSION
        mov dx,[xms_bound_features]
        jmp short bound_query_done
bound_query_bootstrap:
        mov ax,XCP_QUERY
        int 15h
bound_query_done:
        pop si
        pop di
        pop es
        ret
xms_common_query endp

xms_common_send proc near
        cmp word ptr [xms_bound_entry+2],0
        je bound_send_bootstrap
        pushf
        call dword ptr [xms_bound_entry]
        ret
bound_send_bootstrap:
        int 15h
        ret
xms_common_send endp
