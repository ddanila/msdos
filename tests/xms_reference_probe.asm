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

    mov ax, 4300h
    int 2fh
    mov [installed_ax], ax
    mov si, installed_label
    call print_ax_bx_dx
    cmp al, 80h
    jne finish

    mov ax, 4310h
    int 2fh
    mov [xms_entry], bx
    mov [xms_entry+2], es

    xor ah, ah
    mov si, version_label
    call invoke

    mov ah, 07h
    mov si, a20_initial_label
    call invoke

    mov ah, 08h
    mov si, free_initial_label
    call invoke

    mov ah, 09h
    mov dx, 64
    mov si, allocate_label
    call invoke
    or ax, ax
    jz hma_test
    mov [handle], dx

    mov ax, ds
    mov word [move_to_xms+8], ax
    mov word [move_to_xms+10], dx
    mov ah, 0bh
    mov si, move_to_xms
    mov di, move_to_label
    call invoke_move

    mov ax, ds
    mov word [move_from_xms+14], ax
    mov dx, [handle]
    mov word [move_from_xms+4], dx
    push es
    push ds
    pop es
    mov di, move_destination
    mov cx, 16
    xor ax, ax
    rep stosw
    pop es
    mov ah, 0bh
    mov si, move_from_xms
    mov di, move_from_label
    call invoke_move
    push ds
    pop es
    mov si, move_source
    mov di, move_destination
    mov cx, 32
    repe cmpsb
    mov ax, 1
    je short move_verified
    xor ax, ax
move_verified:
    xor bx, bx
    xor dx, dx
    mov si, move_verify_label
    call print_ax_bx_dx

    mov ah, 0eh
    mov dx, [handle]
    mov si, handle_info_label
    call invoke

    mov ah, 0ch
    mov dx, [handle]
    mov si, lock_label
    call invoke

    mov ah, 0dh
    mov dx, [handle]
    mov si, unlock_label
    call invoke

    mov ah, 0fh
    mov bx, 32
    mov dx, [handle]
    mov si, shrink_label
    call invoke

    mov ah, 0eh
    mov dx, [handle]
    mov si, shrunk_info_label
    call invoke

    mov ah, 0ah
    mov dx, [handle]
    mov si, free_label
    call invoke

    mov ah, 0eh
    mov dx, [handle]
    mov si, freed_info_label
    call invoke

    ; Error and boundary behavior needed by the clean-room XMS 2.00 manager.
    mov ah, 0ah
    mov dx, 0ffffh
    mov si, bad_handle_free_label
    call invoke
    mov ah, 0ch
    mov dx, 0ffffh
    mov si, bad_handle_lock_label
    call invoke
    mov ah, 0dh
    mov dx, 0ffffh
    mov si, bad_handle_unlock_label
    call invoke
    mov ah, 0eh
    mov dx, 0ffffh
    mov si, bad_handle_info_label
    call invoke
    mov ah, 0fh
    mov bx, 1
    mov dx, 0ffffh
    mov si, bad_handle_realloc_label
    call invoke

    mov ah, 09h
    xor dx, dx
    mov si, allocate_zero_label
    call invoke
    or ax, ax
    jz short after_zero
    mov [zero_handle], dx
    mov ah, 0eh
    mov si, zero_info_label
    call invoke
    mov ah, 0ah
    mov dx, [zero_handle]
    mov si, zero_free_label
    call invoke
after_zero:
    mov ah, 09h
    mov dx, 4
    mov si, allocate_lock_label
    call invoke
    or ax, ax
    jz short move_errors
    mov [error_handle], dx
    mov ah, 0ch
    mov si, error_lock_label
    call invoke
    mov ah, 0ah
    mov dx, [error_handle]
    mov si, locked_free_label
    call invoke
    mov ah, 0fh
    mov bx, 2
    mov dx, [error_handle]
    mov si, locked_realloc_label
    call invoke
    mov ah, 0dh
    mov dx, [error_handle]
    mov si, error_unlock_label
    call invoke
    mov ah, 0dh
    mov dx, [error_handle]
    mov si, unlock_under_label
    call invoke

move_errors:
    mov ax, ds
    mov [odd_move+8], ax
    mov [odd_move+14], ax
    mov [bad_source_move+14], ax
    mov [bad_dest_move+8], ax
    mov [bad_offset_move+14], ax
    mov ax, [error_handle]
    mov [overlap_move+4], ax
    mov [overlap_move+10], ax
    mov [reverse_overlap_move+4], ax
    mov [reverse_overlap_move+10], ax

    mov ah, 0bh
    mov si, odd_move
    mov di, odd_move_label
    call invoke_move
    mov ah, 0bh
    mov si, bad_source_move
    mov di, bad_source_move_label
    call invoke_move
    mov ah, 0bh
    mov si, bad_dest_move
    mov di, bad_dest_move_label
    call invoke_move
    mov ax, [error_handle]
    mov [bad_offset_move+4], ax
    mov ah, 0bh
    mov si, bad_offset_move
    mov di, bad_offset_move_label
    call invoke_move
    mov ah, 0bh
    mov si, overlap_move
    mov di, overlap_move_label
    call invoke_move
    mov ah, 0bh
    mov si, reverse_overlap_move
    mov di, reverse_overlap_move_label
    call invoke_move

    mov ah, 0ah
    mov dx, [error_handle]
    mov si, error_free_label
    call invoke
    mov ah, 09h
    mov dx, 0ffffh
    mov si, allocate_huge_label
    call invoke

    ; Exhaust the finite handle table with legal zero-sized blocks. Keep the
    ; output compact: DX reports how many caller-visible handles were obtained.
    xor di, di
handle_exhaust_loop:
    mov ah, 09h
    xor dx, dx
    call far [xms_entry]
    or ax, ax
    jz short handle_exhausted
    mov [exhaust_handles+di], dx
    add di, 2
    cmp di, 64
    jb short handle_exhaust_loop
    mov ah, 09h
    xor dx, dx
    call far [xms_entry]
    or ax, ax
    jz short handle_exhausted
    mov ax, 0ffffh
    xor bx, bx
handle_exhausted:
    mov dx, di
    shr dx, 1
    mov si, handle_exhaust_label
    call print_ax_bx_dx
    xor di, di
handle_release_loop:
    cmp di, dx
    jae short lock_overflow_test
    push dx
    mov bx, di
    shl bx, 1
    mov dx, [exhaust_handles+bx]
    mov ah, 0ah
    call far [xms_entry]
    pop dx
    inc di
    jmp short handle_release_loop

lock_overflow_test:
    mov ah, 09h
    mov dx, 1
    call far [xms_entry]
    or ax, ax
    jz short hma_test
    mov [overflow_handle], dx
    mov word [repeat_count], 255
lock_to_limit:
    mov ah, 0ch
    mov dx, [overflow_handle]
    call far [xms_entry]
    or ax, ax
    jz short lock_loop_failed
    dec word [repeat_count]
    jnz short lock_to_limit
    mov ah, 0ch
    mov dx, [overflow_handle]
    mov si, lock_overflow_label
    call invoke
    mov word [repeat_count], 255
unlock_to_zero:
    mov ah, 0dh
    mov dx, [overflow_handle]
    call far [xms_entry]
    or ax, ax
    jz short lock_loop_failed
    dec word [repeat_count]
    jnz short unlock_to_zero
    mov ah, 0dh
    mov dx, [overflow_handle]
    mov si, unlock_after_overflow_label
    call invoke
    mov ah, 0ah
    mov dx, [overflow_handle]
    call far [xms_entry]
    jmp short hma_test
lock_loop_failed:
    mov si, lock_loop_failed_label
    call print_ax_bx_dx

hma_test:
    mov ah, 01h
    mov dx, 0ffffh
    mov si, hma_request_label
    call invoke
    or ax, ax
    jz a20_test
    mov ah, 01h
    mov dx, 0ffffh
    mov si, hma_second_label
    call invoke
    mov ah, 02h
    mov si, hma_release_label
    call invoke
    mov ah, 02h
    mov si, hma_second_release_label
    call invoke

a20_test:
    mov ah, 05h
    mov si, a20_local_on_label
    call invoke
    mov ah, 07h
    mov si, a20_on_query_label
    call invoke
    mov ah, 06h
    mov si, a20_local_off_label
    call invoke
    mov ah, 07h
    mov si, a20_final_label
    call invoke
    mov ah, 06h
    mov si, a20_underflow_label
    call invoke

    mov ah, 10h
    mov dx, 0ffffh
    mov si, umb_largest_label
    call invoke

    mov ah, 11h
    mov dx, 0a000h
    mov si, umb_bad_release_label
    call invoke

    mov ah, 12h
    mov bx, 1
    mov dx, 0a000h
    mov si, umb_bad_realloc_label
    call invoke

    mov ah, 13h
    mov si, unknown_label
    call invoke

finish:
    mov dx, complete
    call print_string
    mov ax, 4c00h
    int 21h

invoke:
    call far [xms_entry]
    jmp short print_ax_bx_dx
invoke_move:
    call far [xms_entry]
    mov si, di
    jmp short print_ax_bx_dx
print_ax_bx_dx:
    pushf
    pop cx
    mov [result_flags], cx
    mov [result_ax], ax
    mov [result_bx], bx
    mov [result_dx], dx
    mov dx, si
    call print_string
    mov dx, cf_label
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
    mov dx, dx_label
    call print_string
    mov ax, [result_dx]
    call print_hex_word
    call print_newline
    mov ax, [result_ax]
    mov bx, [result_bx]
    mov dx, [result_dx]
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

xms_entry dd 0
handle dw 0
zero_handle dw 0
error_handle dw 0
overflow_handle dw 0
repeat_count dw 0
exhaust_handles times 32 dw 0
installed_ax dw 0
result_flags dw 0
result_ax dw 0
result_bx dw 0
result_dx dw 0
character db 0
move_source db '0123456789ABCDEF0123456789ABCDEF'
move_destination times 32 db 0
move_to_xms:
    dd 32
    dw 0
    dw move_source, 0
    dw 0
    dd 0
move_from_xms:
    dd 32
    dw 0
    dd 0
    dw 0
    dw move_destination, 0
odd_move:
    dd 1
    dw 0
    dw move_source, 0
    dw 0
    dw move_destination, 0
bad_source_move:
    dd 2
    dw 0ffffh
    dd 0
    dw 0
    dw move_destination, 0
bad_dest_move:
    dd 2
    dw 0
    dw move_source, 0
    dw 0ffffh
    dd 0
bad_offset_move:
    dd 4
    dw 0
    dd 4094
    dw 0
    dw move_destination, 0
overlap_move:
    dd 4
    dw 0
    dd 0
    dw 0
    dd 2
reverse_overlap_move:
    dd 4
    dw 0
    dd 2
    dw 0
    dd 0
banner db 'XMS_REFERENCE_BEGIN', 13, 10, 0
complete db 'XMS_REFERENCE_END', 13, 10, 0
installed_label db 'INSTALLED', 0
version_label db 'VERSION', 0
a20_initial_label db 'A20_INITIAL', 0
free_initial_label db 'FREE_INITIAL', 0
allocate_label db 'ALLOCATE_64K', 0
move_to_label db 'MOVE_TO_XMS', 0
move_from_label db 'MOVE_FROM_XMS', 0
move_verify_label db 'MOVE_VERIFY', 0
handle_info_label db 'HANDLE_INFO', 0
lock_label db 'LOCK', 0
unlock_label db 'UNLOCK', 0
shrink_label db 'SHRINK_32K', 0
shrunk_info_label db 'SHRUNK_INFO', 0
free_label db 'FREE', 0
freed_info_label db 'FREED_INFO', 0
bad_handle_free_label db 'BAD_HANDLE_FREE', 0
bad_handle_lock_label db 'BAD_HANDLE_LOCK', 0
bad_handle_unlock_label db 'BAD_HANDLE_UNLOCK', 0
bad_handle_info_label db 'BAD_HANDLE_INFO', 0
bad_handle_realloc_label db 'BAD_HANDLE_REALLOC', 0
allocate_zero_label db 'ALLOCATE_ZERO', 0
zero_info_label db 'ZERO_INFO', 0
zero_free_label db 'ZERO_FREE', 0
allocate_lock_label db 'ALLOCATE_LOCK_CASE', 0
error_lock_label db 'ERROR_LOCK', 0
locked_free_label db 'LOCKED_FREE', 0
locked_realloc_label db 'LOCKED_REALLOC', 0
error_unlock_label db 'ERROR_UNLOCK', 0
unlock_under_label db 'UNLOCK_UNDERFLOW', 0
odd_move_label db 'MOVE_ODD_LENGTH', 0
bad_source_move_label db 'MOVE_BAD_SOURCE', 0
bad_dest_move_label db 'MOVE_BAD_DEST', 0
bad_offset_move_label db 'MOVE_BAD_SOURCE_OFFSET', 0
overlap_move_label db 'MOVE_OVERLAP', 0
reverse_overlap_move_label db 'MOVE_REVERSE_OVERLAP', 0
error_free_label db 'ERROR_CASE_FREE', 0
allocate_huge_label db 'ALLOCATE_HUGE', 0
handle_exhaust_label db 'HANDLE_EXHAUSTED', 0
lock_overflow_label db 'LOCK_OVERFLOW', 0
unlock_after_overflow_label db 'UNLOCK_AFTER_OVERFLOW', 0
lock_loop_failed_label db 'LOCK_LOOP_FAILED', 0
hma_request_label db 'HMA_REQUEST', 0
hma_second_label db 'HMA_SECOND_REQUEST', 0
hma_release_label db 'HMA_RELEASE', 0
hma_second_release_label db 'HMA_SECOND_RELEASE', 0
a20_local_on_label db 'A20_LOCAL_ON', 0
a20_on_query_label db 'A20_ON_QUERY', 0
a20_local_off_label db 'A20_LOCAL_OFF', 0
a20_final_label db 'A20_FINAL', 0
a20_underflow_label db 'A20_LOCAL_UNDERFLOW', 0
umb_largest_label db 'UMB_LARGEST', 0
umb_bad_release_label db 'UMB_BAD_RELEASE', 0
umb_bad_realloc_label db 'UMB_BAD_REALLOC', 0
unknown_label db 'UNKNOWN_13', 0
cf_label db ' CF=', 0
ax_label db ' AX=', 0
bx_label db ' BX=', 0
dx_label db ' DX=', 0
newline db 13, 10, 0

align 16
stack_space times 768 db 0
stack_top:
