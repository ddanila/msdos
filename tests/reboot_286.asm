bits 16
cpu 286
org 100h

    mov dx, message
    mov ax, 0900h
    int 21h
    int 19h
    mov ax, 4c01h
    int 21h

message db 'IBM_AT_REBOOTING', 13, 10, '$'
