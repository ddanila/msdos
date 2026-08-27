bits 16
org 100h

start:
    mov ax, 0004h               ; CGA 320x200, profile-supported graphics mode
    int 10h

    ; A deterministic asymmetric pattern makes rotation/reversal observable.
    mov dx, 24
row_loop:
    mov cx, 16
column_loop:
    mov ah, 0ch
    mov al, 3
    xor bh, bh
    int 10h
    inc cx
    cmp cx, 112
    jb column_loop
    inc dx
    cmp dx, 72
    jb row_loop

    mov dx, 82
diagonal_loop:
    mov cx, dx
    sub cx, 70
    mov ah, 0ch
    mov al, 2
    xor bh, bh
    int 10h
    inc dx
    cmp dx, 146
    jb diagonal_loop

    int 05h                     ; GRAPHICS resident Print Screen handler

    mov ax, 0003h
    int 10h
    mov ax, 4c00h
    int 21h
