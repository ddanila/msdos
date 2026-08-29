bits 16
org 100h

; Clean-room resident child for LOADHIGH ownership and lifetime testing.

start:
    push cs
    pop ds
    mov dx, psp_message
    mov ah, 09h
    int 21h
    mov ax, cs
    call print_hex_word
    mov dx, newline
    mov ah, 09h
    int 21h

    mov dx, resident_handler
    mov ax, 2563h
    int 21h
    mov dx, (resident_end - $$ + 100h + 15) / 16
    mov ax, 312ah
    int 21h

resident_handler:
    push ax
    push dx
    push ds
    push cs
    pop ds
    mov dx, handler_message
    mov ah, 09h
    int 21h
    pop ds
    pop dx
    pop ax
    iret

print_hex_word:
    push dx
    push ax
    mov al, ah
    call print_hex_byte
    pop ax
    call print_hex_byte
    pop dx
    ret

print_hex_byte:
    push ax
    shr al, 1
    shr al, 1
    shr al, 1
    shr al, 1
    call print_hex_nibble
    pop ax
    and al, 0fh
print_hex_nibble:
    cmp al, 9
    jbe .digit
    add al, 'A' - 10
    jmp short .write
.digit:
    add al, '0'
.write:
    mov dl, al
    mov ah, 02h
    int 21h
    ret

psp_message     db 'LOADHIGH_TSR_PSP=','$'
handler_message db 'LOADHIGH_TSR_HANDLER_PASS',13,10,'$'
newline         db 13,10,'$'
resident_end:
