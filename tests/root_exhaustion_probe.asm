bits 16
org 100h


start:
    push cs
    pop ds

    xor cx, cx
    mov dx, overflow_name
    mov ah, 3ch
    int 21h
    jnc failed
    cmp ax, 5
    jne failed

    xor cx, cx
    mov dx, temp_template
    mov ah, 5ah
    int 21h
    jnc failed
    cmp ax, 5
    jne failed

    xor cx, cx
    mov dx, overflow_name
    mov ah, 5bh
    int 21h
    jnc failed
    cmp ax, 5
    jne failed

    xor bx, bx
    xor cx, cx
    mov dx, 10h
    mov si, overflow_name
    mov ax, 6c00h
    int 21h
    jnc failed
    cmp ax, 5
    jne failed

    mov dx, filler_name
    mov ah, 41h
    int 21h
    jc failed

    xor cx, cx
    mov dx, overflow_name
    mov ah, 3ch
    int 21h
    jc failed
    mov bx, ax
    mov ah, 3eh
    int 21h
    jc failed
    mov dx, overflow_name
    mov ah, 41h
    int 21h
    jc failed

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

failed:
    mov dx, fail_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

filler_name   db 'RF00000.TMP', 0
overflow_name db 'ROOTFULL.TST', 0
temp_template db 'A:\', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
pass_message  db 'ROOT_EXHAUSTION_PASS', 13, 10, '$'
fail_message  db 'ROOT_EXHAUSTION_FAIL', 13, 10, '$'
