bits 16
cpu 286
org 100h

    push cs
    pop ds
    push cs
    pop es

    xor bx, bx
.fill:
    mov al, bl
    xor al, 5ah
    mov [source + bx], al
    mov byte [target + bx], 0
    inc bx
    cmp bx, 256
    jb .fill

    mov bx, source
    mov di, source_descriptor
    call set_descriptor_base
    mov bx, target
    mov di, target_descriptor
    call set_descriptor_base

    mov si, gdt
    mov cx, 128
    mov ah, 87h
    int 15h
    jc fail
    or ah, ah
    jnz fail

    xor bx, bx
.verify:
    mov al, bl
    xor al, 5ah
    cmp [target + bx], al
    jne fail
    inc bx
    cmp bx, 256
    jb .verify

    mov dx, pass_message
    mov ax, 0900h
    int 21h
    mov ax, 4c00h
    int 21h

fail:
    mov dx, fail_message
    mov ax, 0900h
    int 21h
    mov ax, 4c01h
    int 21h

; DS:BX conventional address to a 24-bit 286 descriptor base at DS:DI.
set_descriptor_base:
    mov ax, ds
    mov dx, ax
    mov cl, 12
    shr dx, cl
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    add ax, bx
    adc dx, 0
    mov [di + 2], ax
    mov [di + 4], dl
    mov byte [di + 7], 0
    ret

align 8
gdt:
    dq 0
    dq 0
source_descriptor:
    dw 0ffffh, 0
    db 0, 093h, 0, 0
target_descriptor:
    dw 0ffffh, 0
    db 0, 093h, 0, 0
    dq 0
    dq 0

pass_message db 'INT15_87_286_PASS', 13, 10, '$'
fail_message db 'INT15_87_286_FAIL', 13, 10, '$'
source times 256 db 0
target times 256 db 0
