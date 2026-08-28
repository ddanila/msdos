bits 16
org 100h

start:
    push cs
    pop ds
    mov ax, 4300h
    int 2fh
    cmp al, 80h
    jne fail
    mov ax, 4310h
    int 2fh
    mov [xms_entry], bx
    mov [xms_entry + 2], es
    mov ah, 0f0h
    call far [xms_entry]
    or ax, ax
    jnz fail
    or bx, bx
    jnz fail
    mov bx, 1
    mov ax, 5803h
    int 21h
    jnc fail
    cmp ax, 1
    jne fail
    mov dx, pass_message
    mov cx, pass_message_end - pass_message
    jmp short print_and_exit
fail:
    mov dx, fail_message
    mov cx, fail_message_end - fail_message
print_and_exit:
    mov bx, 1
    mov ah, 40h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

xms_entry dd 0
pass_message db 'XMS_UMB_DISABLED_PASS', 13, 10
pass_message_end:
fail_message db 'XMS_UMB_DISABLED_FAIL', 13, 10
fail_message_end:
