; Allocate all free XMS, exercise its ownership, then verify exact restoration.
bits 16
org 100h
    mov ax,4310h
    int 2fh
    mov [entry],bx
    mov [entry+2],es
    mov ah,08h
    call far [entry]
    or ax,ax
    jz fail
    mov [counts],ax
    mov [counts+2],dx
    mov dx,ax
    mov ah,09h
    call far [entry]
    cmp ax,1
    jne fail
    mov [handle],dx
    mov ah,0ch
    call far [entry]
    cmp ax,1
    jne fail
    cmp dx,10h
    jb fail
    mov dx,[handle]
    mov ah,0dh
    call far [entry]
    cmp ax,1
    jne fail
    mov dx,[handle]
    mov ah,0ah
    call far [entry]
    cmp ax,1
    jne fail
    mov ah,08h
    call far [entry]
    cmp ax,[counts]
    jne fail
    cmp dx,[counts+2]
    jne fail
    mov dx,filename
    xor cx,cx
    mov ah,3ch
    int 21h
    jc fail
    mov bx,ax
    mov dx,counts
    mov cx,4
    mov ah,40h
    int 21h
    jc fail
    cmp ax,4
    jne fail
    mov ah,3eh
    int 21h
    jc fail
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
entry dd 0
handle dw 0
counts dw 0,0
filename db 'XMSCOUNT.BIN',0
passed db 'XMS_RESTORE_PASS',13,10,'$'
failed db 'XMS_RESTORE_FAIL',13,10,'$'
