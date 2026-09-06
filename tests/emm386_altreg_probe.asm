bits 16
org 100h

    push ds
    pop es
    mov di, info
    mov ax, 5900h
    int 67h
    test ah, ah
    jnz fail
    cmp word [info+2], 2
    jne fail

    mov ax, 5b03h
    int 67h
    test ah, ah
    jnz fail
    mov [set1], bl
    mov ax, 5b03h
    int 67h
    test ah, ah
    jnz fail
    mov [set2], bl
    mov ax, 5b03h
    int 67h
    test ah, ah
    jz fail

    ; Descending and repeated selections must not inherit comparison carry.
    mov bl, [set2]
    mov ax, 5b01h
    int 67h
    test ah, ah
    jnz fail
    mov bl, [set1]
    mov ax, 5b01h
    int 67h
    test ah, ah
    jnz fail
    mov ax, 5b01h
    int 67h
    test ah, ah
    jnz fail
    mov ax, 5b00h
    int 67h
    test ah, ah
    jnz fail
    cmp bl, [set1]
    jne fail
    mov ax, 5b04h
    int 67h
    cmp ah, 9dh
    jne fail
    ; Return to internal set zero, with no external restore buffer.
    xor bx, bx
    mov es, bx
    xor di, di
    mov ax, 5b01h
    int 67h
    test ah, ah
    jnz fail

    mov bl, [set1]
    mov ax, 5b04h
    int 67h
    test ah, ah
    jnz fail
    mov bl, [set2]
    mov ax, 5b04h
    int 67h
    test ah, ah
    jnz fail
    mov bl, [set2]
    mov ax, 5b04h
    int 67h
    cmp ah, 9dh
    jne fail
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

set1 db 0
set2 db 0
info times 10 db 0
pass_message db 'EMM386_ALTREG_LIMIT_PASS', 13, 10, '$'
fail_message db 'EMM386_ALTREG_LIMIT_FAIL', 13, 10, '$'
