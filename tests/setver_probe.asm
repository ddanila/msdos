bits 16
org 100h

start:
    mov ax, 3000h
    int 21h
    push ax
    mov dx, prefix
    mov ah, 09h
    int 21h
    pop ax
    push ax
    call print_u8
    mov dl, '.'
    mov ah, 02h
    int 21h
    pop ax
    mov al, ah
    aam
    push ax
    mov dl, ah
    add dl, '0'
    mov ah, 02h
    int 21h
    pop ax
    mov dl, al
    add dl, '0'
    mov ah, 02h
    int 21h
    mov dx, crlf
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

print_u8:
    aam
    push ax
    test ah, ah
    jz .ones
    mov dl, ah
    add dl, '0'
    mov ah, 02h
    int 21h
.ones:
    pop ax
    mov dl, al
    add dl, '0'
    mov ah, 02h
    int 21h
    ret

prefix db 'SETVER_PROBE_VERSION=', '$'
crlf  db 13, 10, '$'
