bits 16
cpu 8086
org 100h
    mov ax,0ad80h
    int 2fh
    cmp ax,0ffffh
    jne fail
    ; KEYB's shared area begins with three saved interrupt vectors.
    cmp word [es:di+12],2000h
    jne fail
    mov dx,passed
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
fail:
    mov ax,4c01h
    int 21h
passed db 'RU_AT84_TYPE_PASS',13,10,'$'
