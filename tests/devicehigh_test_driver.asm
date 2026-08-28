bits 16
org 0

device_header:
    dd 0ffffffffh
    dw 8000h
    dw strategy
    dw interrupt
    db 'DHREF$  '

request_offset  dw 0
request_segment dw 0

strategy:
    mov [cs:request_offset], bx
    mov [cs:request_segment], es
    retf

interrupt:
    push ax
    push es
    push di
    mov ax, [cs:request_segment]
    mov es, ax
    mov di, [cs:request_offset]
    cmp byte [es:di + 2], 0
    jne .unsupported
    mov word [es:di + 0eh], resident_end
    mov word [es:di + 10h], cs
    mov word [es:di + 3], 0100h
    jmp short .done
.unsupported:
    mov word [es:di + 3], 8103h
.done:
    pop di
    pop es
    pop ax
    retf

resident_end:

