bits 16
org 0

device_header:
    dd 0ffffffffh
    dw 8000h
    dw strategy
    dw interrupt
    db 'A20OFF$ '

request_offset dw 0
request_segment dw 0
old_int21 dd 0

strategy:
    mov [cs:request_offset], bx
    mov [cs:request_segment], es
    call disable_a20
    retf

interrupt:
    push ax
    push ds
    push es
    push di
    call disable_a20
    mov ax, [cs:request_segment]
    mov es, ax
    mov di, [cs:request_offset]
    cmp byte [es:di + 2], 0
    jne .complete
    xor ax, ax
    mov ds, ax
    mov ax, [ds:21h * 4]
    mov [cs:old_int21], ax
    mov ax, [ds:21h * 4 + 2]
    mov [cs:old_int21 + 2], ax
    cli
    mov word [ds:21h * 4], int21_hook
    mov word [ds:21h * 4 + 2], cs
    sti
    mov word [es:di + 0eh], resident_end
    mov word [es:di + 10h], cs
.complete:
    mov word [es:di + 3], 0100h
    pop di
    pop es
    pop ds
    pop ax
    retf

int21_hook:
    jmp far [cs:old_int21]

disable_a20:
    in al, 92h
    and al, 0fdh
    out 92h, al
    ret

resident_end:
