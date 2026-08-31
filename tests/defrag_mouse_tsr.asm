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
    cmp byte [cs:click_sent], 0
    jne released
    mov byte [cs:click_sent], 1
    mov bx, 1                         ; left button
    xor cx, cx
    mov dx, 32                        ; row 4: drive B
    iret
released:
    xor bx, bx
    xor cx, cx
    xor dx, dx
done:
    iret
reset:
    mov ax, 0ffffh
    mov bx, 2
    iret
chain:
    jmp far [cs:old_int33]

old_int33 dd 0
click_sent db 0
resident_end:
