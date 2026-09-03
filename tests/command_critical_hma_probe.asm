bits 16
org 100h

start:
    push cs
    pop ds
    mov ax, 122eh
    mov dl, 4
    int 2fh
    mov ax, es
    cmp ax, 0ffffh
    jne failure
    cmp byte [es:di], 0ffh
    jne failure
    cmp byte [es:di + 1], 6
    jne failure
    cmp byte [es:di + 2], 16h
    jne failure
    cmp byte [es:di + 3], 15h
    jne failure
    mov dx, success_message
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

failure:
    mov dx, failure_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

success_message db 'COMMAND_CRITICAL_HMA_PASS', 13, 10, '$'
failure_message db 'COMMAND_CRITICAL_HMA_FAILURE', 13, 10, '$'
