bits 16
org 100h

start:
    push cs
    pop ds
    mov ax, 5802h
    int 21h
    jc fail
    mov [saved_link], al
    mov bx, 1
    mov ax, 5803h
    int 21h
    jc fail

    mov dx, begin_message
    mov ah, 09h
    int 21h
    mov ah, 52h
    int 21h
    mov ax, [es:bx - 2]
    mov cx, 256
.next:
    mov es, ax
    ; Include the conventional-to-UMA bridge and reserved gap records, not
    ; only the provider-owned UMB blocks themselves.
    cmp ax, 08000h
    jb .advance
    push ax
    mov dx, segment_label
    mov ah, 09h
    int 21h
    pop ax
    call print_hex_word
    mov dx, signature_label
    mov ah, 09h
    int 21h
    mov al, [es:0]
    call print_char
    mov dx, owner_label
    mov ah, 09h
    int 21h
    mov ax, [es:1]
    call print_hex_word
    mov dx, size_label
    mov ah, 09h
    int 21h
    mov ax, [es:3]
    call print_hex_word
    mov dx, newline
    mov ah, 09h
    int 21h
.advance:
    cmp byte [es:0], 'Z'
    je done
    cmp byte [es:0], 'M'
    jne fail_restore
    mov ax, es
    add ax, [es:3]
    inc ax
    loop .next
    jmp short fail_restore

done:
    call restore_link
    mov dx, end_message
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

fail_restore:
    call restore_link
fail:
    mov dx, fail_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

restore_link:
    xor bx, bx
    mov bl, [saved_link]
    mov ax, 5803h
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

saved_link db 0
character db 0
begin_message db 'UMB_MCB_LAYOUT_BEGIN', 13, 10, '$'
segment_label db 'MCB SEG=', '$'
signature_label db ' SIG=', '$'
owner_label db ' OWNER=', '$'
size_label db ' SIZE=', '$'
newline db 13, 10, '$'
end_message db 'UMB_MCB_LAYOUT_END', 13, 10, '$'
fail_message db 'UMB_MCB_LAYOUT_FAIL', 13, 10, '$'
