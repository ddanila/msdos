bits 16
org 100h

start:
    int 23h
    mov dx, failed
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

failed db 'LOADHIGH_CTRLC_RETURNED', 13, 10, '$'
