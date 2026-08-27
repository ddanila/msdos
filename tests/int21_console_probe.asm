bits 16
org 100h

; Focused contracts for console input paths. The QEMU wrapper redirects a
; deterministic byte stream to stdin while stdout remains on AUX/COM1.

start:
    push cs
    pop ds

    mov ah, 01h                    ; Character input with echo.
    int 21h
    cmp al, 'A'
    je input_01_ok
    mov dx, fail_01
    jmp fail
input_01_ok:

    mov ah, 07h                    ; Raw character input without echo/checking.
    int 21h
    cmp al, 'B'
    je input_07_ok
    mov dx, fail_07
    jmp fail
input_07_ok:

    mov ah, 08h                    ; Character input without echo.
    int 21h
    cmp al, 'C'
    je input_08_ok
    mov dx, fail_08
    jmp fail
input_08_ok:

    mov dl, '!'
    mov ah, 06h                    ; Direct console output returns the byte.
    int 21h
    cmp al, '!'
    je output_06_ok
    mov dx, fail_06
    jmp fail
output_06_ok:

    mov dx, first_buffer
    mov ah, 0ah                    ; Buffered input of FIRST.
    int 21h
    cmp byte [first_buffer + 1], 5
    jne buffered_0a_failed
    cmp byte [first_buffer + 2], 'F'
    jne buffered_0a_failed
    cmp byte [first_buffer + 3], 'I'
    je buffered_0a_ok
buffered_0a_failed:
    mov dx, fail_0a
    jmp fail
buffered_0a_ok:

    mov dx, second_buffer
    mov ax, 0c0ah                  ; Flush console input, then buffered read.
    int 21h
    cmp byte [second_buffer + 1], 6
    jne buffered_0c_failed
    cmp byte [second_buffer + 2], 'S'
    jne buffered_0c_failed
    cmp byte [second_buffer + 3], 'E'
    je buffered_0c_ok
buffered_0c_failed:
    mov dx, fail_0c
    jmp fail
buffered_0c_ok:

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

pass_message db 'INT21_CONSOLE_PASS', 13, 10, '$'
fail_01 db 'INT21_01_FAIL', 13, 10, '$'
fail_06 db 'INT21_06_FAIL', 13, 10, '$'
fail_07 db 'INT21_07_FAIL', 13, 10, '$'
fail_08 db 'INT21_08_FAIL', 13, 10, '$'
fail_0a db 'INT21_0A_FAIL', 13, 10, '$'
fail_0c db 'INT21_0C_FAIL', 13, 10, '$'
first_buffer db 16, 0
             times 17 db 0
second_buffer db 16, 0
              times 17 db 0
