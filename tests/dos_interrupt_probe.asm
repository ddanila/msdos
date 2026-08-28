bits 16
org 100h


start:
    push cs
    pop ds

    mov dh, 5
    mov dl, 10
    xor bh, bh
    mov ah, 02h
    int 10h
    mov al, 'X'
    int 29h
    xor bh, bh
    mov ah, 03h
    int 10h
    cmp dh, 5
    jne fail_int29
    cmp dl, 11
    jne fail_int29

    mov ax, 1000h
    int 2fh
    test al, al
    jnz fail_int2f_share
    mov ax, 1100h
    int 2fh
    test al, al
    jnz fail_int2f_net
    mov ax, 1400h
    int 2fh
    test al, al
    jnz fail_int2f_nls
    mov ax, 1200h
    int 2fh
    cmp al, 0ffh
    jne fail_int2f_dos

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

fail_int29:
    mov dx, fail_29
    jmp fail
fail_int2f_share:
    mov dx, fail_2f_share
    jmp fail
fail_int2f_net:
    mov dx, fail_2f_net
    jmp fail
fail_int2f_nls:
    mov dx, fail_2f_nls
    jmp fail
fail_int2f_dos:
    mov dx, fail_2f_dos
fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

pass_message db 'DOS_INTERRUPT_PASS', 13, 10, '$'
fail_29 db 'INT29_FAST_CONSOLE_FAIL', 13, 10, '$'
fail_2f_share db 'INT2F_SHARE_INSTALL_FAIL', 13, 10, '$'
fail_2f_net db 'INT2F_NET_INSTALL_FAIL', 13, 10, '$'
fail_2f_nls db 'INT2F_NLS_INSTALL_FAIL', 13, 10, '$'
fail_2f_dos db 'INT2F_DOS_INSTALL_FAIL', 13, 10, '$'
