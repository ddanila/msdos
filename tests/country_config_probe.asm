; Verify that CONFIG.SYS loaded Germany (049) from COUNTRY.SYS.
;
; DOS INT 21h/AH=38h returns the active 16-bit country code in BX and
; the legacy country-information block at DS:DX.  Germany's COUNTRY.SYS
; record uses DMY dates, a period thousands separator, a comma decimal
; separator, and 24-hour time.

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
    cmp word [country_buffer + 0], 1 ; DMY date order
    jne fail
    cmp byte [country_buffer + 7], '.' ; thousands separator
    jne fail
    cmp byte [country_buffer + 9], ',' ; decimal separator
    jne fail
    cmp byte [country_buffer + 17], 1 ; 24-hour time
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
