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

    ; Force the repository INT 13h wrapper through its PS/2 Model 25/30-only
    ; parameter workaround, while replacing only the underlying BIOS handler.
    ; Patch the unique resident compare operand to the current BIOS model byte;
    ; this also works when SMARTDRV has placed another hook ahead of BLOCK13.
    call force_ps2_path
    jc fail_ps2_scan

    push cs
    pop ds
    mov dx, ps2_probe_int13
    les bx, [saved_old13]
    mov ax, 1300h
    int 2fh
    mov word [cs:ps2_saved_orig13], dx
    mov word [cs:ps2_saved_orig13 + 2], ds
    mov word [cs:ps2_saved_old13], bx
    mov word [cs:ps2_saved_old13 + 2], es

    mov byte [cs:primary_calls], 0
    mov byte [cs:status_calls], 0
    mov byte [cs:primary_error], 0
    mov ax, 0800h
    mov dx, 0080h
    int 13h
    mov byte [cs:failure_step], 1
    pushf
    pop word [cs:returned_flags]
    mov [cs:returned_ds], ds
    mov [cs:returned_es], es
    cmp ax, 1234h
    jne fail_ps2_13
    cmp bx, 2345h
    jne fail_ps2_13
    cmp cx, 3456h
    jne fail_ps2_13
    cmp dx, 4567h
    jne fail_ps2_13
    cmp di, 5678h
    jne fail_ps2_13
    cmp si, 6789h
    jne fail_ps2_13
    cmp bp, 789ah
    jne fail_ps2_13
    mov byte [cs:failure_step], 2
    cmp word [cs:returned_ds], 89abh
    jne fail_ps2_13
    mov byte [cs:failure_step], 3
    cmp word [cs:returned_es], 9abch
    jne fail_ps2_13
    mov byte [cs:failure_step], 4
    test word [cs:returned_flags], 1
    jnz fail_ps2_13
    mov byte [cs:failure_step], 5
    cmp byte [cs:primary_calls], 1
    jne fail_ps2_13
    mov byte [cs:failure_step], 6
    cmp byte [cs:status_calls], 1
    jne fail_ps2_13

    mov byte [cs:failure_step], 7
    mov byte [cs:primary_calls], 0
    mov byte [cs:status_calls], 0
    mov byte [cs:primary_error], 1
    mov ax, 1500h
    mov dx, 0080h
    int 13h
    pushf
    pop word [cs:returned_flags]
    mov [cs:returned_ds], ds
    mov [cs:returned_es], es
    cmp ax, 1234h
    jne fail_ps2_13
    cmp bx, 2345h
    jne fail_ps2_13
    cmp cx, 3456h
    jne fail_ps2_13
    cmp dx, 4567h
    jne fail_ps2_13
    cmp di, 5678h
    jne fail_ps2_13
    cmp si, 6789h
    jne fail_ps2_13
    cmp bp, 789ah
    jne fail_ps2_13
    cmp word [cs:returned_ds], 89abh
    jne fail_ps2_13
    cmp word [cs:returned_es], 9abch
    jne fail_ps2_13
    cmp byte [cs:primary_calls], 1
    jne fail_ps2_13
    cmp byte [cs:status_calls], 1
    jne fail_ps2_13
    test word [cs:returned_flags], 1
    jz fail_ps2_13

    mov byte [cs:failure_step], 0
    call restore_ps2_state
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
    jmp fail
fail_ps2_13:
    call restore_ps2_state
fail_ps2_scan:
    push cs
    pop ds
    mov dx, fail_ps2
    mov ah, 09h
    int 21h
    mov dl, [failure_step]
    add dl, '0'
    mov ah, 02h
    int 21h
    mov dl, [status_calls]
    add dl, '0'
    mov ah, 02h
    int 21h
    mov dx, newline
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h
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
fail_ps2 db 'INT13_PS2_RESULT_PRESERVATION_FAIL', 13, 10, '$'
newline db 13, 10, '$'
saved_orig13 dd 0
saved_old13 dd 0
ps2_saved_orig13 dd 0
ps2_saved_old13 dd 0
patched_segment dw 0
patched_offset dw 0
current_model db 0
primary_calls db 0
status_calls db 0
primary_error db 0
failure_step db 0
returned_flags dw 0
returned_ds dw 0
returned_es dw 0

restore_ps2_state:
    lds dx, [cs:ps2_saved_orig13]
    les bx, [cs:ps2_saved_old13]
    mov ax, 1300h
    int 2fh
    mov es, [cs:patched_segment]
    mov di, [cs:patched_offset]
    mov al, 0fah
    mov es:[di], al
    ret

force_ps2_path:
    mov ah, 0c0h
    int 15h
    jc .rom_model
    mov al, es:[bx + 2]
    jmp .have_model
.rom_model:
    push ds
    mov ax, 0ffffh
    mov ds, ax
    mov al, [000eh]
    pop ds
.have_model:
    mov [cs:current_model], al
    mov bx, 0070h
.segment:
    mov es, bx
    xor di, di
.offset:
    cmp byte [es:di], 02eh
    jne .next
    cmp byte [es:di + 1], 080h
    jne .next
    cmp byte [es:di + 2], 03eh
    jne .next
    cmp byte [es:di + 5], 0fah
    jne .next
    mov al, [cs:current_model]
    mov [es:di + 5], al
    add di, 5
    mov [cs:patched_segment], es
    mov [cs:patched_offset], di
    clc
    ret
.next:
    inc di
    cmp di, 16
    jb .offset
    inc bx
    cmp bx, 09fc0h
    jb .segment
    stc
    ret

probe_int13:
    iret
probe_warm_int13:
    iret

ps2_probe_int13:
    cmp ah, 01h
    je .status
    cmp ah, 08h
    je .primary
    cmp ah, 15h
    jne .unexpected
.primary:
    inc byte [cs:primary_calls]
    mov bx, 2345h
    mov cx, 3456h
    mov dx, 4567h
    mov di, 5678h
    mov si, 6789h
    mov bp, 789ah
    mov ax, 89abh
    mov ds, ax
    mov ax, 9abch
    mov es, ax
    mov ax, 1234h
    push bp
    mov bp, sp
    cmp byte [cs:primary_error], 0
    jne .error
    and word [ss:bp + 6], 0fffeh
    pop bp
    iret
.error:
    or word [ss:bp + 6], 1
    pop bp
    iret
.status:
    inc byte [cs:status_calls]
    mov ax, 0deadh
    mov bx, 0beefh
    mov cx, 0aaaah
    mov dx, 0bbbbh
    mov di, 0cccch
    mov si, 0ddddh
    mov bp, 0eeeeh
    push bp
    mov bp, sp
    or word [ss:bp + 6], 1
    pop bp
    iret
.unexpected:
    iret
