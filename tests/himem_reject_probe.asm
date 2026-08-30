bits 16
org 100h

    mov ax,4300h
    int 2fh
    cmp al,80h
    je fail
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

pass_msg db 'HIMEM_REJECT_PASS',13,10,'$'
fail_msg db 'HIMEM_REJECT_FAIL',13,10,'$'
