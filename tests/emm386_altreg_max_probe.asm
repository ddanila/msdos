bits 16
org 100h

    push ds
    pop es
    mov di, info
    mov ax, 5900h
    int 67h
    test ah, ah
    jnz fail
    cmp word [info+2], 254
    jne fail

    mov cx, 254
    mov dl, 1
.allocate:
    mov ax, 5b03h
    int 67h
    test ah, ah
    jnz fail
    cmp bl, dl
    jne fail
    inc dl
    loop .allocate

    mov ax, 5b03h
    int 67h
    cmp ah, 9bh
    jne fail

    mov si, released_sets
    mov cx, 3
.release:
    mov bl, [si]
    mov ax, 5b04h
    int 67h
    test ah, ah
    jnz fail
    inc si
    loop .release

    mov si, released_sets
    mov cx, 3
.reuse:
    mov ax, 5b03h
    int 67h
    test ah, ah
    jnz fail
    cmp bl, [si]
    jne fail
    inc si
    loop .reuse

    mov ax, 5b03h
    int 67h
    cmp ah, 9bh
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

released_sets db 1, 127, 254
info times 10 db 0
pass_message db 'EMM386_ALTREG_MAX_PASS', 13, 10, '$'
fail_message db 'EMM386_ALTREG_MAX_FAIL', 13, 10, '$'
