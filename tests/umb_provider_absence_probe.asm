bits 16
org 100h

start:
    mov ax, 5802h
    int 21h
    jc fail
    or al, al
    jnz fail

    mov bx, 1
    mov ax, 5803h
    int 21h
    jnc fail

    mov ax, 5802h
    int 21h
    jc fail
    or al, al
    jnz fail

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

fail:
    mov dx, fail_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

pass_message db 'UMB_PROVIDER_ABSENT_PASS', 13, 10, '$'
fail_message db 'UMB_PROVIDER_ABSENT_FAIL', 13, 10, '$'
