bits 16
org 100h

timeout_ticks equ 182

start:
    push cs
    pop ds
    mov ah, 00h
    int 1ah
    mov [start_tick], dx

poll:
    mov ax, 0104h              ; PRINT: lock and return queue status
    int 2fh
    jc busy
    cmp byte [si], 0
    pushf
    mov ax, 0105h              ; PRINT: unlock queue
    int 2fh
    popf
    push cs
    pop ds
    je complete

busy:
    push cs
    pop ds
    int 28h                    ; yield while PRINT drains in the background
    mov ah, 00h
    int 1ah
    sub dx, [start_tick]
    cmp dx, timeout_ticks
    jb poll
    mov ax, 4c01h
    int 21h

complete:
    mov ax, 4c00h
    int 21h

start_tick dw 0
