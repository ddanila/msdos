bits 16
org 100h

    mov dx, high_msg
    push cs
    pop ax
    cmp ax, 1000h
    jae short print_high
    mov dx, low_msg
print_high:
    mov ah, 09h
    int 21h
    xor cx, cx
    mov cl, [80h]
    mov dx, 81h
    mov bx, 1
    mov ah, 40h
    int 21h
    mov dx, crlf
    mov ah, 09h
    int 21h
    mov ax, 4c25h
    int 21h

high_msg db 'LOADFIX_HIGH ', '$'
low_msg  db 'LOADFIX_LOW ', '$'
crlf     db 13, 10, '$'
