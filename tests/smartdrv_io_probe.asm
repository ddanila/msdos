bits 16
org 100h

sector_number equ 1000

start:
    push cs
    pop ds
    push cs
    pop es

    mov di, write_buffer
    mov cx, 512
    mov al, 0a5h
    rep stosb
    mov si, marker
    mov di, write_buffer
    mov cx, marker_size
    rep movsb

    ; INT 26h leaves the caller flags word on the stack.
    mov al, 2                   ; C:
    mov cx, 1
    mov dx, sector_number
    mov bx, write_buffer
    int 26h
    popf
    jc failed

    mov al, 2
    mov cx, 1
    mov dx, sector_number
    mov bx, read_buffer
    int 25h
    popf
    jc failed

    mov si, write_buffer
    mov di, read_buffer
    mov cx, 512
    repe cmpsb
    jne failed

    mov ax, 4c00h
    int 21h

failed:
    mov ax, 4c01h
    int 21h

marker db 'SMARTDRV_SECTOR_OK'
marker_size equ $ - marker
write_buffer times 512 db 0
read_buffer times 512 db 0
