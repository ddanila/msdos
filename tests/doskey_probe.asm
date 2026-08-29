bits 16
org 100h

start:
    mov ax, 4800h
    int 2fh
    cmp ax, 0aa02h
    jne fail_install
    mov dx, installed
    call print

    mov dx, input_buffer
    mov ax, 4810h
    int 2fh
    test ax, ax
    jnz fail_input
    mov dx, first_prefix
    call print
    call print_buffer

    mov dx, input_buffer
    mov byte [input_buffer+1], 0
    mov ax, 4810h
    int 2fh
    test ax, ax
    jnz fail_input
    mov dx, second_prefix
    call print
    call print_buffer

    mov dx, input_buffer
    mov byte [input_buffer+1], 0
    mov ax, 4810h
    int 2fh
    test ax, ax
    jnz fail_input
    mov dx, third_prefix
    call print
    call print_buffer

    mov dx, input_buffer
    mov byte [input_buffer+1], 0
    mov ax, 4810h
    int 2fh
    test ax, ax
    jnz fail_input
    mov dx, fourth_prefix
    call print
    call print_buffer

    ; Replace redirected stdin with CON so DOSKEY selects its interactive
    ; BIOS-key editor.  The four commands above are now the history corpus.
    mov dx, con_name
    mov ax, 3d00h
    int 21h
    jc fail_input
    mov bx, ax
    xor cx, cx
    mov ah, 46h
    int 21h
    jc fail_input

    mov cx, 4800h               ; Up: newest command
    call stuff_key
    mov cx, 1c0dh
    call stuff_key
    call read_doskey
    mov dx, up_prefix
    call print
    call print_buffer

    mov cx, 4900h               ; Page Up: oldest command
    call stuff_key
    mov cx, 1c0dh
    call stuff_key
    call read_doskey
    mov dx, pgup_prefix
    call print
    call print_buffer

    mov cx, 4900h               ; Oldest, then Down: next command
    call stuff_key
    mov cx, 5000h
    call stuff_key
    mov cx, 1c0dh
    call stuff_key
    call read_doskey
    mov dx, down_prefix
    call print
    call print_buffer
    call read_doskey            ; drain MULTI's queued second command

    mov cx, 5100h               ; Page Down: newest command
    call stuff_key
    mov cx, 1c0dh
    call stuff_key
    call read_doskey
    mov dx, pgdn_prefix
    call print
    call print_buffer
    call read_doskey            ; drain MULTI's queued second command

    mov cx, 006dh               ; "m", F8: newest matching command
    call stuff_key
    mov cx, 4200h
    call stuff_key
    mov cx, 1c0dh
    call stuff_key
    call read_doskey
    mov dx, f8_prefix
    call print
    call print_buffer

    ; The selected macro queues its second $T command.  Drain it before the
    ; next keyboard-navigation case so F7 consumes the keys intended for it.
    call read_doskey
    mov dx, f8_pending_prefix
    call print
    call print_buffer

    mov cx, 4100h               ; F7: numbered history list
    call stuff_key
    mov cx, 1c0dh
    call stuff_key
    call read_doskey
    mov dx, f7_prefix
    call print
    call print_buffer

    mov cx, 4300h               ; F9, 2: original second command
    call stuff_key
    mov cx, 0032h
    call stuff_key
    mov cx, 1c0dh
    call stuff_key
    mov cx, 1c0dh
    call stuff_key
    call read_doskey
    mov dx, f9_prefix
    call print
    call print_buffer
    call read_doskey            ; drain MULTI's queued second command

    mov cx, 6e00h               ; Alt+F7 clears history; Up stays blank
    call stuff_key
    mov cx, 4800h
    call stuff_key
    mov cx, 1c0dh
    call stuff_key
    call read_doskey
    mov dx, clear_prefix
    call print
    call print_buffer

    mov dx, passed
    call print
    mov ax, 4c00h
    int 21h

print_buffer:
    xor cx, cx
    mov cl, [input_buffer+1]
    mov si, input_buffer+2
.loop:
    jcxz .done
    lodsb
    mov dl, al
    mov ah, 02h
    int 21h
    loop .loop
.done:
    mov dx, crlf
    jmp print

read_doskey:
    mov byte [input_buffer+1], 0
    mov dx, input_buffer
    mov ax, 4810h
    int 2fh
    test ax, ax
    jnz fail_input
    ret

stuff_key:
    mov ah, 05h
    int 16h
    cmp al, 0
    jne fail_input
    ret

fail_install:
    mov dx, bad_install
    jmp fail
fail_input:
    mov dx, bad_input
fail:
    call print
    mov ax, 4c01h
    int 21h
print:
    mov ah, 09h
    int 21h
    ret

input_buffer db 127, 0, 128 dup(0)
installed    db 'DOSKEY_4800_PASS',13,10,'$'
first_prefix db 'DOSKEY_FIRST=[','$'
second_prefix db 'DOSKEY_SECOND=[','$'
third_prefix db 'DOSKEY_THIRD=[','$'
fourth_prefix db 'DOSKEY_FOURTH=[','$'
up_prefix     db 'DOSKEY_UP=[','$'
pgup_prefix   db 'DOSKEY_PGUP=[','$'
down_prefix   db 'DOSKEY_DOWN=[','$'
pgdn_prefix   db 'DOSKEY_PGDN=[','$'
f8_prefix     db 'DOSKEY_F8=[','$'
f8_pending_prefix db 'DOSKEY_F8_PENDING=[','$'
f7_prefix     db 'DOSKEY_F7_RETURN=[','$'
f9_prefix     db 'DOSKEY_F9=[','$'
clear_prefix  db 'DOSKEY_ALTF7_UP=[','$'
con_name      db 'CON',0
crlf         db ']',13,10,'$'
passed       db 'DOSKEY_PROBE_PASS',13,10,'$'
bad_install  db 'DOSKEY_4800_FAIL',13,10,'$'
bad_input    db 'DOSKEY_4810_FAIL',13,10,'$'
