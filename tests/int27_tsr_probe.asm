bits 16
org 100h

; Install a resident INT 61h handler through the original DOS 1.x INT 27h API.

start:
    push cs
    pop ds
    mov dx, resident_handler
    mov ax, 2561h
    int 21h
    mov dx, resident_end
    int 27h

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

resident_message db 'INT27_TSR_HANDLER_PASS', 13, 10, '$'
resident_end:
