bits 16
org 100h

start:
    mov ax, 1500h
    xor bx, bx
    int 2fh
    cmp bx, 1
    jne fail
    cmp cx, 4
    jne fail

    mov bx, 4
    mov ax, 150bh
    int 2fh
    cmp ax, 0adadh
    jne fail
    mov bx, 3
    mov ax, 150bh
    int 2fh
    or ax, ax
    jne fail

    mov ax, 150ch
    int 2fh
    cmp bx, 0217h
    jne fail

    push ds
    pop es
    mov bx, drive_list
    mov ax, 150dh
    int 2fh
    cmp byte [drive_list], 4
    jne fail

    mov bx, device_list
    mov ax, 1501h
    int 2fh
    cmp byte [device_list], 0
    jne fail
    mov ax, [device_list + 1]
    or ax, [device_list + 3]
    jz fail

    mov dx, pass_message
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

fail:
    mov dx, fail_message
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

drive_list  times 8 db 0ffh
device_list times 40 db 0
pass_message db 'MSCDEX_API_PASS',13,10,'$'
fail_message db 'MSCDEX_API_FAIL',13,10,'$'
