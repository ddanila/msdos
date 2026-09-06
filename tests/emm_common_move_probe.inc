; Public Move must not use the old low endpoint/handle resolver.
check_common_public_move:
    mov es,[himem_segment]
    mov ax,[es:MOVE_RESOLVER_OFFSET]
    mov [pm_saved_resolver],ax
    mov word [es:MOVE_RESOLVER_OFFSET],0c3f9h ; STC; RET
    mov dx,1
    mov ah,9
    UMB_CALL
    cmp ax,1
    jne umb_failed
    mov [pm_handle],dx
    mov [pm_descriptor+10],dx
    mov ax,cs
    mov [pm_descriptor+8],ax
    call pm_move
    cmp ax,1
    jne umb_failed
    mov ax,[pm_handle]
    mov [pm_descriptor+4],ax
    mov dword [pm_descriptor+6],0
    mov word [pm_descriptor+10],0
    mov word [pm_descriptor+12],pm_dest
    mov ax,cs
    mov [pm_descriptor+14],ax
    call pm_move
    cmp ax,1
    jne umb_failed
    mov si,pm_source
    mov di,pm_dest
    mov cx,16
.compare:
    mov al,[si]
    cmp al,[di]
    jne umb_failed
    inc si
    inc di
    loop .compare
    mov word [pm_descriptor+4],0ffffh
    call pm_move
    mov dl,0a3h
    call pm_error
    mov ax,[pm_handle]
    mov [pm_descriptor+4],ax
    mov dword [pm_descriptor+6],1010
    call pm_move
    mov dl,0a7h
    call pm_error
    mov dword [pm_descriptor+6],0fffffff8h
    call pm_move
    mov dl,0a7h
    call pm_error
    mov dword [pm_descriptor+6],0
    mov ax,[pm_handle]
    mov [pm_descriptor+10],ax
    mov dword [pm_descriptor+12],0
    call pm_move               ; exact physical identity is allowed
    cmp ax,1
    jne umb_failed
    mov dword [pm_descriptor+12],2
    call pm_move               ; non-identical physical overlap is refused
    mov dl,8eh
    call pm_error
    mov word [pm_descriptor+10],0ffffh
    call pm_move
    mov dl,0a5h
    call pm_error
    mov dword [pm_descriptor],3
    call pm_move
    mov dl,0a7h
    call pm_error
    mov dword [pm_descriptor],0
    mov word [pm_descriptor+4],0ffffh
    call pm_move
    cmp ax,1
    jne umb_failed
    mov dx,[pm_handle]
    mov ah,0ah
    UMB_CALL
    cmp ax,1
    jne umb_failed
    mov es,[himem_segment]
    cmp word [es:MOVE_RESOLVER_OFFSET],0c3f9h
    jne umb_failed
    mov ax,[pm_saved_resolver]
    mov [es:MOVE_RESOLVER_OFFSET],ax
    mov dx,0e9h
    mov al,'P'
    out dx,al
    mov al,'M'
    out dx,al
    ret
pm_move:
    mov byte [pm_function],0bh
.run:
    mov si,pm_descriptor
    mov di,pm_saved_descriptor
    mov cx,16
.save:
    mov al,[si]
    mov [di],al
    inc si
    inc di
    loop .save
    mov si,pm_descriptor
    mov bx,1234h
    mov dx,5678h
    mov ah,[pm_function]
    UMB_CALL
    push ax
    mov si,pm_descriptor
    mov di,pm_saved_descriptor
    mov cx,16
.unchanged:
    mov al,[si]
    cmp al,[di]
    jne umb_failed
    inc si
    inc di
    loop .unchanged
    pop ax
    cmp dx,5678h
    jne umb_failed
    cmp ax,1
    jne .done
    cmp bx,1234h
    jne umb_failed
.done:
    cmp byte [pm_function],8bh
    je .alias_result
    mov [pm_result_ax],ax
    mov [pm_result_bx],bx
    mov byte [pm_function],8bh
    jmp .run
.alias_result:
    cmp ax,[pm_result_ax]
    jne umb_failed
    cmp bx,[pm_result_bx]
    jne umb_failed
    ret
pm_error:
    test ax,ax
    jnz umb_failed
    cmp bl,dl
    jne umb_failed
    ret
pm_handle dw 0
pm_function db 0
pm_result_ax dw 0
pm_result_bx dw 0
pm_saved_resolver dw 0
pm_saved_descriptor times 16 db 0
pm_descriptor dd 16
    dw 0,pm_source,0,0,0,0
pm_source db 'high move owner!'
    db 0
pm_dest times 16 db 0
