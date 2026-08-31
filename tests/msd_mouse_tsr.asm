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
    cmp byte [cs:phase], 0
    je memory_click
    cmp byte [cs:phase], 1
    je release_one
    cmp byte [cs:phase], 2
    je exit_click
    xor bx, bx
    iret
memory_click:
    inc byte [cs:phase]
    mov bx, 1
    mov cx, 256                       ; middle column, Memory
    mov dx, 32                        ; row 4
    iret
release_one:
    inc byte [cs:phase]
    xor bx, bx
    iret
exit_click:
    inc byte [cs:phase]
    mov bx, 1
    mov cx, 480                       ; right column, Exit
    mov dx, 64                        ; row 8
    iret
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
