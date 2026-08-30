bits 16
org 100h

    mov bx, 1
    mov ah, 43h
    int 67h
    test ah, ah
    jnz fail
    mov [handle], dx

    mov bx, 1
    mov ah, 43h
    int 67h
    cmp ah, 85h
    jne fail

    mov dx, [handle]
    mov ah, 45h
    int 67h
    test ah, ah
    jnz fail
    mov dx, pass_message
    jmp short print
fail:
    mov dx, fail_message
print:
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

handle dw 0
pass_message db 'EMM386_HANDLE_LIMIT_PASS', 13, 10, '$'
fail_message db 'EMM386_HANDLE_LIMIT_FAIL', 13, 10, '$'
