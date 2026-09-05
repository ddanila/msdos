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

    ; The BIOS reset-vector service exchanges both INT 13h targets.
    ; Restore the old pointers immediately, then verify that the second exchange
    ; returns the exact runtime and warm-boot pointers installed by this probe.
    push cs
    pop es
    mov dx, probe_int13
    mov bx, probe_warm_int13
    mov ax, 1300h
    int 2fh
    mov word [cs:saved_orig13], dx
    mov word [cs:saved_orig13 + 2], ds
    mov word [cs:saved_old13], bx
    mov word [cs:saved_old13 + 2], es
    lds dx, [cs:saved_orig13]
    les bx, [cs:saved_old13]
    mov ax, 1300h
    int 2fh
    mov cx, cs
    mov ax, ds
    cmp ax, cx
    jne fail_int2f_13
    cmp dx, probe_int13
    jne fail_int2f_13
    mov ax, es
    cmp ax, cx
    jne fail_int2f_13
    cmp bx, probe_warm_int13
    jne fail_int2f_13
    push cs
    pop ds

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
    jmp fail
fail_int2f_13:
    push cs
    pop ds
    mov dx, fail_2f_13
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
fail_2f_13 db 'INT2F_INT13_EXCHANGE_FAIL', 13, 10, '$'
saved_orig13 dd 0
saved_old13 dd 0

probe_int13:
    iret
probe_warm_int13:
    iret
