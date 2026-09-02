bits 16
org 100h

%ifndef HANDLE_COUNT
%define HANDLE_COUNT 3
%endif

start:
    mov ax,4300h
    int 2fh
    cmp al,80h
    jne fail
    mov ax,4310h
    int 2fh
    mov [entry],bx
    mov [entry+2],es

    mov ah,1
    mov dx,1023
    call far [entry]
    or ax,ax
    jnz fail
    cmp bl,92h
    jne fail
    mov ah,1
    mov dx,1024
    call far [entry]
    cmp ax,1
    jne fail
    mov ah,2
    call far [entry]
    cmp ax,1
    jne fail

    mov cx,HANDLE_COUNT
allocate_loop:
    mov ah,9
    xor dx,dx
    call far [entry]
    cmp ax,1
    jne fail
    loop allocate_loop
    mov ah,9
    xor dx,dx
    call far [entry]
    or ax,ax
    jnz fail
    cmp bl,0a1h
    jne fail

    mov ah,88h
    int 15h
    cmp ax,128
    jne fail
    mov dx,pass_msg
    jmp short finish
fail:
    mov dx,fail_msg
finish:
    mov ah,9
    int 21h
    mov dx,0f4h
    mov ax,10h
    out dx,ax
    mov ax,4c00h
    int 21h

entry       dd 0
pass_msg    db 'HIMEM_OPTIONS_PASS',13,10,'$'
fail_msg    db 'HIMEM_OPTIONS_FAIL',13,10,'$'
