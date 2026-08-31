bits 16
org 100h

sector_number equ 1000

start:
    push cs
    pop ds
    push cs
    pop es
    cld
    mov al, 2
    mov cx, 1
    mov dx, sector_number
    mov bx, read_buffer
    int 25h
    popf
    jc failed
    mov si, marker
    mov di, read_buffer
    mov cx, marker_size
    repe cmpsb
    jne failed
    mov ax, 4c00h
    int 21h

failed:
    mov ax, 4c01h
    int 21h

marker db 'SMARTDRV_SECTOR_OK'
marker_size equ $ - marker
read_buffer times 512 db 0
