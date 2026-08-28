bits 16
org 100h


start:
    push cs
    pop ds

    mov ah, 52h
    int 21h
    mov si, [es:bx + 59]
    mov ax, [es:bx + 61]
    cmp si, 0ffffh
    jne .pointer_present
    cmp ax, 0ffffh
    je failed
.pointer_present:
    mov es, ax
    add si, 4
    mov di, expected_name
    mov cx, 8
.compare:
    mov al, [es:si]
    cmp al, [di]
    jne failed
    inc si
    inc di
    loop .compare

    mov si, pass_message
    call serial_print
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

failed:
    mov si, fail_message
    call serial_print
    mov ax, 4c01h
    int 21h

serial_print:
    lodsb
    test al, al
    jz .done
    mov ah, al
.wait:
    mov dx, 03fdh
    in al, dx
    test al, 20h
    jz .wait
    mov dx, 03f8h
    mov al, ah
    out dx, al
    jmp serial_print
.done:
    ret

expected_name db 'TESTIFS '
pass_message  db 'CONFIG_IFS_PASS', 13, 10, 0
fail_message  db 'CONFIG_IFS_FAIL', 13, 10, 0
