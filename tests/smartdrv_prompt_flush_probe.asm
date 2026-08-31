bits 16
org 100h

start:
    mov ax, 4a11h
    mov bx, 1
    int 2fh
    or ax, ax
    jnz failed
    mov dx, pass_message
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

failed:
    mov dx, fail_message
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

pass_message db 'SMARTDRV_PROMPT_FLUSH_PASS',13,10,'$'
fail_message db 'SMARTDRV_PROMPT_FLUSH_FAIL',13,10,'$'
