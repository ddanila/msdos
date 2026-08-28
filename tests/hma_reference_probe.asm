bits 16
org 100h

start:
    cli
    mov sp, stack_top
    sti
    push cs
    pop ds
    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    jc no_xms

    mov ax, 352fh
    int 21h
    mov ax, es
    mov si, int2f_segment_label
    call print_word
    mov ax, bx
    mov si, int2f_offset_label
    call print_word

    mov ax, 4300h
    int 2fh
    cmp al, 80h
    jne no_xms
    mov ax, 4310h
    int 2fh
    mov [xms_entry], bx
    mov [xms_entry+2], es

    mov ax, 0ffffh
    int 2fh
    mov dx, int2f_chain_message
    mov ah, 09h
    int 21h

    mov ah, 07h
    call far [xms_entry]
    mov si, a20_label
    call print_result

    mov ah, 01h
    mov dx, 0ffffh
    call far [xms_entry]
    mov [hma_request_ax], ax
    mov si, hma_label
    call print_result
    cmp word [hma_request_ax], 1
    jne short memory_query
    mov ah, 02h
    call far [xms_entry]

memory_query:
    mov bx, 0ffffh
    mov ah, 48h
    int 21h
    mov ax, bx
    mov si, largest_label
    call print_word

    mov ah, 52h
    int 21h
    mov ax, [es:bx - 2]
    mov [first_mcb], ax
    mov si, first_mcb_label
    call print_word

    xor dx, dx
    mov ax, [first_mcb]
.arena_next:
    mov es, ax
    cmp word [es:1], 0
    jne .arena_owned
    add dx, [es:3]
.arena_owned:
    mov cl, [es:0]
    cmp cl, 'Z'
    je .arena_done
    cmp cl, 'M'
    jne .arena_bad
    add ax, [es:3]
    inc ax
    jmp short .arena_next
.arena_bad:
    mov dx, 0ffffh
.arena_done:
    mov ax, dx
    mov si, total_free_label
    call print_word

    mov ah, 30h
    int 21h
    mov si, version_label
    call print_word

    mov dx, complete
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

no_xms:
    mov dx, no_xms_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

print_result:
    push ax
    push bx
    push dx
    mov dx, si
    mov ah, 09h
    int 21h
    pop dx
    pop bx
    pop ax
    call print_hex_word
    mov dx, bx_label
    push ax
    mov ah, 09h
    int 21h
    pop ax
    mov ax, bx
    call print_hex_word
    mov dx, newline
    mov ah, 09h
    int 21h
    ret

print_word:
    push ax
    mov dx, si
    mov ah, 09h
    int 21h
    pop ax
    call print_hex_word
    mov dx, newline
    mov ah, 09h
    int 21h
    ret

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
    mov [character], al
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
    ret

xms_entry dd 0
hma_request_ax dw 0
first_mcb dw 0
character db 0
a20_label db 'A20 AX=', '$'
int2f_segment_label db 'INT2F_SEGMENT=', '$'
int2f_offset_label db 'INT2F_OFFSET=', '$'
hma_label db 'HMA_REQUEST AX=', '$'
largest_label db 'LARGEST_LOW=', '$'
first_mcb_label db 'FIRST_MCB=', '$'
total_free_label db 'TOTAL_FREE=', '$'
version_label db 'DOS_VERSION_AX=', '$'
bx_label db ' BL=', '$'
newline db 13, 10, '$'
complete db 'HMA_REFERENCE_END', 13, 10, '$'
no_xms_message db 'HMA_REFERENCE_NO_XMS', 13, 10, '$'
int2f_chain_message db 'INT2F_CHAIN_RETURNED', 13, 10, '$'

align 16
stack_space times 512 db 0
stack_top:
program_end:
