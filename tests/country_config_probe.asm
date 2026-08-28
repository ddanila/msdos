
bits 16
org 100h

start:
    push cs
    pop ds
    mov dx, country_buffer
    xor al, al
    mov ah, 38h
    int 21h
    jc fail

    cmp bx, 49
    jne fail
    cmp ax, 49
    jne fail
    cmp word [country_buffer + 0], 1
    jne fail
    cmp byte [country_buffer + 7], '.'
    jne fail
    cmp byte [country_buffer + 9], ','
    jne fail
    cmp byte [country_buffer + 17], 1
    jne fail

    mov dx, pass_message
    jmp print_and_exit

fail:
    mov dx, fail_message

print_and_exit:
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

pass_message db 'COUNTRY_CONFIG_PASS', 13, 10, '$'
fail_message db 'COUNTRY_CONFIG_FAIL', 13, 10, '$'
country_buffer times 34 db 0
