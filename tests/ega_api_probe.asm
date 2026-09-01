bits 16
org 100h

start:
    mov ax, 0bc00h
    int 2fh
    cmp al, 0ffh
    je .default_mux
    mov ax, 0ac00h
    int 2fh
    cmp al, 0ffh
    jne fail_mux
    cmp bx, 5456h
    jne fail_mux
    mov byte [mux], 0ach
    mov ax, 0bc00h
    int 2fh
    or al, al
    jnz fail_conflict
    jmp short .version
.default_mux:
    cmp bx, 5456h
    jne fail_mux
.version:
    mov ah, [mux]
    mov al, 6
    int 2fh
    cmp bx, 5456h
    jne fail_version
    cmp cx, 020bh
    jne fail_version
    cmp dl, 9
    jne fail_version

    mov ah, 0fah
    xor bx, bx
    int 10h
    or bx, bx
    jz fail_interrogate
    cmp byte [es:bx], 2
    jne fail_interrogate
    cmp byte [es:bx+1], 11
    jne fail_interrogate

    ; A normal BIOS palette call must be reflected in the RIL shadow.
    mov ax, 1000h
    mov bx, 0502h
    int 10h
    mov ah, 0f0h
    mov dx, 18h
    mov bx, 0002h
    int 10h
    and bl, 3fh
    cmp bl, 5
    jne fail_bios_shadow

    ; Single indexed register write/read.
    mov ah, 0f1h
    mov dx, 8
    mov bx, 0f02h
    int 10h
    mov ah, 0f0h
    mov dx, 8
    mov bx, 0002h
    int 10h
    cmp bl, 0fh
    jne fail_single

    ; Range write/read through caller storage.
    push cs
    pop es
    mov ah, 0f3h
    mov dx, 10h
    mov cx, 0502h
    mov bx, range_write
    int 10h
    mov word [range_read], 0
    mov ah, 0f2h
    mov dx, 10h
    mov cx, 0502h
    mov bx, range_read
    int 10h
    cmp word [range_read], 3412h
    jne fail_range

    ; Record-set write/read.
    mov ah, 0f5h
    mov cx, 2
    mov bx, set_write
    int 10h
    mov byte [set_read+3], 0
    mov byte [set_read+7], 0
    mov ah, 0f4h
    mov cx, 2
    mov bx, set_read
    int 10h
    cmp byte [set_read+3], 5ah
    jne fail_set
    cmp byte [set_read+7], 0ch
    jne fail_set

    ; Define and restore the sequencer default table.
    mov ah, 0f7h
    mov dx, 8
    mov bx, default_seq
    int 10h
    mov ah, 0f1h
    mov dx, 8
    mov bx, 7702h
    int 10h
    mov ah, 0f6h
    int 10h
    mov ah, 0f0h
    mov dx, 8
    mov bx, 0002h
    int 10h
    cmp bl, 0ah
    jne fail_default

    mov dx, ok_message
    jmp short print_exit_ok

fail_mux:         mov dx, msg_mux
                  jmp short print_exit_fail
fail_conflict:    mov dx, msg_conflict
                  jmp short print_exit_fail
fail_version:     mov dx, msg_version
                  jmp short print_exit_fail
fail_interrogate: mov dx, msg_interrogate
                  jmp short print_exit_fail
fail_bios_shadow: mov dx, msg_bios_shadow
                  jmp short print_exit_fail
fail_single:      mov dx, msg_single
                  jmp short print_exit_fail
fail_range:       mov dx, msg_range
                  jmp short print_exit_fail
fail_set:         mov dx, msg_set
                  jmp short print_exit_fail
fail_default:     mov dx, msg_default
print_exit_fail:
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
print_exit_ok:
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

mux             db 0bch
range_write     db 12h, 34h
range_read      db 0, 0
set_write       dw 10h
                db 7, 5ah
                dw 20h
                db 0, 0ch
set_read        dw 10h
                db 7, 0
                dw 20h
                db 0, 0
default_seq     db 3, 1, 0ah, 0, 6
ok_message      db 'EGA_API_OK', 13, 10, '$'
msg_mux         db 'EGA_FAIL_MUX', 13, 10, '$'
msg_conflict    db 'EGA_FAIL_CONFLICT', 13, 10, '$'
msg_version     db 'EGA_FAIL_VERSION', 13, 10, '$'
msg_interrogate db 'EGA_FAIL_INTERROGATE', 13, 10, '$'
msg_bios_shadow db 'EGA_FAIL_BIOS_SHADOW', 13, 10, '$'
msg_single      db 'EGA_FAIL_SINGLE', 13, 10, '$'
msg_range       db 'EGA_FAIL_RANGE', 13, 10, '$'
msg_set         db 'EGA_FAIL_SET', 13, 10, '$'
msg_default     db 'EGA_FAIL_DEFAULT', 13, 10, '$'
