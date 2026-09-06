; An external pipeline leg that overwrites its complete extra allocation,
; forcing COMMAND to reload its transient while preserving resident pipe text.
bits 16
org 100h
    mov sp,stack_end
    mov bx,(image_end-$$+100h+15)/16
    mov ah,4ah
    int 21h
    jc fail
    mov bx,0ffffh
    mov ah,48h
    int 21h
    mov ah,48h
    int 21h
    jc fail
    mov [allocation],ax
    mov dx,bx
    mov es,ax
    xor di,di
    cld
    mov ax,0a55ah
.paragraph:
    mov cx,8
    rep stosw
    dec dx
    jz .filled
    or di,di
    jnz .paragraph
    mov bx,es
    add bx,1000h
    mov es,bx
    jmp .paragraph
.filled:
    mov es,[allocation]
    mov ah,49h
    int 21h
    mov bx,2
    mov dx,overwritten
    mov cx,overwritten_end-overwritten
    mov ah,40h
    int 21h
.copy:
    xor bx,bx
    mov cx,128
    mov dx,buffer
    mov ah,3fh
    int 21h
    jc fail
    or ax,ax
    jz done
    mov cx,ax
    mov bx,1
    mov ah,40h
    int 21h
    jc fail
    cmp ax,cx
    jne fail
    jmp .copy
done:
    mov ax,4c00h
    int 21h
fail:
    mov ax,4c01h
    int 21h
allocation dw 0
overwritten db 'PIPE_FILTER_OVERWRITE',13,10
overwritten_end:
buffer times 128 db 0
    times 128 db 0
stack_end:
image_end:
