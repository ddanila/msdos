bits 16
org 100h

start:
    mov ax, 3533h
    int 21h
    mov [old_int33], bx
    mov [old_int33 + 2], es
    push cs
    pop ds
    mov dx, handler
    mov ax, 2533h
    int 21h
    mov dx, (100h + resident_end - $$ + 15) >> 4
    mov ax, 3100h
    int 21h

handler:
    cmp ax, 0
    je reset
    cmp ax, 1
    je done
    cmp ax, 3
    jne chain
    mov al, [cs:phase]
    inc byte [cs:phase]
    cmp al, 0
    je thorough
    cmp al, 2
    je auto_fix
    cmp al, 4
    je start_click
released:
    xor bx, bx
    xor cx, cx
    xor dx, dx
    iret
thorough:
    mov bx, 1
    mov cx, 100                       ; Thorough button
    mov dx, 32                        ; row 4, Start button
    iret
auto_fix:
    mov bx, 1
    mov cx, 220                       ; Auto Fix button
    mov dx, 32
    iret
start_click:
    mov bx, 1
    xor cx, cx                        ; Start button
    mov dx, 32
done:
    iret
reset:
    mov ax, 0ffffh
    mov bx, 2
    iret
chain:
    jmp far [cs:old_int33]

old_int33 dd 0
phase db 0
resident_end:
