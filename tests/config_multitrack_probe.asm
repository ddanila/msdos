bits 16
org 100h


start:
    push cs
    pop ds

    mov ax, 3513h
    int 21h
    mov [old_int13_off], bx
    mov [old_int13_seg], es

    mov dx, int13_hook
    mov ax, 2513h
    int 21h

    mov byte [read_calls], 0
    mov byte [max_sectors], 0
    mov al, 2
    mov bx, disk_buffer
    mov cx, 10
    mov dx, 60
    int 25h
    pushf
    pop ax
    pop dx
    mov [result_flags], ax

    mov byte [write_calls], 0
    mov al, 2
    mov bx, disk_buffer
    mov cx, 1
    mov dx, 60
    int 26h
    pushf
    pop ax
    pop dx
    mov [write_result_flags], ax

    call restore_vector
    test word [result_flags], 1
    jnz failed
    test word [write_result_flags], 1
    jnz failed
    cmp byte [read_calls], 0
    je failed
    cmp byte [write_calls], 0
    je failed

    mov si, prefix
    call serial_print
    mov al, [read_calls]
    call serial_hex_byte
    mov al, ','
    call serial_char
    mov al, [max_sectors]
    call serial_hex_byte
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

restore_vector:
    push ds
    mov dx, [old_int13_off]
    mov ax, [old_int13_seg]
    mov ds, ax
    mov ax, 2513h
    int 21h
    pop ds
    ret

int13_hook:
    cmp ah, 02h
    jne .check_write
    cmp dl, 80h
    jne .chain
    inc byte [cs:read_calls]
    cmp al, [cs:max_sectors]
    jbe .chain
    mov [cs:max_sectors], al
.check_write:
    cmp ah, 03h
    jne .chain
    cmp dl, 80h
    jne .chain
    inc byte [cs:write_calls]
.chain:
    jmp far [cs:old_int13_off]

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

prefix          db 'CONFIG_MULTITRACK_IO=', 0
newline         db 13, 10, 0
fail_message    db 'CONFIG_MULTITRACK_FAIL', 13, 10, 0
old_int13_off   dw 0
old_int13_seg   dw 0
result_flags    dw 0
write_result_flags dw 0
read_calls      db 0
write_calls     db 0
max_sectors     db 0
disk_buffer     times 10 * 512 db 0
