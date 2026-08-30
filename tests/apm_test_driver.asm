bits 16
org 0

device_header:
    dd 0ffffffffh
    dw 8000h
    dw strategy
    dw interrupt
    db 'APMTEST$'

request_offset dw 0
request_segment dw 0
old_int15 dd 0
old_int2f dd 0
install_calls dw 0
connect_calls dw 0
enable_calls dw 0
disable_calls dw 0
idle_calls dw 0

strategy:
    mov [cs:request_offset], bx
    mov [cs:request_segment], es
    retf

interrupt:
    push ax
    push bx
    push dx
    push ds
    push es
    push di
    mov ax, [cs:request_segment]
    mov es, ax
    mov di, [cs:request_offset]
    cmp byte [es:di + 2], 0
    jne .unsupported
    mov ax, 3515h
    int 21h
    mov [cs:old_int15], bx
    mov [cs:old_int15 + 2], es
    mov ax, 352fh
    int 21h
    mov [cs:old_int2f], bx
    mov [cs:old_int2f + 2], es
    push cs
    pop ds
    mov dx, int15_handler
    mov ax, 2515h
    int 21h
    mov dx, int2f_handler
    mov ax, 252fh
    int 21h
    mov ax, [cs:request_segment]
    mov es, ax
    mov di, [cs:request_offset]
    mov word [es:di + 0eh], resident_end
    mov word [es:di + 10h], cs
    mov word [es:di + 3], 0100h
    jmp short .done
.unsupported:
    mov word [es:di + 3], 8103h
.done:
    pop di
    pop es
    pop ds
    pop dx
    pop bx
    pop ax
    retf

int15_handler:
    cmp ax, 5300h
    je .install
    cmp ax, 5301h
    je .connect
    cmp ax, 5305h
    je .idle
    cmp ax, 5308h
    je .enable
    jmp far [cs:old_int15]
.install:
    inc word [cs:install_calls]
    mov bx, 504dh
    mov ax, 0102h
    jmp short .success
.connect:
    inc word [cs:connect_calls]
    jmp short .success
.idle:
    inc word [cs:idle_calls]
    jmp short .success
.enable:
    or cx, cx
    jz short .disable
    inc word [cs:enable_calls]
    jmp short .success
.disable:
    inc word [cs:disable_calls]
.success:
    push bp
    mov bp, sp
    and word [ss:bp + 6], 0fffeh
    pop bp
    iret

int2f_handler:
    cmp ax, 0e7ffh
    jne short .chain
    mov bx, [cs:install_calls]
    mov cx, [cs:connect_calls]
    mov dx, [cs:enable_calls]
    mov si, [cs:disable_calls]
    mov di, [cs:idle_calls]
    iret
.chain:
    jmp far [cs:old_int2f]

resident_end:
