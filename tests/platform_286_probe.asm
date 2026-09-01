bits 16
cpu 286
org 100h

start:
    push cs
    pop ds

    ; A 286 keeps the high four FLAGS bits clear; a 386 permits setting them.
    pushf
    pop ax
    mov bx, ax
    or ax, 0xf000
    push ax
    popf
    pushf
    pop ax
    push bx
    popf
    and ax, 0xf000
    or ax, ax
    jne fail

    mov ax, 4300h
    int 2fh
    cmp al, 80h
    jne fail
    mov ax, 4310h
    int 2fh
    mov [xms_entry], bx
    mov [xms_entry + 2], es

    ; Exercise both balanced A20 ownership APIs. DOS=HIGH owns the global
    ; gate, so releasing our references must leave physical A20 enabled.
    mov ah, 03h
    call far [xms_entry]
    cmp ax, 1
    jne fail
    mov ah, 04h
    call far [xms_entry]
    cmp ax, 1
    jne fail
    mov ah, 05h
    call far [xms_entry]
    cmp ax, 1
    jne fail
    mov ah, 06h
    call far [xms_entry]
    cmp ax, 1
    jne fail
    mov ah, 07h
    call far [xms_entry]
    cmp ax, 1
    jne fail

    ; DOS=HIGH must retain HMA ownership.
    mov ah, 01h
    mov dx, 0ffffh
    call far [xms_entry]
    or ax, ax
    jnz fail
    cmp bl, 91h
    jne fail

    ; IBM 5170 1.2 MiB drive geometry: 80 cylinders, two heads, 15 sectors.
    xor dx, dx
    mov ah, 08h
    int 13h
    jc fail
    mov al, cl
    and al, 3fh
    cmp al, 15
    jne fail
    cmp ch, 79
    jne fail
    cmp dh, 1
    jne fail

    ; Exercise the AT BIOS keyboard polling path without requiring host input.
    mov ah, 01h
    int 16h

    mov dx, pass_message
    mov ax, 0900h
    int 21h
    mov ax, 4c00h
    int 21h

fail:
    mov dx, fail_message
    mov ax, 0900h
    int 21h
    mov ax, 4c01h
    int 21h

xms_entry dd 0
pass_message db 'PLATFORM_286_PASS', 13, 10, '$'
fail_message db 'PLATFORM_286_FAIL', 13, 10, '$'
