bits 16
org 100h

start:
    cli
    mov sp, program_stack_top
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

    mov ah, 30h
    int 21h
    mov dx, version_label
    call print_string
    call print_version
    call print_newline

    mov ax, 5800h
    xor bx, bx
    mov dx, get_initial_label
    call invoke_and_print
    mov [original_strategy], ax

    mov si, strategy_cases
strategy_loop:
    lodsw
    cmp ax, 0ffffh
    je strategy_done
    mov bx, ax
    mov ax, 5801h
    mov dx, set_strategy_label
    call invoke_and_print
    mov ax, 5800h
    xor bx, bx
    mov dx, get_strategy_label
    call invoke_and_print
    jmp strategy_loop
strategy_done:

    mov bx, 0003h
    mov ax, 5801h
    mov dx, invalid_strategy_label
    call invoke_and_print
    mov bx, 0043h
    mov ax, 5801h
    mov dx, invalid_high_strategy_label
    call invoke_and_print
    mov bx, 0083h
    mov ax, 5801h
    mov dx, invalid_fallback_strategy_label
    call invoke_and_print
    mov bx, 0100h
    mov ax, 5801h
    mov dx, invalid_bh_strategy_label
    call invoke_and_print

    mov bx, [original_strategy]
    mov ax, 5801h
    int 21h

    mov ax, 5802h
    xor bx, bx
    mov dx, get_link_initial_label
    call invoke_and_print
    mov [original_link], ax

    mov bx, 0001h
    mov ax, 5803h
    mov dx, link_on_label
    call invoke_and_print
    mov ax, 5802h
    xor bx, bx
    mov dx, get_link_on_label
    call invoke_and_print

    mov bx, 0000h
    mov ax, 5803h
    mov dx, link_off_label
    call invoke_and_print
    mov ax, 5802h
    xor bx, bx
    mov dx, get_link_off_label
    call invoke_and_print

    mov bx, 0002h
    mov ax, 5803h
    mov dx, invalid_link_label
    call invoke_and_print
    mov bx, 0100h
    mov ax, 5803h
    mov dx, invalid_link_bh_label
    call invoke_and_print
    mov ax, 5804h
    xor bx, bx
    mov dx, invalid_subfunction_label
    call invoke_and_print

    mov bx, 0040h
    mov ax, 5801h
    int 21h
    mov bx, 0010h
    mov ah, 48h
    int 21h
    pushf
    pop cx
    mov dx, allocate_upper_unlinked_label
    call print_result
    test cl, 1
    jnz upper_unlinked_done
    mov es, ax
    mov ah, 49h
    int 21h
upper_unlinked_done:

    xor bx, bx
    cmp byte [original_link], 0
    je restore_link
    inc bx
restore_link:
    mov ax, 5803h
    int 21h

    mov bx, 0001h
    mov ax, 5803h
    int 21h
    mov ax, 5802h
    xor bx, bx
    mov dx, get_link_before_allocation_label
    call invoke_and_print
    mov bx, 0040h
    mov ax, 5801h
    int 21h
    mov ax, 5800h
    xor bx, bx
    mov dx, get_strategy_before_upper_only_label
    call invoke_and_print
    mov bx, 0010h
    mov ah, 48h
    int 21h
    pushf
    pop cx
    mov dx, allocate_upper_only_label
    call print_result
    test cl, 1
    jnz allocate_upper_then_low
    mov es, ax
    mov ah, 49h
    int 21h
allocate_upper_then_low:
    mov bx, 0080h
    mov ax, 5801h
    int 21h
    mov ax, 5800h
    xor bx, bx
    mov dx, get_strategy_before_fallback_label
    call invoke_and_print
    mov bx, 0010h
    mov ah, 48h
    int 21h
    pushf
    pop cx
    mov dx, allocate_upper_then_low_label
    call print_result
    test cl, 1
    jnz allocation_done
    mov es, ax
    mov ah, 49h
    int 21h
allocation_done:

    mov bx, [original_strategy]
    mov ax, 5801h
    int 21h
    xor bx, bx
    cmp byte [original_link], 0
    je restore_after_allocation
    inc bx
restore_after_allocation:
    mov ax, 5803h
    int 21h

    mov dx, complete
    call print_string
    mov ax, 4c00h
    int 21h

invoke_and_print:
    push dx
    int 21h
    pushf
    pop cx
    pop dx
    call print_result
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

print_version:
    push ax
    call print_hex_byte
    mov al, '.'
    call print_character
    pop ax
    mov al, ah
    call print_hex_byte
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
    jbe decimal_digit
    add al, 'A' - 10
    jmp print_character
decimal_digit:
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
find_string_end:
    cmp byte [si], 0
    je string_length_found
    inc si
    inc cx
    jmp find_string_end
string_length_found:
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
    jmp print_string

strategy_cases dw 0000h, 0001h, 0002h
               dw 0040h, 0041h, 0042h
               dw 0080h, 0081h, 0082h
               dw 0ffffh
original_strategy dw 0
original_link dw 0
result_ax dw 0
result_bx dw 0
result_flags dw 0
character db 0
banner db 'UMB_API_BEGIN', 13, 10, 0
version_label db 'VERSION_HEX=', 0
get_initial_label db 'GET_INITIAL', 0
set_strategy_label db 'SET_STRATEGY', 0
get_strategy_label db 'GET_STRATEGY', 0
invalid_strategy_label db 'SET_INVALID_0003', 0
invalid_high_strategy_label db 'SET_INVALID_0043', 0
invalid_fallback_strategy_label db 'SET_INVALID_0083', 0
invalid_bh_strategy_label db 'SET_INVALID_0100', 0
get_link_initial_label db 'GET_LINK_INITIAL', 0
link_on_label db 'SET_LINK_1', 0
get_link_on_label db 'GET_LINK_1', 0
link_off_label db 'SET_LINK_0', 0
get_link_off_label db 'GET_LINK_0', 0
invalid_link_label db 'SET_LINK_INVALID_2', 0
invalid_link_bh_label db 'SET_LINK_INVALID_0100', 0
invalid_subfunction_label db 'INVALID_5804', 0
allocate_upper_unlinked_label db 'ALLOC_UPPER_UNLINKED_0010', 0
get_link_before_allocation_label db 'GET_LINK_BEFORE_ALLOC', 0
get_strategy_before_upper_only_label db 'GET_STRATEGY_BEFORE_UPPER_ONLY', 0
get_strategy_before_fallback_label db 'GET_STRATEGY_BEFORE_UPPER_THEN_LOW', 0
allocate_upper_only_label db 'ALLOC_UPPER_ONLY_0010', 0
allocate_upper_then_low_label db 'ALLOC_UPPER_THEN_LOW_0010', 0
carry_label db ' C=', 0
ax_label db ' AX=', 0
bx_label db ' BX=', 0
newline db 13, 10, 0
complete db 'UMB_API_END', 13, 10, 0
program_stack times 512 db 0
program_stack_top:
program_end:
