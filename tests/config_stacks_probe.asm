bits 16
org 100h

; Report the largest free DOS memory block after releasing the COM arena.

start:
    push cs
    pop ds
    push ds
    pop es

    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    jc failed

    mov bx, 0ffffh
    mov ah, 48h
    int 21h
    jnc failed                     ; The deliberately oversized request fails.

    mov si, prefix
    call serial_print
    mov ax, bx
    call serial_hex_word
    mov si, newline
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

serial_hex_word:
    push ax
    mov al, ah
    call serial_hex_byte
    pop ax
serial_hex_byte:
    push ax
    shr al, 1
    shr al, 1
    shr al, 1
    shr al, 1
    call serial_hex_nibble
    pop ax
    and al, 0fh
serial_hex_nibble:
    add al, '0'
    cmp al, '9'
    jbe serial_char
    add al, 'A' - '9' - 1
serial_char:
    mov ah, al
.wait:
    mov dx, 03fdh
    in al, dx
    test al, 20h
    jz .wait
    mov dx, 03f8h
    mov al, ah
    out dx, al
    ret

serial_print:
    lodsb
    test al, al
    jz .done
    call serial_char
    jmp serial_print
.done:
    ret

prefix       db 'CONFIG_STACKS_FREE=', 0
newline      db 13, 10, 0
fail_message db 'CONFIG_STACKS_FAIL', 13, 10, 0
program_end:
