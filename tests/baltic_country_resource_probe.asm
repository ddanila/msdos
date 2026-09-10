bits 16
cpu 8086
org 100h
%ifndef TARGET
%define TARGET 371
%endif
%ifndef ERROR
%define ERROR 1
%endif
    push cs
    pop ds
    push cs
    pop es
    mov ax,6501h
    mov bx,775
    mov dx,TARGET
    mov cx,41
    mov di,buffer
    int 21h
    jnc query_accepted
    cmp ax,ERROR
    jne wrong_error
    mov ax,38ffh
    mov bx,TARGET
    mov dx,-1
    int 21h
    jnc set_accepted
    cmp ax,ERROR
    jne wrong_error
    mov dx,passed
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
query_accepted:
    mov dx,query_message
    jmp fail
set_accepted:
    mov dx,set_message
    jmp fail
wrong_error:
    mov dx,error_message
fail:
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h
buffer times 64 db 0
passed db 'BALTIC_RESOURCE_REJECTED',13,10,'$'
query_message db 'BALTIC_RESOURCE_FAIL QUERY_ACCEPTED',13,10,'$'
set_message db 'BALTIC_RESOURCE_FAIL SET_ACCEPTED',13,10,'$'
error_message db 'BALTIC_RESOURCE_FAIL WRONG_ERROR',13,10,'$'
