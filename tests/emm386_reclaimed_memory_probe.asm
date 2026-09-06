; Overwrite only a DOS-allocated free conventional block before later EMS use.
bits 16
org 100h
    mov sp, stack_end
    push cs
    pop ds
    push cs
    pop es
    mov bx, (stack_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    jc failed
    mov bx, 0ffffh
    mov ah, 48h
    int 21h
    jnc failed
    cmp ax, 8
    jne failed
    test bx, bx
    jz failed
    mov si, bx
    mov ah, 48h
    int 21h
    jc failed
    mov [owner], ax
    mov dx, ax
    add dx, si
    jc failed
    cmp dx, 0a000h
    ja failed
    mov dx, ax
    cld
.fill:
    mov es, dx
    xor di, di
    mov ax, 0a55ah
    mov cx, 8
    rep stosw
    inc dx
    dec si
    jnz .fill
    mov es, [owner]
    mov ah, 49h
    int 21h
    jc failed
    mov dx, passed
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h
failed:
    mov dx, failure
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 11h
    out dx, ax
    mov ax, 4c01h
    int 21h
owner dw 0
passed db 'EMM386_RECLAIM_OVERWRITE_PASS',13,10,'$'
failure db 'EMM386_RECLAIM_OVERWRITE_FAIL',13,10,'$'
times 256 db 0
stack_end:
