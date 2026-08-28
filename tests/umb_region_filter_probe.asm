bits 16
org 100h

start:
    push cs
    pop ds

    mov ax, 5808h
    mov bx, 1111h
    int 21h
    jnc fail
    cmp ax, 1
    jne fail

    call signed_get_filter
    jc fail
    cmp ax, 0ffffh
    jne fail

    mov bx, 1
    mov ax, 5803h
    int 21h
    jc fail

    mov bx, 0040h
    mov ax, 5801h
    int 21h
    jc fail

    mov bx, 0001h
    call signed_set_filter
    jc fail
    mov bx, 10h
    mov ah, 48h
    int 21h
    jc fail
    cmp ax, 09001h
    jne fail
    mov es, ax
    mov ah, 49h
    int 21h
    jc fail

    mov bx, 1
    call signed_get_region_info
    jc fail
    cmp ax, 01feh
    jne fail
    mov bx, 1
    call signed_get_region_start
    jc fail
    cmp ax, 09000h
    jne fail
    mov bx, 1
    call signed_get_region_end
    jc fail
    cmp ax, 09200h
    jne fail
    mov bx, 2
    call signed_get_region_start
    jc fail
    cmp ax, 09400h
    jne fail
    mov bx, 2
    call signed_get_region_end
    jc fail
    cmp ax, 09500h
    jne fail
    call signed_get_hma_state
    jc fail
    or ax, ax
    jnz fail
    mov bx, 1
    call signed_get_region_limit
    jc fail
    cmp ax, 0ffffh
    jne fail
    mov bx, 1
    mov dx, 20h
    call signed_set_region_limit
    jc fail
    mov bx, 21h
    mov ah, 48h
    int 21h
    jnc fail
    cmp ax, 8
    jne fail
    cmp bx, 20h
    jne fail
    mov bx, 20h
    mov ah, 48h
    int 21h
    jc fail
    cmp ax, 09001h
    jne fail
    mov es, ax
    mov ah, 49h
    int 21h
    jc fail
    mov bx, 1
    mov dx, 0ffffh
    call signed_set_region_limit
    jc fail

    mov bx, 0002h
    call signed_set_filter
    jc fail
    mov bx, 10h
    mov ah, 48h
    int 21h
    jc fail
    cmp ax, 09401h
    jne fail
    mov es, ax
    mov ah, 49h
    int 21h
    jc fail

    xor bx, bx
    call signed_set_filter
    jc fail
    mov bx, 1
    mov ah, 48h
    int 21h
    jnc fail
    cmp ax, 8
    jne fail
    or bx, bx
    jne fail

    mov bx, 0ffffh
    call signed_set_filter
    jc fail
    xor bx, bx
    mov ax, 5801h
    int 21h
    jc fail

    mov dx, pass_message
    jmp short print_and_exit

signed_set_filter:
    mov cx, 4d55h
    mov si, 2142h
    mov di, 0a55ah
    mov ax, 5807h
    int 21h
    ret

signed_get_filter:
    mov cx, 4d55h
    mov si, 2142h
    mov di, 0a55ah
    mov ax, 5808h
    int 21h
    ret

signed_get_region_info:
    mov cx, 4d55h
    mov si, 2142h
    mov di, 0a55ah
    mov ax, 5809h
    int 21h
    ret

signed_set_region_limit:
    mov cx, 4d55h
    mov si, 2142h
    mov di, 0a55ah
    mov ax, 580ah
    int 21h
    ret

signed_get_region_limit:
    mov cx, 4d55h
    mov si, 2142h
    mov di, 0a55ah
    mov ax, 580bh
    int 21h
    ret

signed_get_region_start:
    mov cx, 4d55h
    mov si, 2142h
    mov di, 0a55ah
    mov ax, 580ch
    int 21h
    ret

signed_get_region_end:
    mov cx, 4d55h
    mov si, 2142h
    mov di, 0a55ah
    mov ax, 580dh
    int 21h
    ret

signed_get_hma_state:
    mov cx, 4d55h
    mov si, 2142h
    mov di, 0a55ah
    mov ax, 580eh
    int 21h
    ret

fail:
    mov dx, fail_message
print_and_exit:
    push cs
    pop ds
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

pass_message db 'UMB_REGION_FILTER_PASS', 13, 10, '$'
fail_message db 'UMB_REGION_FILTER_FAIL', 13, 10, '$'
