bits 16
org 100h


start:
    push cs
    pop ds

    mov ax, 3d02h
    mov dx, con_name
    int 21h
    jc failed
    mov bx, ax
    mov ax, 440ch
    mov ch, 3
    mov cl, 7fh
    mov dx, ioctl_packet
    int 21h
    pushf
    mov ah, 3eh
    int 21h
    popf
    jc failed
    cmp byte [ioctl_packet + 6], 1
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
    cmp dh, 9
    jne failed
    cmp dl, 19
    jne failed

    mov dx, read_ready
    call screen_print
    mov ah, 08h
    int 21h
    cmp al, 'r'
    jne failed

    mov dx, rdnd_ready
    call screen_print
.poll_rdnd:
    mov ah, 06h
    mov dl, 0ffh
    int 21h
    jz .poll_rdnd
    cmp al, 'n'
    jne failed

    mov dx, flush_ready
    call screen_print
.wait_queued:
    mov ah, 0bh
    int 21h
    test al, al
    jz .wait_queued
    mov ax, 0c06h
    mov dl, 0ffh
    int 21h
    jnz failed

    call find_live_con
    jc failed
    mov [driver_header], si
    mov ax, es
    mov [driver_header + 2], ax
    mov ax, [es:si + 6]
    mov [driver_strategy], ax
    mov ax, [es:si + 8]
    mov [driver_interrupt], ax
    mov ax, es
    mov [driver_strategy + 2], ax
    mov [driver_interrupt + 2], ax

    mov si, pass_through_success
.success_request:
    lodsb
    cmp al, 0ffh
    je .error_requests
    call issue_request
    mov ax, [request_packet + 3]
    and ax, 0ff00h
    cmp ax, 0100h
    jne failed
    jmp .success_request

.error_requests:
    mov si, pass_through_errors
.error_request:
    lodsb
    cmp al, 0ffh
    je .requests_done
    call issue_request
    cmp word [request_packet + 3], 8103h
    jne failed
    jmp .error_request

.requests_done:
    mov si, pass_message
    call serial_print
.passed:
    hlt
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

issue_request:
    mov [request_packet + 2], al
    mov word [request_packet + 3], 0deadh
    push cs
    pop es
    mov bx, request_packet
    push ds
    push si
    lds si, [driver_header]
    call far [cs:driver_strategy]
    call far [cs:driver_interrupt]
    pop si
    pop ds
    ret

find_live_con:
    mov ah, 52h
    int 21h
    les si, [es:bx + 34]
    mov cx, 256
.next:
    test word [es:si + 4], 8000h
    jz .advance
    push si
    add si, 10
    mov di, con_header_name
    mov dx, 8
.compare:
    mov al, [es:si]
    cmp al, [di]
    jne .different
    inc si
    inc di
    dec dx
    jnz .compare
    pop si
    clc
    ret
.different:
    pop si
.advance:
    mov ax, [es:si + 2]
    mov si, [es:si]
    cmp si, 0ffffh
    je .missing
    mov es, ax
    loop .next
.missing:
    stc
    ret

ansi_sequence db 27, '[2J', 27, '[10;20H'
ansi_sequence_end:
con_name db 'CON', 0
con_header_name db 'CON     '
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
pass_through_success db 1, 2, 6, 10, 0ffh
pass_through_errors db 3, 11, 12, 13, 14, 15, 16, 17, 18, 20, 0ffh
driver_strategy dd 0
driver_interrupt dd 0
driver_header dd 0
request_packet:
    db 22, 0, 0
    dw 0
    times 8 db 0
    db 0
    dw 0, 0
    dw 0
    dw 0
