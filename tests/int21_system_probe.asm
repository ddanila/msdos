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

start:
    push cs
    pop ds
    push ds
    pop es

    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    fail_if_carry setup

    mov ah, 0bh
    int 21h
    or al, al
    jz console_status_ok
    cmp al, 0ffh
    je console_status_ok
    mov dx, fail_0b
    jmp fail
console_status_ok:

    mov ah, 0dh
    int 21h

    mov ah, 19h
    int 21h
    mov [current_drive], al
    mov dl, al
    mov ah, 0eh
    int 21h
    cmp al, [current_drive]
    ja drive_count_ok
    mov dx, fail_0e
    jmp fail
drive_count_ok:
    mov ah, 19h
    int 21h
    cmp al, [current_drive]
    je current_drive_ok
    mov dx, fail_19
    jmp fail
current_drive_ok:

    mov ax, 3560h
    int 21h
    mov [old_vector_offset], bx
    mov [old_vector_segment], es
    mov dx, vector_handler
    mov ax, 2560h
    int 21h
    mov ax, 3560h
    int 21h
    cmp bx, vector_handler
    jne vector_failed
    push es
    pop ax
    push cs
    pop dx
    cmp ax, dx
    je vector_verified
vector_failed:
    mov dx, fail_25
    jmp fail
vector_verified:
    push ds
    mov ax, [old_vector_segment]
    mov ds, ax
    mov dx, [cs:old_vector_offset]
    mov ax, 2560h
    int 21h
    pop ds

    mov ah, 2ah
    int 21h
    cmp cx, 1980
    jb date_failed
    cmp dh, 1
    jb date_failed
    cmp dh, 12
    ja date_failed
    cmp dl, 1
    jb date_failed
    cmp dl, 31
    ja date_failed
    mov ah, 2bh
    int 21h
    or al, al
    jz date_ok
date_failed:
    mov dx, fail_2a
    jmp fail
date_ok:

    mov ah, 2ch
    int 21h
    cmp ch, 23
    ja time_failed
    cmp cl, 59
    ja time_failed
    cmp dh, 59
    ja time_failed
    cmp dl, 99
    ja time_failed
    mov ah, 2dh
    int 21h
    or al, al
    jz time_ok
time_failed:
    mov dx, fail_2c
    jmp fail
time_ok:

    mov ah, 54h
    int 21h
    and al, 1
    mov [original_verify], al
    xor al, 1
    mov [changed_verify], al
    mov ah, 2eh
    int 21h
    mov ah, 54h
    int 21h
    and al, 1
    cmp al, [changed_verify]
    je verify_changed
    mov dx, fail_2e
    jmp fail
verify_changed:
    mov al, [original_verify]
    mov ah, 2eh
    int 21h
    mov ah, 54h
    int 21h
    and al, 1
    cmp al, [original_verify]
    je verify_restored
    mov dx, fail_54
    jmp fail
verify_restored:

    mov dx, dta
    mov ah, 1ah
    int 21h
    mov ah, 2fh
    int 21h
    cmp bx, dta
    jne dta_failed
    push es
    pop ax
    push ds
    pop dx
    cmp ax, dx
    je dta_ok
dta_failed:
    mov dx, fail_2f
    jmp fail
dta_ok:

    mov ah, 30h
    int 21h
    cmp al, 6
    je version_ok
    mov dx, fail_30
    jmp fail
version_ok:

    mov ax, 3306h
    int 21h
    cmp bx, 1606h
    jne true_version_failed
    or dx, dx
    jz true_version_ok
true_version_failed:
    mov dx, fail_3306
    jmp fail
true_version_ok:

    mov ax, 3300h
    int 21h
    and dl, 1
    mov [break_state], dl
    mov ax, 3301h
    int 21h
    mov ax, 3300h
    int 21h
    cmp dl, [break_state]
    je break_ok
    mov dx, fail_33
    jmp fail
break_ok:

    mov ah, 34h
    int 21h
    mov ax, es
    or ax, bx
    jnz indos_ok
    mov dx, fail_34
    jmp fail
indos_ok:

    xor dl, dl
    mov ah, 36h
    int 21h
    cmp ax, 0ffffh
    je disk_space_failed
    or ax, ax
    jnz disk_space_ok
disk_space_failed:
    mov dx, fail_36
    jmp fail
disk_space_ok:

    mov ax, 3700h
    int 21h
    mov [switch_character], dl
    mov ax, 3701h
    int 21h
    mov ax, 3700h
    int 21h
    cmp dl, [switch_character]
    je switch_ok
    mov dx, fail_37
    jmp fail
switch_ok:

    mov dx, country_buffer
    xor al, al
    mov ah, 38h
    int 21h
    fail_if_carry 38

    mov ah, 62h
    int 21h
    mov [psp_segment], bx
    or bx, bx
    jnz psp_nonzero
    mov dx, fail_62
    jmp fail
psp_nonzero:
    mov ah, 50h
    int 21h
    mov ah, 51h
    int 21h
    cmp bx, [psp_segment]
    je psp_ok
    mov dx, fail_51
    jmp fail
psp_ok:

    mov ah, 52h
    int 21h
    mov ax, es
    or ax, bx
    jnz list_ok
    mov dx, fail_52
    jmp fail
list_ok:

    mov ax, 5800h
    int 21h
    fail_if_carry 58
    mov [allocation_strategy], ax
    mov bx, ax
    mov ax, 5801h
    int 21h
    fail_if_carry 58
    mov ax, 5800h
    int 21h
    fail_if_carry 58
    cmp ax, [allocation_strategy]
    je strategy_ok
    mov dx, fail_58
    jmp fail
strategy_ok:

    mov bx, 0042h
    mov ax, 5801h
    int 21h
    fail_if_carry 58
    mov ax, 5800h
    int 21h
    fail_if_carry 58
    cmp ax, 0042h
    jne strategy_failed

    mov bx, 0081h
    mov ax, 5801h
    int 21h
    fail_if_carry 58
    mov ax, 5800h
    int 21h
    fail_if_carry 58
    cmp ax, 0081h
    jne strategy_failed

    mov bx, 0043h
    mov ax, 5801h
    int 21h
    fail_unless_carry 58
    cmp ax, 1
    jne strategy_failed
    mov ax, 5800h
    int 21h
    fail_if_carry 58
    cmp ax, 0081h
    jne strategy_failed

    mov bx, 0100h
    mov ax, 5801h
    int 21h
    fail_unless_carry 58
    cmp ax, 1
    jne strategy_failed

    mov ax, 5802h
    int 21h
    fail_if_carry 58
    or al, al
    jnz strategy_failed

    mov bx, 1
    mov ax, 5803h
    int 21h
    fail_unless_carry 58
    cmp ax, 1
    jne strategy_failed

    mov bx, 0
    mov ax, 5803h
    int 21h
    fail_unless_carry 58
    cmp ax, 1
    jne strategy_failed

    mov bx, 2
    mov ax, 5803h
    int 21h
    fail_unless_carry 58
    cmp ax, 1
    jne strategy_failed

    mov ax, 5804h
    int 21h
    fail_unless_carry 58
    cmp ax, 1
    jne strategy_failed

    mov bx, [allocation_strategy]
    mov ax, 5801h
    int 21h
    fail_if_carry 58
    jmp strategy_complete

strategy_failed:
    mov dx, fail_58
    jmp fail
strategy_complete:

    xor cx, cx
    mov dx, temporary_template
    mov ah, 5ah
    int 21h
    fail_if_carry 5a_create
    mov [file_handle], ax
    cmp byte [temporary_template + 2], '\'
    je temporary_named
    mov dx, fail_5a_name
    jmp fail
temporary_named:
    mov bx, [file_handle]
    mov ah, 6ah
    int 21h
    fail_if_carry 6a
    mov bx, [file_handle]
    mov ah, 3eh
    int 21h
    fail_if_carry 5a_close
    mov dx, temporary_template
    mov ah, 41h
    int 21h
    fail_if_carry 5a_delete

    xor cx, cx
    mov dx, new_file_name
    mov ah, 5bh
    int 21h
    fail_if_carry 5b
    mov [file_handle], ax
    xor cx, cx
    mov dx, new_file_name
    mov ah, 5bh
    int 21h
    fail_unless_carry 5b
    cmp ax, 50h
    je create_new_rejected
    mov dx, fail_5b
    jmp fail
create_new_rejected:
    mov bx, [file_handle]
    mov ah, 3eh
    int 21h
    fail_if_carry 5b
    mov dx, new_file_name
    mov ah, 41h
    int 21h
    fail_if_carry 5b

    push ds
    pop es
    mov si, dot_path
    mov di, canonical_path
    mov ax, 6000h
    int 21h
    fail_if_carry 60
    mov al, [current_drive]
    add al, 'A'
    cmp [canonical_path], al
    jne truename_failed
    cmp byte [canonical_path + 1], ':'
    je truename_ok
truename_failed:
    mov dx, fail_60
    jmp fail
truename_ok:

    ; Failed opens must release their reserved JFN/SFT. Windows 95 EXTRACT
    ; repeatedly probes absent temporary names before creating them.
    ; Keep two files open, as EXTRACT does with its cabinet readers, so the
    ; failing open uses an SFT in the dynamically allocated FILES= table.
    mov dx, nul_name
    mov ax, 3d00h
    int 21h
    fail_if_carry 67
    push ax
    mov dx, nul_name
    mov ax, 3d00h
    int 21h
    fail_if_carry 67
    push ax
    mov cx, 64
missing_open_loop:
    push cx
    mov dx, new_file_name
    mov ax, 3d02h
    int 21h
    pop cx
    jnc missing_open_failed
    cmp ax, 2
    jne missing_open_failed
    loop missing_open_loop
    jmp missing_open_ok
missing_open_failed:
    mov dx, fail_missing_open
    jmp fail
missing_open_ok:
    pop bx
    mov ah, 3eh
    int 21h
    fail_if_carry 67
    pop bx
    mov ah, 3eh
    int 21h
    fail_if_carry 67
    mov bx, 24
    mov ah, 67h
    int 21h
    fail_if_carry 67
    mov ax, 3d00h
    mov dx, nul_name
    int 21h
    fail_if_carry 67
    mov [file_handle], ax
    mov bx, ax
    mov cx, 23
    mov ah, 46h
    int 21h
    fail_if_carry 67
    mov bx, 23
    mov ah, 3eh
    int 21h
    fail_if_carry 67
    mov bx, [file_handle]
    mov ah, 3eh
    int 21h
    fail_if_carry 67

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

vector_handler:
    iret

fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

pass_message        db 'INT21_SYSTEM_PASS', 13, 10, '$'
fail_0b             db 'INT21_0B_FAIL', 13, 10, '$'
fail_0e             db 'INT21_0E_FAIL', 13, 10, '$'
fail_19             db 'INT21_19_FAIL', 13, 10, '$'
fail_25             db 'INT21_25_35_FAIL', 13, 10, '$'
fail_2a             db 'INT21_2A_2B_FAIL', 13, 10, '$'
fail_2c             db 'INT21_2C_2D_FAIL', 13, 10, '$'
fail_2e             db 'INT21_2E_FAIL', 13, 10, '$'
fail_2f             db 'INT21_2F_FAIL', 13, 10, '$'
fail_30             db 'INT21_30_FAIL', 13, 10, '$'
fail_33             db 'INT21_33_FAIL', 13, 10, '$'
fail_3306           db 'INT21_3306_FAIL', 13, 10, '$'
fail_34             db 'INT21_34_FAIL', 13, 10, '$'
fail_36             db 'INT21_36_FAIL', 13, 10, '$'
fail_37             db 'INT21_37_FAIL', 13, 10, '$'
fail_38             db 'INT21_38_FAIL', 13, 10, '$'
fail_50             db 'INT21_50_FAIL', 13, 10, '$'
fail_51             db 'INT21_51_FAIL', 13, 10, '$'
fail_52             db 'INT21_52_FAIL', 13, 10, '$'
fail_54             db 'INT21_54_FAIL', 13, 10, '$'
fail_58             db 'INT21_58_FAIL', 13, 10, '$'
fail_5a_create      db 'INT21_5A_CREATE_FAIL', 13, 10, '$'
fail_5a_name        db 'INT21_5A_NAME_FAIL', 13, 10, '$'
fail_5a_close       db 'INT21_5A_CLOSE_FAIL', 13, 10, '$'
fail_5a_delete      db 'INT21_5A_DELETE_FAIL', 13, 10, '$'
fail_5b             db 'INT21_5B_FAIL', 13, 10, '$'
fail_60             db 'INT21_60_FAIL', 13, 10, '$'
fail_62             db 'INT21_62_FAIL', 13, 10, '$'
fail_67             db 'INT21_67_FAIL', 13, 10, '$'
fail_missing_open   db 'INT21_MISSING_OPEN_LEAK', 13, 10, '$'
fail_6a             db 'INT21_6A_FAIL', 13, 10, '$'
fail_setup          db 'INT21_SYSTEM_SETUP_FAIL', 13, 10, '$'
temporary_template  db 'A:', 0
                    times 16 db 0
new_file_name       db 'I21NEW.TMP', 0
dot_path            db '.', 0
nul_name             db 'NUL', 0
current_drive       db 0
original_verify     db 0
changed_verify      db 0
break_state         db 0
switch_character    db 0
old_vector_offset   dw 0
old_vector_segment  dw 0
psp_segment         dw 0
allocation_strategy dw 0
file_handle         dw 0
country_buffer      times 64 db 0
canonical_path      times 128 db 0
dta                 times 128 db 0
program_end:
