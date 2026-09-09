bits 16
org 100h
%ifndef HIGH
%define HIGH 1
%endif
    push ds
    mov ax,1203h
    int 2fh
    mov ax,ds
    pop ds
    cmp ax,0ffffh
%if HIGH
    jne fail
    mov ax,5800h
    int 21h
    jc fail
    mov [strategy],ax
    mov ax,5802h
    int 21h
    jc fail
    xor ah,ah
    mov [linked],ax
    mov ax,5803h
    mov bx,1
    int 21h
    jc fail
    mov ax,5801h
    mov bx,80h
    int 21h
    jc fail
    mov ah,48h
    mov bx,16
    int 21h
    jc fail
    mov es,ax
    cmp ax,0a000h
    jb fail
    mov ah,49h
    int 21h
    jc fail
    mov ax,5801h
    mov bx,[strategy]
    int 21h
    jc fail
    mov ax,5803h
    mov bx,[linked]
    int 21h
    jc fail
%else
    je fail
%endif
    mov dx,passed
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
fail:
    mov dx,failed
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h
strategy dw 0
linked dw 0
%if HIGH
passed db 'RU_HIGH_UMB_PASS',13,10,'$'
%else
passed db 'RU_LOW_PASS',13,10,'$'
%endif
failed db 'RU_PROFILE_FAIL',13,10,'$'
