bits 16
org 100h


start:
    push cs
    pop ds
    cld

    mov si, expected_437
    cmp byte [80h], 0
    je install_failed
    cmp byte [82h], '8'
    jne .have_expected
    mov si, expected_850
.have_expected:

    mov ax, 0b000h
    int 2fh
    cmp al, 0ffh
    jne install_failed

    mov bx, table_pointer
    mov ax, 0b001h
    int 2fh
    cmp al, 0ffh
    jne install_failed
    les di, [table_pointer]

    push ds
    xor ax, ax
    mov ds, ax
    cmp di, [1fh * 4]
    jne .vector_failed
    mov ax, es
    cmp ax, [1fh * 4 + 2]
.vector_failed:
    pop ds
    jne vector_failed

    mov cx, 1024
    repe cmpsb
    jne glyph_failed
    mov cx, 16
    repe cmpsb
    jne metadata_failed

    mov ax, 4c00h
    int 21h

install_failed:
    mov ax, 4c01h
    int 21h

vector_failed:
    mov ax, 4c02h
    int 21h

glyph_failed:
    dec di
    dec si
    mov bl, [es:di]
    mov bh, [si]
    mov ax, 1023
    sub ax, cx
    push ax
    mov dx, mismatch_message
    mov ah, 09h
    int 21h
    pop ax
    call print_hex_word
    mov dl, ':'
    call print_char
    mov al, bl
    call print_hex_byte
    mov dl, '/'
    call print_char
    mov al, bh
    call print_hex_byte
    mov dx, newline
    mov ah, 09h
    int 21h
    mov ax, 4c03h
    int 21h

metadata_failed:
    mov ax, 4c04h
    int 21h

print_hex_word:
    push ax
    mov al, ah
    call print_hex_byte
    pop ax
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
    add al, '0'
    cmp al, '9'
    jbe .emit
    add al, 'A' - '9' - 1
.emit:
    mov dl, al
print_char:
    mov ah, 02h
    int 21h
    ret

table_pointer dd 0
mismatch_message db 'GRAFTABL_MISMATCH=', '$'
newline db 13, 10, '$'

expected_437:
    incbin "out/graftabl-437.bin"
    dw 437
    db 'USA', 0
    times 10 db 0

expected_850:
    incbin "out/graftabl-850.bin"
    dw 850
    db 'Multi-lingual', 0
