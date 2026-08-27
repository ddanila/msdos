bits 16
org 100h

; Exercise ANSI.SYS escape parsing and assert its visible cursor effect.

start:
    push cs
    pop ds

    mov bx, 1
    mov cx, ansi_sequence_end - ansi_sequence
    mov dx, ansi_sequence
    mov ah, 40h
    int 21h
    jc failed
    cmp ax, cx
    jne failed

    mov bh, 0
    mov ah, 03h
    int 10h
    cmp dh, 9                     ; ESC[10;20H uses one-based coordinates.
    jne failed
    cmp dl, 19
    jne failed

    mov si, pass_message
    call serial_print
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

failed:
    mov si, fail_message
    call serial_print
    mov ax, 4c01h
    int 21h

serial_print:
    lodsb
    test al, al
    jz .done
    mov ah, al
.wait:
    mov dx, 03fdh
    in al, dx
    test al, 20h
    jz .wait
    mov dx, 03f8h
    mov al, ah
    out dx, al
    jmp serial_print
.done:
    ret

ansi_sequence db 27, '[2J', 27, '[10;20H'
ansi_sequence_end:
pass_message db 'ANSI_DRIVER_PASS', 13, 10, 0
fail_message db 'ANSI_DRIVER_FAIL', 13, 10, 0
