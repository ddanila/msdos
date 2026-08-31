bits 16
org 100h

start:
    push cs
    pop ds
    mov al, [82h]
    and al, 0dfh
    cmp al, 'R'
    je install_read
    cmp al, 'W'
    jne bad
    mov byte [mode], 3
    jmp short install
install_read:
    mov byte [mode], 2
install:
    mov ax, 3513h
    int 21h
    mov [old_int13], bx
    mov [old_int13 + 2], es
    mov dx, handler
    mov ax, 2513h
    int 21h
    mov dx, (100h + resident_end - $$ + 15) >> 4
    mov ax, 3100h
    int 21h
bad:
    mov ax, 4c01h
    int 21h

handler:
    cmp dl, 1                         ; only physical B:
    jne chain
    cmp ah, [cs:mode]
    jne chain
    inc byte [cs:operation_count]
    cmp byte [cs:mode], 2
    jne short write_fault
    cmp byte [cs:operation_count], 2
    jb chain                          ; permit the boot-sector read
    jmp short fail                    ; sustained read outage
write_fault:
    cmp byte [cs:operation_count], 3
    ja chain                          ; one exhausted write/retry cycle
fail:
    push bp
    mov bp, sp
    or word [ss:bp + 6], 1
    pop bp
    mov ah, 20h                       ; controller failure
    iret
chain:
    jmp far [cs:old_int13]

old_int13 dd 0
mode db 0
operation_count db 0
resident_end:
