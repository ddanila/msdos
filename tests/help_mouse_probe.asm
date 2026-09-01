bits 16
org 100h

start:
    mov ax, 3533h
    int 21h
    mov [old_int33], bx
    mov [old_int33+2], es
    mov ax, 40h
    mov es, ax
    mov ax, [es:6ch]
    add ax, 36
    mov [click_tick], ax
    push cs
    pop ds
    mov dx, handler
    mov ax, 2533h
    int 21h
    mov dx, (resident_end - start + 100h + 15) / 16
    mov ax, 3100h
    int 21h

handler:
    cmp ax, 0
    je .reset
    cmp ax, 1
    je .done
    cmp ax, 2
    je .done
    cmp ax, 3
    je .position
    jmp far [cs:old_int33]
.reset:
    mov ax, 0ffffh
    mov bx, 2
    mov byte [cs:emitted], 0
    iret
.position:
    xor bx, bx
    cmp byte [cs:emitted], 0
    jne .done
    push ax
    push ds
    mov ax, 40h
    mov ds, ax
    mov ax, [6ch]
    cmp ax, [cs:click_tick]
    pop ds
    pop ax
    jb .done
    mov byte [cs:emitted], 1
    mov bx, 1
    mov cx, 16
    mov dx, 24
.done:
    iret

old_int33  dd 0
click_tick dw 0
emitted    db 0
resident_end:
