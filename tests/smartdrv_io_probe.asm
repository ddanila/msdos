bits 16
org 100h

sector_number equ 1000

start:
    push cs
    pop ds
    push cs
    pop es
    cld

    call find_smartdrv
    jc failed

    mov si, successful_requests
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
    mov si, invalid_requests
.invalid_request:
    lodsb
    cmp al, 0ffh
    je .requests_done
    call issue_request
    cmp word [request_packet + 3], 8103h
    jne failed
    jmp .invalid_request

.requests_done:

    mov di, write_buffer
    mov cx, 512
    mov al, 0a5h
    rep stosb
    mov si, marker
    mov di, write_buffer
    mov cx, marker_size
    rep movsb

    ; INT 26h leaves the caller flags word on the stack.
    mov al, 2                   ; C:
    mov cx, 1
    mov dx, sector_number
    mov bx, write_buffer
    int 26h
    popf
    jc failed

    mov al, 2
    mov cx, 1
    mov dx, sector_number
    mov bx, read_buffer
    int 25h
    popf
    jc failed

    mov si, write_buffer
    mov di, read_buffer
    mov cx, 512
    repe cmpsb
    jne failed

    mov ax, 4c00h
    int 21h

; Resolve the installed SMARTAAR character-device header and retain its live
; strategy and interrupt entry points.
find_smartdrv:
    mov ah, 52h
    int 21h
    les si, [es:bx + 34]
    mov cx, 256
.next:
    test word [es:si + 4], 8000h
    jz .advance
    push si
    add si, 10
    mov di, smartdrv_name
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
    mov ax, [es:si + 6]
    mov [driver_strategy], ax
    mov ax, [es:si + 8]
    mov [driver_interrupt], ax
    mov ax, es
    mov [driver_strategy + 2], ax
    mov [driver_interrupt + 2], ax
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
    push cs
    pop es
    stc
    ret

issue_request:
    mov [request_packet + 2], al
    mov word [request_packet + 3], 0deadh
    push cs
    pop es
    mov bx, request_packet
    call far [driver_strategy]
    call far [driver_interrupt]
    ret

failed:
    mov ax, 4c01h
    int 21h

marker db 'SMARTDRV_SECTOR_OK'
marker_size equ $ - marker
smartdrv_name db 'SMARTAAR'
successful_requests db 13, 14, 0ffh
invalid_requests db 1, 2, 4, 5, 7, 8, 9, 11, 15, 16, 0ffh
driver_strategy dd 0
driver_interrupt dd 0
request_packet:
    db 22, 0, 0
    dw 0
    times 8 db 0
    db 0
    dw 0, 0
    dw 0
    dw 0
write_buffer times 512 db 0
read_buffer times 512 db 0
