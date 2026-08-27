bits 16
org 100h

; Focused contracts for EXEC/wait, IOCTL device classification, and NLS case.

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

start:
    push cs
    pop ds
    push ds
    pop es

    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    jnc memory_ready
    mov dx, fail_4b
    jmp fail
memory_ready:

    mov ax, ds
    mov [exec_command_segment], ax
    mov [exec_fcb1_segment], ax
    mov [exec_fcb2_segment], ax

    mov dx, child_name
    mov bx, exec_block
    mov ax, 4bffh                  ; Undefined EXEC mode.
    int 21h
    require_error 1, fail_exec_mode
    mov dx, missing_child
    mov bx, exec_block
    mov ax, 4b00h
    int 21h
    require_error 2, fail_exec_file
    mov dx, missing_path_child
    mov bx, exec_block
    mov ax, 4b00h
    int 21h
    require_error 3, fail_exec_path
    mov dx, root_path              ; A directory is not executable.
    mov bx, exec_block
    mov ax, 4b00h
    int 21h
    require_error 5, fail_exec_access

    xor cx, cx                     ; A zero-byte image has no executable header.
    mov dx, empty_child
    mov ah, 3ch
    int 21h
    jc exec_format_setup_failed
    mov bx, ax
    mov ah, 3eh
    int 21h
    jc exec_format_setup_failed
    mov dx, empty_child
    mov bx, exec_block
    mov ax, 4b00h
    int 21h
    require_error 11, fail_exec_format
    mov dx, empty_child
    mov ah, 41h
    int 21h
    jc exec_format_setup_failed

    mov bx, 800h                   ; Build 32 KiB with no double-NUL terminator.
    mov ah, 48h
    int 21h
    jc exec_environment_setup_failed
    mov [environment_segment], ax
    mov es, ax
    xor di, di
    mov ax, 4141h
    mov cx, 4000h
    rep stosw
    push ds
    pop es
    mov ax, [environment_segment]
    mov [exec_block], ax
    mov dx, child_name
    mov bx, exec_block
    mov ax, 4b00h
    int 21h
    require_error 10, fail_exec_environment
    mov word [exec_block], 0
    mov es, [environment_segment]
    mov ah, 49h
    int 21h
    jc exec_environment_setup_failed
    push ds
    pop es

    xor di, di                     ; Fill the system file table with opens.
.open_until_full:
    mov dx, child_name
    mov ax, 3d00h
    int 21h
    jc .open_table_full
    mov [open_handles + di], ax
    add di, 2
    cmp di, open_handles_end - open_handles
    jb .open_until_full
    mov dx, fail_exec_sft_setup
    jmp fail
.open_table_full:
    require_error 4, fail_exec_sft_setup
    mov dx, child_name             ; EXEC must report the same exhausted SFT.
    mov bx, exec_block
    mov ax, 4b00h
    int 21h
    require_error 4, fail_exec_sft
.close_open_handles:
    test di, di
    jz .handles_closed
    sub di, 2
    mov bx, [open_handles + di]
    mov ah, 3eh
    int 21h
    jc exec_sft_setup_failed
    jmp .close_open_handles
.handles_closed:

    mov bx, 0ffffh                 ; Consume the largest free arena block.
    mov ah, 48h
    int 21h
    require_error 8, fail_exec_memory_setup
    mov ah, 48h                    ; BX is the reported largest block.
    int 21h
    jc exec_memory_setup_failed
    mov [memory_segment], ax
    mov dx, child_name
    mov bx, exec_block
    mov ax, 4b00h
    int 21h
    require_error 8, fail_exec_memory
    mov es, [memory_segment]
    mov ah, 49h
    int 21h
    jc exec_memory_setup_failed
    push ds
    pop es

    mov dx, child_name
    mov bx, exec_block
    mov ax, 4b00h                  ; Load and execute child returning 2Ah.
    int 21h
    jnc exec_ok
    mov dx, fail_4b
    jmp fail
exec_ok:

    mov ah, 4dh                    ; Consume child termination status.
    int 21h
    cmp ah, 0                      ; Normal termination.
    jne wait_failed
    cmp al, 2ah
    je wait_ok
wait_failed:
    mov dx, fail_4d
    jmp fail
wait_ok:

    mov bx, 1                     ; stdout remains the AUX character device.
    mov ax, 4400h
    int 21h
    jc ioctl_failed
    test dx, 80h
    jnz ioctl_ok
ioctl_failed:
    mov dx, fail_44
    jmp fail
ioctl_ok:

    mov dl, 'a'                   ; Active NLS table uppercases ASCII a.
    mov ax, 6520h
    int 21h
    jc nls_failed
    cmp dl, 'A'
    je nls_ok
nls_failed:
    mov dx, fail_65
    jmp fail
nls_ok:

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

exec_environment_setup_failed:
    mov dx, fail_exec_environment_setup
    jmp fail

exec_sft_setup_failed:
    mov dx, fail_exec_sft_setup
    jmp fail

exec_memory_setup_failed:
    mov dx, fail_exec_memory_setup
    jmp fail

exec_format_setup_failed:
    mov dx, fail_exec_format_setup
    jmp fail

fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

child_name db 'I21CHILD.COM', 0
missing_child db 'MISSING.COM', 0
missing_path_child db 'NOEXIST\CHILD.COM', 0
root_path db 'A:\', 0
empty_child db 'EMPTY.COM', 0
command_tail db 0, 13
exec_block:
    dw 0
    dw command_tail
exec_command_segment dw 0
    dw 5ch
exec_fcb1_segment dw 0
    dw 6ch
exec_fcb2_segment dw 0
pass_message db 'INT21_PROCESS_PASS', 13, 10, '$'
fail_44 db 'INT21_44_FAIL', 13, 10, '$'
fail_4b db 'INT21_4B_FAIL', 13, 10, '$'
fail_exec_mode db 'INT21_EXEC_MODE_FAIL', 13, 10, '$'
fail_exec_file db 'INT21_EXEC_FILE_FAIL', 13, 10, '$'
fail_exec_path db 'INT21_EXEC_PATH_FAIL', 13, 10, '$'
fail_exec_access db 'INT21_EXEC_ACCESS_FAIL', 13, 10, '$'
fail_exec_format db 'INT21_EXEC_FORMAT_FAIL', 13, 10, '$'
fail_exec_format_setup db 'INT21_EXEC_FORMAT_SETUP_FAIL', 13, 10, '$'
fail_exec_environment db 'INT21_EXEC_ENVIRONMENT_FAIL', 13, 10, '$'
fail_exec_environment_setup db 'INT21_EXEC_ENVIRONMENT_SETUP_FAIL', 13, 10, '$'
fail_exec_sft db 'INT21_EXEC_SFT_FAIL', 13, 10, '$'
fail_exec_sft_setup db 'INT21_EXEC_SFT_SETUP_FAIL', 13, 10, '$'
fail_exec_memory db 'INT21_EXEC_MEMORY_FAIL', 13, 10, '$'
fail_exec_memory_setup db 'INT21_EXEC_MEMORY_SETUP_FAIL', 13, 10, '$'
fail_4d db 'INT21_4D_FAIL', 13, 10, '$'
fail_65 db 'INT21_65_FAIL', 13, 10, '$'
memory_segment dw 0
environment_segment dw 0
open_handles times 20 dw 0
open_handles_end:
program_end:
