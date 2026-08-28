bits 16
org 100h

start:
    push cs
    pop ds
    mov si, message
    call serial_print
    mov ax, cs
    call serial_hex_word
    mov si, newline
    call serial_print
    mov ax, 4c2ah
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
    push ax
    push dx
    mov ah, al
.wait:
    mov dx, 03fdh
    in al, dx
    test al, 20h
    jz .wait
    mov dx, 03f8h
    mov al, ah
    out dx, al
    pop dx
    pop ax
    ret

serial_print:
.next:
    lodsb
    test al, al
    jz .done
    call serial_char
    jmp .next
.done:
    ret

message db 'INSTALLHIGH_REF_RAN SEG=', 0
newline db 13, 10, 0
