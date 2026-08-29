bits 16
org 100h

start:
    ; EXEC copies only the strings needed by this probe. Inspect the parent
    ; COMMAND PSP to measure the environment block governed by /E itself.
    mov ax, [16h]
    or ax, ax
    jz fail
    mov es, ax
    mov ax, [es:2ch]
    or ax, ax
    jz fail
    dec ax
    mov es, ax
    cmp byte [es:0], 'M'
    je .valid
    cmp byte [es:0], 'Z'
    jne fail
.valid:
    mov ax, [es:3]
    push ax
    mov dx, message
    mov ah, 09h
    int 21h
    pop ax
    call print_hex_word
    mov dx, newline
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

fail:
    mov dx, fail_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

print_hex_word:
    push ax
    xchg al, ah
    call print_hex_byte
    pop ax
print_hex_byte:
    push ax
    shr al, 1
    shr al, 1
    shr al, 1
    shr al, 1
    call print_nibble
    pop ax
    and al, 0fh
print_nibble:
    cmp al, 9
    jbe .digit
    add al, 'A' - 10
    jmp short .write
.digit:
    add al, '0'
.write:
    mov [character], al
    push ax
    push bx
    push cx
    push dx
    mov bx, 1
    mov cx, 1
    mov dx, character
    mov ah, 40h
    int 21h
    pop dx
    pop cx
    pop bx
    pop ax
    ret

message db 'COMMAND_ENV_SIZE=', '$'
fail_message db 'COMMAND_ENV_PROBE_FAIL', 13, 10, '$'
newline db 13, 10, '$'
character db 0
