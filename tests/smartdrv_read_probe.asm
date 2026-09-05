bits 16
org 100h

sector_number equ 1000

start:
    push cs
    pop ds
    push cs
    pop es
    cld
    ; Both the initial cache miss and repeated hit must copy exactly one
    ; sector, leaving the following guard untouched.
    mov di, guard
    mov cx, 8192
    mov al, 0x5a
    rep stosb
    call read_sector
    jc failed
    mov di, guard
    mov cx, 8192
    mov al, 0x5a
    repe scasb
    jne failed
    call read_sector
    jc failed
    mov di, guard
    mov cx, 8192
    mov al, 0x5a
    repe scasb
    jne failed
    mov ax, 4c00h
    int 21h

read_sector:
    mov al, 2
    mov cx, 1
    mov dx, sector_number
    mov bx, read_buffer
    int 25h
    popf
    jc read_done
    mov si, marker
    mov di, read_buffer
    mov cx, marker_size
    repe cmpsb
    je read_done
    stc
read_done:
    ret

failed:
    mov ax, 4c01h
    int 21h

marker db 'SMARTDRV_SECTOR_OK'
marker_size equ $ - marker
read_buffer times 512 db 0
guard times 8192 db 0
