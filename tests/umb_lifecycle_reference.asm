bits 16
org 100h

start:
    cli
    mov sp, stack_top
    sti
    push cs
    pop ds
    push cs
    pop es
    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h

    mov dx, banner
    call print_string
    mov bx, 1
    mov ax, 5803h
    mov dx, link_label
    call invoke_and_print
    mov bx, 0040h
    mov ax, 5801h
    mov dx, strategy_label
    call invoke_and_print

    mov bx, 0ffffh
    mov ah, 48h
    mov dx, largest_upper_label
    call invoke_and_print
    mov [largest_upper], bx

    mov bx, 10h
    mov ah, 48h
    mov dx, allocate_label
    call invoke_and_print
    jc finish
    mov [allocated_segment], ax
    mov es, ax
    mov word [es:0], 5aa5h

    mov bx, 8
    mov ah, 4ah
    mov dx, shrink_label
    call invoke_and_print
    call print_current_mcb_size
    mov bx, 20h
    mov ah, 4ah
    mov dx, grow_label
    call invoke_and_print
    call print_current_mcb_size
    mov bx, 0ffffh
    mov ah, 4ah
    mov dx, grow_fail_label
    call invoke_and_print
    call print_current_mcb_size
    call print_current_mcb_signature

    xor bx, bx
    mov ax, 5803h
    mov dx, unlink_live_label
    call invoke_and_print
    mov ax, [es:0]
    mov dx, live_value_label
    call print_word_line
    mov bx, 1
    mov ax, 5803h
    mov dx, relink_live_label
    call invoke_and_print
    mov ah, 49h
    mov dx, free_label
    call invoke_and_print

    mov bx, [largest_upper]
    mov ah, 48h
    mov dx, exact_largest_label
    call invoke_and_print
    jc fallback_largest
    mov [allocated_segment], ax
    mov bx, 1
    mov ah, 48h
    mov dx, after_largest_label
    call invoke_and_print
    jc free_largest
    mov [second_segment], ax
    mov es, ax
    mov ah, 49h
    int 21h
free_largest:
    mov es, [allocated_segment]
    mov ah, 49h
    int 21h

fallback_largest:
    mov bx, [largest_upper]
    inc bx
    mov ah, 48h
    mov dx, upper_no_fallback_label
    call invoke_and_print
    mov bx, 0080h
    mov ax, 5801h
    int 21h
    mov bx, [largest_upper]
    inc bx
    mov ah, 48h
    mov dx, upper_then_low_label
    call invoke_and_print
    jc query_fallback_largest
    mov es, ax
    mov ah, 49h
    int 21h
query_fallback_largest:
    mov bx, 0ffffh
    mov ah, 48h
    mov dx, largest_fallback_label
    call invoke_and_print

finish:
    mov dx, complete
    call print_string
    mov ax, 4c00h
    int 21h

print_current_mcb_size:
    push ax
    push es
    mov ax, es
    dec ax
    mov es, ax
    mov ax, [es:3]
    mov dx, mcb_size_label
    call print_word_line
    pop es
    pop ax
    ret
print_current_mcb_signature:
    push ax
    push dx
    push es
    mov ax, es
    dec ax
    mov es, ax
    mov al, [es:0]
    mov [mcb_signature], al
    mov dx, mcb_signature_label
    call print_string
    mov al, [mcb_signature]
    call print_character
    call print_newline
    pop es
    pop dx
    pop ax
    ret

invoke_and_print:
    push dx
    int 21h
    pushf
    pop cx
    pop dx
    call print_result
    push word [result_flags]
    popf
    ret

print_result:
    push ax
    push bx
    push cx
    push dx
    mov [result_ax], ax
    mov [result_bx], bx
    mov [result_flags], cx
    call print_string
    mov dx, carry_label
    call print_string
    mov ax, [result_flags]
    and al, 1
    add al, '0'
    call print_character
    mov dx, ax_label
    call print_string
    mov ax, [result_ax]
    call print_hex_word
    mov dx, bx_label
    call print_string
    mov ax, [result_bx]
    call print_hex_word
    call print_newline
    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_word_line:
    push ax
    call print_string
    pop ax
    call print_hex_word
    jmp short print_newline

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

largest_upper dw 0
allocated_segment dw 0
second_segment dw 0
result_ax dw 0
result_bx dw 0
result_flags dw 0
character db 0
mcb_signature db 0
banner db 'UMB_LIFECYCLE_BEGIN', 13, 10, 0
link_label db 'LINK ', 0
strategy_label db 'STRATEGY_0040 ', 0
largest_upper_label db 'LARGEST_UPPER ', 0
allocate_label db 'ALLOC_0010 ', 0
shrink_label db 'SHRINK_0008 ', 0
grow_label db 'GROW_0020 ', 0
grow_fail_label db 'GROW_FFFF ', 0
mcb_size_label db 'MCB_SIZE=', 0
mcb_signature_label db 'MCB_SIGNATURE=', 0
unlink_live_label db 'UNLINK_LIVE ', 0
live_value_label db 'LIVE_VALUE=', 0
relink_live_label db 'RELINK_LIVE ', 0
free_label db 'FREE_LIVE ', 0
exact_largest_label db 'ALLOC_EXACT_LARGEST ', 0
after_largest_label db 'ALLOC_AFTER_LARGEST ', 0
upper_no_fallback_label db 'UPPER_NO_FALLBACK ', 0
upper_then_low_label db 'UPPER_THEN_LOW ', 0
largest_fallback_label db 'LARGEST_FALLBACK ', 0
carry_label db 'C=', 0
ax_label db ' AX=', 0
bx_label db ' BX=', 0
newline db 13, 10, 0
complete db 'UMB_LIFECYCLE_END', 13, 10, 0
stack_space times 512 db 0
stack_top:
program_end:
