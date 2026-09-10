bits 16
cpu 8086
org 100h
    cld
    push cs
    pop ds
    push cs
    pop es
    mov ax,6504h
    mov bx,PAGE
    mov dx,COUNTRY
    mov cx,5
    mov di,buffer
    int 21h
    jc fail
    cmp cx,5
    jne fail
    cmp byte [buffer],4
    jne fail
    push ds
    lds si,[buffer+1]
    cmp word [si],128
    jne restore_fail
    add si,2
    mov di,expected
    mov cx,128
    repe cmpsb
    jne restore_fail
    pop ds
    mov dx,passed
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
restore_fail:
    pop ds
fail:
    mov dx,failed
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h
buffer times 5 db 0
expected incbin 'fileupper.bin'
passed db 'FILECASE_QUERY_PASS',13,10,'$'
failed db 'FILECASE_QUERY_FAIL',13,10,'$'
