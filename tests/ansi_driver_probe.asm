bits 16
org 100h

; Exercise ANSI.SYS escape parsing and assert its visible cursor effect.

start:
    push cs
    pop ds

    ; Generic IOCTL get-current-settings must be handled by ANSI itself.
    mov ax, 3d02h
    mov dx, con_name
    int 21h
    jc failed
    mov bx, ax
    mov ax, 440ch
    mov ch, 3                     ; display-device category
    mov cl, 7fh                   ; ANSI get-settings minor function
    mov dx, ioctl_packet
    int 21h
    pushf
    mov ah, 3eh
    int 21h
    popf
    jc failed
    cmp byte [ioctl_packet + 6], 1 ; text mode
    jne failed
    cmp word [ioctl_packet + 14], 80
    jne failed

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

    mov dx, read_ready
    call screen_print
    mov ah, 08h                   ; blocking CON read -> command 4
    int 21h
    cmp al, 'r'
    jne failed

    mov dx, rdnd_ready
    call screen_print
.poll_rdnd:
    mov ah, 06h                   ; direct/non-destructive CON input -> command 5
    mov dl, 0ffh
    int 21h
    jz .poll_rdnd
    cmp al, 'n'
    jne failed

    mov dx, flush_ready
    call screen_print
.wait_queued:
    mov ah, 0bh                   ; wait until the injected key is queued
    int 21h
    test al, al
    jz .wait_queued
    mov ax, 0c06h                 ; flush command 7, then nonblocking input
    mov dl, 0ffh
    int 21h
    jnz failed                    ; the queued 'f' must have been discarded

    mov si, pass_message
    call serial_print
.passed:
    hlt                           ; host ends QEMU after its final screen capture
    jmp .passed

failed:
    mov si, fail_message
    call serial_print
    mov ax, 4c01h
    int 21h

screen_print:
    mov ah, 09h
    int 21h
    ret

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
con_name db 'CON', 0
ioctl_packet db 0, 0
             dw 14
             dw 0
             db 0, 0
             dw 0, 0, 0, 0, 0
read_ready db 13, 10, 'ANSI_READ_READY', 13, 10, '$'
rdnd_ready db 13, 10, 'ANSI_RDND_READY', 13, 10, '$'
flush_ready db 13, 10, 'ANSI_FLUSH_READY', 13, 10, '$'
pass_message db 'ANSI_DRIVER_PASS', 13, 10, 0
fail_message db 'ANSI_DRIVER_FAIL', 13, 10, 0
