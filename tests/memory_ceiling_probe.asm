bits 16
org 100h

start:
    int 12h
    mov [int12_kb], ax
    mov ax, 40h
    mov es, ax
    mov ax, [es:13h]
    mov [bda_kb], ax
    mov ax, [es:0eh]
    mov [ebda_segment], ax

    mov dx, prefix
    call print_string
    mov ax, [int12_kb]
    call print_hex_word
    mov dx, bda_label
    call print_string
    mov ax, [bda_kb]
    call print_hex_word
    mov dx, ebda_label
    call print_string
    mov ax, [ebda_segment]
    call print_hex_word
    mov dx, newline
    call print_string
    mov ax, 4c00h
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
    jmp short print_char
.digit:
    add al, '0'
print_char:
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

print_string:
    mov ah, 09h
    int 21h
    ret

int12_kb dw 0
bda_kb dw 0
ebda_segment dw 0
character db 0
prefix db 'MEMORY_CEILING INT12=', '$'
bda_label db ' BDA=', '$'
ebda_label db ' EBDA=', '$'
newline db 13, 10, '$'
