bits 16
org 100h


%macro fail_if_carry 1
    jnc %%ok
    mov dx, fail_%1
    jmp fail
%%ok:
%endmacro

%macro fail_unless_carry 1
    jc %%ok
    mov dx, fail_%1
    jmp fail
%%ok:
%endmacro

%macro require_error 2
    jc %%carried
    mov dx, %2
    jmp fail
%%carried:
    cmp ax, %1
    je %%ok
    mov dx, %2
    jmp fail
%%ok:
%endmacro

%macro check_cpm 2
    mov al, 0ffh
    mov ah, %1
    int 21h
    or al, al
    jz %%ok
    mov dx, fail_%2
    jmp fail
%%ok:
%endmacro

start:
    push cs
    pop ds
    push ds
    pop es

    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    fail_if_carry setup

    check_cpm 18h, 18
    check_cpm 1dh, 1d
    check_cpm 1eh, 1e
    check_cpm 20h, 20
    check_cpm 61h, 61

    mov ax, 38ffh
    mov bx, 9999
    mov dx, country_buffer
    int 21h
    require_error 2, fail_nls_country

    mov ax, 6501h
    mov bx, 0ffffh
    mov dx, 9999
    mov cx, 64
    mov di, country_buffer
    int 21h
    require_error 2, fail_nls_extended

    mov ax, 6602h
    mov bx, 9999
    int 21h
    require_error 2, fail_nls_codepage

    mov ah, 1bh
    int 21h
    cmp al, 0ffh
    je disk_info_1b_failed
    or al, al
    jz disk_info_1b_failed
    or cx, cx
    jnz disk_info_1b_ok
disk_info_1b_failed:
    push cs
    pop ds
    mov dx, fail_1b
    jmp fail
disk_info_1b_ok:
    push cs
    pop ds

    xor dl, dl
    mov ah, 1ch
    int 21h
    cmp al, 0ffh
    je disk_info_1c_failed
    or al, al
    jz disk_info_1c_failed
    or cx, cx
    jnz disk_info_1c_ok
disk_info_1c_failed:
    push cs
    pop ds
    mov dx, fail_1c
    jmp fail
disk_info_1c_ok:
    push cs
    pop ds

    mov ah, 1fh
    int 21h
    or al, al
    jnz default_dpb_failed
    mov ax, ds
    or ax, bx
    jnz default_dpb_ok
default_dpb_failed:
    push cs
    pop ds
    mov dx, fail_1f
    jmp fail
default_dpb_ok:
    push cs
    pop ds

    xor dl, dl
    mov ah, 32h
    int 21h
    or al, al
    jnz drive_dpb_failed
    mov ax, ds
    or ax, bx
    jnz drive_dpb_ok
drive_dpb_failed:
    push cs
    pop ds
    mov dx, fail_32
    jmp fail
drive_dpb_ok:
    push cs
    pop ds

    mov bx, 32
    mov ah, 48h
    int 21h
    fail_if_carry 26
    mov [child_segment], ax
    mov dx, ax
    mov ah, 26h
    int 21h
    mov ax, [cs:child_segment]
    mov es, ax
    cmp word [es:0], 20cdh
    je child_psp_ok
    push cs
    pop ds
    mov dx, fail_26
    jmp fail
child_psp_ok:
    mov ah, 49h
    int 21h
    push cs
    pop ds
    push ds
    pop es
    fail_if_carry 26

    mov si, floppy_bpb
    mov bp, converted_dpb
    mov ah, 53h
    int 21h
    cmp word [converted_dpb + 2], 512
    jne set_dpb_failed
    cmp byte [converted_dpb + 4], 0
    jne set_dpb_failed
    cmp word [converted_dpb + 11], 33
    jne set_dpb_failed
    cmp word [converted_dpb + 13], 2848
    je set_dpb_ok
set_dpb_failed:
    mov dx, fail_53
    jmp fail
set_dpb_ok:

    mov ax, 5d0bh
    int 21h
    mov ax, ds
    or ax, si
    jnz server_data_ok
    push cs
    pop ds
    mov dx, fail_5d
    jmp fail
server_data_ok:
    push cs
    pop ds

    mov dx, original_user_name
    xor al, al
    mov ah, 5eh
    int 21h
    fail_if_carry 5e
    mov [original_user_number], cx
    mov dx, test_user_name
    mov cx, 1234h
    mov ax, 5e01h
    int 21h
    fail_if_carry 5e
    mov dx, returned_user_name
    xor al, al
    mov ah, 5eh
    int 21h
    fail_if_carry 5e
    cmp cx, 1234h
    jne user_name_failed
    cmp byte [returned_user_name], 'T'
    je user_name_ok
user_name_failed:
    mov dx, fail_5e
    jmp fail
user_name_ok:
    mov dx, original_user_name
    mov cx, [original_user_number]
    mov ax, 5e01h
    int 21h
    fail_if_carry 5e

    xor cx, cx
    mov dx, lock_file
    mov ah, 3ch
    int 21h
    fail_if_carry 5c
    mov [file_handle], ax
    mov bx, ax
    xor cx, cx
    xor dx, dx
    xor si, si
    mov di, 1
    mov ax, 5c00h
    int 21h
    fail_if_carry 5c
    mov bx, [file_handle]
    xor cx, cx
    xor dx, dx
    xor si, si
    mov di, 1
    mov ax, 5c00h
    int 21h
    require_error 33, fail_lock_violation
    mov bx, [file_handle]
    xor cx, cx
    xor dx, dx
    xor si, si
    mov di, 1
    mov ax, 5c01h
    int 21h
    fail_if_carry 5c

    mov word [lock_count], 0
.fill_lock_table:
    mov bx, [file_handle]
    xor cx, cx
    mov dx, [lock_count]
    shl dx, 1
    xor si, si
    mov di, 1
    mov ax, 5c00h
    int 21h
    jc .lock_table_full
    inc word [lock_count]
    cmp word [lock_count], 256
    jb .fill_lock_table
    mov dx, fail_lock_table_setup
    jmp fail
.lock_table_full:
    require_error 36, fail_lock_buffer
    mov word [unlock_count], 0
.release_locks:
    mov dx, [unlock_count]
    cmp dx, [lock_count]
    jae .locks_released
    shl dx, 1
    mov bx, [file_handle]
    xor cx, cx
    xor si, si
    mov di, 1
    mov ax, 5c01h
    int 21h
    jc lock_cleanup_failed
    inc word [unlock_count]
    jmp .release_locks
.locks_released:
    mov bx, [file_handle]
    mov ah, 3eh
    int 21h
    fail_if_carry 5c

    jmp lock_cleanup_ok
lock_cleanup_failed:
    mov dx, fail_lock_cleanup
    jmp fail
lock_cleanup_ok:
    mov dx, lock_file
    mov ah, 41h
    int 21h
    fail_if_carry 5c

    xor al, al
    mov ah, 63h
    int 21h
    cmp word [si], 0
    je dbcs_ok
    push cs
    pop ds
    mov dx, fail_63
    jmp fail
dbcs_ok:
    push cs
    pop ds

    xor al, al
    xor bx, bx
    xor cx, cx
    mov dx, ifs_buffer
    mov ah, 6bh
    int 21h
    fail_unless_carry 6b

    push ds
    pop es
    mov si, extended_name
    mov di, extended_parameters
    mov bx, 2
    xor cx, cx
    mov dx, 11h
    mov ax, 6c00h
    int 21h
    fail_if_carry 6c
    cmp cx, 2
    jne extended_open_failed
    mov [file_handle], ax
    mov bx, ax
    mov ah, 3eh
    int 21h
    fail_if_carry 6c

    mov si, extended_name
    mov di, extended_parameters
    mov bx, 2
    xor cx, cx
    mov dx, 11h
    mov ax, 6c00h
    int 21h
    fail_if_carry 6c
    cmp cx, 1
    jne extended_open_failed
    mov bx, ax
    mov ah, 3eh
    int 21h
    fail_if_carry 6c
    mov dx, extended_name
    mov ah, 41h
    int 21h
    fail_if_carry 6c
    jmp extended_open_ok
extended_open_failed:
    mov dx, fail_6c
    jmp fail
extended_open_ok:

    mov ah, 19h
    int 21h
    mov dl, al
    mov ax, 5f07h
    int 21h
    fail_if_carry 5f
    mov ah, 19h
    int 21h
    mov dl, al
    mov ax, 5f08h
    int 21h
    fail_if_carry 5f

    mov ah, 62h
    int 21h
    mov [parent_segment], bx
    mov bx, 32
    mov ah, 48h
    int 21h
    fail_if_carry 55
    mov [child_segment], ax
    mov dx, ax
    add ax, 32
    mov si, ax
    mov ah, 55h
    int 21h
    mov ah, 51h
    int 21h
    cmp bx, [child_segment]
    je duplicated_psp_ok
    mov dx, fail_55
    jmp fail
duplicated_psp_ok:
    mov bx, [parent_segment]
    mov ah, 50h
    int 21h
    mov es, [child_segment]
    mov ah, 49h
    int 21h
    push ds
    pop es
    fail_if_carry 55

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

pass_message db 'INT21_COMPAT_PASS', 13, 10, '$'
fail_18      db 'INT21_18_FAIL', 13, 10, '$'
fail_1b      db 'INT21_1B_FAIL', 13, 10, '$'
fail_1c      db 'INT21_1C_FAIL', 13, 10, '$'
fail_1d      db 'INT21_1D_FAIL', 13, 10, '$'
fail_1e      db 'INT21_1E_FAIL', 13, 10, '$'
fail_1f      db 'INT21_1F_FAIL', 13, 10, '$'
fail_20      db 'INT21_20_FAIL', 13, 10, '$'
fail_26      db 'INT21_26_FAIL', 13, 10, '$'
fail_32      db 'INT21_32_FAIL', 13, 10, '$'
fail_53      db 'INT21_53_FAIL', 13, 10, '$'
fail_55      db 'INT21_55_FAIL', 13, 10, '$'
fail_5c      db 'INT21_5C_FAIL', 13, 10, '$'
fail_5d      db 'INT21_5D_FAIL', 13, 10, '$'
fail_5e      db 'INT21_5E_FAIL', 13, 10, '$'
fail_5f      db 'INT21_5F_FAIL', 13, 10, '$'
fail_61      db 'INT21_61_FAIL', 13, 10, '$'
fail_63      db 'INT21_63_FAIL', 13, 10, '$'
fail_6b      db 'INT21_6B_FAIL', 13, 10, '$'
fail_6c      db 'INT21_6C_FAIL', 13, 10, '$'
fail_lock_violation db 'INT21_LOCK_VIOLATION_FAIL', 13, 10, '$'
fail_lock_buffer db 'INT21_LOCK_BUFFER_FAIL', 13, 10, '$'
fail_lock_table_setup db 'INT21_LOCK_TABLE_SETUP_FAIL', 13, 10, '$'
fail_lock_cleanup db 'INT21_LOCK_CLEANUP_FAIL', 13, 10, '$'
fail_nls_country db 'INT21_NLS_COUNTRY_FAIL', 13, 10, '$'
fail_nls_extended db 'INT21_NLS_EXTENDED_FAIL', 13, 10, '$'
fail_nls_codepage db 'INT21_NLS_CODEPAGE_FAIL', 13, 10, '$'
fail_setup   db 'INT21_COMPAT_SETUP_FAIL', 13, 10, '$'

floppy_bpb:
    dw 512
    db 1
    dw 1
    db 2
    dw 224, 2880
    db 0f0h
    dw 9, 18, 2
    dd 0, 0
lock_file db 'I21LOCK.TMP', 0
extended_name db 'I21EXT.TMP', 0
child_segment dw 0
parent_segment dw 0
file_handle dw 0
lock_count dw 0
unlock_count dw 0
original_user_number dw 0
test_user_name db 'TRACEUSER      ', 0
original_user_name times 16 db 0
returned_user_name times 16 db 0
extended_parameters times 8 db 0
converted_dpb times 40 db 0
ifs_buffer times 32 db 0
country_buffer times 64 db 0
program_end:
