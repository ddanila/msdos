bits 16
cpu 8086
org 100h

    mov ax, 6601h
    int 21h
    jc fail
    mov bp, bx
    mov ax, 0ad02h
    int 2fh
    jc fail
    cmp bx, bp
    jne fail
    mov dx, passed
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
fail:
    mov dx, failed
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
passed db 'RU_CODEPAGE_PASS',13,10,'$'
failed db 'RU_CODEPAGE_FAIL',13,10,'$'
