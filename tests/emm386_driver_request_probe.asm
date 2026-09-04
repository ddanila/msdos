bits 16
org 100h


start:
    push cs
    pop ds
    call find_emm386
    jc failed

    mov ax, [es:si + 6]
    mov [driver_strategy], ax
    mov ax, [es:si + 8]
    mov [driver_interrupt], ax
    mov ax, es
    mov [driver_strategy + 2], ax
    mov [driver_interrupt + 2], ax

    mov al, 1
.valid_request:
    call issue_request
    cmp word [request_packet + 3], 0100h
    jne failed
    inc al
    cmp al, 0dh
    jb .valid_request

    call issue_request
    cmp word [request_packet + 3], 8103h
    jne failed
    mov al, 0ffh
    call issue_request
    cmp word [request_packet + 3], 8103h
    jne failed

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

failed:
    mov dx, fail_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

issue_request:
    mov [request_packet + 2], al
    mov word [request_packet + 3], 0deadh
    push ax
    push bx
    push ds
    push es
    push cs
    pop es
    mov bx, request_packet
    call far [cs:driver_strategy]
    call far [cs:driver_interrupt]
    pop es
    pop ds
    pop bx
    pop ax
    ret

find_emm386:
    mov ah, 52h
    int 21h
    les si, [es:bx + 34]
    mov cx, 256
.next:
    test word [es:si + 4], 8000h
    jz .advance
    push si
    add si, 10
    mov di, device_name
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

driver_strategy dd 0
driver_interrupt dd 0
request_packet:
    db 13, 0, 0
    dw 0
    times 8 db 0
device_name db 'EMMXXXX0'
pass_message db 'EMM386_DRIVER_REQUEST_PASS', 13, 10, '$'
fail_message db 'EMM386_DRIVER_REQUEST_FAIL', 13, 10, '$'
