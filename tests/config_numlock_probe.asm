bits 16
org 100h

    mov ax, 40h
    mov es, ax
    test byte [es:17h], 20h
    jz .off
    mov dx, on_msg
    jmp short .print
.off:
    mov dx, off_msg
.print:
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

on_msg  db 'NUMLOCK=ON', 13, 10, '$'
off_msg db 'NUMLOCK=OFF', 13, 10, '$'
