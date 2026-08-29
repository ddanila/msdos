bits 16
org 100h

start:
    mov ax, 4800h
    int 2fh
    cmp ax, 0aa02h
    jne fail_install
    mov dx, installed
    call print

    mov dx, input_buffer
    mov ax, 4810h
    int 2fh
    test ax, ax
    jnz fail_input
    mov dx, first_prefix
    call print
    call print_buffer

    mov dx, input_buffer
    mov byte [input_buffer+1], 0
    mov ax, 4810h
    int 2fh
    test ax, ax
    jnz fail_input
    mov dx, second_prefix
    call print
    call print_buffer

    mov dx, input_buffer
    mov byte [input_buffer+1], 0
    mov ax, 4810h
    int 2fh
    test ax, ax
    jnz fail_input
    mov dx, third_prefix
    call print
    call print_buffer

    mov dx, input_buffer
    mov byte [input_buffer+1], 0
    mov ax, 4810h
    int 2fh
    test ax, ax
    jnz fail_input
    mov dx, fourth_prefix
    call print
    call print_buffer

    mov dx, passed
    call print
    mov ax, 4c00h
    int 21h

print_buffer:
    xor cx, cx
    mov cl, [input_buffer+1]
    mov si, input_buffer+2
.loop:
    jcxz .done
    lodsb
    mov dl, al
    mov ah, 02h
    int 21h
    loop .loop
.done:
    mov dx, crlf
    jmp print

fail_install:
    mov dx, bad_install
    jmp fail
fail_input:
    mov dx, bad_input
fail:
    call print
    mov ax, 4c01h
    int 21h
print:
    mov ah, 09h
    int 21h
    ret

input_buffer db 127, 0, 128 dup(0)
installed    db 'DOSKEY_4800_PASS',13,10,'$'
first_prefix db 'DOSKEY_FIRST=[','$'
second_prefix db 'DOSKEY_SECOND=[','$'
third_prefix db 'DOSKEY_THIRD=[','$'
fourth_prefix db 'DOSKEY_FOURTH=[','$'
crlf         db ']',13,10,'$'
passed       db 'DOSKEY_PROBE_PASS',13,10,'$'
bad_install  db 'DOSKEY_4800_FAIL',13,10,'$'
bad_input    db 'DOSKEY_4810_FAIL',13,10,'$'
