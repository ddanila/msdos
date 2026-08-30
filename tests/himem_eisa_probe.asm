bits 16
org 100h

    mov ax,4300h
    int 2fh
    cmp al,80h
    jne fail
    mov ax,4310h
    int 2fh
    mov [entry],bx
    mov [entry+2],es
    mov ah,8
    call far [entry]
    cmp dx,65000
%ifdef EXPECT_EISA
    jb fail
%else
    jae fail
%endif
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

entry dd 0
pass_msg db 'HIMEM_EISA_PASS',13,10,'$'
fail_msg db 'HIMEM_EISA_FAIL',13,10,'$'
