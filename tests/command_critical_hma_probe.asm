bits 16
org 100h

start:
    push cs
    pop ds

%ifdef EXPECTED_CLASS_PTRS
    mov ah, 51h
    int 21h
    mov es, bx
    mov ax, [es:16h]            ; parent PSP: the permanent COMMAND shell
    mov es, ax
    mov si, EXPECTED_CLASS_PTRS
    mov cx, 5
    xor dx, dx                  ; retained classes copied to HMA
.class_loop:
    cmp word [es:si + 2], 0ffffh
    jne .nonresident_class
    mov bx, [es:si]
    cmp bx, EXPECTED_CATALOG_BASE
    jb failure
    cmp bx, EXPECTED_CATALOG_END
    jae failure
    push es
    mov ax, 0ffffh
    mov es, ax
    cmp byte [es:bx], 0ffh
    pop es
    jne failure
    inc dx
    jmp .next_class
.nonresident_class:
.next_class:
    add si, 4
    loop .class_loop
    cmp dx, EXPECTED_HMA_CLASSES
    jne failure
%endif

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

success_message db 'COMMAND_CATALOG_HMA_PASS', 13, 10, '$'
failure_message db 'COMMAND_CATALOG_HMA_FAILURE', 13, 10, '$'
