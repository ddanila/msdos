; Public DOS APIs and INT 19h only: usable without vendor internals or hooks.
bits 16
org 100h
    push cs
    pop ds
    push cs
    pop es
    cld
    mov dx,tag
    mov ax,3d00h
    int 21h
    jc first
    mov bx,ax
    mov dx,receipt
    mov cx,8
    mov ah,3fh
    int 21h
    jc fail
    cmp ax,8
    jne fail
    mov ah,3eh
    int 21h
    jc fail
    mov si,receipt
    mov di,magic
    mov cx,8
    repe cmpsb
    jne fail
    mov dx,tag
    mov ah,41h
    int 21h
    jc fail
    mov si,passed
    call debug
    mov ax,10h
    out 0f4h,ax
    jmp halt
first:
    cmp ax,2
    jne fail
    xor cx,cx
    mov ah,3ch
    int 21h
    jc fail
    mov bx,ax
    mov dx,magic
    mov cx,8
    mov ah,40h
    int 21h
    jc fail
    cmp ax,8
    jne fail
    mov ah,3eh
    int 21h
    jc fail
    mov ah,0dh
    int 21h
    mov si,ready
    call debug
    int 19h
fail:
    mov si,failed
    call debug
    mov ax,11h
    out 0f4h,ax
halt:
    cli
    hlt
    jmp halt
debug:
    mov al,[cs:si]
    inc si
    test al,al
    jz .done
    out 0e9h,al
    jmp debug
.done:
    ret
tag db 'SWBOOT.TAG',0
magic db 'SWRBOOT!'
receipt times 8 db 0
ready db 'SOFTWARE_REBOOT_READY',13,10,0
passed db 'SOFTWARE_REBOOT_SECOND_BOOT_PASS',13,10,0
failed db 'SOFTWARE_REBOOT_FAIL',13,10,0
