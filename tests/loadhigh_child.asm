bits 16
org 100h

start:
    push cs
    pop ds

    mov ax, [2ch]
    or ax, ax
    jz fail
    mov es, ax
    dec ax
    mov es, ax
    mov ax, cs
    cmp [es:1], ax
    jne fail

    mov ax, cs
    mov si, psp_label
    call print_word

    mov ax, 5800h
    int 21h
    jc fail
    mov si, strategy_label
    call print_word

    mov ax, 5802h
    int 21h
    jc fail
    xor ah, ah
    mov si, link_label
    call print_word

    mov dx, tail_label
    mov ah, 09h
    int 21h
    xor cx, cx
    mov cl, [80h]
    mov bx, 1
    mov dx, 81h
    mov ah, 40h
    int 21h
    mov dx, newline
    mov ah, 09h
    int 21h

    mov dx, complete
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

fail:
    mov dx, failed
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

print_word:
    push ax
    mov dx, si
    mov ah, 09h
    int 21h
    pop ax
    xchg al, ah
    call print_byte
    xchg al, ah
    call print_byte
    mov dx, newline
    mov ah, 09h
    int 21h
    ret

print_byte:
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

psp_label db 'CHILD_PSP=', '$'
strategy_label db 'CHILD_STRATEGY=', '$'
link_label db 'CHILD_UMB_LINK=', '$'
tail_label db 'CHILD_TAIL=', '$'
newline db 13, 10, '$'
complete db 'LOADHIGH_CHILD_END', 13, 10, '$'
failed db 'LOADHIGH_CHILD_FAIL', 13, 10, '$'
character db 0
