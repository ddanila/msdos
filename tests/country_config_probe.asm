
bits 16
org 100h

%ifndef COUNTRY_ID
%define COUNTRY_ID 49
%endif

start:
    push cs
    pop ds
    mov dx, country_buffer
    xor al, al
    mov ah, 38h
    int 21h
    jc fail

    cmp bx, COUNTRY_ID
    jne fail
    cmp ax, COUNTRY_ID
    jne fail
%if COUNTRY_ID = 49
    cmp word [country_buffer + 0], 1
    jne fail
    cmp byte [country_buffer + 7], '.'
    jne fail
    cmp byte [country_buffer + 9], ','
    jne fail
    cmp byte [country_buffer + 17], 1
    jne fail
%endif

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
