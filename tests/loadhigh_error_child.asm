bits 16
org 100h

start:
    mov dx, message
    mov ah, 09h
    int 21h
    mov ax, 4c25h
    int 21h

message db 'LOADHIGH_ERROR_CHILD', 13, 10, '$'
