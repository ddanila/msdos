bits 16
org 100h

start:
    cli
    mov sp, stack_top
    sti
    push cs
    pop ds
    mov dx, banner
    call print_string

    mov ax, 5800h
    mov bx, 2222h
    mov byte [case_id], '0'
    call invoke

    mov ax, 5801h
    mov bx, 0000h
    mov byte [case_id], '1'
    call invoke

    mov ax, 5801h
    mov bx, 0100h
    mov byte [case_id], 'I'
    call invoke

    mov ax, 5802h
    mov bx, 2222h
    mov byte [case_id], '2'
    call invoke

    mov ax, 5803h
    xor bx, bx
    mov byte [case_id], '3'
    call invoke

    mov ax, 5803h
    mov bx, 0100h
    mov byte [case_id], 'L'
    call invoke

    mov ax, 5804h
    mov bx, 2222h
    mov byte [case_id], '4'
    call invoke

    mov dx, complete
    call print_string
    mov ax, 4c00h
    int 21h

invoke:
    mov cx, 3333h
    mov dx, 4444h
    mov si, 5555h
    mov di, 6666h
    mov bp, 7777h
    push ds
    mov word [saved_ds], ds
    mov word [saved_es], 8888h
    mov es, [saved_es]
    int 21h
    pushf
    pop word [cs:result_flags]
    mov [cs:result_ax], ax
    mov [cs:result_bx], bx
    mov [cs:result_cx], cx
    mov [cs:result_dx], dx
    mov [cs:result_si], si
    mov [cs:result_di], di
    mov [cs:result_bp], bp
    mov [cs:result_ds], ds
    mov [cs:result_es], es
    pop ds
    push cs
    pop es
    call print_result
    ret

print_result:
    mov dx, case_label
    call print_string
    mov al, [case_id]
    call print_character
    mov dx, cf_label
    call print_string
    mov ax, [result_flags]
    and al, 1
    add al, '0'
    call print_character
    mov si, result_words
    mov di, word_labels
    mov cx, 9
.word:
    mov dx, [di]
    call print_string
    mov ax, [si]
    call print_hex_word
    add si, 2
    add di, 2
    loop .word
    call print_newline
    ret

print_hex_word:
    push ax
    xchg al, ah
    call print_hex_byte
    pop ax
    call print_hex_byte
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
    call print_hex_nibble
    ret
print_hex_nibble:
    cmp al, 9
    jbe .digit
    add al, 'A' - 10
    jmp short print_character
.digit:
    add al, '0'
print_character:
    push ax
    push bx
    push cx
    push dx
    mov [character], al
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
    push ax
    push bx
    push cx
    push si
    mov si, dx
    xor cx, cx
.find_end:
    cmp byte [si], 0
    je .write
    inc si
    inc cx
    jmp short .find_end
.write:
    mov bx, 1
    mov ah, 40h
    int 21h
    pop si
    pop cx
    pop bx
    pop ax
    ret
print_newline:
    mov dx, newline
    jmp short print_string

case_id db 0
character db 0
saved_ds dw 0
saved_es dw 0
result_words:
result_ax dw 0
result_bx dw 0
result_cx dw 0
result_dx dw 0
result_si dw 0
result_di dw 0
result_bp dw 0
result_ds dw 0
result_es dw 0
result_flags dw 0
word_labels dw ax_label, bx_label, cx_label, dx_label, si_label
            dw di_label, bp_label, ds_label, es_label
banner db 'UMB_REGISTERS_BEGIN', 13, 10, 0
complete db 'UMB_REGISTERS_END', 13, 10, 0
case_label db 'CASE=', 0
cf_label db ' CF=', 0
ax_label db ' AX=', 0
bx_label db ' BX=', 0
cx_label db ' CX=', 0
dx_label db ' DX=', 0
si_label db ' SI=', 0
di_label db ' DI=', 0
bp_label db ' BP=', 0
ds_label db ' DS=', 0
es_label db ' ES=', 0
newline db 13, 10, 0

align 16
stack_space times 512 db 0
stack_top:
program_end:
