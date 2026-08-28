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
