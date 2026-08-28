bits 16
org 100h


start:
    push cs
    pop ds
    mov dx, resident_handler
    mov ax, 2560h
    int 21h
    mov dx, (resident_end - $$ + 100h + 15) / 16
    mov ax, 3100h
    int 21h

resident_handler:
    push ax
    push dx
    push ds
    push cs
    pop ds
    mov dx, resident_message
    mov ah, 09h
    int 21h
    pop ds
    pop dx
    pop ax
    iret

resident_message db 'INT21_TSR_HANDLER_PASS', 13, 10, '$'
resident_end:
