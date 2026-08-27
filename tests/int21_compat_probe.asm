bits 16
org 100h

; Focused contracts for compatibility and DOS 4.0 extended INT 21h calls.

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

    ; Leave arena space for the temporary PSP allocation.
    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    fail_if_carry setup

    check_cpm 18h, 18              ; Reserved CP/M compatibility slots.
    check_cpm 1dh, 1d
    check_cpm 1eh, 1e
    check_cpm 20h, 20
    check_cpm 61h, 61

    mov ah, 1bh                    ; Default-drive allocation information.
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

    xor dl, dl                     ; Explicit current-drive allocation info.
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

    mov ah, 1fh                    ; Default DPB pointer.
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

    xor dl, dl                     ; DPB pointer for current drive.
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
    mov ah, 26h                    ; Build an old-style child PSP.
    int 21h
    mov ax, [cs:child_segment]
    mov es, ax
    cmp word [es:0], 20cdh         ; PSP starts with INT 20h.
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

    mov si, floppy_bpb             ; Convert a known 1.44 MB BPB to a DPB.
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
    mov ax, 5c00h                  ; Lock byte zero, then unlock it.
    int 21h
    fail_if_carry 5c
    mov bx, [file_handle]
    xor cx, cx
    xor dx, dx
    xor si, si
    mov di, 1
    mov ax, 5c01h
    int 21h
    fail_if_carry 5c
    mov bx, [file_handle]
    mov ah, 3eh
    int 21h
    fail_if_carry 5c
    mov dx, lock_file
    mov ah, 41h
    int 21h
    fail_if_carry 5c

    xor al, al                     ; Get the DBCS lead-byte table.
    mov ah, 63h
    int 21h
    cmp word [si], 0               ; This non-DBCS build exposes an empty table.
    je dbcs_ok
    push cs
    pop ds
    mov dx, fail_63
    jmp fail
dbcs_ok:
    push cs
    pop ds

    xor al, al                     ; No IFS is installed: IOCTL must fail.
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
    mov bx, 2                      ; Read/write, compatibility sharing.
    xor cx, cx
    mov dx, 11h                   ; Open existing or create absent.
    mov ax, 6c00h
    int 21h
    fail_if_carry 6c
    cmp cx, 2                     ; File was newly created.
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
    cmp cx, 1                     ; Existing file was opened.
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
fail_5c      db 'INT21_5C_FAIL', 13, 10, '$'
fail_61      db 'INT21_61_FAIL', 13, 10, '$'
fail_63      db 'INT21_63_FAIL', 13, 10, '$'
fail_6b      db 'INT21_6B_FAIL', 13, 10, '$'
fail_6c      db 'INT21_6C_FAIL', 13, 10, '$'
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
file_handle dw 0
extended_parameters times 8 db 0
converted_dpb times 40 db 0
ifs_buffer times 32 db 0
program_end:
