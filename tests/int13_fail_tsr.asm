bits 16
org 100h

start:
    push cs
    pop ds
    mov al, [82h]
    and al, 0dfh
    cmp al, 'R'
    je install
    cmp al, 'W'
    jne bad
    mov byte [fail_mode], 3
    mov byte [fail_after], 1
    jmp short install
bad:
    mov ax, 4c01h
    int 21h
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

handler:
    cmp dl, 1                         ; only physical B:
    jne chain
    cmp ah, [cs:fail_mode]
    jne chain
    inc byte [cs:operation_count]
    push ax
    mov al, [cs:operation_count]
    cmp al, [cs:fail_after]
    pop ax
    jb chain
    push bp
    mov bp, sp
    or word [ss:bp + 6], 1            ; carry in caller's saved FLAGS
    pop bp
    mov ah, 20h                       ; controller failure
    iret
chain:
    jmp far [cs:old_int13]

old_int13 dd 0
fail_mode db 2
fail_after db 2
operation_count db 0
resident_end:
