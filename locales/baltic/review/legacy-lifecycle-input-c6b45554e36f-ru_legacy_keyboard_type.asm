bits 16
cpu 8086
org 100h
    mov ax,0ad80h
    int 2fh
    cmp ax,0ffffh
    jne fail
    ; KEYB's shared area begins with three saved interrupt vectors.
%ifdef XT83
    cmp word [es:di+12],4000h
%else
    cmp word [es:di+12],2000h
%endif
    jne fail
    mov dx,passed
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
fail:
    mov ax,4c01h
    int 21h
%ifdef XT83
passed db 'RU_XT83_TYPE_PASS',13,10,'$'
%else
passed db 'RU_AT84_TYPE_PASS',13,10,'$'
%endif
