bits 16
org 0

header:
    dw 05a4dh
    dw (image_end - $$) & 01ffh
    dw ((image_end - $$) + 511) / 512
    dw 0
    dw 2
    dw 0010h
    dw 0020h
    dw 0
    dw 0100h
    dw 0
    dw entry - load_start
    dw 0
    dw 01ch
    dw 0
    times 32 - ($ - $$) db 0

load_start:
entry:
    mov bx, ds
    push cs
    pop ds

    mov ax, bx
    mov si, psp_label - load_start
    call print_word

    mov ax, 5800h
    int 21h
    jc fail
    mov si, strategy_label - load_start
    call print_word

    mov ax, 5802h
    int 21h
    jc fail
    xor ah, ah
    mov si, link_label - load_start
    call print_word

    mov dx, complete - load_start
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

fail:
    mov dx, failed - load_start
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
    mov dx, newline - load_start
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
    mov [character - load_start], al
    push ax
    push dx
    mov dx, character - load_start
    mov ah, 09h
    int 21h
    pop dx
    pop ax
    ret

psp_label db 'EXE_PSP=', '$'
strategy_label db 'EXE_STRATEGY=', '$'
link_label db 'EXE_UMB_LINK=', '$'
newline db 13, 10, '$'
complete db 'LOADHIGH_EXE_END', 13, 10, '$'
failed db 'LOADHIGH_EXE_FAIL', 13, 10, '$'
character db 0, '$'
image_end:
