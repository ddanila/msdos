bits 16
org 100h

mov ax, 3521h
int 21h
mov [old_21], bx
mov [old_21 + 2], es
push cs
pop ds
mov dx, handler
mov ax, 2521h
int 21h
mov dx, (resident_end - $$ + 100h + 15) / 16
mov ax, 3100h
int 21h

handler:
jmp far [cs:old_21]

old_21 dd 0
resident_end:
