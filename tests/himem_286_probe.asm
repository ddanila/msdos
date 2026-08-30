bits 16
org 100h

    mov ax, 4300h
    int 2fh
    cmp al, 80h
    jne fail
    mov ax, 4310h
    int 2fh
    mov [entry], bx
    mov [entry+2], es

    xor ah, ah
    call far [entry]
    cmp ax, 0200h
    jne fail

    mov ah, 09h
    mov dx, 16
    call far [entry]
    cmp ax, 1
    jne fail
    mov [handle], dx

    mov ah, 0ch
    mov dx, [handle]
    call far [entry]
    cmp ax, 1
    jne release_fail
    mov ah, 0dh
    mov dx, [handle]
    call far [entry]
    cmp ax, 1
    jne release_fail

    mov ah, 0ah
    mov dx, [handle]
    call far [entry]
    cmp ax, 1
    jne fail
    mov dx, pass_message
    jmp short print

release_fail:
    mov ah, 0ah
    mov dx, [handle]
    call far [entry]
fail:
    mov dx, fail_message
print:
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

entry dd 0
handle dw 0
pass_message db 'HIMEM_286_PASS', 13, 10, '$'
fail_message db 'HIMEM_286_FAIL', 13, 10, '$'
