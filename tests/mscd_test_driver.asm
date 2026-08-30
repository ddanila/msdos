bits 16
org 0

; Test-only CD-ROM character driver header.  MSCDEX uses it to prove /D
; discovery and publishes its address through INT 2Fh/1501h.
device_header:
    dd 0ffffffffh
    dw 0c800h
    dw strategy
    dw interrupt
    db 'MSCD001 '

request_offset  dw 0
request_segment dw 0

strategy:
    mov [cs:request_offset], bx
    mov [cs:request_segment], es
    retf

interrupt:
    push ax
    push bx
    push cx
    push ds
    push es
    push di
    mov ax, [cs:request_segment]
    mov es, ax
    mov di, [cs:request_offset]
    cmp byte [es:di + 2], 0
    jne .forwarded
    mov word [es:di + 0eh], resident_end
    mov word [es:di + 10h], cs
    jmp .complete
.forwarded:
    mov byte [es:di + 0dh], 0a5h
    cmp byte [es:di + 2], 80h
    jne .complete
    cmp word [es:di + 18], 1
    jne .request_error
    cmp word [es:di + 20], 5678h
    jne .request_error
    cmp word [es:di + 22], 1234h
    jne .request_error
    mov bx, [es:di + 14]
    mov ax, [es:di + 16]
    mov ds, ax
    mov word [bx], 'DC'
    mov word [bx + 2], '22'
    jmp .complete
.request_error:
    mov word [es:di + 3], 810bh
    jmp .return
.complete:
    mov word [es:di + 3], 0100h
.return:
    pop di
    pop es
    pop ds
    pop cx
    pop bx
    pop ax
    retf

resident_end:
