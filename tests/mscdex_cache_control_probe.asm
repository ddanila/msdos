bits 16
org 100h

start:
    mov ax, 1511h
    mov bx, 2
    int 2fh
    jc failed
    mov si, 81h
skip_spaces:
    cmp byte [si], ' '
    jne have_expected
    inc si
    jmp skip_spaces
have_expected:
    xor ax, ax
    mov al, [si]
    sub al, '0'
    cmp bx, ax
    jne failed
    mov dx, pass_message
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

failed:
    mov dx, fail_message
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

pass_message db 'MSCDEX_SMARTDRV_CACHE_PASS',13,10,'$'
fail_message db 'MSCDEX_SMARTDRV_CACHE_FAIL',13,10,'$'
