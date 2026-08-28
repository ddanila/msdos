bits 16
org 100h

start:
    push cs
    pop ds
    mov ax, 0e700h
    int 2fh
    cmp ax, 0e7ffh
    jne fail_01
    cmp bx, 04d55h
    jne fail_01

    mov si, umb_map
    mov ax, 0e701h
    int 2fh
    cmp ax, 1
    jne fail_02

    mov ax, 4310h
    int 2fh
    mov [xms_entry], bx
    mov [xms_entry+2], es

    mov ah, 10h
    mov dx, 0ffffh
    call far [xms_entry]
    or ax, ax
    jnz fail_03
    cmp bl, 0b0h
    jne fail_03
    cmp dx, 0100h
    jne fail_03

    mov ah, 10h
    mov dx, 0080h
    call far [xms_entry]
    cmp ax, 1
    jne fail_04
    cmp bx, 0c800h
    jne fail_04
    cmp dx, 0080h
    jne fail_04
    mov [first_block], bx

    mov ah, 10h
    mov dx, 0080h
    call far [xms_entry]
    cmp ax, 1
    jne fail_05
    cmp bx, 0c880h
    jne fail_05
    mov [second_block], bx

    mov ah, 11h
    mov dx, [first_block]
    call far [xms_entry]
    cmp ax, 1
    jne fail_06
    mov ah, 11h
    mov dx, [second_block]
    call far [xms_entry]
    cmp ax, 1
    jne fail_06

    mov ah, 10h
    mov dx, 0100h
    call far [xms_entry]
    cmp ax, 1
    jne fail_07
    cmp bx, 0c800h
    jne fail_07
    mov dx, bx
    mov ah, 11h
    call far [xms_entry]
    cmp ax, 1
    jne fail_07

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    xor al, al
    out dx, al
    mov ax, 4c00h
    int 21h

fail_01: mov al, 1
    jmp short fail
fail_02: mov al, 2
    jmp short fail
fail_03: mov al, 3
    jmp short fail
fail_04: mov al, 4
    jmp short fail
fail_05: mov al, 5
    jmp short fail
fail_06: mov al, 6
    jmp short fail
fail_07: mov al, 7
fail:
    mov [failure_code], al
    mov dx, fail_message
    mov ah, 09h
    int 21h
    mov al, [failure_code]
    mov dx, 0f4h
    out dx, al
    mov ax, 4c01h
    int 21h

xms_entry dd 0
first_block dw 0
second_block dw 0
failure_code db 0
umb_map:
    dw 1, 2
    dw 0c800h, 0100h
    dw 0d800h, 0080h
pass_message db 'HIMEM_PROVIDER_PASS', 13, 10, '$'
fail_message db 'HIMEM_PROVIDER_FAIL', 13, 10, '$'
