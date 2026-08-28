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

hma_test:
    mov ah, 01h
    mov dx, 0ffffh
    mov si, hma_request_label
    call invoke
    or ax, ax
    jz a20_test
    mov ah, 02h
    mov si, hma_release_label
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
installed_ax dw 0
result_flags dw 0
result_ax dw 0
result_bx dw 0
result_dx dw 0
character db 0
banner db 'XMS_REFERENCE_BEGIN', 13, 10, 0
complete db 'XMS_REFERENCE_END', 13, 10, 0
installed_label db 'INSTALLED', 0
version_label db 'VERSION', 0
a20_initial_label db 'A20_INITIAL', 0
free_initial_label db 'FREE_INITIAL', 0
allocate_label db 'ALLOCATE_64K', 0
handle_info_label db 'HANDLE_INFO', 0
lock_label db 'LOCK', 0
unlock_label db 'UNLOCK', 0
shrink_label db 'SHRINK_32K', 0
shrunk_info_label db 'SHRUNK_INFO', 0
free_label db 'FREE', 0
freed_info_label db 'FREED_INFO', 0
hma_request_label db 'HMA_REQUEST', 0
hma_release_label db 'HMA_RELEASE', 0
a20_local_on_label db 'A20_LOCAL_ON', 0
a20_on_query_label db 'A20_ON_QUERY', 0
a20_local_off_label db 'A20_LOCAL_OFF', 0
a20_final_label db 'A20_FINAL', 0
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
