bits 16
org 100h

start:
    push cs
    pop ds
    mov ah, 52h
    int 21h
    les si, [es:bx]
    mov cx, 32
.next_dpb:
    cmp byte [es:si], 2            ; first drive after A: and B:
    je .found
    les si, [es:si + 25]
    cmp si, 0ffffh
    je failed
    loop .next_dpb
    jmp short failed
.found:
    les bx, [es:si + 19]
    mov ax, es
    cmp ax, 8000h
    jb failed
    mov ax, [es:bx + 6]
    mov [driver_strategy], ax
    mov ax, [es:bx + 8]
    mov [driver_interrupt], ax
    mov ax, es
    mov [driver_strategy + 2], ax
    mov [driver_interrupt + 2], ax
    mov [driver_header], bx
    mov [driver_header + 2], ax

    mov al, 13
    call issue_request
    cmp word [request_packet + 3], 0100h
    jne failed
    mov al, 14
    call issue_request
    cmp word [request_packet + 3], 0100h
    jne failed
    mov al, 16
    call issue_request
    cmp word [request_packet + 3], 8103h
    jne failed

    mov si, pass_message
    call serial_print
    mov ax, 4c00h
    int 21h

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

pass_message db 'DEVICEHIGH_BLOCK_PASS', 13, 10, 0
fail_message db 'DEVICEHIGH_BLOCK_FAIL', 13, 10, 0
driver_strategy dd 0
driver_interrupt dd 0
driver_header dd 0
request_packet:
    db 22, 0, 0
    dw 0
    times 17 db 0
