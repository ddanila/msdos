bits 16
org 100h

first_sector equ 1000
track_stride equ 63
write_count equ 10

start:
    push cs
    pop ds
    push cs
    pop es
    cld
    xor si, si
.next:
    mov al, [pattern]
    mov di, sector_buffer
    mov cx, 512
    rep stosb
    mov ax, si
    mov dx, track_stride
    mul dx
    add ax, first_sector
    mov dx, ax
    mov al, 2
    mov cx, 1
    mov bx, sector_buffer
    push si
    int 26h
    popf
    pop si
    jc failed
    inc si
    inc byte [pattern]
    cmp si, write_count
    jb .next
    mov ax, 4c00h
    int 21h

failed:
    mov ax, 4c01h
    int 21h

pattern db 0a0h
sector_buffer times 512 db 0
