bits 16
org 100h

start:
    push cs
    pop ds

    mov ah, 30h
    int 21h
    mov si, dos_version_label
    call print_record

    mov ax, 5800h
    int 21h
    mov si, dos_strategy_label
    call print_record

    mov ax, 5802h
    int 21h
    mov si, dos_umb_link_label
    call print_record

    mov ax, 4300h
    int 2fh
    mov si, xms_present_label
    call print_record
    cmp al, 80h
    jne short no_xms

    mov ax, 4310h
    int 2fh
    mov [xms_entry], bx
    mov [xms_entry+2], es

    xor ah, ah
    call far [xms_entry]
    mov si, xms_version_label
    call print_record

    mov ah, 07h
    call far [xms_entry]
    mov si, a20_initial_label
    call print_record

    mov ah, 08h
    call far [xms_entry]
    mov si, xms_free_label
    call print_record

    mov ah, 10h
    mov dx, 0ffffh
    call far [xms_entry]
    mov si, umb_largest_label
    call print_record
    jmp short probe_ems

no_xms:
    mov dx, xms_unavailable
    call print_string

probe_ems:
    mov ax, 3567h
    int 21h
    push ds
    push cs
    pop ds
    mov si, emm_signature
    mov di, 10
    mov cx, 8
.signature_loop:
    mov al, [si]
    cmp al, [es:di]
    jne short .no_ems
    inc si
    inc di
    loop .signature_loop
    pop ds

    mov ah, 40h
    int 67h
    mov si, ems_status_label
    call print_record

    mov ah, 46h
    int 67h
    mov si, ems_version_label
    call print_record

    mov ah, 41h
    int 67h
    mov si, ems_frame_label
    call print_record

    mov ah, 42h
    int 67h
    mov si, ems_pages_label
    call print_record
    jmp short finish

.no_ems:
    pop ds
    mov dx, ems_unavailable
    call print_string

finish:
    mov dx, complete
    call print_string
    mov ax, 4c00h
    int 21h

print_record:
    pushf
    pop word [result_flags]
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
    mov dx, newline
    call print_string
    mov ax, [result_ax]
    mov bx, [result_bx]
    mov dx, [result_dx]
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
    jbe short .digit
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
    je short .write
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

xms_entry dd 0
result_flags dw 0
result_ax dw 0
result_bx dw 0
result_dx dw 0
character db 0

emm_signature db 'EMMXXXX0'
dos_version_label db 'DOS_VERSION', 0
dos_strategy_label db 'DOS_ALLOC_STRATEGY', 0
dos_umb_link_label db 'DOS_UMB_LINK', 0
xms_present_label db 'XMS_PRESENT', 0
xms_version_label db 'XMS_VERSION', 0
a20_initial_label db 'A20_QUERY', 0
xms_free_label db 'XMS_FREE', 0
umb_largest_label db 'XMS_UMB_LARGEST', 0
ems_status_label db 'EMS_STATUS', 0
ems_version_label db 'EMS_VERSION', 0
ems_frame_label db 'EMS_FRAME', 0
ems_pages_label db 'EMS_PAGES', 0
cf_label db ' CF=', 0
ax_label db ' AX=', 0
bx_label db ' BX=', 0
dx_label db ' DX=', 0
newline db 13, 10, 0
xms_unavailable db 'XMS_UNAVAILABLE', 13, 10, 0
ems_unavailable db 'EMS_UNAVAILABLE', 13, 10, 0
complete db 'DRDOS_PUBLIC_MEMORY_END', 13, 10, 0
